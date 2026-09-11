class_name HUDPresenter
extends Control
## Gameplay HUD faithfully implementing 01_original_gameplay.png:
## - Circular glowing microphone button with concentric rings
## - Real-time audio waveform / sound equalizer feedback
## - "Whisper... to Roar!" dynamic color-coded power meter
## - Dedicated Strokes pill badge
## - Seamless Voice / Touch input switching
## - Full safe-area adaptation and pause/overview/results/calibration flows

signal pause_requested()
signal resume_requested()
signal overview_toggled()
signal restart_requested()
signal map_requested()
signal next_hole_requested()

var session: GameSessionController
var coordinator: InputCoordinator
var voice: VoiceInputService
var camera_rig: CameraRig
var gameplay: Node = null  # GameRoot; typed loosely to avoid a cyclic preload

var _top_box: VBoxContainer
var _hole_label: Label
var _par_label: Label
var _strokes_label: Label
var _state_label: Label
var _tray: VBoxContainer
var _tray_panel: PanelContainer
var _mode_chip: Button
var _power_bar: ProgressBar
var _power_label: Label
var _touch_box: HBoxContainer
var _power_slider: HSlider
var _shoot_button: Button
var _voice_box: HBoxContainer
var _mic_button: Button
var _mic_pulse_tick := 0.0
var _wave_label: Label
var _wave_tick := 0.0
var _overview_button: Button
var _balls_button: Button
var _status_label: Label
var _sheet_blocker: ColorRect
var _pause_layer: PanelContainer
var _result_layer: PanelContainer
var _result_title: Label
var _star_labels: Array[Label] = []
var _result_detail: Label
var _save_banner: PanelContainer
var _retry_save_button: Button
var _oob_banner: PanelContainer
var _pause_confirm_box: VBoxContainer
var _mode_switch_button: Button
var _quality_button: Button
var _motion_button: Button
var _recal_button: Button
var _music_slider: HSlider
var _effects_slider: HSlider
var _stuck_button: Button
var _cal_sheet: PanelContainer
var _cal_step_label: Label
var _cal_hint_label: Label
var _cal_start_button: Button
var _cal_wave_label: Label
var _last_input_mode := ""
var _cal_stage_index := -1

