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
var _face_rig: Node3D = null
var _mouth_smile: MeshInstance3D = null
var _mouth_o: MeshInstance3D = null
var _expression_timer: SceneTreeTimer = null
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

	_apply_world_sky(level_id)
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
	session.shot_committed.connect(func(_shot: ShotCommand) -> void:
		AudioDirector.play_effect("putt")
		_spawn_burst(ball.global_position, Color("6fce4e"), 10, 2.0)
		_set_expression("surprised")
	)
	session.hole_completed.connect(func(_result: Dictionary) -> void:
		AudioDirector.play_effect("cup")
		_spawn_burst(level.cup_position() + Vector3(0, 0.4, 0), RoarTheme.WARM_ACCENT, 26, 5.0)
		_spawn_burst(level.cup_position() + Vector3(0, 0.5, 0), RoarTheme.VOICE_CYAN, 18, 4.5)
		_spawn_burst(level.cup_position() + Vector3(0, 0.6, 0), RoarTheme.PRIMARY_GREEN, 18, 4.5)
		_set_expression("happy")
	)
	ball.fall_detected.connect(func(_reason: String) -> void: _on_any_fall())
	level.kill_zone_entered.connect(func() -> void: _on_any_fall())
	ball.settled.connect(func(_t: Transform3D, _ok: bool) -> void:
		_spawn_burst(ball.global_position, Color(0.75, 0.72, 0.66), 8, 1.2))  # landing dust

	_apply_equipped_cosmetic()
	_build_face_rig()
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


## Camera-facing face rig (docs/07 §5): the lion face billboards toward the
## camera independently of the rolling sphere so the mascot stays readable.
func _build_face_rig() -> void:
	_face_rig = Node3D.new()
	_face_rig.name = "FaceRig"
	ball.add_child(_face_rig)
	for face_part in ["EyeLeft", "EyeRight", "Muzzle", "Nose"]:
		var mesh := ball.get_node_or_null(NodePath(face_part))
		if mesh is Node3D:
			(mesh as Node3D).reparent(_face_rig)
	# Expressions: smile (default) and O-mouth (surprised)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("2a1f1a")
	_mouth_smile = MeshInstance3D.new()
	var smile_mesh := BoxMesh.new()
	smile_mesh.size = Vector3(0.13, 0.035, 0.02)
	_mouth_smile.mesh = smile_mesh
	_mouth_smile.material_override = dark
	_mouth_smile.position = Vector3(0, -0.095, 0.245)
	_mouth_smile.rotation_degrees = Vector3(0, 0, 8)
	_face_rig.add_child(_mouth_smile)
	_mouth_o = MeshInstance3D.new()
	var o_mesh := SphereMesh.new()
	o_mesh.radius = 0.035
	o_mesh.height = 0.03
	_mouth_o.mesh = o_mesh
	_mouth_o.material_override = dark
	_mouth_o.position = Vector3(0, -0.10, 0.245)
	_mouth_o.visible = false
	_face_rig.add_child(_mouth_o)


func _set_expression(kind: String) -> void:
	if _mouth_smile == null or _mouth_o == null:
		return
	match kind:
		"surprised":
			_mouth_smile.visible = false
			_mouth_o.visible = true
			_expression_timer = get_tree().create_timer(0.9, true)
			_expression_timer.timeout.connect(func() -> void: _set_expression("idle"))
		"happy":
			_mouth_smile.visible = true
			_mouth_o.visible = false
		_:
			_mouth_smile.visible = true
			_mouth_o.visible = false


## Asset-pack VFX: short one-shot particle bursts (confetti, grass, dust).
func _spawn_burst(pos: Vector3, color: Color, count: int, speed: float) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = count
	particles.lifetime = 1.1
	particles.direction = Vector3.UP
	particles.spread = 75.0
	particles.initial_velocity_min = speed * 0.5
	particles.initial_velocity_max = speed
	particles.gravity = Vector3(0, -9.8, 0)
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.2
	var chunk := BoxMesh.new()
	chunk.size = Vector3(0.055, 0.055, 0.055)
	particles.mesh = chunk
	particles.color = color
	add_child(particles)
	particles.global_position = pos
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


## Portal Peaks gets the asset-pack sunset sky; Cloud Cliffs keeps sunny day.
func _apply_world_sky(level_id: String) -> void:
	if not level_id.begins_with("PP"):
		return
	var env := ($WorldRoot/Lighting/WorldEnvironment.environment as Environment)
	if env == null or env.sky == null:
		return
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
	if sky_mat != null:
		sky_mat.sky_top_color = Color("4a2d6e")
		sky_mat.sky_horizon_color = Color("ff9a5c")
		sky_mat.ground_horizon_color = Color("e8875a")
		sky_mat.ground_bottom_color = Color("3a2b4f")
	var sun := $WorldRoot/Lighting/DirectionalLight3D as DirectionalLight3D
	if sun != null:
		sun.light_color = Color("ffd2a0")


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


func _process(delta: float) -> void:
	if _face_rig != null and is_instance_valid(ball) and camera_rig != null:
		_face_rig.global_position = ball.global_position
		var cam := camera_rig.camera
		if cam != null:
			_face_rig.look_at(cam.global_position, Vector3.UP)
			_face_rig.rotate_y(PI)  # face meshes live on the rig's +Z side
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
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED:
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
