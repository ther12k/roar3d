class_name GameStateMachine
extends RefCounted
## Authoritative Playing-state machine (docs/03_TECHNICAL_ARCHITECTURE.md §5).
## Pure transition authority: it never touches nodes, audio, or saves. The
## GameSessionController drives it and owns every side effect. Capture states
## and pending commands can never spend a stroke by canceling.

signal state_changed(from_state: int, to_state: int)

enum State {
	INTRO,
	READY,
	CAPTURE_WARMUP,
	CAPTURING,
	COMMIT_PENDING,
	ROLLING,
	SETTLING,
	RESETTING,
	PAUSED,
	COMPLETE,
	FAILED,
}

const CAPTURE_STATES: Array[int] = [State.CAPTURE_WARMUP, State.CAPTURING]

var state: int = State.INTRO
var _state_before_pause: int = State.INTRO
var _completed := false
var _failed := false


static func state_name(state_value: int) -> String:
	return State.keys()[state_value]


func is_capture_state(state_value := -1) -> bool:
	var value := state if state_value < 0 else state_value
	return value == State.CAPTURE_WARMUP or value == State.CAPTURING


func is_playing() -> bool:
	return state != State.COMPLETE and state != State.FAILED and state != State.PAUSED


## Aiming is allowed only in Ready — locked during capture so a thumb motion
## cannot redirect the shot (docs/05_PHYSICS_AND_CAMERA.md §7).
func can_aim() -> bool:
	return state == State.READY


func can_accept_touch_shot() -> bool:
	return state == State.READY


func can_accept_voice_shot() -> bool:
	return state == State.CAPTURING


func _transition(to: int, allowed_from: Array) -> bool:
	if not allowed_from.has(state):
		return false
	var from := state
	state = to
	state_changed.emit(from, to)
	return true


## --- Transitions (guards mirror the doc §5 table) ---


func enter_intro() -> bool:
	return _transition(State.INTRO, [State.INTRO])


func enter_ready() -> bool:
	return _transition(
		State.READY,
		[
			State.INTRO,  # spawn settled
			State.CAPTURE_WARMUP,  # cancel / no signal / timeout / route change
			State.CAPTURING,  # cancel / timeout / invalid release
			State.SETTLING,  # stable settlement reached
			State.RESETTING,  # verified reset finished
			State.COMMIT_PENDING,  # pending shot discarded (pause before physics tick)
		]
	)


func begin_capture_warmup() -> bool:
	return _transition(State.CAPTURE_WARMUP, [State.READY])


func capture_active() -> bool:
	return _transition(State.CAPTURING, [State.CAPTURE_WARMUP])


func begin_commit() -> bool:
	# Touch commits from Ready; voice commits from Capturing (valid release).
	return _transition(State.COMMIT_PENDING, [State.READY, State.CAPTURING])


func cancel_capture() -> bool:
	return _transition(State.READY, CAPTURE_STATES)


func begin_rolling() -> bool:
	return _transition(State.ROLLING, [State.COMMIT_PENDING])


func begin_settling() -> bool:
	return _transition(State.SETTLING, [State.ROLLING])


func begin_resetting() -> bool:
	return _transition(State.RESETTING, [State.ROLLING, State.SETTLING, State.READY])


func finish_reset() -> bool:
	return _transition(State.READY, [State.RESETTING])


func pause() -> bool:
	if state == State.PAUSED or state == State.COMPLETE or state == State.FAILED:
		return false
	_state_before_pause = state
	state = State.PAUSED
	state_changed.emit(_state_before_pause, State.PAUSED)
	return true


## Resume returns to the prior non-capture state; the microphone is never
## restarted automatically (docs/03 §5).
func resume() -> bool:
	if state != State.PAUSED:
		return false
	var target := _state_before_pause
	if target == State.CAPTURE_WARMUP or target == State.CAPTURING:
		target = State.READY
	if target == State.COMMIT_PENDING:
		# A pending command was canceled on pause; it cannot resume into a shot.
		target = State.READY
	var from := state
	state = target
	state_changed.emit(from, target)
	return true


func mark_complete() -> bool:
	if _completed:
		return false
	var ok := _transition(State.COMPLETE, [State.ROLLING, State.SETTLING, State.READY])
	if ok:
		_completed = true
	return ok


func mark_failed() -> bool:
	if _failed or _completed:
		return false
	# An attempt fails only when a shot resolves over the limit — i.e. from a
	# post-shot state — never directly from Ready or a capture state.
	var ok := _transition(State.FAILED, [State.ROLLING, State.SETTLING, State.RESETTING])
	if ok:
		_failed = true
	return ok


## Force-clear for level restart. Never used to leave terminal states during
## live play; only a fresh session resets them.
func reset_for_new_session() -> void:
	_completed = false
	_failed = false
	_state_before_pause = State.INTRO
	var from := state
	state = State.INTRO
	if from != State.INTRO:
		state_changed.emit(from, State.INTRO)
