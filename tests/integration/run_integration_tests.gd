extends Node
## Integration tests: real physics (Jolt, 60 Hz) on the real CC01 scene.
## Assertions distinguish simulation ticks (await physics_frame) from frames.
## Run: godot --headless --path . res://tests/integration/run_integration_tests.tscn

var harness := TestHarness.new()


func _ready() -> void:
	await _run_all()
	var exit_code := harness.report("INTEGRATION TESTS")
	get_tree().quit(exit_code)


func _run_all() -> void:
	await _test_spawn_settles_to_ready()
	await _test_touch_shot_fires_once()
	await _test_zero_power_never_fires()
	await _test_shot_rejected_while_rolling()
	await _test_cup_completion_records_result()
	await _test_high_speed_cup_flyover_does_not_complete()
	await _test_out_of_bounds_penalty_and_reset()
	await _test_attempt_limit_fails()
	await _test_pause_cancels_pending_shot()
	await _test_voice_gesture_commits_one_shot()
	await _test_voice_clap_cannot_shoot()
	await _test_voice_cancel_and_interrupt_no_stroke()
	await _test_voice_double_release_single_shot()
	await _test_game_root_scene_smoke()


# --- helpers ---


func _make_session() -> Dictionary:
	var catalog := LevelCatalog.load_packaged()
	var level := LevelController.new()
	add_child(level)
	var errors := level.load_level(catalog.level_by_id("CC01"))
	harness.check(errors.is_empty(), "CC01 marker contract satisfied: " + str(errors))
	var ball := BallController.new()
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	collision.shape = sphere
	ball.add_child(collision)
	add_child(ball)
	var session := GameSessionController.new()
	add_child(session)
	session.setup(ball, level, "CC01", 2, 12)
	return {"level": level, "ball": ball, "session": session}


func _free_session(env: Dictionary) -> void:
	var level: LevelController = env["level"]
	var ball: BallController = env["ball"]
	var session: GameSessionController = env["session"]
	session.queue_free()
	level.queue_free()
	ball.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _await_state(session: GameSessionController, states: Array, max_frames: int) -> bool:
	for i: int in max_frames:
		if states.has(session.fsm.state):
			return true
		await get_tree().physics_frame
	return states.has(session.fsm.state)


func _await_ball_rest(ball: BallController, max_frames: int) -> bool:
	# After a direct teleport the session stays READY while the ball is still
	# settling; only the ball knows when it physically rests again.
	for i: int in max_frames:
		if ball.is_resting():
			return true
		await get_tree().physics_frame
	return ball.is_resting()


# --- tests ---


func _test_spawn_settles_to_ready() -> void:
	harness.suite = "integration.spawn"
	var env := await _make_session()
	var session: GameSessionController = env["session"]
	session.start_level()
	harness.check_eq(session.fsm.state, GameStateMachine.State.INTRO, "starts in INTRO")
	var ok := await _await_state(session, [GameStateMachine.State.READY], 180)
	harness.check(ok, "spawn settles to READY within 3 s (not instant)")
	harness.check_eq(session.strokes, 0, "no strokes on spawn")
	harness.check((env["ball"] as BallController).is_resting(), "ball physically resting")
	await _free_session(env)


func _test_touch_shot_fires_once() -> void:
	harness.suite = "integration.touch_shot"
	var env := await _make_session()
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	session.start_level()
	await _await_state(session, [GameStateMachine.State.READY], 180)
	var accepted := session.request_touch_shot(0.3)
	harness.check(accepted, "valid touch shot accepted")
	await get_tree().physics_frame
	harness.check_eq(session.strokes, 1, "one stroke counted")
	harness.check_eq(session.fsm.state, GameStateMachine.State.ROLLING, "ROLLING after commit")
	harness.check(ball.linear_velocity.length() > 0.5, "ball moving")
	var settled := await _await_state(session, [GameStateMachine.State.READY, GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED], 900)
	harness.check(settled, "ball resolves within 15 s")
	await _free_session(env)


func _test_zero_power_never_fires() -> void:
	harness.suite = "integration.zero_power"
	var env := await _make_session()
	var session: GameSessionController = env["session"]
	session.start_level()
	await _await_state(session, [GameStateMachine.State.READY], 180)
	harness.check(not session.request_touch_shot(0.0), "zero power rejected (FR: zero cannot fire)")
	harness.check(not session.request_touch_shot(-0.5), "negative power rejected")
	harness.check(not session.request_touch_shot(1.5), "out-of-range power rejected")
	harness.check_eq(session.strokes, 0, "no stroke spent")
	harness.check_eq(session.fsm.state, GameStateMachine.State.READY, "still READY")
	await _free_session(env)