const CAL_STAGES: Array[String] = ["room", "soft", "strong"]
const CAL_STAGE_COPY: Dictionary = {
	"room": "Step 1/3 — Stay quiet for a moment.",
	"soft": "Step 2/3 — Make a comfortable SOFT sound (Whisper).",
	"strong": "Step 3/3 — Now a comfortable STRONGER sound (Roar). No shouting.",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # usable while paused
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # playfield events pass through
	theme = RoarTheme.build()
	_build()


func _build() -> void:
	var safe := _safe_area_margins()

	# Dim focus blocker behind pause/result/calibration sheets (first child,
	# so every later sibling draws above it). STOP filter keeps stray taps
	# from reaching the playfield while a sheet is open.
	_sheet_blocker = ColorRect.new()
	_sheet_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sheet_blocker.color = Color(0.01, 0.04, 0.08, 0.5)
	_sheet_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet_blocker.visible = false
	add_child(_sheet_blocker)

	# --- Top Header: Compact glass pill, pause slot, no clipping ---
	_top_box = VBoxContainer.new()
	_top_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_box.offset_left = safe.left
	_top_box.offset_right = -safe.right
	_top_box.offset_top = safe.top
	_top_box.add_theme_constant_override("separation", 4)
	add_child(_top_box)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)
	_top_box.add_child(header_row)

	# 1. Left: Hole & Par pill card
	var header_pill := RoarTheme.make_pill_panel(RoarTheme.NAVY_PANEL, RoarTheme.NAVY_BORDER)
	header_pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header_pill)

	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 8)
	header_pill.add_child(info_row)

	var flag_icon := Label.new()
	flag_icon.text = "🚩"
	flag_icon.add_theme_font_size_override("font_size", 13)
	info_row.add_child(flag_icon)

	var hole_col := VBoxContainer.new()
	hole_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hole_col.add_theme_constant_override("separation", 0)
	info_row.add_child(hole_col)

	_hole_label = Label.new()
	_hole_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hole_label.add_theme_font_size_override("font_size", 12)
	hole_col.add_child(_hole_label)

	var sub_info := HBoxContainer.new()
	sub_info.add_theme_constant_override("separation", 6)
	hole_col.add_child(sub_info)

	_par_label = Label.new()
	_par_label.add_theme_color_override("font_color", RoarTheme.WARM_ACCENT)
	_par_label.add_theme_font_size_override("font_size", 11)
	sub_info.add_child(_par_label)

	_strokes_label = Label.new()
	_strokes_label.add_theme_color_override("font_color", RoarTheme.VOICE_CYAN)
	_strokes_label.add_theme_font_size_override("font_size", 11)
	sub_info.add_child(_strokes_label)

	# 2. Center: Stylized Roarball game logo badge (01_original_gameplay.png)
	var logo_pill := PanelContainer.new()
	var logo_style := StyleBoxFlat.new()
	logo_style.bg_color = Color(0.06, 0.14, 0.20, 0.85)
	logo_style.set_corner_radius_all(16)
	logo_style.border_color = RoarTheme.NAVY_BORDER
	logo_style.set_border_width_all(1)
	logo_style.shadow_color = Color(0, 0, 0, 0.3)
	logo_style.shadow_size = 6
	logo_style.content_margin_left = 10
	logo_style.content_margin_right = 10
	logo_style.content_margin_top = 3
	logo_style.content_margin_bottom = 3
	logo_pill.add_theme_stylebox_override("panel", logo_style)
	var logo_col := VBoxContainer.new()
	logo_col.alignment = BoxContainer.ALIGNMENT_CENTER
	logo_col.add_theme_constant_override("separation", -3)
	logo_pill.add_child(logo_col)

	var logo_title := Label.new()
	logo_title.text = "👑 Roarball"
	logo_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo_title.add_theme_color_override("font_color", RoarTheme.WARM_ACCENT)
	logo_title.add_theme_font_size_override("font_size", 14)
	logo_col.add_child(logo_title)

	var logo_sub := Label.new()
	logo_sub.text = "SMALL SHOTS · BIG ROARS"
	logo_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo_sub.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	logo_sub.add_theme_font_size_override("font_size", 7)
	logo_col.add_child(logo_sub)
	header_row.add_child(logo_pill)

	# 3. Right: Sleek Navy Pause button
	var pause_button := Button.new()
	pause_button.text = "❚❚"
	pause_button.custom_minimum_size = Vector2(44, 44)
	pause_button.focus_mode = Control.FOCUS_NONE
	var pause_box := StyleBoxFlat.new()
	pause_box.bg_color = RoarTheme.NAVY_PANEL
	pause_box.border_color = RoarTheme.NAVY_BORDER
	pause_box.set_border_width_all(2)
	pause_box.set_corner_radius_all(14)
	pause_box.shadow_color = Color(0, 0, 0, 0.35)
	pause_box.shadow_size = 6
	pause_button.add_theme_stylebox_override("normal", pause_box)
	pause_button.add_theme_stylebox_override("hover", pause_box)
	var pause_press := pause_box.duplicate() as StyleBoxFlat
	pause_press.bg_color = RoarTheme.NAVY_CARD
	pause_button.add_theme_stylebox_override("pressed", pause_press)
	pause_button.add_theme_color_override("font_color", RoarTheme.VOICE_CYAN)
	pause_button.add_theme_font_size_override("font_size", 15)
	pause_button.pressed.connect(func() -> void: pause_requested.emit())
	header_row.add_child(pause_button)

	_state_label = Label.new()
	_state_label.add_theme_color_override("font_color", RoarTheme.VOICE_CYAN)
	_state_label.add_theme_font_size_override("font_size", 12)
	_top_box.add_child(_state_label)

	# --- Bottom Control Tray: The Roarball Console (01_original_gameplay.png) ---
	_tray_panel = PanelContainer.new()
	_tray_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_tray_panel.offset_left = safe.left + 4
	_tray_panel.offset_right = -safe.right - 4
	_tray_panel.offset_top = -safe.bottom - 184
	_tray_panel.offset_bottom = -safe.bottom
	var tray_style := StyleBoxFlat.new()
	tray_style.bg_color = RoarTheme.NAVY_PANEL
	tray_style.set_corner_radius_all(24)
	tray_style.border_color = RoarTheme.NAVY_BORDER
	tray_style.set_border_width_all(2)
	tray_style.shadow_color = Color(0, 0, 0, 0.4)
	tray_style.shadow_size = 10
	tray_style.content_margin_left = 12
	tray_style.content_margin_right = 12
	tray_style.content_margin_top = 8
	tray_style.content_margin_bottom = 6
	_tray_panel.add_theme_stylebox_override("panel", tray_style)
	add_child(_tray_panel)

	_tray = VBoxContainer.new()
	_tray.add_theme_constant_override("separation", 4)
	_tray_panel.add_child(_tray)

	# 1. Status Bar with Soundwave Graphic
	var status_row := HBoxContainer.new()
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.add_theme_constant_override("separation", 8)
	_tray.add_child(status_row)

	_wave_label = Label.new()
	_wave_label.text = " ▂▃▅▆▇▆▅▃ "
	_wave_label.add_theme_color_override("font_color", RoarTheme.VOICE_CYAN)
	_wave_label.add_theme_font_size_override("font_size", 12)
	status_row.add_child(_wave_label)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", RoarTheme.TEXT_LIGHT)
	_status_label.add_theme_font_size_override("font_size", 13)
	status_row.add_child(_status_label)

	# 2. Main Action Console: [Strokes Badge]  [Center Mic / Slider]  [Power Meter]
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tray.add_child(action_row)

	# Left: Strokes Pill Badge
	var strokes_box := RoarTheme.make_pill_panel(RoarTheme.NAVY_CARD, RoarTheme.NAVY_BORDER)
	strokes_box.custom_minimum_size = Vector2(76, 76)
	var strokes_inner := VBoxContainer.new()
	strokes_inner.alignment = BoxContainer.ALIGNMENT_CENTER
	strokes_inner.add_theme_constant_override("separation", 2)
	var strokes_tag := Label.new()
	strokes_tag.text = tr("STROKES_HEADER")
	strokes_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	strokes_tag.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	strokes_tag.add_theme_font_size_override("font_size", 10)
	strokes_inner.add_child(strokes_tag)
	var strokes_num := Label.new()
	strokes_num.name = "StrokesNum"
	strokes_num.text = "0"
	strokes_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	strokes_num.add_theme_font_size_override("font_size", 24)
	strokes_inner.add_child(strokes_num)
	strokes_box.add_child(strokes_inner)
	action_row.add_child(strokes_box)

	# Center: Circular Glowing Mic (Voice) OR Slider + Shoot (Touch)
	_voice_box = HBoxContainer.new()
	_voice_box.add_theme_constant_override("separation", 8)
	_voice_box.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_child(_voice_box)

	_mic_button = RoarTheme.make_circular_mic_button(80)
	_mic_button.button_down.connect(_on_mic_down)
	_mic_button.button_up.connect(_on_mic_up)
	_voice_box.add_child(_mic_button)

	_touch_box = HBoxContainer.new()
	_touch_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_touch_box.add_theme_constant_override("separation", 8)
	action_row.add_child(_touch_box)

	_power_slider = HSlider.new()
	_power_slider.min_value = 1.0
	_power_slider.max_value = 100.0
	_power_slider.step = 1.0
	_power_slider.value = 50.0
	_power_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_power_slider.custom_minimum_size = Vector2(0, 48)
	_touch_box.add_child(_power_slider)

	_shoot_button = RoarTheme.make_flat_button(tr("SHOOT"))
	_shoot_button.custom_minimum_size = Vector2(88, 52)
	_shoot_button.pressed.connect(_on_shoot)
	_touch_box.add_child(_shoot_button)

	# Right: The "Whisper to Roar" Meter Box
	var meter_box := VBoxContainer.new()
	meter_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter_box.add_theme_constant_override("separation", 2)
	action_row.add_child(meter_box)

	_power_label = Label.new()
	_power_label.text = "Shot power 50%"
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_power_label.add_theme_font_size_override("font_size", 12)
	_power_label.add_theme_color_override("font_color", RoarTheme.TEXT_LIGHT)
	meter_box.add_child(_power_label)

	_power_bar = ProgressBar.new()
	_power_bar.min_value = 0.0
	_power_bar.max_value = 100.0
	_power_bar.show_percentage = false
	_power_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_power_bar.custom_minimum_size = Vector2(0, 22)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = RoarTheme.PRIMARY_GREEN
	bar_fill.set_corner_radius_all(10)
	bar_fill.border_color = Color("8EF8A0")
	bar_fill.set_border_width_all(1)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = RoarTheme.NAVY_CARD
	bar_bg.set_corner_radius_all(10)
	bar_bg.border_color = RoarTheme.NAVY_BORDER
	bar_bg.set_border_width_all(1)
	_power_bar.add_theme_stylebox_override("fill", bar_fill)
	_power_bar.add_theme_stylebox_override("background", bar_bg)
	meter_box.add_child(_power_bar)

	var sublabels_row := HBoxContainer.new()
	sublabels_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var whisper_tag := Label.new()
	whisper_tag.text = "🌿 WHISPER\nGentle"
	whisper_tag.add_theme_color_override("font_color", RoarTheme.PRIMARY_GREEN)
	whisper_tag.add_theme_font_size_override("font_size", 10)
	whisper_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sublabels_row.add_child(whisper_tag)

	var roar_tag := Label.new()
	roar_tag.text = "🦁 ROAR\nMax"
	roar_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	roar_tag.add_theme_color_override("font_color", RoarTheme.METER_ROAR)
	roar_tag.add_theme_font_size_override("font_size", 10)
	sublabels_row.add_child(roar_tag)
	meter_box.add_child(sublabels_row)

	# 3. Bottom Utility Row
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 8)
	_tray.add_child(bottom_row)

	_balls_button = RoarTheme.make_flat_button("🦁 Balls", true)
	_balls_button.custom_minimum_size = Vector2(86, 42)
	_balls_button.add_theme_font_size_override("font_size", 12)
	_balls_button.pressed.connect(func() -> void: AppRouter.goto_collection())
	bottom_row.add_child(_balls_button)

	_mode_chip = RoarTheme.make_flat_button("Voice 🎙", true)
	_mode_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_chip.custom_minimum_size = Vector2(96, 42)
	_mode_chip.add_theme_font_size_override("font_size", 12)
	_mode_chip.pressed.connect(_on_mode_chip)
	bottom_row.add_child(_mode_chip)

	_overview_button = RoarTheme.make_flat_button(tr("OVERVIEW"), true)
	_overview_button.custom_minimum_size = Vector2(96, 42)
	_overview_button.add_theme_font_size_override("font_size", 12)
	_overview_button.pressed.connect(func() -> void: overview_toggled.emit())
	bottom_row.add_child(_overview_button)

	_stuck_button = RoarTheme.make_flat_button("Stuck? +1", true)
	_stuck_button.custom_minimum_size = Vector2(88, 42)
	_stuck_button.add_theme_font_size_override("font_size", 12)
	_stuck_button.visible = false
	_stuck_button.pressed.connect(_on_stuck_recovery)
	bottom_row.add_child(_stuck_button)

	_save_banner = _make_banner(tr("SAVE_PROBLEM"), RoarTheme.DANGER)
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	_retry_save_button = RoarTheme.make_flat_button(tr("RETRY_SAVE"))
	_retry_save_button.pressed.connect(on_retry_save_pressed)
	save_row.add_child(_retry_save_button)
	_save_banner.add_child(save_row)
	_save_banner.visible = false
	add_child(_save_banner)

	_oob_banner = _make_banner(tr("OOB"), RoarTheme.WARM_ACCENT)
	_oob_banner.visible = false
	add_child(_oob_banner)

	_build_pause_layer()
	_build_result_layer()
	_build_calibration_sheet()


