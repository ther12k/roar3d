class_name InputCoordinator
extends Node
## Transforms touch/mouse/voice into session intents (docs/03 §3). The UI
## never writes ball velocity or strokes; everything funnels through the
## guarded session methods. The pointer that started a voice hold owns it
## (QA-011); a second release finds the token closed and does nothing.
##
## Touch primary gesture (slingshot): press anywhere on the playfield, drag
## back to stretch, release to shoot. Pull direction maps to the opposite
## shot direction relative to the camera's flat basis; drag length is power.

signal aim_gesture_changed(active: bool, power: float, valid: bool)

const AIM_DRAG_SENSITIVITY := 0.008  # radians per logical px (voice fine-aim)
const AIM_KEY_STEP := 0.06
const SLING_MAX_DRAG_PX := 170.0  # drag length that reaches 100% power
const SLING_DEAD_ZONE_PX := 22.0  # shorter drags cancel (tap = no stroke)
const SLING_MIN_POWER := 0.06
const SLING_EASE := 1.35  # drag->power curve: fine control near zero power

var session: GameSessionController
var voice: VoiceInputService
var hud: HUDPresenter = null
var camera_rig: CameraRig = null

var _drag_aiming := false
var _sling_active := false
var _sling_start := Vector2.ZERO
var _sling_vector := Vector2.ZERO
var _sling_valid := false
var _voice_hold_open := false


func _process(_delta: float) -> void:
	if _voice_hold_open:
		# Warmup completes once the service publishes fresh frames; timeout or
		# error closes capture and must return the session to Ready (no stroke).
		if not voice.is_listening():
			_voice_hold_open = false
			session.cancel_capture()
		elif session.fsm.state == GameStateMachine.State.CAPTURE_WARMUP:
			session.capture_became_active()


# --- Aiming: slingshot drag (touch mode) / horizontal fine-aim (voice) ---


## Slingshot state for the HUD/aim-guide presentation: live power while the
## player stretches, and whether the current drag is past the dead zone.
func is_slinging() -> bool:
	return _sling_active


## Eased drag->power (D-020): the curve puts the finishing-putt band
## (p ≈ 0.05–0.08) right at the dead-zone edge, where a short cautious drag
## lands naturally, while full power stays at the max drag length.
func slingshot_power() -> float:
	var linear := clampf(_sling_vector.length() / SLING_MAX_DRAG_PX, SLING_MIN_POWER, 1.0)
	return pow(linear, SLING_EASE)


func slingshot_valid() -> bool:
	return _sling_valid


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if session != null and session.fsm.state in [GameStateMachine.State.ROLLING, GameStateMachine.State.SETTLING]:
				trigger_jump()
			elif not _drag_aiming and not _sling_active and session.can_aim():
				if SettingsStore.input_mode() == "touch":
					_sling_active = true
					_sling_start = event.position
					_sling_vector = Vector2.ZERO
					_sling_valid = false
					aim_gesture_changed.emit(true, 0.0, false)
				else:
					_drag_aiming = true
		elif not event.pressed:
			if _sling_active:
				_sling_release()
			_drag_aiming = false
	elif event is InputEventMouseMotion:
		if _sling_active:
			_sling_update(event.position)
		elif _drag_aiming and session.can_aim():
			_rotate_aim(-event.relative.x * AIM_DRAG_SENSITIVITY)
	elif event.is_action_pressed("ui_left") and session.can_aim():
		_rotate_aim(-AIM_KEY_STEP)
	elif event.is_action_pressed("ui_right") and session.can_aim():
		_rotate_aim(AIM_KEY_STEP)
	elif event.is_action_pressed("ui_select") or event.is_action_pressed("ui_accept"):
		trigger_jump()