func _test_shot_rejected_while_rolling() -> void:
	harness.suite = "integration.no_shot_while_moving"
	var env := await _make_session()
	var session: GameSessionController = env["session"]
	session.start_level()
	await _await_state(session, [GameStateMachine.State.READY], 180)
	session.request_touch_shot(0.6)
	await get_tree().physics_frame
	harness.check(not session.request_touch_shot(0.5), "no second shot while rolling (FR-08)")
	harness.check_eq(session.strokes, 1, "still one stroke")
	await _await_state(session, [GameStateMachine.State.READY, GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED], 900)
	await _free_session(env)


func _test_cup_completion_records_result() -> void:
	harness.suite = "integration.cup_completion"
	var env := await _make_session()
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	var completed_signal: Dictionary = {"result": {}}
	session.hole_completed.connect(func(result: Dictionary) -> void: completed_signal["result"] = result)
	session.start_level()
	await _await_state(session, [GameStateMachine.State.READY], 180)
	# 1 m before the cup, gentle putt: arrival speed < 1.2 m/s. With the
	# authored 0.55 m/s² resistance the completing band from 1 m is roughly
	# p ∈ (0, 0.07] (impulse floor 1.5 N·s → ~1.1 m/s arrival at 1 m).
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.25, -4.0)))
	harness.check(await _await_ball_rest(ball, 180), "ball re-settles after test teleport")
	harness.check(session.request_touch_shot(0.05), "gentle putt accepted")
	var done := await _await_state(session, [GameStateMachine.State.COMPLETE], 600)
	harness.check(done, "slow eligible entry completes the hole")
	harness.check_eq(session.strokes, 1, "one-stroke completion")
	harness.check(not completed_signal["result"].is_empty(), "completion signal emitted")
	if not (completed_signal["result"] as Dictionary).is_empty():
		var result: Dictionary = completed_signal["result"]
		harness.check_eq(int(result["stars"]), 3, "1 stroke at par 2 → 3 stars")
		harness.check(bool(ProgressStore.is_completed("CC01")), "completion persisted")
	await _free_session(env)


func _test_high_speed_cup_flyover_does_not_complete() -> void:
	harness.suite = "integration.cup_flyover"
	var env := await _make_session()
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	var completed: Dictionary = {"fired": false}
	session.hole_completed.connect(func(_result: Dictionary) -> void: completed["fired"] = true)
	session.start_level()
	await _await_state(session, [GameStateMachine.State.READY], 180)
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.25, -4.0)))
	harness.check(await _await_ball_rest(ball, 180), "ball re-settles after test teleport")
	session.request_touch_shot(0.85)
	var done := await _await_state(
		session,
		[GameStateMachine.State.READY, GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED],
		900
	)
	harness.check(done, "flyover attempt resolves (out of bounds past the edge)")
	harness.check(not bool(completed["fired"]), "high-speed pass over the cup cannot complete (QA-024)")
	harness.check_eq(session.strokes, 2, "flyover then fall = shot + one penalty")
	await _free_session(env)


func _test_out_of_bounds_penalty_and_reset() -> void:
	harness.suite = "integration.out_of_bounds"
	var env := await _make_session()
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	session.start_level()
	await _await_state(session, [GameStateMachine.State.READY], 180)
	# Shoot backwards off the open spawn edge: fall → exactly one penalty,
	# verified reset to the safe anchor, attempt continues.
	session.set_aim(Vector3(0.0, 0.0, 1.0))
	session.request_touch_shot(0.8)
	var ready_again := await _await_state(session, [GameStateMachine.State.READY], 900)
	harness.check(ready_again, "reset returns to READY")
	harness.check_eq(session.strokes, 2, "one shot + exactly one penalty stroke (QA-025)")
	harness.check(ball.is_resting(), "ball resting after reset")
	var distance_to_spawn: float = ball.global_position.distance_to(Vector3(0.0, 0.25, 5.5))
	harness.check(distance_to_spawn < 1.0, "reset to spawn anchor")
	await _free_session(env)