## Shared navy card look for the pause / result / calibration sheets.
func _card_style(panel: PanelContainer) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = RoarTheme.NAVY_PANEL
	box.border_color = RoarTheme.NAVY_BORDER
	box.set_border_width_all(2)
	box.set_corner_radius_all(24)
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 12
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 16
	box.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", box)


## Sheets are modal-feeling: the dim blocker shows whenever any of them does.
func _update_sheet_blocker() -> void:
	_sheet_blocker.visible = _pause_layer.visible or _result_layer.visible or _cal_sheet.visible


func _make_banner(text: String, color: Color) -> PanelContainer:
	var banner := PanelContainer.new()
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.anchor_left = 0.1
	banner.anchor_right = 0.9
	banner.offset_top = 80
	var box := StyleBoxFlat.new()
	box.bg_color = color.darkened(0.4)
	box.border_color = color
	box.set_border_width_all(2)
	box.set_corner_radius_all(14)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	banner.add_theme_stylebox_override("panel", box)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.add_child(label)
	return banner


func _build_pause_layer() -> void:
	_pause_layer = PanelContainer.new()
	_pause_layer.set_anchors_preset(Control.PRESET_CENTER)
	_pause_layer.anchor_left = 0.08
	_pause_layer.anchor_right = 0.92
	# Span most of the screen: the settings stack is taller than the old
	# auto-sized card, which pushed Quality/Reduced Motion off-screen.
	_pause_layer.anchor_top = 0.05
	_pause_layer.anchor_bottom = 0.95
	_pause_layer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card_style(_pause_layer)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pause_layer.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)

	var title := Label.new()
	title.text = "🦁  " + tr("PAUSED")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", RoarTheme.WARM_ACCENT)
	box.add_child(title)

	var resume := RoarTheme.make_flat_button(tr("RESUME"))
	resume.pressed.connect(func() -> void: resume_requested.emit())
	box.add_child(resume)

	var restart := RoarTheme.make_flat_button(tr("RESTART_HOLE"), true)
	restart.pressed.connect(_on_restart_pressed)
	box.add_child(restart)

	_pause_confirm_box = VBoxContainer.new()
	_pause_confirm_box.add_theme_constant_override("separation", 6)
	_pause_confirm_box.visible = false
	box.add_child(_pause_confirm_box)
	var confirm_label := Label.new()
	confirm_label.text = tr("CONFIRM_ABANDON")
	confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pause_confirm_box.add_child(confirm_label)
	var confirm_yes := RoarTheme.make_flat_button(tr("CONFIRM_YES"), true)
	confirm_yes.pressed.connect(func() -> void:
		_pause_confirm_box.visible = false
		resume_requested.emit()
		restart_requested.emit()
	)
	_pause_confirm_box.add_child(confirm_yes)
	var confirm_no := RoarTheme.make_flat_button(tr("CONFIRM_NO"), true)
	confirm_no.pressed.connect(func() -> void: _pause_confirm_box.visible = false)
	_pause_confirm_box.add_child(confirm_no)

	var to_map := RoarTheme.make_flat_button(tr("MAP"), true)
	to_map.pressed.connect(func() -> void:
		resume_requested.emit()
		map_requested.emit()
	)
	box.add_child(to_map)

	# --- Input & Sound (UI-09) ---
	var settings_title := Label.new()
	settings_title.text = tr("INPUT_SOUND")
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_title.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	box.add_child(settings_title)

	_mode_switch_button = RoarTheme.make_flat_button("", true)
	_mode_switch_button.pressed.connect(func() -> void:
		SettingsStore.set_input_mode("touch" if SettingsStore.is_voice_mode() else "voice")
		_refresh_pause_settings())
	box.add_child(_mode_switch_button)

	var music_row := HBoxContainer.new()
	music_row.add_theme_constant_override("separation", 8)
	box.add_child(music_row)
	var music_label := Label.new()
	music_label.text = "Music"
	music_label.custom_minimum_size = Vector2(64, 24)
	music_row.add_child(music_label)
	_music_slider = HSlider.new()
	_music_slider.min_value = 0.0
	_music_slider.max_value = 1.0
	_music_slider.step = 0.05
	_music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_music_slider.value = float(SettingsStore.settings.get("music_volume", 0.7))
	_music_slider.value_changed.connect(func(v: float) -> void:
		SettingsStore.set_volumes(v, float(SettingsStore.settings.get("effects_volume", 0.8))))
	music_row.add_child(_music_slider)

	var effects_row := HBoxContainer.new()
	effects_row.add_theme_constant_override("separation", 8)
	box.add_child(effects_row)
	var effects_label := Label.new()
	effects_label.text = "Effects"
	effects_label.custom_minimum_size = Vector2(64, 24)
	effects_row.add_child(effects_label)
	_effects_slider = HSlider.new()
	_effects_slider.min_value = 0.0
	_effects_slider.max_value = 1.0
	_effects_slider.step = 0.05
	_effects_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effects_slider.value = float(SettingsStore.settings.get("effects_volume", 0.8))
	_effects_slider.value_changed.connect(func(v: float) -> void:
		SettingsStore.set_volumes(float(SettingsStore.settings.get("music_volume", 0.7)), v))
	effects_row.add_child(_effects_slider)

	_quality_button = RoarTheme.make_flat_button("", true)
	_quality_button.pressed.connect(func() -> void:
		var next_quality: String = {"low": "medium", "medium": "high", "high": "low"}.get(SettingsStore.quality(), "medium")
		SettingsStore.set_quality(next_quality)
		_refresh_pause_settings())
	box.add_child(_quality_button)

	_motion_button = RoarTheme.make_flat_button("", true)
	_motion_button.pressed.connect(func() -> void:
		SettingsStore.set_flag("reduced_motion", not SettingsStore.reduced_motion())
		_refresh_pause_settings())
	box.add_child(_motion_button)

	_recal_button = RoarTheme.make_flat_button(tr("RECALIBRATE"), true)
	_recal_button.pressed.connect(func() -> void:
		resume_requested.emit()
		open_calibration_sheet())
	box.add_child(_recal_button)

	_refresh_pause_settings()
	_pause_layer.visible = false
	add_child(_pause_layer)