## Pull-back mapping: screen-down stretches the shot forward (away from the
## camera), screen-left aims right — release launches opposite the pull.
func _sling_update(position: Vector2) -> void:
	_sling_vector = position - _sling_start
	var drag_len := _sling_vector.length()
	if session.can_aim() and drag_len >= 1.0:
		var cam: Camera3D = camera_rig.camera if camera_rig != null else null
		var fwd := Vector3.FORWARD
		var right := Vector3.RIGHT
		if cam != null:
			fwd = -cam.global_transform.basis.z
			fwd.y = 0.0
			right = cam.global_transform.basis.x
			right.y = 0.0
			if fwd.length() > 0.01:
				fwd = fwd.normalized()
			if right.length() > 0.01:
				right = right.normalized()
		var pull := (-_sling_vector.y * fwd + _sling_vector.x * right) / SLING_MAX_DRAG_PX
		if pull.length() > 0.01:
			session.set_aim(-pull.normalized())
	_sling_valid = drag_len >= SLING_DEAD_ZONE_PX
	aim_gesture_changed.emit(true, slingshot_power(), _sling_valid)


func _sling_release() -> void:
	_sling_active = false
	var power := slingshot_power()
	aim_gesture_changed.emit(false, 0.0, false)
	if not _sling_valid or not session.can_aim():
		_sling_valid = false
		return
	_sling_valid = false
	# Loft is the session's shared rule now — full-power slingshot, slider,
	# and voice all behave identically (input parity).
	session.request_touch_shot(power)


## Active jump action: delegates to the session (gameplay authority).
## Plays audio based on whether the ball was rolling or resting.
func trigger_jump() -> bool:
	if session == null:
		return false
	var was_rolling := session.fsm.state in [GameStateMachine.State.ROLLING, GameStateMachine.State.SETTLING]
	if session.request_jump():
		AudioDirector.play_effect("bounce", 0.9 if was_rolling else 0.6)
		return true
	return false


func _rotate_aim(angle: float) -> void:
	var aim := session.aim_direction.rotated(Vector3.UP, angle)
	session.set_aim(aim)


# --- Voice gesture: aim -> hold -> comfortable sound -> preview -> release ---


## Mic button pressed. Returns false when a shot is not allowed right now;
## never opens a capture that cannot become a shot. Without a calibration
## profile the power mapping is unusable — route to calibration instead.
func voice_hold_started() -> bool:
	if _voice_hold_open:
		return false
	if not session.can_begin_capture():
		return false
	if voice.calibration.is_empty():
		if hud != null:
			hud.open_calibration_sheet()
		return false
	if not voice.begin_capture():
		return false  # permission denied / no input: no state change, no stroke
	if not session.begin_capture_warmup():
		voice.end_capture()
		return false
	_voice_hold_open = true
	return true


## Pointer released inside the active mic hit region: commit the preview the
## player saw, or abort cleanly with no stroke.
func voice_release_inside() -> void:
	if not _voice_hold_open:
		return
	_voice_hold_open = false
	var result := voice.release_capture_for_shot()
	if result["valid"] and session.fsm.is_capture_state():
		session.request_voice_shot(float(result["power"]))
	else:
		session.cancel_capture()


## Pointer released outside (cancel region or elsewhere): abort, no stroke.
func voice_release_outside() -> void:
	if not _voice_hold_open:
		return
	_voice_hold_open = false
	voice.end_capture()
	session.cancel_capture()


## External interruption (pause, background, route change): close input and
## cancel any un-committed shot (FR-15). Called by the gameplay root.
func interrupt_capture() -> void:
	if _voice_hold_open:
		_voice_hold_open = false
	if _sling_active:
		_sling_active = false
		_sling_valid = false
		aim_gesture_changed.emit(false, 0.0, false)
	voice.end_capture()
	if session.fsm.is_capture_state():
		session.cancel_capture()


# --- Touch path (slider + Shoot live in the HUD; they call these) ---


func touch_shoot(power: float) -> bool:
	return session.request_touch_shot(power)


func touch_slider_visible() -> bool:
	return true
