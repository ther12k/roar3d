extends Control
## Home (UI-02) with the mode-choice sheet (UI-03, RB-019): Voice requires the
## contextual permission pre-prompt with the honest privacy copy; denial
## lands on Touch without nagging. Play resolves to the next unlocked hole.

var _mode_sheet: PanelContainer
var _hint: Label


func _ready() -> void:
	theme = RoarTheme.build()
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.anchor_left = 0.1
	box.anchor_right = 0.9
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var title := Label.new()
	title.text = tr("ROARBALL")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = tr("TAGLINE")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	box.add_child(subtitle)

	var play := RoarTheme.make_flat_button(tr("PLAY"))
	play.pressed.connect(_on_play)
	box.add_child(play)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	box.add_child(nav)
	var map_button := RoarTheme.make_flat_button(tr("WORLD_MAP"), true)
	map_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_button.pressed.connect(func() -> void: AppRouter.goto_map())
	nav.add_child(map_button)
	var balls_button := RoarTheme.make_flat_button(tr("BALLS"), true)
	balls_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	balls_button.pressed.connect(func() -> void: AppRouter.goto_collection())
	nav.add_child(balls_button)

	var mode_label := Label.new()
	mode_label.text = tr("INPUT_SWITCH") % ("Voice" if SettingsStore.is_voice_mode() else "Touch")
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(mode_label)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", RoarTheme.WARM_ACCENT)
	_hint.visible = false
	box.add_child(_hint)

	var mode_button := RoarTheme.make_flat_button("Switch to %s" % ("Touch" if SettingsStore.is_voice_mode() else "Voice"), true)
	mode_button.pressed.connect(func() -> void:
		if SettingsStore.is_voice_mode():
			SettingsStore.set_input_mode("touch")
			_rebuild()
		else:
			_open_mode_sheet())
	box.add_child(mode_button)

	if SettingsStore.is_voice_mode() and not SettingsStore.has_valid_calibration():
		_hint.text = "Voice selected — your first mic hold will guide calibration. Touch always works too."
		_hint.visible = true

	_build_mode_sheet()


## UI-03: two equally visible options, honest local-processing copy, and the
## platform permission requested only on Continue. Denial never loops.
func _build_mode_sheet() -> void:
	_mode_sheet = PanelContainer.new()
	_mode_sheet.set_anchors_preset(Control.PRESET_CENTER)
	_mode_sheet.anchor_left = 0.08
	_mode_sheet.anchor_right = 0.92
	_mode_sheet.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var sheet_box := VBoxContainer.new()
	sheet_box.add_theme_constant_override("separation", 10)
	_mode_sheet.add_child(sheet_box)
	var sheet_title := Label.new()
	sheet_title.text = tr("CHOOSE_INPUT")
	sheet_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sheet_box.add_child(sheet_title)
	var privacy := Label.new()
	privacy.text = tr("MODE_PRIVACY")
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	sheet_box.add_child(privacy)
	var voice_option := RoarTheme.make_flat_button(tr("USE_VOICE"))
	voice_option.pressed.connect(_on_voice_chosen)
	sheet_box.add_child(voice_option)
	var touch_option := RoarTheme.make_flat_button(tr("USE_TOUCH_MODE"), true)
	touch_option.pressed.connect(func() -> void:
		SettingsStore.set_input_mode("touch")
		_mode_sheet.visible = false
		_rebuild())
	sheet_box.add_child(touch_option)
	var cancel := RoarTheme.make_flat_button(tr("BACK"), true)
	cancel.pressed.connect(func() -> void: _mode_sheet.visible = false)
	sheet_box.add_child(cancel)
	_mode_sheet.visible = false
	add_child(_mode_sheet)


func _on_play() -> void:
	var next := ProgressStore.next_playable_level()
	if next.is_empty():
		next = ProgressStore.ordered_ids()[0]
	AppRouter.goto_game(next)


func _open_mode_sheet() -> void:
	_mode_sheet.visible = true


func _on_voice_chosen() -> void:
	# Contextual permission request (desktop/dev best-effort; Android timing
	# is RB-005). Denial persists Touch and explains — never a prompt loop.
	var granted := PlatformAdapter.try_request_microphone_permission()
	if not granted:
		_mode_sheet.visible = false
		SettingsStore.set_input_mode("touch")
		_hint.text = "Microphone not available — Touch mode is fully playable."
		_hint.visible = true
		_rebuild()
		return
	SettingsStore.set_input_mode("voice")
	_mode_sheet.visible = false
	_hint.text = "Voice on. Your first mic hold will guide a short calibration."
	_hint.visible = true
	_rebuild()


## Re-render mode-dependent labels without a scene reload (settings changes
## must not punch through to any world state — docs/06 §6).
func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_mode_sheet = null
	var staged := Callable(self, "_ready")
	staged.call_deferred()
