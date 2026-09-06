class_name InputCoordinator
extends Node
## Transforms touch/mouse/voice into session intents (docs/03 §3). The UI
## never writes ball velocity or strokes; everything funnels through the
## guarded session methods. The pointer that started a voice hold owns it
## (QA-011); a second release finds the token closed and does nothing.

const AIM_DRAG_SENSITIVITY := 0.008  # radians per logical px
const AIM_KEY_STEP := 0.06

var session: GameSessionController
var voice: VoiceInputService
var hud: HUDPresenter = null

var _drag_aiming := false
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


# --- Aiming (drag on the playfield outside UI hit regions; locked in capture) ---


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not _drag_aiming and session.can_aim():
			_drag_aiming = true
		elif not event.pressed:
			_drag_aiming = false
	elif event is InputEventMouseMotion and _drag_aiming and session.can_aim():
		_rotate_aim(-event.relative.x * AIM_DRAG_SENSITIVITY)
	elif event.is_action_pressed("ui_left") and session.can_aim():
		_rotate_aim(-AIM_KEY_STEP)
	elif event.is_action_pressed("ui_right") and session.can_aim():
		_rotate_aim(AIM_KEY_STEP)


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
	voice.end_capture()
	if session.fsm.is_capture_state():
		session.cancel_capture()


# --- Touch path (slider + Shoot live in the HUD; they call these) ---


func touch_shoot(power: float) -> bool:
	return session.request_touch_shot(power)


func touch_slider_visible() -> bool:
	return true
