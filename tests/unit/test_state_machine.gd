extends RefCounted
## State machine unit tests: the full docs/03 §5 transition table, guard
## rejects, pause semantics, and terminal idempotence.


func run(h: TestHarness) -> void:
	h.suite = "state_machine_happy_path"
	_happy_path(h)
	h.suite = "state_machine_capturing"
	_capture_paths(h)
	h.suite = "state_machine_pause"
	_pause(h)
	h.suite = "state_machine_guards"
	_guards(h)


func _happy_path(h: TestHarness) -> void:
	var fsm := GameStateMachine.new()
	h.check_eq(fsm.state, GameStateMachine.State.INTRO, "starts in INTRO")
	h.check(fsm.enter_ready(), "INTRO → READY on settle")
	h.check(fsm.begin_commit(), "READY → COMMIT_PENDING (touch)")
	h.check(fsm.begin_rolling(), "COMMIT_PENDING → ROLLING")
	h.check(fsm.begin_settling(), "ROLLING → SETTLING")
	h.check(fsm.enter_ready(), "SETTLING → READY")
	h.check(fsm.mark_complete(), "READY → COMPLETE allowed")
	h.check(not fsm.mark_complete(), "complete is idempotent")
	h.check(not fsm.begin_capture_warmup(), "no capture after complete")


func _capture_paths(h: TestHarness) -> void:
	var fsm := GameStateMachine.new()
	fsm.enter_ready()
	h.check(fsm.begin_capture_warmup(), "READY → CAPTURE_WARMUP")
	h.check(fsm.capture_active(), "WARMUP → CAPTURING on frames")
	h.check(fsm.begin_commit(), "CAPTURING → COMMIT_PENDING (voice release)")
	fsm.begin_rolling()
	fsm.begin_settling()
	fsm.enter_ready()
	h.check(fsm.begin_capture_warmup(), "READY → WARMUP again")
	h.check(fsm.cancel_capture(), "WARMUP → READY on cancel")
	h.check(fsm.begin_capture_warmup(), "READY → WARMUP after cancel")
	fsm.capture_active()
	h.check(fsm.cancel_capture(), "CAPTURING → READY on cancel")
	# Timeout > 3 s cancels with no stroke.
	fsm.begin_capture_warmup()
	h.check(fsm.cancel_capture(), "timeout cancels capture")


func _pause(h: TestHarness) -> void:
	var fsm := GameStateMachine.new()
	fsm.enter_ready()
	fsm.begin_capture_warmup()
	h.check(fsm.pause(), "pause from capture state")
	h.check_eq(fsm.state, GameStateMachine.State.PAUSED, "PAUSED entered")
	h.check(fsm.resume(), "resume works")
	h.check_eq(fsm.state, GameStateMachine.State.READY, "resume from capture → READY, never auto-restart mic")
	fsm.begin_commit()
	fsm.pause()
	fsm.resume()
	h.check_eq(fsm.state, GameStateMachine.State.READY, "resume from COMMIT_PENDING → READY (pending canceled)")
	fsm.begin_commit()
	fsm.begin_rolling()
	fsm.pause()
	fsm.resume()
	h.check_eq(fsm.state, GameStateMachine.State.ROLLING, "resume from ROLLING keeps ROLLING")
	fsm.pause()
	h.check(not fsm.pause(), "double pause rejected")
	fsm.resume()


func _guards(h: TestHarness) -> void:
	var fsm := GameStateMachine.new()
	h.check(not fsm.begin_rolling(), "no impulse without commit")
	h.check(not fsm.begin_capture_warmup(), "no capture from INTRO")
	fsm.enter_ready()
	h.check(not fsm.begin_settling(), "no settling from READY")
	h.check(not fsm.mark_failed(), "cannot fail directly from READY")
	fsm.begin_commit()
	h.check(not fsm.begin_capture_warmup(), "no capture while commit pending")
	fsm.begin_rolling()
	h.check(not fsm.can_aim(), "aim locked while rolling")
	h.check(not fsm.can_accept_touch_shot(), "no touch shot while rolling")
	h.check(not fsm.can_accept_voice_shot(), "no voice shot while rolling")
	fsm.begin_settling()
	h.check(fsm.mark_failed(), "attempt limit can fail from SETTLING")
	h.check(not fsm.mark_failed(), "fail is idempotent")
	h.check(not fsm.pause(), "cannot pause after fail")
	fsm.reset_for_new_session()
	h.check_eq(fsm.state, GameStateMachine.State.INTRO, "reset returns to INTRO for next attempt")
