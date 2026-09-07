class_name GameRoot
extends Node
## Gameplay composition root and the SINGLE pause/overview authority
## (review round 1: pause/overview previously split across HUD, CameraRig and
## the session, which could leave the player stuck or the session paused
## while the world ran). All pause-flavored state changes funnel through
## set_gameplay_paused()/toggle_overview(): cancel capture → update session
## state machine → pause the tree → show/hide overlay, in that order.

const AIM_GUIDE_LENGTH := 2.4
const CAL_STAGE_SECONDS := 1.5

@onready var session: GameSessionController = $GameSessionController
@onready var coordinator: InputCoordinator = $InputCoordinator
@onready var level: LevelController = $WorldRoot/LevelController
@onready var ball: BallController = $WorldRoot/Ball
@onready var camera_rig: CameraRig = $WorldRoot/CameraRig
@onready var voice: VoiceInputService = $VoiceInputService
@onready var hud: HUDPresenter = $GameUI/SafeAreaRoot

var _aim_guide: Node3D = null
var _cal_stage: String = ""
var _cal_room: Dictionary = {}
var _cal_soft: Dictionary = {}
var _cal_strong: Dictionary = {}


func _ready() -> void:
	var level_id := AppRouter.current_level_id
	if level_id.is_empty():
		AppRouter.goto_home()
		return
	var catalog := LevelCatalog.load_packaged()
	if not catalog.valid or not catalog.ordered_ids.has(level_id):
		push_error("Cannot start unknown level " + level_id)
		AppRouter.goto_home()
		return
	var meta: Dictionary = catalog.level_by_id(level_id)
	if not catalog.is_playable(level_id):
		push_error("Level " + level_id + " is not playable (status/scene).")
		AppRouter.goto_home()
		return

	var errors := level.load_level(meta)
	if not errors.is_empty():
		push_error("Level marker contract failed for " + level_id + ": " + ", ".join(errors))
		AppRouter.goto_home()
		return

	session.setup(ball, level, level_id, int(meta["par"]), int(meta["max_strokes"]))
	coordinator.session = session
	coordinator.voice = voice
	camera_rig.session = session
	camera_rig.level = level
	# A saved calibration profile is the only way Voice power mapping works;
	# load it before any hold can start (review finding: empty profile).
	if SettingsStore.has_valid_calibration():
		voice.calibration = SettingsStore.calibration()
	hud.gameplay = self
	hud.bind(session, coordinator, voice, camera_rig)
	hud.set_hole_info("%s · %s" % [level_id, String(meta["title"])], int(meta["par"]))
	hud.pause_requested.connect(func() -> void: set_gameplay_paused(true))
	hud.resume_requested.connect(func() -> void: set_gameplay_paused(false))
	hud.overview_toggled.connect(func() -> void: toggle_overview())
	hud.restart_requested.connect(_restart_level)
	hud.map_requested.connect(_to_map)
	hud.next_hole_requested.connect(_next_hole)
	# Nonverbal feedback cues (RB-025): effects bus only, never the mic path.
	session.shot_committed.connect(func(_shot: ShotCommand) -> void: AudioDirector.play_effect("putt"))
	session.hole_completed.connect(func(_result: Dictionary) -> void: AudioDirector.play_effect("cup"))
	ball.fall_detected.connect(func(_reason: String) -> void: _on_any_fall())
	level.kill_zone_entered.connect(func() -> void: _on_any_fall())

	_apply_equipped_cosmetic()
	_build_aim_guide()
	ball.freeze = true
	session.start_level()
	ball.freeze = false
	_maybe_capture_evidence_screenshot()


## Cosmetics are visual-only (docs/07 §5): collider, mass, and physics stay
## identical; the equipped ball just re-tints the body mesh.
func _apply_equipped_cosmetic() -> void:
	var equipped := ProgressStore.equipped_cosmetic()
	if equipped == ProgressionRules.COSMETIC_LION:
		return
	var mesh: MeshInstance3D = ball.find_child("BallMesh", true, false)
	if mesh == null:
		return
	var material := StandardMaterial3D.new()
	match equipped:
		ProgressionRules.COSMETIC_PANDA:
			material.albedo_color = Color(0.92, 0.93, 0.95)
		ProgressionRules.COSMETIC_ROBOT:
			material.albedo_color = Color(0.62, 0.68, 0.75)
		_:
			return
	mesh.material_override = material


