class_name HUDPresenter
extends Control
## Graybox gameplay HUD (RB-018 subset). Displays immutable session/view data
## and emits intents through InputCoordinator — it never touches the ball,
## strokes, or saves directly. Text + icon indicate voice state, never color
## alone (docs/01 §8). Safe-area margins come from the OS, mapped into canvas
## coordinates (docs/06 §5).

signal pause_requested()
signal restart_requested()
signal map_requested()
signal next_hole_requested()

var session: GameSessionController
var coordinator: InputCoordinator
var voice: VoiceInputService
var camera_rig: CameraRig

var _top_bar: HBoxContainer
var _hole_label: Label
var _par_label: Label
var _strokes_label: Label
var _state_label: Label
var _tray: VBoxContainer
var _mode_chip: Button
var _power_bar: ProgressBar
var _power_label: Label
var _touch_box: HBoxContainer
var _power_slider: HSlider
var _shoot_button: Button
var _voice_box: HBoxContainer
var _mic_button: Button
var _cancel_region: PanelContainer
var _cancel_label: Label
var _overview_button: Button
var _status_label: Label
var _pause_layer: PanelContainer
var _result_layer: PanelContainer
var _result_title: Label
var _result_stars: Label
var _result_detail: Label
var _save_banner: PanelContainer
var _stuck_button: Button
var _last_input_mode := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visibility_changed.connect(_on_visibility)


func _on_visibility() -> void:
	if not is_visible_in_tree() and coordinator != null:
		coordinator.interrupt_capture()


func _build() -> void:
	var safe := _safe_area_margins()
	_top_bar = HBoxContainer.new()
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_bar.offset_left = safe.left
	_top_bar.offset_right = -safe.right
	_top_bar.offset_top = safe.top
	_top_bar.offset_bottom = safe.top + 48
	_top_bar.add_theme_constant_override("separation", 12)
	add_child(_top_bar)

	var info_panel := PanelContainer.new()
	_top_bar.add_child(info_panel)
	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 16)
	info_panel.add_child(info_row)
	_hole_label = Label.new()
	_par_label = Label.new()
	_strokes_label = Label.new()
	_state_label = Label.new()
	_state_label.add_theme_color_override("font_color", RoarTheme.VOICE_CYAN)
	for label: Label in [_hole_label, _par_label, _strokes_label, _state_label]:
		info_row.add_child(label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_bar.add_child(spacer)
	var pause_button := RoarTheme.make_flat_button("II")
	pause_button.custom_minimum_size = Vector2(48, 48)
	pause_button.pressed.connect(_on_pause_pressed)
	_top_bar.add_child(pause_button)

	# --- Bottom control tray, thumb-reachable ---
	_tray = VBoxContainer.new()
	_tray.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_tray.offset_left = safe.left + 8
	_tray.offset_right = -safe.right - 8
	_tray.offset_top = -safe.bottom - 168
	_tray.offset_bottom = -safe.bottom
	_tray.add_theme_constant_override("separation", 8)
	add_child(_tray)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	_tray.add_child(_status_label)

	var power_row := HBoxContainer.new()
	power_row.add_theme_constant_override("separation", 8)
	_tray.add_child(power_row)
	_power_bar = ProgressBar.new()
	_power_bar.min_value = 0.0
	_power_bar.max_value = 100.0
	_power_bar.show_percentage = false
	_power_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_power_bar.custom_minimum_size = Vector2(0, 24)
	power_row.add_child(_power_bar)
	_power_label = Label.new()
	_power_label.custom_minimum_size = Vector2(84, 24)
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	power_row.add_child(_power_label)

	_touch_box = HBoxContainer.new()
	_touch_box.add_theme_constant_override("separation", 8)
	_tray.add_child(_touch_box)
	_power_slider = HSlider.new()
	_power_slider.min_value = 1.0
	_power_slider.max_value = 100.0
	_power_slider.step = 1.0
	_power_slider.value = 50.0
	_power_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_power_slider.custom_minimum_size = Vector2(0, 48)
	_touch_box.add_child(_power_slider)
	_shoot_button = RoarTheme.make_flat_button("Shoot")
	_shoot_button.custom_minimum_size = Vector2(96, 56)
	_shoot_button.pressed.connect(_on_shoot)
	_touch_box.add_child(_shoot_button)

	_voice_box = HBoxContainer.new()
	_voice_box.add_theme_constant_override("separation", 8)
	_tray.add_child(_voice_box)
	_mic_button = RoarTheme.make_flat_button("MIC\nHOLD")
	_mic_button.custom_minimum_size = Vector2(80, 80)
	_mic_button.button_down.connect(_on_mic_down)
	_mic_button.button_up.connect(_on_mic_up)
	_voice_box.add_child(_mic_button)
	_cancel_region = PanelContainer.new()
	_cancel_region.custom_minimum_size = Vector2(140, 80)
	_cancel_label = Label.new()
	_cancel_label.text = "Slide here\nto cancel"
	_cancel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cancel_region.add_child(_cancel_label)
	_voice_box.add_child(_cancel_region)

	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 8)
	_tray.add_child(bottom_row)
	_mode_chip = RoarTheme.make_flat_button("Touch", true)
	_mode_chip.custom_minimum_size = Vector2(96, 48)
	_mode_chip.pressed.connect(_on_mode_chip)
	bottom_row.add_child(_mode_chip)
	_overview_button = RoarTheme.make_flat_button("Overview", true)
	_overview_button.custom_minimum_size = Vector2(110, 48)
	_overview_button.pressed.connect(_on_overview)
	bottom_row.add_child(_overview_button)
	_stuck_button = RoarTheme.make_flat_button("Stuck? +1", true)
	_stuck_button.custom_minimum_size = Vector2(120, 48)
	_stuck_button.visible = false
	_stuck_button.pressed.connect(_on_stuck_recovery)
	bottom_row.add_child(_stuck_button)

	_save_banner = _make_banner("Save problem — progress may not be kept.", RoarTheme.DANGER)
	_save_banner.visible = false
	add_child(_save_banner)

	_build_pause_layer()
	_build_result_layer()


