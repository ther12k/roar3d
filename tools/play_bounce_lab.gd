extends Node
## Bounce Lab bootstrap (experiment branch ONLY): plays scenes/levels/CC04X.tscn
## through the real gameplay components without touching the packaged catalog
## (the 12-hole contract stays intact for rc comparisons). Composes the same
## pieces the integration harness uses — LevelController + BallController +
## GameSessionController + CameraRig + InputCoordinator — with dev keys.
##
## Run: godot --path . res://tools/play_bounce_lab.tscn
## Keys: Arrows aim · Enter/Space shoot (80%) · Z jump / pre-landing Perfect
## Bounce · R restart · Esc quit.

const LEVEL_ID := "CC04X"
const SCENE_PATH := "res://scenes/levels/CC04X.tscn"

var session: GameSessionController
var level: LevelController
var ball: BallController
var camera_rig: CameraRig


func _ready() -> void:
	var catalog := LevelCatalog.CatalogData.new()
	catalog.valid = true
	var meta := {
		"id": LEVEL_ID,
		"par": 3,
		"max_strokes": 12,
		"scene_path": SCENE_PATH,
	}
	level = LevelController.new()
	add_child(level)
	var errors := level.load_level(meta)
	if not errors.is_empty():
		printerr("CC04X load errors: " + str(errors))
		get_tree().quit(1)
		return
	ball = BallController.new()
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	collision.shape = sphere
	ball.add_child(collision)
	add_child(ball)
	session = GameSessionController.new()
	add_child(session)
	session.setup(ball, level, LEVEL_ID, 3, 12)
	session.start_level()
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	camera_rig.add_child(cam)
	camera_rig.camera = cam  # before add_child: _ready() dereferences camera
	camera_rig.session = session
	camera_rig.level = level
	add_child(camera_rig)
	cam.current = true
	# Minimal lighting rig (game_root.tscn owns the real one).
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.2
	add_child(sun)
	var env := WorldEnvironment.new()
	var env_res := Environment.new()
	env_res.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("3a86dd")
	sky_mat.sky_horizon_color = Color("cfe9ff")
	sky_mat.ground_horizon_color = Color("aedcf5")
	sky_mat.ground_bottom_color = Color("6f95a8")
	sky.sky_material = sky_mat
	env_res.sky = sky
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color = Color(1.0, 0.98, 0.94)
	env_res.ambient_light_energy = 1.0
	env.environment = env_res
	add_child(env)
	print("Bounce Lab ready — Arrows aim, Enter shoot, Z jump/perfect-bounce, R restart, Esc quit")
	# Evidence capture: one phone-size PNG after settle (review-friendly).
	var shot := OS.get_environment("ROAR3D_LAB_SHOT")
	if not shot.is_empty() and DisplayServer.get_name() != "headless":
		for i: int in 240:
			await get_tree().physics_frame
			if session.fsm.state == GameStateMachine.State.READY:
				break
		await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		if image != null:
			image.save_png(shot)
			print("lab capture: " + shot)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_ENTER, KEY_SPACE:
				if session.fsm.state == GameStateMachine.State.READY:
					session.request_touch_shot(0.8)
			KEY_Z:
				session.request_jump()
			KEY_R:
				session.start_level()
			KEY_ESCAPE:
				get_tree().quit()
	elif event is InputEventKey and event.echo:
		match (event as InputEventKey).keycode:
			KEY_LEFT:
				session.set_aim(session.aim_direction.rotated(Vector3.UP, 0.05))
			KEY_RIGHT:
				session.set_aim(session.aim_direction.rotated(Vector3.UP, -0.05))