## Fall coalescing for presentation only: either the kill plane or the kill
## volume may fire; penalties remain the session's once-only decision.
func _on_any_fall() -> void:
	AudioDirector.play_effect("fall")
	hud.show_out_of_bounds()


func _build_aim_guide() -> void:
	# Graybox dotted guide: flat segments pointing along the aim direction;
	# not a trajectory promise.
	_aim_guide = Node3D.new()
	_aim_guide.name = "AimGuide"
	for i: int in 6:
		var segment := MeshInstance3D.new()
		var quad := BoxMesh.new()
		quad.size = Vector3(0.08, 0.02, 0.22)
		segment.mesh = quad
		segment.position = Vector3(0.0, 0.0, -0.45 - float(i) * 0.38)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 1.0, 1.0, 0.55)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		segment.material_override = material
		_aim_guide.add_child(segment)
	camera_rig.add_child(_aim_guide)


func _process(_delta: float) -> void:
	if _aim_guide == null or session == null:
		return
	var show_guide := session.can_aim() and not camera_rig.is_overview()
	_aim_guide.visible = show_guide
	if show_guide:
		var ball_pos := session.ball.global_position
		_aim_guide.global_position = ball_pos + Vector3(0.0, 0.03, 0.0)
		_aim_guide.look_at(ball_pos + session.aim_direction, Vector3.UP)


# --- Pause / overview: one authority, one order of operations ---


## Pause cancels capture first (never a hidden hold), then cancels any
## un-committed shot in the session, then pauses the tree. Resume reverses;
## the mic never restarts by itself.
func set_gameplay_paused(paused: bool) -> void:
	if paused:
		if camera_rig.is_overview():
			camera_rig.set_overview_active(false)
			hud.set_overview_indicator(false)
		coordinator.interrupt_capture()
		session.pause_session()  # discards COMMIT_PENDING without a stroke
		hud.show_pause()
		get_tree().paused = true
	else:
		get_tree().paused = false
		session.resume_session()
		hud.hide_pause()


## Overview is a Ready-only inspection; the whole simulation pauses
## consistently while it is open (docs/05 §7), through this same authority.
func toggle_overview() -> void:
	if camera_rig.is_overview():
		camera_rig.set_overview_active(false)
		hud.set_overview_indicator(false)
		get_tree().paused = false
		return
	if get_tree().paused or session.fsm.state != GameStateMachine.State.READY:
		return
	camera_rig.set_overview_active(true)
	hud.set_overview_indicator(true)
	get_tree().paused = true


# --- Calibration orchestration (RB-021 core; HUD drives, service measures) ---


func start_calibration_stage(stage: String) -> bool:
	if stage not in ["room", "soft", "strong"]:
		return false
	coordinator.interrupt_capture()
	if not PlatformAdapter.try_request_microphone_permission():
		hud.on_calibration_stage_done({"ok": false, "error_code": "permission_denied"})
		return true  # sheet already informed; no async stage running
	if not voice.begin_calibration_stage(stage):
		hud.on_calibration_stage_done({"ok": false, "error_code": "no_input"})
		return true
	_cal_stage = stage
	get_tree().create_timer(CAL_STAGE_SECONDS, true, false, true).timeout.connect(_finish_calibration_stage)
	return true