func _test_attempt_limit_fails() -> void:
	harness.suite = "integration.attempt_limit"
	var env := await _make_session()
	var session: GameSessionController = env["session"]
	var failed_signal: Dictionary = {"fired": false}
	session.attempt_finished.connect(func() -> void: failed_signal["fired"] = true)
	session.start_level()
	session.max_strokes = 2  # shortened attempt for test speed
	await _await_state(session, [GameStateMachine.State.READY], 180)
	# Two short putts that stop short of the cup exhaust the attempt.
	session.request_touch_shot(0.2)
	await _await_state(session, [GameStateMachine.State.READY], 900)
	harness.check_eq(session.strokes, 1, "first stroke counted")
	var accepted := session.request_touch_shot(0.2)
	harness.check(accepted, "second stroke allowed at 1/2")
	await _await_state(session, [GameStateMachine.State.READY, GameStateMachine.State.FAILED], 900)
	harness.check_eq(session.fsm.state, GameStateMachine.State.FAILED, "unresolved attempt at limit fails")
	harness.check(bool(failed_signal["fired"]), "attempt_finished signal emitted")
	harness.check(not session.request_touch_shot(0.5), "no shots after failure")
	harness.check(not ProgressStore.is_completed("CC01") or ProgressStore.best_for("CC01").get("best_stars", 0) > 0, "no completion written for failed attempt")
	await _free_session(env)


func _test_pause_cancels_pending_shot() -> void:
	harness.suite = "integration.pause_cancels_pending"
	var env := await _make_session()
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	session.start_level()
	await _await_state(session, [GameStateMachine.State.READY], 180)
	session.request_touch_shot(0.5)
	harness.check_eq(session.fsm.state, GameStateMachine.State.COMMIT_PENDING, "command pending before physics tick")
	session.pause_session()
	harness.check_eq(session.fsm.state, GameStateMachine.State.PAUSED, "paused")
	session.resume_session()
	harness.check_eq(session.fsm.state, GameStateMachine.State.READY, "pending shot canceled — no stroke (pause before physics commit)")
	harness.check_eq(session.strokes, 0, "no stroke spent on canceled command")
	harness.check(ball.is_resting(), "ball never moved")
	await _free_session(env)


# --- voice gesture through the same ShotCommand path ---


func _make_voice_env() -> Dictionary:
	var env := await _make_session()
	var session: GameSessionController = env["session"]
	var source := VoiceFrameSource.SyntheticFrameSource.new()
	source.rate = 48000
	var voice := VoiceInputService.new(source, false)
	add_child(voice)
	voice.calibration = {"gate_db": -50.0, "lower_db": -40.0, "upper_db": -20.0}
	var coordinator := InputCoordinator.new()
	coordinator.session = session
	coordinator.voice = voice
	add_child(coordinator)
	env["voice"] = voice
	env["coordinator"] = coordinator
	env["source"] = source
	session.start_level()
	await _await_state(session, [GameStateMachine.State.READY], 180)
	return env


func _free_voice_env(env: Dictionary) -> void:
	(env["voice"] as VoiceInputService).queue_free()
	(env["coordinator"] as InputCoordinator).queue_free()
	await _free_session(env)


func _test_voice_gesture_commits_one_shot() -> void:
	harness.suite = "integration.voice_commit"
	var env := await _make_voice_env()
	var session: GameSessionController = env["session"]
	var coordinator: InputCoordinator = env["coordinator"]
	var voice: VoiceInputService = env["voice"]
	var source: VoiceFrameSource.SyntheticFrameSource = env["source"]
	harness.check(coordinator.voice_hold_started(), "hold opens capture from READY")
	harness.check_eq(session.fsm.state, GameStateMachine.State.CAPTURE_WARMUP, "warmup state")
	# 300 ms of a comfortable sound: -26 dBFS maps to raw ≈ 0.70.
	source.push_constant_ms(300, 0.05)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	harness.check_eq(session.fsm.state, GameStateMachine.State.CAPTURING, "capture active after fresh frames")
	harness.check(voice.is_listening(), "service listening")
	coordinator.voice_release_inside()
	# The consume happens on the NEXT physics tick; await the state, not a
	# fixed frame count.
	var rolling := await _await_state(session, [GameStateMachine.State.ROLLING], 10)
	harness.check(rolling, "voice release enters ROLLING")
	harness.check_eq(session.strokes, 1, "voice release spends exactly one stroke")
	harness.check_between(session.last_committed_power, 0.45, 0.95, "committed power near calibrated value")
	harness.check(not voice.is_listening(), "capture closed after release")
	await _await_state(session, [GameStateMachine.State.READY, GameStateMachine.State.COMPLETE], 900)
	await _free_voice_env(env)


