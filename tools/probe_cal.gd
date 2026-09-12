extends Node
func _ready() -> void:
	await get_tree().process_frame
	AppRouter.current_level_id = "CC01"
	var game: PackedScene = load("res://scenes/game/game_root.tscn")
	var root: GameRoot = game.instantiate()
	add_child(root)
	for i: int in 30:
		await get_tree().physics_frame
	var source := VoiceFrameSource.SyntheticFrameSource.new()
	source.rate = 48000
	root.voice._source = source
	root.voice._is_real_mic = false
	SettingsStore.invalidate_calibration()
	root.voice.calibration = {}
	root.hud.open_calibration_sheet()
	var levels := {"room": 0.004, "soft": 0.06, "strong": 0.32}
	var t0 := Time.get_ticks_msec()
	for stage: String in ["room", "soft", "strong"]:
		root.hud._on_cal_start()
		await get_tree().process_frame
		source.push_constant_ms(3000, float(levels[stage]))
		for i: int in 16:
			if not root.voice.is_listening():
				break
			await get_tree().create_timer(0.12).timeout
		print(stage, " t=", Time.get_ticks_msec() - t0, " listening=", root.voice.is_listening(), " hint=", root.hud._cal_hint_label.text)
	print("room=", root._cal_room)
	print("strong=", root._cal_strong)
	print("cal=", root.voice.calibration)
	get_tree().quit(0)