func _make_banner(text: String, color: Color) -> PanelContainer:
	var banner := PanelContainer.new()
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.anchor_left = 0.1
	banner.anchor_right = 0.9
	banner.offset_top = 90
	var box := StyleBoxFlat.new()
	box.bg_color = color.darkened(0.55)
	box.set_corner_radius_all(12)
	banner.add_theme_stylebox_override("panel", box)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(label)
	return banner


func _build_pause_layer() -> void:
	_pause_layer = PanelContainer.new()
	_pause_layer.set_anchors_preset(Control.PRESET_CENTER)
	_pause_layer.anchor_left = 0.08
	_pause_layer.anchor_right = 0.92
	_pause_layer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_pause_layer.add_child(box)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var resume := RoarTheme.make_flat_button("Resume")
	resume.pressed.connect(_on_resume)
	box.add_child(resume)
	var restart := RoarTheme.make_flat_button("Restart Hole", true)
	restart.pressed.connect(func() -> void:
		_on_resume()
		restart_requested.emit()
	)
	box.add_child(restart)
	var to_map := RoarTheme.make_flat_button("Map", true)
	to_map.pressed.connect(func() -> void:
		_on_resume()
		map_requested.emit()
	)
	box.add_child(to_map)
	_pause_layer.visible = false
	add_child(_pause_layer)


func _build_result_layer() -> void:
	_result_layer = PanelContainer.new()
	_result_layer.set_anchors_preset(Control.PRESET_CENTER)
	_result_layer.anchor_left = 0.08
	_result_layer.anchor_right = 0.92
	_result_layer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_result_layer.add_child(box)
	_result_title = Label.new()
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_title)
	_result_stars = Label.new()
	_result_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_stars)
	_result_detail = Label.new()
	_result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_detail)
	var next := RoarTheme.make_flat_button("Next Hole")
	next.pressed.connect(func() -> void: next_hole_requested.emit())
	box.add_child(next)
	var retry := RoarTheme.make_flat_button("Retry", true)
	retry.pressed.connect(func() -> void:
		_result_layer.visible = false
		restart_requested.emit()
	)
	box.add_child(retry)
	var result_map := RoarTheme.make_flat_button("Map", true)
	result_map.pressed.connect(func() -> void: map_requested.emit())
	box.add_child(result_map)
	_result_layer.visible = false
	add_child(_result_layer)


func _safe_area_margins() -> Dictionary:
	var area := DisplayServer.get_display_safe_area()
	var window_size := DisplayServer.window_get_size()
	if window_size.x <= 0 or window_size.y <= 0 or area.size.x <= 0 or area.size.y <= 0:
		return {"left": 16.0, "right": 16.0, "top": 16.0, "bottom": 16.0}
	var scale := get_viewport().get_visible_rect().size / Vector2(window_size)
	var scale_avg := (scale.x + scale.y) * 0.5
	return {
		"left": maxf(area.position.x, 0) * scale_avg + 8,
		"right": maxf(window_size.x - area.end.x, 0) * scale_avg + 8,
		"top": maxf(area.position.y, 0) * scale_avg + 8,
		"bottom": maxf(window_size.y - area.end.y, 0) * scale_avg + 8,
	}


