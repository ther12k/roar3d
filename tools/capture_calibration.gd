extends Node
## Dev tool: captures the calibration sheet (SettingsStore invalidated).

func _ready() -> void:
	await _run()

func _run() -> void:
	# Invalidate BEFORE the game boots so its startup reads no calibration.
	SettingsStore.set_input_mode("voice")
	SettingsStore.invalidate_calibration()
	AppRouter.current_level_id = "CC01"
	var packed: PackedScene = load("res://scenes/game/game_root.tscn")
	var root: GameRoot = packed.instantiate()
	add_child(root)
	for i: int in 300:
		await get_tree().process_frame
		if is_instance_valid(root) and root.hud != null and root.hud._cal_sheet.visible:
			break
	if not is_instance_valid(root) or root.hud == null or not root.hud._cal_sheet.visible:
		# Fall back to opening the sheet directly (same path as a voice hold).
		root.hud.open_calibration_sheet()
		await get_tree().process_frame
	for j: int in 20:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/roar3d_calibration.png")
	print("CALIBRATION_CAPTURED")
	get_tree().quit(0)
