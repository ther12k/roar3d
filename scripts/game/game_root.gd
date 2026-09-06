class_name GameRoot
extends Node
## Gameplay composition root. Builds one GameSession per level load; leaving
## the scene tears down capture, listeners, and pending commands (FR-19).

const AIM_GUIDE_LENGTH := 2.4

@onready var session: GameSessionController = $GameSessionController
@onready var coordinator: InputCoordinator = $InputCoordinator
@onready var level: LevelController = $WorldRoot/LevelController
@onready var ball: BallController = $WorldRoot/Ball
@onready var camera_rig: CameraRig = $WorldRoot/CameraRig
@onready var voice: VoiceInputService = $VoiceInputService
@onready var hud: HUDPresenter = $GameUI/SafeAreaRoot

var _aim_guide: Node3D = null


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
	hud.bind(session, coordinator, voice, camera_rig)
	hud.set_hole_info("%s · %s" % [level_id, String(meta["title"])], int(meta["par"]))
	hud.pause_requested.connect(_on_pause)
	hud.restart_requested.connect(_restart_level)
	hud.map_requested.connect(_to_map)
	hud.next_hole_requested.connect(_next_hole)

	_build_aim_guide()
	ball.freeze = true
	session.start_level()
	ball.freeze = false
	_maybe_capture_evidence_screenshot()


## Dev-only visual evidence helper: ROAR3D_SCREENSHOT=/tmp/shot.png godot --path .
## Waits for the Ready state, then saves the viewport and quits.
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
	get_tree().quit(0)


func _build_aim_guide() -> void:
	# Graybox dotted guide: a few flat segments pointing along the aim
	# direction; clipped look is fine — it is not a trajectory promise.
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
	var show_guide := session.fsm.can_aim() and not camera_rig.is_overview()
	_aim_guide.visible = show_guide
	if show_guide:
		var ball_pos := session.ball.global_position
		_aim_guide.global_position = ball_pos + Vector3(0.0, 0.03, 0.0)
		_aim_guide.look_at(ball_pos + session.aim_direction, Vector3.UP)


# --- Navigation / lifecycle ---


func _on_pause() -> void:
	coordinator.interrupt_capture()
	session.pause_session()
	hud.show_pause()


func _restart_level() -> void:
	_teardown()
	AppRouter.goto_game(session.level_id)


func _to_map() -> void:
	_teardown()
	AppRouter.goto_home()  # map screen lands with RB-031; home is the graybox exit


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
			if is_instance_valid(coordinator):
				coordinator.interrupt_capture()
			if is_instance_valid(voice):
				voice.end_capture()
			if is_instance_valid(session) and not get_tree().paused:
				session.pause_session()
				if is_instance_valid(hud):
					hud.show_pause()
		NOTIFICATION_PREDELETE:
			if is_instance_valid(level):
				level.unload()
