class_name HUDPresenter
extends Control
## Graybox gameplay HUD (RB-018 subset). Displays immutable session/view data
## and emits intents through InputCoordinator / GameRoot — it never touches
## the ball, strokes, or saves directly.
##
## Structural rules (review round 1):
## - PROCESS_MODE_ALWAYS + root MOUSE_FILTER_IGNORE: pause/overview controls
##   keep working while the tree is paused, and empty playfield input falls
##   through to the aiming handler instead of being swallowed by the HUD.
## - Pause/resume/overview are requested from GameRoot (single authority);
##   the HUD never flips SceneTree.paused itself.
## - Power display is three-state: selected slider (Touch, pre-shot), live
##   qualified preview (Voice capture), committed power (rolling) — the
##   preview a player trusted must match the shot (FR-04).

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
var _mode_chip: Button
var _power_bar: ProgressBar
var _power_label: Label
var _touch_box: HBoxContainer
var _power_slider: HSlider
var _shoot_button: Button
var _voice_box: HBoxContainer
var _mic_button: Button
var _overview_button: Button
var _status_label: Label
var _pause_layer: PanelContainer
var _result_layer: PanelContainer
var _result_title: Label
var _result_stars: Label
var _result_detail: Label
var _save_banner: PanelContainer
var _stuck_button: Button
var _cal_sheet: PanelContainer
var _cal_step_label: Label
var _cal_hint_label: Label
var _cal_start_button: Button
var _last_input_mode := ""
var _cal_stage_index := -1
const CAL_STAGES: Array[String] = ["room", "soft", "strong"]
const CAL_STAGE_COPY: Dictionary = {
	"room": "Step 1/3 — Stay quiet for a moment.",
	"soft": "Step 2/3 — Make a comfortable SOFT sound.",
	"strong": "Step 3/3 — Now a comfortable STRONGER sound. No shouting.",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # usable while paused
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # playfield events pass through
	theme = RoarTheme.build()
	_build()


func _build() -> void:
	var safe := _safe_area_margins()

	# --- Top: compact header, fixed pause slot, no clipping at 360 px ---
	_top_box = VBoxContainer.new()
	_top_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_box.offset_left = safe.left
	_top_box.offset_right = -safe.right
	_top_box.offset_top = safe.top
	_top_box.add_theme_constant_override("separation", 2)
	add_child(_top_box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_top_box.add_child(row)
	var info := PanelContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 10)
	info.add_child(info_row)
	_hole_label = Label.new()
	_hole_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hole_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hole_label.custom_minimum_size = Vector2(60, 24)
	info_row.add_child(_hole_label)
	_par_label = Label.new()
	info_row.add_child(_par_label)
	_strokes_label = Label.new()
	info_row.add_child(_strokes_label)
	var pause_button := RoarTheme.make_flat_button("II")
	pause_button.custom_minimum_size = Vector2(48, 48)
	pause_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	pause_button.pressed.connect(func() -> void: pause_requested.emit())
	row.add_child(pause_button)

	_state_label = Label.new()
	_state_label.add_theme_color_override("font_color", RoarTheme.VOICE_CYAN)
	_top_box.add_child(_state_label)

	# --- Bottom control tray, thumb-reachable ---
	_tray = VBoxContainer.new()
	_tray.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_tray.offset_left = safe.left + 8
	_tray.offset_right = -safe.right - 8
	_tray.offset_top = -safe.bottom - 172
	_tray.offset_bottom = -safe.bottom
	_tray.add_theme_constant_override("separation", 8)
	add_child(_tray)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	_power_label.custom_minimum_size = Vector2(96, 24)
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
	var cancel_region := PanelContainer.new()
	cancel_region.custom_minimum_size = Vector2(140, 80)
	var cancel_label := Label.new()
	cancel_label.text = "Slide here\nto cancel"
	cancel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cancel_region.add_child(cancel_label)
	_voice_box.add_child(cancel_region)

	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 8)
	_tray.add_child(bottom_row)
	_mode_chip = RoarTheme.make_flat_button("Touch", true)
	_mode_chip.custom_minimum_size = Vector2(96, 48)
	_mode_chip.pressed.connect(_on_mode_chip)
	bottom_row.add_child(_mode_chip)
	_overview_button = RoarTheme.make_flat_button("Overview", true)
	_overview_button.custom_minimum_size = Vector2(110, 48)
	_overview_button.pressed.connect(func() -> void: overview_toggled.emit())
	bottom_row.add_child(_overview_button)
	_stuck_button = RoarTheme.make_flat_button("Stuck? +1", true)
	_stuck_button.custom_minimum_size = Vector2(120, 48)
	_stuck_button.visible = false
	_stuck_button.pressed.connect(_on_stuck_recovery)
	bottom_row.add_child(_stuck_button)

	_save_banner = _make_banner("Save problem — progress may not be kept. Results kept in memory.", RoarTheme.DANGER)
	_save_banner.visible = false
	add_child(_save_banner)

	_build_pause_layer()
	_build_result_layer()
	_build_calibration_sheet()