func _build_result_layer() -> void:
	_result_layer = PanelContainer.new()
	_result_layer.set_anchors_preset(Control.PRESET_CENTER)
	_result_layer.anchor_left = 0.1
	_result_layer.anchor_right = 0.9
	_result_layer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card_style(_result_layer)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_result_layer.add_child(box)

	_result_title = Label.new()
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_title.add_theme_font_size_override("font_size", 26)
	_result_title.add_theme_color_override("font_color", RoarTheme.WARM_ACCENT)
	box.add_child(_result_title)

	# Fixed-size star cells so the pop animation never reflows the sheet.
	var star_row := HBoxContainer.new()
	star_row.alignment = BoxContainer.ALIGNMENT_CENTER
	star_row.add_theme_constant_override("separation", 10)
	box.add_child(star_row)
	for i: int in 3:
		var star := Label.new()
		star.text = "★"
		star.custom_minimum_size = Vector2(52, 56)
		star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		star.pivot_offset = Vector2(26, 28)
		star.add_theme_font_size_override("font_size", 40)
		star.add_theme_color_override("font_color", RoarTheme.NAVY_BORDER)
		star_row.add_child(star)
		_star_labels.append(star)

	_result_detail = Label.new()
	_result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_detail.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	box.add_child(_result_detail)

	var next := RoarTheme.make_hero_play_button("▶  " + tr("NEXT_HOLE"))
	next.pressed.connect(func() -> void: next_hole_requested.emit())
	box.add_child(next)

	var buttons_row := HBoxContainer.new()
	buttons_row.add_theme_constant_override("separation", 8)
	box.add_child(buttons_row)

	var retry := RoarTheme.make_flat_button(tr("RETRY"), true)
	retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retry.pressed.connect(func() -> void:
		_result_layer.visible = false
		_update_sheet_blocker()
		restart_requested.emit()
	)
	buttons_row.add_child(retry)

	var result_map := RoarTheme.make_flat_button(tr("MAP"), true)
	result_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_map.pressed.connect(func() -> void: map_requested.emit())
	buttons_row.add_child(result_map)

	_result_layer.visible = false
	add_child(_result_layer)