# --- Session wiring ---


func bind(p_session: GameSessionController, p_coordinator: InputCoordinator, p_voice: VoiceInputService, p_camera: CameraRig) -> void:
	session = p_session
	coordinator = p_coordinator
	voice = p_voice
	camera_rig = p_camera
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


func _process(_delta: float) -> void:
	if session == null:
		return
	var power := session.last_committed_power
	if voice != null and coordinator != null and voice.is_listening():
		power = float(voice.published_preview()["power"])
	_power_bar.value = power * 100.0
	_power_label.text = "Shot power %d%%" % roundi(power * 100.0)
	_refresh_input_mode()


func _refresh_input_mode() -> void:
	var mode := SettingsStore.input_mode()
	if mode == _last_input_mode:
		return
	_last_input_mode = mode
	_touch_box.visible = mode == "touch"
	_voice_box.visible = mode == "voice"
	_mode_chip.text = "Voice" if mode == "voice" else "Touch"
	if mode != "voice" and coordinator != null:
		coordinator.interrupt_capture()


func _on_state(state_name: String) -> void:
	_state_label.text = state_name.to_lower()
	var rolling := session.fsm.state in [
		GameStateMachine.State.ROLLING,
		GameStateMachine.State.SETTLING,
		GameStateMachine.State.COMMIT_PENDING,
	]
	_shoot_button.disabled = rolling or session.fsm.state != GameStateMachine.State.READY
	_power_slider.editable = not rolling
	_mic_button.disabled = rolling
	if rolling:
		_status_label.text = "Ball moving"


func _on_strokes(count: int) -> void:
	_strokes_label.text = "Strokes %d/%d" % [count, session.max_strokes]


func set_hole_info(title: String, par: int) -> void:
	_hole_label.text = title
	_par_label.text = "Par %d" % par


func _on_voice_status(status: Dictionary) -> void:
	match String(status["phase"]):
		"STARTING":
			_status_label.text = "Starting mic..."
		"LISTENING":
			_status_label.text = "Listening — hold, sound, release"
		_:
			_status_label.text = _error_copy(String(status["error_code"]))


func _error_copy(code: String) -> String:
	match code:
		"permission_denied":
			return "Microphone not available. Touch works fully."
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
		_:
			return ""


# --- Input handlers (intents only) ---


func _on_shoot() -> void:
	if coordinator == null:
		return
	var power := _power_slider.value / 100.0
	coordinator.touch_shoot(power)


func _on_mic_down() -> void:
	if coordinator != null:
		coordinator.voice_hold_started()


func _on_mic_up() -> void:
	if coordinator == null:
		return
	# Release inside the mic button commits; anywhere else is the cancel path.
	var pointer := get_viewport().get_mouse_position()
	var button_rect := _mic_button.get_global_rect()
	if button_rect.grow(24.0).has_point(pointer):
		coordinator.voice_release_inside()
	else:
		coordinator.voice_release_outside()


func _on_mode_chip() -> void:
	coordinator.interrupt_capture()
	SettingsStore.set_input_mode("touch" if SettingsStore.is_voice_mode() else "voice")
	_refresh_input_mode()


func _on_overview() -> void:
	if camera_rig != null:
		camera_rig.toggle_overview()
	_overview_button.text = "Resume view" if camera_rig.is_overview() else "Overview"


func _on_stuck_recovery() -> void:
	if session != null:
		session.request_stuck_recovery()


func _on_pause_pressed() -> void:
	pause_requested.emit()


func _on_resume() -> void:
	if camera_rig != null:
		camera_rig.force_close_overview()
		_overview_button.text = "Overview"
	_pause_layer.visible = false
	get_tree().paused = false


func show_pause() -> void:
	_pause_layer.visible = true
	get_tree().paused = true


func _on_hole_completed(result: Dictionary) -> void:
	_result_title.text = "Hole Complete!"
	_result_stars.text = "*".repeat(int(result["stars"]))
	var detail := "%d strokes · par %d" % [int(result["strokes"]), int(result["par"])]
	if bool(result.get("is_new_best", false)):
		detail += " · New Best"
	_result_detail.text = detail
	_result_layer.visible = true


func _on_attempt_finished() -> void:
	_result_title.text = "Attempt Finished"
	_result_stars.text = ""
	_result_detail.text = "Stroke limit reached."
	_result_layer.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and session != null:
		if _result_layer.visible:
			return  # results own navigation
		if _pause_layer.visible:
			_on_resume()
		else:
			show_pause()