func _finish_calibration_stage() -> void:
	if _cal_stage.is_empty():
		return
	var summary := voice.finish_calibration_stage()
	summary["ok"] = _calibration_stage_ok(summary)
	var stage := String(summary.get("stage", ""))
	match stage:
		"room":
			_cal_room = summary
		"soft":
			_cal_soft = summary
		"strong":
			_cal_strong = summary
	_cal_stage = ""
	if stage == "strong" and bool(summary["ok"]):
		# Derive + persist before the sheet celebrates; a failed derivation
		# must offer a retry, not close into an uncalibrated voice mode.
		var result: Dictionary = voice.apply_calibration(_cal_room, _cal_soft, _cal_strong)
		if bool(result["valid"]):
			SettingsStore.set_calibration(result["calibration"])
			voice.calibration = result["calibration"]
		else:
			summary = {"ok": false, "error_code": String(result["error_code"]), "stage": "strong"}
	hud.on_calibration_stage_done(summary)


func _calibration_stage_ok(summary: Dictionary) -> bool:
	# Room only needs enough data; soft/strong need >= 0.3 s qualified
	# (docs/04 §4) and a usable level.
	if String(summary.get("stage", "")) == "room":
		return float(summary.get("noise_level_db", -999.0)) > -999.0
	return float(summary.get("qualified_sec", 0.0)) >= 0.3 and float(summary.get("level_db", -999.0)) > -999.0


func cancel_calibration_stage() -> void:
	if not _cal_stage.is_empty():
		_cal_stage = ""
		voice.end_capture()


# --- Navigation / lifecycle ---


func _restart_level() -> void:
	_teardown()
	AppRouter.goto_game(session.level_id)


func _to_map() -> void:
	_teardown()
	AppRouter.goto_map()


func _next_hole() -> void:
	_teardown()
	var next := ProgressStore.next_playable_level()
	if next.is_empty() or next == session.level_id:
		AppRouter.goto_home()
	else:
		AppRouter.goto_game(next)


func _teardown() -> void:
	get_tree().paused = false
	coordinator.interrupt_capture()
	voice.end_capture()
	level.unload()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			# Background/focus loss: close capture, cancel un-committed shot,
			# pause the session; resume never restarts the mic (FR-15).
			if is_instance_valid(hud) and not hud.is_paused_sheet_visible():
				set_gameplay_paused(true)
		NOTIFICATION_PREDELETE:
			if is_instance_valid(level):
				level.unload()


# --- Dev-only visual evidence helpers (env-gated) ---


## ROAR3D_SCREENSHOT=/tmp/shot.png — Ready state capture.
func _maybe_capture_evidence_screenshot() -> void:
	var shot_path := OS.get_environment("ROAR3D_SCREENSHOT")
	if shot_path.is_empty():
		return
	for i: int in 300:
		if session.fsm.state == GameStateMachine.State.READY:
			break
		await get_tree().create_timer(0.05).timeout
	await get_tree().create_timer(0.8).timeout
	var image := get_viewport().get_texture().get_image()
	image.save_png(shot_path)
	print("screenshot saved: " + shot_path)
	# Ground-truth dump for visual verification: what occupies the ball's
	# screen position in this exact capture.
	var cam := camera_rig.camera
	var screen_pos := cam.unproject_position(ball.global_position)
	var img_size := image.get_size()
	if screen_pos.x >= 0 and screen_pos.y >= 0 and screen_pos.x < img_size.x and screen_pos.y < img_size.y:
		var px := int(screen_pos.x)
		var py := int(screen_pos.y)
		var samples: Array[String] = []
		for dy: int in range(-8, 9, 4):
			for dx: int in range(-8, 9, 4):
				var x := clampi(px + dx, 0, img_size.x - 1)
				var y := clampi(py + dy, 0, img_size.y - 1)
				var c := image.get_pixel(x, y)
				samples.append("(%d,%d)%s" % [x, y, c.to_html(false)])
		print("ball_screen=", screen_pos, " samples=", " ".join(samples))
	# Optional second capture: ROAR3D_SCREENSHOT_PAUSE — paused sheet state.
	var pause_path := OS.get_environment("ROAR3D_SCREENSHOT_PAUSE")
	if not pause_path.is_empty():
		set_gameplay_paused(true)
		await get_tree().create_timer(0.4).timeout
		var paused_image := get_viewport().get_texture().get_image()
		paused_image.save_png(pause_path)
		print("screenshot saved: " + pause_path)
		set_gameplay_paused(false)
	get_tree().quit(0)
