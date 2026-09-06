extends Control
## Graybox Home (UI-02 subset). Hero art, full menus, and the world map land
## in M2 (RB-030/RB-031); this screen proves navigation + Play-resume wiring
## without any mockup screenshots.


func _ready() -> void:
	theme = RoarTheme.build()
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.anchor_left = 0.1
	box.anchor_right = 0.9
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var title := Label.new()
	title.text = "Roarball"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Small shots. Big roars."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	box.add_child(subtitle)

	var play := RoarTheme.make_flat_button("Play")
	play.pressed.connect(_on_play)
	box.add_child(play)

	var mode_label := Label.new()
	mode_label.text = "Input: %s (tap to switch)" % ("Voice" if SettingsStore.is_voice_mode() else "Touch")
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(mode_label)

	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", RoarTheme.WARM_ACCENT)
	hint.visible = false
	box.add_child(hint)

	var mode_button := RoarTheme.make_flat_button("Switch to %s" % ("Touch" if SettingsStore.is_voice_mode() else "Voice"), true)
	mode_button.pressed.connect(func() -> void:
		SettingsStore.set_input_mode("touch" if SettingsStore.is_voice_mode() else "voice")
		if SettingsStore.is_voice_mode() and not SettingsStore.has_valid_calibration():
			hint.text = "Voice: your first mic hold will guide a short calibration. Touch always works too."
			hint.visible = true
		get_tree().reload_current_scene()
	)
	box.add_child(mode_button)

	if SettingsStore.is_voice_mode() and not SettingsStore.has_valid_calibration():
		hint.text = "Voice selected — first mic hold will guide calibration."
		hint.visible = true


func _on_play() -> void:
	var next := ProgressStore.next_playable_level()
	if next.is_empty():
		next = ProgressStore.ordered_ids()[0]
	AppRouter.goto_game(next)