func _make_banner(text: String, color: Color) -> PanelContainer:
	var banner := PanelContainer.new()
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.anchor_left = 0.1
	banner.anchor_right = 0.9
	banner.offset_top = 100
	var box := StyleBoxFlat.new()
	box.bg_color = color.darkened(0.55)
	box.set_corner_radius_all(12)
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
	_pause_layer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_pause_layer.add_child(box)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var resume := RoarTheme.make_flat_button("Resume")
	resume.pressed.connect(func() -> void: resume_requested.emit())
	box.add_child(resume)
	var restart := RoarTheme.make_flat_button("Restart Hole", true)
	restart.pressed.connect(func() -> void:
		resume_requested.emit()
		restart_requested.emit()
	)
	box.add_child(restart)
	var to_map := RoarTheme.make_flat_button("Map", true)
	to_map.pressed.connect(func() -> void:
		resume_requested.emit()
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


## Minimal 3-stage calibration sheet (RB-021 core). The service owns capture
## and math; GameRoot orchestrates; this sheet only explains, starts stages,
## and reflects status. "Use Touch" is always equally visible.
func _build_calibration_sheet() -> void:
	_cal_sheet = PanelContainer.new()
	_cal_sheet.set_anchors_preset(Control.PRESET_CENTER)
	_cal_sheet.anchor_left = 0.08
	_cal_sheet.anchor_right = 0.92
	_cal_sheet.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_cal_sheet.add_child(box)
	var title := Label.new()
	title.text = "Find your shot power"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var privacy := Label.new()
	privacy.text = "Sound is processed on this device only. Nothing is saved or uploaded. A comfortable voice is enough — no shouting."
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	box.add_child(privacy)
	_cal_step_label = Label.new()
	_cal_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cal_step_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_cal_step_label)
	_cal_hint_label = Label.new()
	_cal_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cal_hint_label.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	box.add_child(_cal_hint_label)
	_cal_start_button = RoarTheme.make_flat_button("Start")
	_cal_start_button.pressed.connect(_on_cal_start)
	box.add_child(_cal_start_button)
	var use_touch := RoarTheme.make_flat_button("Use Touch instead", true)
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


func _close_calibration_sheet() -> void:
	_cal_stage_index = -1
	_cal_sheet.visible = false
	if gameplay != null and gameplay.has_method("cancel_calibration_stage"):
		gameplay.call("cancel_calibration_stage")


func _update_calibration_copy(hint: String) -> void:
	if _cal_stage_index < 0 or _cal_stage_index >= CAL_STAGES.size():
		return
	_cal_step_label.text = String(CAL_STAGE_COPY[CAL_STAGES[_cal_stage_index]])
	_cal_hint_label.text = hint
	_cal_start_button.text = "Start"


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


## Called by GameRoot when a stage completes/fails.
func on_calibration_stage_done(summary: Dictionary) -> void:
	_cal_start_button.disabled = false
	if not bool(summary.get("ok", false)):
		_update_calibration_copy(_error_copy(String(summary.get("error_code", ""))))
		return
	_cal_stage_index += 1
	if _cal_stage_index >= CAL_STAGES.size():
		_close_calibration_sheet()
		_status_label.text = "Calibrated! Hold, make a sound, release to shoot."
		return
	_update_calibration_copy("Got it.")


## OS safe area mapped into canvas coordinates. Degenerate or oversized
## reports (headless dummy display returns 0×0) fall back to page margins;
## insets are clamped so a bad driver report cannot eat the screen.
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


# --- Session wiring ---


func bind(p_session: GameSessionController, p_coordinator: InputCoordinator, p_voice: VoiceInputService, p_camera: CameraRig) -> void:
	session = p_session
	coordinator = p_coordinator
	voice = p_voice
	camera_rig = p_camera
	coordinator.hud = self
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
	_update_power_display()
	_refresh_input_mode()


## FR-04: what the player sees must match what the shot will use.
## Selected slider value (Touch, pre-shot) / qualified preview (Voice,
## capturing) / last committed power (rolling).
func _update_power_display() -> void:
	var power := 0.0
	if voice != null and voice.is_listening():
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
	_strokes_label.text = "Strokes %d" % count


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
	if _mic_button.get_global_rect().grow(24.0).has_point(pointer):
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


func show_pause() -> void:
	_pause_layer.visible = true


func hide_pause() -> void:
	_pause_layer.visible = false


func is_paused_sheet_visible() -> bool:
	return _pause_layer.visible


func set_overview_indicator(active: bool) -> void:
	_overview_button.text = "Resume view" if active else "Overview"


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


## Android Back / Escape: dismiss the top sheet first (calibration → pause),
## then pause gameplay. Results own their navigation. The event is always
## marked handled — otherwise the router's back handler would also receive
## it and navigate home on top of the pause toggle.
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