## Calibration Sheet (UI-04) faithfully matching 04_calibration.png:
## - "Calibrate Your Voice — Find your whisper and your roar!"
## - Real-time animated audio waveform visualizer
## - Whisper -> Speak -> Roar segmented color bar
## - Circular glowing microphone button to tap and test
func _build_calibration_sheet() -> void:
	_cal_sheet = PanelContainer.new()
	_cal_sheet.set_anchors_preset(Control.PRESET_CENTER)
	_cal_sheet.anchor_left = 0.06
	_cal_sheet.anchor_right = 0.94
	_cal_sheet.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card_style(_cal_sheet)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_cal_sheet.add_child(box)

	var title := Label.new()
	title.text = tr("CAL_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", RoarTheme.WARM_ACCENT)
	box.add_child(title)

	var sub := Label.new()
	sub.text = "Find your whisper and your roar!\nYour voice controls the shot power."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	sub.add_theme_font_size_override("font_size", 13)
	box.add_child(sub)

	# Sound wave visualizer in calibration
	_cal_wave_label = Label.new()
	_cal_wave_label.text = "  ▂▃▅▆▇█▇▆▅▃▂  "
	_cal_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cal_wave_label.add_theme_color_override("font_color", RoarTheme.VOICE_CYAN)
	_cal_wave_label.add_theme_font_size_override("font_size", 16)
	box.add_child(_cal_wave_label)

	_cal_step_label = Label.new()
	_cal_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cal_step_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cal_step_label.add_theme_font_size_override("font_size", 14)
	box.add_child(_cal_step_label)

	_cal_hint_label = Label.new()
	_cal_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cal_hint_label.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	_cal_hint_label.add_theme_font_size_override("font_size", 12)
	box.add_child(_cal_hint_label)

	_cal_start_button = RoarTheme.make_hero_play_button("🎙  Start")
	_cal_start_button.pressed.connect(_on_cal_start)
	box.add_child(_cal_start_button)

	var privacy := Label.new()
	privacy.text = tr("CAL_PRIVACY")
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	privacy.add_theme_font_size_override("font_size", 11)
	box.add_child(privacy)

	var use_touch := RoarTheme.make_flat_button(tr("USE_TOUCH"), true)
	use_touch.pressed.connect(func() -> void:
		SettingsStore.set_input_mode("touch")
		_close_calibration_sheet()
		_refresh_input_mode()
	)
	box.add_child(use_touch)

	_cal_sheet.visible = false
	add_child(_cal_sheet)


