extends Control
## Home Screen (UI-02) matching 02_home.png reference art:
## - Dominant, glossy green PLAY button
## - Prominent Voice hero showcase card ("Use your voice to power every shot!")
## - Adventure (World Map), Balls (Collection), and Settings navigation cards
## - Seamless mode choice sheet with contextual permissions (UI-03, RB-019)

var _mode_sheet: PanelContainer
var _hint: Label
var _wave_label: Label
var _wave_tick := 0.0


func _ready() -> void:
	theme = RoarTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Fullscreen background panel
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = RoarTheme.NAVY
	bg.add_theme_stylebox_override("panel", bg_style)
	add_child(bg)

	var main_box := VBoxContainer.new()
	main_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_box.offset_left = 20
	main_box.offset_right = -20
	main_box.offset_top = 28
	main_box.offset_bottom = -24
	main_box.add_theme_constant_override("separation", 14)
	add_child(main_box)

	# --- Top bar: Player status pill & star count ---
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 10)
	main_box.add_child(top_bar)

	var player_pill := RoarTheme.make_pill_panel(RoarTheme.NAVY_PANEL, RoarTheme.NAVY_BORDER)
	var player_row := HBoxContainer.new()
	player_row.add_theme_constant_override("separation", 6)
	var crown_icon := Label.new()
	crown_icon.text = "👑"
	player_row.add_child(crown_icon)
	var player_label := Label.new()
	var completed_count := ProgressStore.completed_set().size()
	player_label.text = "Player · %d/12 Holes" % completed_count
	player_label.add_theme_font_size_override("font_size", 13)
	player_row.add_child(player_label)
	player_pill.add_child(player_row)
	top_bar.add_child(player_pill)

	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(top_spacer)

	var star_pill := RoarTheme.make_pill_panel(RoarTheme.NAVY_PANEL, RoarTheme.WARM_ACCENT)
	var star_label := Label.new()
	var total_stars := 0
	for lid in ProgressStore.ordered_ids():
		total_stars += int(ProgressStore.best_for(lid).get("best_stars", 0))
	star_label.text = "⭐ %d" % total_stars
	star_label.add_theme_color_override("font_color", RoarTheme.WARM_ACCENT)
	star_label.add_theme_font_size_override("font_size", 14)
	star_pill.add_child(star_label)
	top_bar.add_child(star_pill)

	# --- Brand Title Area ---
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 4)
	main_box.add_child(title_box)

	var title := Label.new()
	title.text = tr("ROARBALL")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", RoarTheme.WARM_ACCENT)
	title_box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = tr("TAGLINE")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	subtitle.add_theme_font_size_override("font_size", 14)
	title_box.add_child(subtitle)

	# --- Center Mascot Hero Card (matching 02_home.png) ---
	var hero_card := PanelContainer.new()
	hero_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var hero_style := StyleBoxFlat.new()
	hero_style.bg_color = RoarTheme.NAVY_PANEL
	hero_style.set_corner_radius_all(RoarTheme.PANEL_RADIUS)
	hero_style.border_color = RoarTheme.NAVY_BORDER
	hero_style.set_border_width_all(2)
	hero_style.content_margin_left = 16
	hero_style.content_margin_right = 16
	hero_style.content_margin_top = 16
	hero_style.content_margin_bottom = 16
	hero_card.add_theme_stylebox_override("panel", hero_style)
	main_box.add_child(hero_card)

	var hero_vbox := VBoxContainer.new()
	hero_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_vbox.add_theme_constant_override("separation", 10)
	hero_card.add_child(hero_vbox)

	# Lion mascot circle
	var lion_circle := PanelContainer.new()
	lion_circle.custom_minimum_size = Vector2(80, 80)
	lion_circle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var lion_style := StyleBoxFlat.new()
	lion_style.bg_color = Color("FFD036")
	lion_style.set_corner_radius_all(40)
	lion_style.border_color = Color("FFEAA0")
	lion_style.set_border_width_all(3)
	lion_circle.add_theme_stylebox_override("panel", lion_style)
	var lion_label := Label.new()
	lion_label.text = "🦁"
	lion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lion_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lion_label.add_theme_font_size_override("font_size", 42)
	lion_circle.add_child(lion_label)
	hero_vbox.add_child(lion_circle)

	var hero_pitch := Label.new()
	hero_pitch.text = "WHISPER... TO ROAR!"
	hero_pitch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_pitch.add_theme_color_override("font_color", RoarTheme.WARM_ACCENT)
	hero_pitch.add_theme_font_size_override("font_size", 16)
	hero_vbox.add_child(hero_pitch)

	var hero_guide := Label.new()
	hero_guide.text = "Aim your line with touch.
