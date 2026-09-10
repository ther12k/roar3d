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
	SettingsStore.set_input_mode(OS.get_environment("INPUT_MODE") if not OS.get_environment("INPUT_MODE").is_empty() else "voice")
	var packed: PackedScene = load("res://scenes/game/game_root.tscn")
	if packed == null:
		printerr("game_root scene failed to load")
		get_tree().quit(1)
		return
	var root: GameRoot = packed.instantiate()
	add_child(root)
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
	var out_path := OS.get_environment("LEVEL_CAPTURE_OUT")
	if out_path.is_empty():
		out_path = "/tmp/roar3d_%s_ready.png" % level_id.to_lower()
	var err := image.save_png(out_path)
	if err != OK:
		printerr("PNG save failed: %s" % error_string(err))
		get_tree().quit(1)
		return
	print("LEVEL_CAPTURE_SAVED %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	get_tree().quit(0)