func open_calibration_sheet() -> void:
	_cal_stage_index = 0
	_update_calibration_copy("")
	_cal_sheet.visible = true
	_update_sheet_blocker()


func _close_calibration_sheet() -> void:
	_cal_stage_index = -1
	_cal_sheet.visible = false
	_update_sheet_blocker()
	if gameplay != null and gameplay.has_method("cancel_calibration_stage"):
		gameplay.call("cancel_calibration_stage")


func _update_calibration_copy(hint: String) -> void:
	if _cal_stage_index < 0 or _cal_stage_index >= CAL_STAGES.size():
		return
	_cal_step_label.text = String(CAL_STAGE_COPY[CAL_STAGES[_cal_stage_index]])
	_cal_hint_label.text = hint
	_cal_start_button.text = "🎙  Start"


func _on_cal_start() -> void:
	if gameplay == null or not gameplay.has_method("start_calibration_stage"):
		return
	if _cal_stage_index < 0:
		return
	_cal_start_button.disabled = true
	_cal_hint_label.text = "Listening..."
	var ok: bool = gameplay.call("start_calibration_stage", CAL_STAGES[_cal_stage_index])
	if not ok:
		_cal_start_button.disabled = false
		_cal_hint_label.text = "Microphone not available. You can use Touch."
		return


func on_calibration_stage_done(summary: Dictionary) -> void:
	_cal_start_button.disabled = false
	if not bool(summary.get("ok", false)):
		_update_calibration_copy(_error_copy(String(summary.get("error_code", ""))))
		return
	_cal_stage_index += 1
	if _cal_stage_index >= CAL_STAGES.size():
		_close_calibration_sheet()
		_status_label.text = tr("CALIBRATED")
		return
	_update_calibration_copy("Got it.")


func _safe_area_margins() -> Dictionary:
	var area := DisplayServer.get_display_safe_area()
	var window_size := DisplayServer.window_get_size()
	var usable := window_size.x > 0 and window_size.y > 0 and area.size.x > 0 and area.size.y > 0
	usable = usable and area.position.x >= 0 and area.position.y >= 0 and area.end.x <= window_size.x and area.end.y <= window_size.y
	var insets := {"left": 0.0, "right": 0.0, "top": 0.0, "bottom": 0.0}
	if usable:
		insets["left"] = float(area.position.x)
		insets["right"] = float(maxi(window_size.x - area.end.x, 0))
		insets["top"] = float(area.position.y)
		insets["bottom"] = float(maxi(window_size.y - area.end.y, 0))
	var out: Dictionary = {}
	for key: String in insets:
		out[key] = clampf(float(insets[key]), 0.0, 48.0) + 8.0
	return out


func bind(p_session: GameSessionController, p_coordinator: InputCoordinator, p_voice: VoiceInputService, p_camera: CameraRig) -> void:
	session = p_session
	coordinator = p_coordinator
	voice = p_voice
	camera_rig = p_camera
	coordinator.hud = self
	coordinator.aim_gesture_changed.connect(_on_aim_gesture)
	session.session_state_changed.connect(_on_state)
	session.strokes_changed.connect(_on_strokes)
	session.hole_completed.connect(_on_hole_completed)
	session.attempt_finished.connect(_on_attempt_finished)
	session.save_warning.connect(func() -> void: _save_banner.visible = true)
	session.stuck_recovery_changed.connect(func(available: bool) -> void: _stuck_button.visible = available)
	if voice != null:
		voice.status_updated.connect(_on_voice_status)
	_on_strokes(session.strokes)
	_on_state(GameStateMachine.state_name(session.fsm.state))
	_refresh_input_mode()


func _process(delta: float) -> void:
	if session == null:
		return
	_update_power_display()
	_refresh_input_mode()
	_animate_audio_feedback(delta)


