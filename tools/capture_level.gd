extends Node
## Dev tool scene: boots a level through the real game_root scene (camera +
## HUD + session) and saves a PNG evidence capture. Run as a scene so
## autoloads are live (a `-s` script cannot compile game scripts):
##   LEVEL_ID=CC02 godot --path . --resolution 390x844 res://tools/capture_level.tscn
## Optional env: LEVEL_CAPTURE_OUT (default /tmp/roar3d_<level>_ready.png)

const SETTLE_FRAMES_MAX := 300


func _ready() -> void:
	await _run()


func _run() -> void:
	var level_id := OS.get_environment("LEVEL_ID")
	if level_id.is_empty():
		level_id = "CC01"
	AppRouter.current_level_id = level_id
	SettingsStore.set_input_mode(OS.get_environment("INPUT_MODE") if not OS.get_environment("INPUT_MODE").is_empty() else "touch")
	var packed: PackedScene = load("res://scenes/game/game_root.tscn")
	if packed == null:
		printerr("game_root scene failed to load")
		get_tree().quit(1)
		return
	var root: GameRoot = packed.instantiate()
	add_child(root)
	if not OS.get_environment("ROAR3D_DEBUG_LIGHT").is_empty():
		await get_tree().process_frame
		for light in root.find_children("*", "DirectionalLight3D", true, false):
			var l := light as DirectionalLight3D
			print("LIGHT path=%s energy=%.2f visible_in_tree=%s color=%s shadow=%s ambient=%s" % [
				l.get_path(), l.light_energy, l.is_visible_in_tree(), l.light_color,
				l.shadow_enabled, l.light_angular_distance])
		var env_node := root.get_node_or_null("WorldRoot/Lighting/WorldEnvironment")
		if env_node != null:
			var env: Environment = (env_node as WorldEnvironment).environment
			print("ENV bg_mode=%d ambient_source=%d ambient_energy=%.2f tonemap=%d" % [
				env.background_mode, env.ambient_light_source, env.ambient_light_energy, env.tonemap_mode])
	if not OS.get_environment("ROAR3D_FORCE_SUN").is_empty():
		var sun := root.get_node("WorldRoot/Lighting/DirectionalLight3D") as DirectionalLight3D
		sun.light_energy = 5.0
		sun.shadow_enabled = false
		sun.global_transform.basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
		print("FORCE_SUN applied")
	var ready := false
	for i: int in SETTLE_FRAMES_MAX:
		await get_tree().process_frame
		if is_instance_valid(root) and root.session.fsm.state == GameStateMachine.State.READY:
			ready = true
			# A few extra frames so the follow camera finishes its fit.
			for j: int in 20:
				await get_tree().process_frame
			break
	if not ready:
		printerr("level %s did not reach READY" % level_id)
		get_tree().quit(1)
		return
	var image: Image = get_viewport().get_texture().get_image()
	if not OS.get_environment("ROAR3D_DEBUG_FACE").is_empty():
		var rig := root.find_child("FaceRig", true, false) as Node3D
		var cam3 := root.camera_rig.camera
		print("FACE ball=%s cam=%s rig_pos=%s rig_+Z=%s z_dot=%s" % [
			root.ball.global_position, cam3.global_position, rig.global_position,
			rig.global_basis.z, rig.global_basis.z.normalized().dot(
				(cam3.global_position - root.ball.global_position).normalized())])
	var out_path := OS.get_environment("LEVEL_CAPTURE_OUT")
	if out_path.is_empty():
		out_path = "/tmp/roar3d_%s_ready.png" % level_id.to_lower()
	# Ground-truth: pixels at the ball's projected screen position.
	var cam := root.camera_rig.camera
	var screen_pos := cam.unproject_position(root.ball.global_position)
	var img_size := image.get_size()
	if screen_pos.x >= 0 and screen_pos.y >= 0 and screen_pos.x < img_size.x and screen_pos.y < img_size.y:
		var px := int(screen_pos.x)
		var c := image.get_pixel(int(screen_pos.x), clampi(int(screen_pos.y), 0, img_size.y - 1))
		print("ball_screen=%s px_color=%s console_top_expected=%d" % [screen_pos, c.to_html(false), img_size.y - 190])
	var err := image.save_png(out_path)
	if err != OK:
		printerr("PNG save failed: %s" % error_string(err))
		get_tree().quit(1)
		return
	print("LEVEL_CAPTURE_SAVED %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	# Optional extra sheet captures (dev evidence): pause sheet and the
	# restyled result sheet with its star pop settled. Display-only; the
	# fake result payload never touches progress storage.
	var pause_path := OS.get_environment("ROAR3D_SCREENSHOT_PAUSE")
	if not pause_path.is_empty():
		root.set_gameplay_paused(true)
		for j: int in 25:
			await get_tree().process_frame
		var pause_image := get_viewport().get_texture().get_image()
		pause_image.save_png(pause_path)
		print("screenshot saved: " + pause_path)
		root.set_gameplay_paused(false)
	var result_path := OS.get_environment("ROAR3D_SCREENSHOT_RESULT")
	if not result_path.is_empty():
		root.hud._on_hole_completed({"stars": 3, "strokes": 2, "par": 3, "is_new_best": true})
		for j: int in 110:
			await get_tree().process_frame
		var result_image := get_viewport().get_texture().get_image()
		result_image.save_png(result_path)
		print("screenshot saved: " + result_path)
	get_tree().quit(0)