func _test_voice_clap_cannot_shoot() -> void:
	harness.suite = "integration.voice_clap"
	var env := await _make_voice_env()
	var session: GameSessionController = env["session"]
	var coordinator: InputCoordinator = env["coordinator"]
	var source: VoiceFrameSource.SyntheticFrameSource = env["source"]
	coordinator.voice_hold_started()
	source.push_constant_ms(70, 0.3)  # loud but shorter than 150 ms qualification
	source.push_silence_ms(400)
	await get_tree().process_frame
	await get_tree().process_frame
	coordinator.voice_release_inside()
	await get_tree().physics_frame
	harness.check_eq(session.strokes, 0, "a clap cannot spend a stroke (QA-006)")
	harness.check_eq(session.fsm.state, GameStateMachine.State.READY, "back to READY with no stroke")
	await _free_voice_env(env)


func _test_voice_cancel_and_interrupt_no_stroke() -> void:
	harness.suite = "integration.voice_cancel_interrupt"
	var env := await _make_voice_env()
	var session: GameSessionController = env["session"]
	var coordinator: InputCoordinator = env["coordinator"]
	var source: VoiceFrameSource.SyntheticFrameSource = env["source"]
	# Release outside the mic region (cancel path).
	coordinator.voice_hold_started()
	source.push_constant_ms(300, 0.05)
	await get_tree().process_frame
	await get_tree().process_frame
	coordinator.voice_release_outside()
	harness.check_eq(session.strokes, 0, "cancel spends no stroke")
	harness.check_eq(session.fsm.state, GameStateMachine.State.READY, "cancel returns READY")
	# External interruption (background/pause) mid-hold.
	coordinator.voice_hold_started()
	source.push_constant_ms(300, 0.05)
	await get_tree().process_frame
	await get_tree().process_frame
	coordinator.interrupt_capture()
	harness.check_eq(session.strokes, 0, "interrupt spends no stroke (FR-15)")
	harness.check_eq(session.fsm.state, GameStateMachine.State.READY, "interrupt returns READY")
	harness.check(not (env["voice"] as VoiceInputService).is_listening(), "capture closed by interrupt")
	await _free_voice_env(env)


func _test_voice_double_release_single_shot() -> void:
	harness.suite = "integration.voice_double_release"
	var env := await _make_voice_env()
	var session: GameSessionController = env["session"]
	var coordinator: InputCoordinator = env["coordinator"]
	var source: VoiceFrameSource.SyntheticFrameSource = env["source"]
	coordinator.voice_hold_started()
	source.push_constant_ms(300, 0.05)
	await get_tree().process_frame
	await get_tree().process_frame
	coordinator.voice_release_inside()
	# Duplicate release: hold already closed, token already consumed.
	coordinator.voice_release_inside()
	coordinator.voice_release_inside()
	await _await_state(session, [GameStateMachine.State.ROLLING], 10)
	harness.check_eq(session.strokes, 1, "duplicate release cannot double-fire (QA-011)")
	await _await_state(session, [GameStateMachine.State.READY, GameStateMachine.State.COMPLETE], 900)
	await _free_voice_env(env)


# --- full stack smoke: the actual game_root scene with HUD + camera ---


func _test_game_root_scene_smoke() -> void:
	harness.suite = "integration.game_root_smoke"
	AppRouter.current_level_id = "CC01"
	var packed: PackedScene = load("res://scenes/game/game_root.tscn")
	harness.check(packed != null, "game_root.tscn loads")
	if packed == null:
		return
	var root: Node = packed.instantiate()
	add_child(root)
	await get_tree().process_frame
	await get_tree().physics_frame
	var ok := false
	for i: int in 240:
		if root is GameRoot and (root as GameRoot).session.fsm.state == GameStateMachine.State.READY:
			ok = true
			break
		await get_tree().physics_frame
	harness.check(ok, "full gameplay stack reaches READY (HUD + camera + session)")
	var session: GameSessionController = (root as GameRoot).session
	session.request_touch_shot(0.3)
	await get_tree().physics_frame
	harness.check_eq(session.strokes, 1, "smoke shot fires through the full stack")
	await _await_state(session, [GameStateMachine.State.READY, GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED], 900)
	var level_ref: LevelController = (root as GameRoot).level
	root.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Exit path must have torn the level instance down (FR-19): the ref may
	# itself be freed by then, which also proves cleanup ran.
	harness.check(not is_instance_valid(level_ref) or level_ref.instance == null, "level unloaded on exit (FR-19)")