## Animate the mic pulse and sound equalizer based on microphone activity
func _animate_audio_feedback(delta: float) -> void:
	_wave_tick += delta * 8.0
	var waves := [
		" ▂▃▅▆▇▆▅▃ ",
		"▂▃▅▆▇█▇▆▅ ",
		"▃▅▆▇█▇▆▅▃▂",
		"▅▆▇█▇▆▅▃▂ ",
		"▆▇▆▅▃▂ ▂▃▅"
	]
	var idx := int(_wave_tick) % waves.size()
	if voice != null and voice.is_listening():
		if _wave_label != null:
			_wave_label.text = waves[idx]
			_wave_label.add_theme_color_override("font_color", RoarTheme.VOICE_CYAN)
		if _cal_wave_label != null:
			_cal_wave_label.text = waves[idx]
		if _mic_button != null:
			_mic_button.text = "🎙 LISTENING!"
	else:
		if _wave_label != null:
			_wave_label.text = " — — — "
			_wave_label.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
		if _mic_button != null:
			_mic_button.text = "🎙 ROAR!"


## FR-04: power displayed must match what will be committed
func _update_power_display() -> void:
	var power := 0.0
	if coordinator != null and coordinator.is_slinging():
		power = coordinator.slingshot_power()
	elif voice != null and voice.is_listening():
		power = float(voice.published_preview()["power"])
	elif session.fsm.state in [
		GameStateMachine.State.ROLLING,
		GameStateMachine.State.SETTLING,
		GameStateMachine.State.COMMIT_PENDING,
	]:
		power = session.last_committed_power
	elif SettingsStore.input_mode() == "touch":
		power = _power_slider.value / 100.0

	_power_bar.value = power * 100.0
	_power_label.text = "Shot power %d%%" % roundi(power * 100.0)

	# Dynamic meter coloring: green for whisper, orange for speak, red for roar
	var fill_style := _power_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style != null:
		if power < 0.35:
			fill_style.bg_color = RoarTheme.METER_WHISPER
		elif power < 0.70:
			fill_style.bg_color = RoarTheme.METER_SPEAK
		else:
			fill_style.bg_color = RoarTheme.METER_ROAR


func _refresh_input_mode() -> void:
	var mode := SettingsStore.input_mode()
	if mode == _last_input_mode:
		return
	_last_input_mode = mode
	_touch_box.visible = mode == "touch"
	_voice_box.visible = mode == "voice"
	_mode_chip.text = "Voice 🎙" if mode == "voice" else "Touch 👆"
	if mode != "voice" and coordinator != null:
		coordinator.interrupt_capture()


func _on_state(state_name: String) -> void:
	_state_label.text = state_name.to_lower()
	# The tray status line carries all player guidance; the floating state
	# word only earns screen space during transitions (rolling/settling).
	_state_label.visible = state_name.to_lower() != "ready"
	var rolling := session.fsm.state in [
		GameStateMachine.State.ROLLING,
		GameStateMachine.State.SETTLING,
		GameStateMachine.State.COMMIT_PENDING,
	]
	_shoot_button.disabled = rolling or session.fsm.state != GameStateMachine.State.READY
	_power_slider.editable = not rolling
	_mic_button.disabled = rolling
	if rolling:
		_status_label.text = tr("BALL_MOVING")
	elif session.fsm.state == GameStateMachine.State.READY:
		_show_ready_copy()


func _show_ready_copy() -> void:
	if SettingsStore.is_voice_mode():
		_status_label.text = "Hold mic & sound to shoot!"
	else:
		_status_label.text = "Touch & drag anywhere: pull back, release!"


## Live slingshot feedback while the player stretches a shot.
func _on_aim_gesture(active: bool, power: float, valid: bool) -> void:
	if session.fsm.state != GameStateMachine.State.READY:
		return
	if not active:
		_show_ready_copy()  # drag canceled without a shot
		return
	if valid:
		_status_label.text = "Release to shoot!  %d%%" % roundi(power * 100.0)
	else:
		_status_label.text = "Keep dragging to charge..."


func _on_strokes(count: int) -> void:
	_strokes_label.text = tr("STROKES_COUNT") % count
	if _tray != null:
		var strokes_num: Label = _tray.find_child("StrokesNum", true, false)
		if strokes_num != null:
			strokes_num.text = str(count)


func set_hole_info(title: String, par: int) -> void:
	_hole_label.text = title
	_par_label.text = tr("PAR") % par


func _on_voice_status(status: Dictionary) -> void:
	match String(status["phase"]):
		"STARTING":
			_status_label.text = tr("STARTING_MIC")
		"LISTENING":
			_status_label.text = "Listening... 🔊 WHISPER to ROAR!"
		_:
			_status_label.text = _error_copy(String(status["error_code"]))


func _error_copy(code: String) -> String:
	match code:
		"permission_denied":
			return "Microphone not available. Touch works fully."
		"needs_calibration":
			return "Calibrate first — one short setup, comfortable sounds only."
		"no_input":
			return "We couldn't detect a usable sound. Try again or use touch."
		"too_noisy":
			return "Too noisy here. Try a quieter place, recalibrate, or use touch."
		"timeout":
			return "Try a short sound — release within 3 seconds."
		"buffer_overrun":
			return "Audio problem — shot canceled. Try again."
		"route_changed":
			return "Audio route changed — shot canceled."
		"range_too_small", "soft_too_quiet", "insufficient_data", "clipping", "invalid_signal":
			return "That didn't give a usable range. Try again (comfortable sounds), or use Touch."
		_:
			return ""