Make a sound to set your power.
Whisper to putt · Roar to leap!"
	hero_guide.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_guide.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	hero_guide.add_theme_font_size_override("font_size", 13)
	hero_vbox.add_child(hero_guide)

	# --- Hero PLAY Button (dominant central action) ---
	var play_button := RoarTheme.make_hero_play_button(tr("PLAY"))
	play_button.pressed.connect(_on_play)
	main_box.add_child(play_button)

	# --- 3-Card Navigation Grid (Adventure, Balls, Mode) ---
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	main_box.add_child(nav)

	var map_button := RoarTheme.make_flat_button(tr("WORLD_MAP"), true)
	map_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_button.text = tr("WORLD_MAP")
	map_button.custom_minimum_size = Vector2(0, 60)
	map_button.pressed.connect(func() -> void: AppRouter.goto_map())
	nav.add_child(map_button)

	var balls_button := RoarTheme.make_flat_button(tr("BALLS"), true)
	balls_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	balls_button.text = tr("BALLS")
	balls_button.custom_minimum_size = Vector2(0, 60)
	balls_button.pressed.connect(func() -> void: AppRouter.goto_collection())
	nav.add_child(balls_button)

	# --- Prominent Voice Hero Banner (matching 02_home.png bottom card) ---
	var voice_card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = RoarTheme.NAVY_PANEL
	card_style.set_corner_radius_all(RoarTheme.PANEL_RADIUS)
	card_style.border_color = RoarTheme.VOICE_CYAN if SettingsStore.is_voice_mode() else RoarTheme.NAVY_BORDER
	card_style.set_border_width_all(2)
	card_style.content_margin_left = 14
	card_style.content_margin_right = 14
	card_style.content_margin_top = 10
	card_style.content_margin_bottom = 10
	voice_card.add_theme_stylebox_override("panel", card_style)
	main_box.add_child(voice_card)

	var card_row := HBoxContainer.new()
	card_row.add_theme_constant_override("separation", 12)
	voice_card.add_child(card_row)

	var mic_badge := RoarTheme.make_pill_panel(
		RoarTheme.VOICE_CYAN.darkened(0.6) if SettingsStore.is_voice_mode() else RoarTheme.NAVY_CARD,
		RoarTheme.VOICE_CYAN if SettingsStore.is_voice_mode() else RoarTheme.NAVY_BORDER
	)
	var mic_glyph := Label.new()
	mic_glyph.text = "🎙"
	mic_glyph.add_theme_font_size_override("font_size", 20)
	mic_badge.add_child(mic_glyph)
	card_row.add_child(mic_badge)

	var card_info := VBoxContainer.new()
	card_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_info.add_theme_constant_override("separation", 2)
	card_row.add_child(card_info)

	var card_title := Label.new()
	card_title.text = "Use your voice to power every shot!"
	card_title.add_theme_font_size_override("font_size", 13)
	card_info.add_child(card_title)

	var card_sub := Label.new()
	card_sub.text = "WHISPER... TO ROAR!"
	card_sub.add_theme_color_override("font_color", RoarTheme.VOICE_CYAN if SettingsStore.is_voice_mode() else RoarTheme.TEXT_SECONDARY)
	card_sub.add_theme_font_size_override("font_size", 12)
	card_info.add_child(card_sub)

	_wave_label = Label.new()
	_wave_label.text = " ▂▃▅▆▇▆▅▃ "
	_wave_label.add_theme_color_override("font_color", RoarTheme.VOICE_CYAN)
	_wave_label.add_theme_font_size_override("font_size", 11)
	card_info.add_child(_wave_label)

	var mode_switch := RoarTheme.make_flat_button(
		"Switch to %s" % ("Touch" if SettingsStore.is_voice_mode() else "Voice"),
		true
	)
	mode_switch.custom_minimum_size = Vector2(100, 44)
	mode_switch.add_theme_font_size_override("font_size", 12)
	mode_switch.pressed.connect(func() -> void:
		if SettingsStore.is_voice_mode():
			SettingsStore.set_input_mode("touch")
			_rebuild()
		else:
			_open_mode_sheet())
	card_row.add_child(mode_switch)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", RoarTheme.WARM_ACCENT)
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.visible = false
	main_box.add_child(_hint)

	if SettingsStore.is_voice_mode() and not SettingsStore.has_valid_calibration():
		_hint.text = "Voice selected — your first mic hold will guide a short calibration. Touch always works too."
		_hint.visible = true

	_build_mode_sheet()


func _process(delta: float) -> void:
	_wave_tick += delta * 6.0
	if _wave_label != null and SettingsStore.is_voice_mode():
		var waves := [
			" ▂▃▅▆▇▆▅▃ ",
			"▂▃▅▆▇█▇▆▅ ",
			"▃▅▆▇█▇▆▅▃▂",
			"▅▆▇█▇▆▅▃▂ ",
			"▆▇▆▅▃▂ ▂▃▅"
		]
		var idx := int(_wave_tick) % waves.size()
		_wave_label.text = waves[idx]


## UI-03: mode-choice sheet with honest privacy copy and equal touch path.
func _build_mode_sheet() -> void:
	_mode_sheet = PanelContainer.new()
	_mode_sheet.set_anchors_preset(Control.PRESET_CENTER)
	_mode_sheet.anchor_left = 0.06
	_mode_sheet.anchor_right = 0.94
	_mode_sheet.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var sheet_box := VBoxContainer.new()
	sheet_box.add_theme_constant_override("separation", 12)
	_mode_sheet.add_child(sheet_box)

	var sheet_title := Label.new()
	sheet_title.text = tr("CHOOSE_INPUT")
	sheet_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sheet_title.add_theme_font_size_override("font_size", 20)
	sheet_title.add_theme_color_override("font_color", RoarTheme.WARM_ACCENT)
	sheet_box.add_child(sheet_title)

	var privacy := Label.new()
	privacy.text = tr("MODE_PRIVACY")
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	privacy.add_theme_font_size_override("font_size", 13)
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


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_mode_sheet = null
	var staged := Callable(self, "_ready")
	staged.call_deferred()