func _on_shoot() -> void:
	if coordinator == null:
		return
	AudioDirector.play_effect("click")
	var power := _power_slider.value / 100.0
	coordinator.touch_shoot(power)


func _on_mic_down() -> void:
	if coordinator != null:
		coordinator.voice_hold_started()


func _on_mic_up() -> void:
	if coordinator == null:
		return
	var pointer := get_viewport().get_mouse_position()
	if _mic_button.get_global_rect().grow(28.0).has_point(pointer):
		coordinator.voice_release_inside()
	else:
		coordinator.voice_release_outside()


func _on_mode_chip() -> void:
	coordinator.interrupt_capture()
	if SettingsStore.is_voice_mode():
		SettingsStore.set_input_mode("touch")
	else:
		SettingsStore.set_input_mode("voice")
		if not SettingsStore.has_valid_calibration():
			open_calibration_sheet()
	_refresh_input_mode()


func _on_stuck_recovery() -> void:
	if session != null:
		session.request_stuck_recovery()


func _refresh_pause_settings() -> void:
	_mode_switch_button.text = tr("INPUT_SWITCH") % ("Voice" if SettingsStore.is_voice_mode() else "Touch")
	_quality_button.text = tr("QUALITY_BUTTON") % SettingsStore.quality()
	_motion_button.text = tr("REDUCED_MOTION_ON") if SettingsStore.reduced_motion() else tr("REDUCED_MOTION_OFF")
	_recal_button.visible = SettingsStore.is_voice_mode()


func _on_restart_pressed() -> void:
	if session != null and session.strokes > 0:
		_pause_confirm_box.visible = true
		return
	_pause_confirm_box.visible = false
	resume_requested.emit()
	restart_requested.emit()


func on_retry_save_pressed() -> void:
	if ProgressStore.retry_save():
		_save_banner.visible = false


func show_out_of_bounds() -> void:
	_oob_banner.visible = true
	var timer := get_tree().create_timer(2.5, true)
	timer.timeout.connect(func() -> void: _oob_banner.visible = false)


func show_pause() -> void:
	_pause_layer.visible = true
	_update_sheet_blocker()


func hide_pause() -> void:
	_pause_layer.visible = false
	_update_sheet_blocker()


func is_paused_sheet_visible() -> bool:
	return _pause_layer.visible


func set_overview_indicator(active: bool) -> void:
	_overview_button.text = "Resume" if active else tr("OVERVIEW")


func _on_hole_completed(result: Dictionary) -> void:
	_result_title.text = tr("HOLE_COMPLETE")
	var stars := int(result["stars"])
	var detail := "%d strokes · par %d" % [int(result["strokes"]), int(result["par"])]
	if bool(result.get("is_new_best", false)):
		detail = "🏆 " + detail + " · " + tr("NEW_BEST")
	_result_detail.text = detail
	for i: int in _star_labels.size():
		var star := _star_labels[i]
		star.scale = Vector2.ONE
		star.modulate = Color(1, 1, 1, 1)
		star.add_theme_color_override("font_color",
			RoarTheme.WARM_ACCENT if i < stars else RoarTheme.NAVY_BORDER)
	_result_layer.visible = true
	_update_sheet_blocker()
	_animate_stars(stars)


func _on_attempt_finished() -> void:
	_result_title.text = tr("ATTEMPT_DONE")
	_result_detail.text = tr("STROKE_LIMIT")
	for star: Label in _star_labels:
		star.scale = Vector2.ONE
		star.modulate = Color(1, 1, 1, 1)
		star.add_theme_color_override("font_color", RoarTheme.NAVY_BORDER)
	_result_layer.visible = true
	_update_sheet_blocker()


## Stars pop in one by one (gold), each with a little chime; unearned cells
## stay dim. Skipped entirely under reduced motion.
func _animate_stars(stars: int) -> void:
	if SettingsStore.reduced_motion() or stars <= 0:
		return
	for i: int in stars:
		var star := _star_labels[i]
		star.modulate = Color(1, 1, 1, 0)
		star.scale = Vector2(0.2, 0.2)
	for i: int in stars:
		var star := _star_labels[i]
		var tw := create_tween()
		tw.tween_interval(0.25 + i * 0.24)
		tw.tween_callback(func() -> void: AudioDirector.play_effect("click", 0.5 + 0.12 * i))
		tw.parallel().tween_property(star, "modulate:a", 1.0, 0.15)
		tw.parallel().tween_property(star, "scale", Vector2(1.28, 1.28), 0.15)
		tw.chain().tween_property(star, "scale", Vector2.ONE, 0.12)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _result_layer.visible:
		return
	get_viewport().set_input_as_handled()
	if _cal_sheet.visible:
		_close_calibration_sheet()
		SettingsStore.set_input_mode("touch")
		_refresh_input_mode()
		return
	if _pause_layer.visible:
		resume_requested.emit()
	else:
		pause_requested.emit()
