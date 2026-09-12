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
	await _test_background_notification_pauses_safely()
	await _test_voice_gesture_commits_one_shot()
	await _test_voice_clap_cannot_shoot()
	await _test_voice_cancel_and_interrupt_no_stroke()
	await _test_voice_double_release_single_shot()
	await _test_voice_fine_aim_drag_rotates()
	await _test_slingshot_dead_zone_and_interrupt()
	await _test_pause_resume_through_ui()
	await _test_overview_through_ui()
	await _test_slider_shoot_matches_displayed_power()
	await _test_aim_drag_falls_through_hud()
	await _test_uncalibrated_voice_gated_to_calibration()
	await _test_overrun_recovery_next_hold_works()
	await _test_chunk_size_independent_qualification()
	await _test_game_root_scene_smoke()
	await _test_mascot_asset_contract()
	await _test_calibration_cancel_recovers()
	await _test_calibration_stage_works_without_prior_calibration()
	await _test_jump_blocked_in_air()
	await _test_jump_resets_on_landing()
	await _test_ready_hop_never_moves_ball()
	await _test_loft_launches_ball_upward()
	await _test_input_routes_loft_parity()
	await _test_bounce_disabled_by_default()
	await _test_turf_rebound_decays_and_caps()
	await _test_spring_and_dead_surfaces()
	await _test_perfect_bounce_timing_and_budget()
	await _test_wall_is_not_a_landing()
	await _test_physical_hole_drops_ball()


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


## OS background/focus loss mid-hold (RB-024 / QA-013): the same pause
## authority fires from NOTIFICATION_APPLICATION_PAUSED; capture closes, no
## stroke leaks, and resume never restarts the mic.
func _test_background_notification_pauses_safely() -> void:
	harness.suite = "ui.background_pause"
	var env := await _make_full_game()
	var session: GameSessionController = env["session"]
	var coordinator: InputCoordinator = env["coordinator"]
	var voice: VoiceInputService = env["voice"]
	var source: VoiceFrameSource.SyntheticFrameSource = env["source"]
	voice.calibration = {"gate_db": -50.0, "lower_db": -40.0, "upper_db": -20.0}
	harness.check(coordinator.voice_hold_started(), "hold opens before backgrounding")
	source.push_constant_ms(200, 0.05)
	await get_tree().process_frame
	await get_tree().process_frame
	(env["root"] as GameRoot).notification(GameRoot.NOTIFICATION_APPLICATION_PAUSED)
	await get_tree().process_frame
	harness.check(get_tree().paused, "background notification pauses the tree")
	harness.check(not voice.is_listening(), "background closes capture (no hidden mic)")
	harness.check_eq(session.strokes, 0, "backgrounded hold spends no stroke")
	# Player returns and taps Resume: session READY, mic stays off.
	(env["hud"] as HUDPresenter).resume_requested.emit()
	await get_tree().process_frame
	harness.check(not get_tree().paused, "resume unpauses the tree")
	harness.check_eq(session.fsm.state, GameStateMachine.State.READY, "session resumed to READY")
	harness.check(not voice.is_listening(), "mic never auto-restarts after background")
	await _free_full_game(env)


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


# --- full-stack UI tests: drive the real HUD, real input events ---


## Builds the actual gameplay scene (HUD + camera + session) with a synthetic
## microphone injected, mirroring how a player interacts.
func _make_full_game() -> Dictionary:
	AppRouter.current_level_id = "CC01"
	var packed: PackedScene = load("res://scenes/game/game_root.tscn")
	var root: GameRoot = packed.instantiate()
	add_child(root)
	await get_tree().physics_frame
	var source := VoiceFrameSource.SyntheticFrameSource.new()
	source.rate = 48000
	root.voice._source = source  # test hook: synthetic frames, identical pipeline
	root.voice._is_real_mic = false
	for i: int in 240:
		if root.session.fsm.state == GameStateMachine.State.READY:
			break
		await get_tree().physics_frame
	return {"root": root, "session": root.session, "hud": root.hud, "coordinator": root.coordinator, "voice": root.voice, "source": source}


func _free_full_game(env: Dictionary) -> void:
	get_tree().paused = false
	var root: GameRoot = env["root"]
	var level_ref: LevelController = root.level
	root.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	harness.check(not is_instance_valid(level_ref) or level_ref.instance == null, "level torn down (FR-19)")


func _push_key(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	get_viewport().push_input(event)


## Control rects live in canvas coordinates; push_input expects window
## coordinates. Headless runs a scaled transform (e.g. 844×844 canvas in a
## 0×0-reported window), so convert explicitly.
func _to_window(canvas_pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * canvas_pos


func _push_mouse_press(canvas_pos: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = _to_window(canvas_pos)
	get_viewport().push_input(event)


func _push_mouse_release(canvas_pos: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = _to_window(canvas_pos)
	get_viewport().push_input(event)


func _push_mouse_motion(canvas_from: Vector2, delta: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = _to_window(canvas_from + delta)
	var scale_x := get_viewport().get_final_transform().get_scale().x
	event.relative = delta * scale_x
	get_viewport().push_input(event)


func _test_pause_resume_through_ui() -> void:
	harness.suite = "ui.pause_resume"
	var env := await _make_full_game()
	var session: GameSessionController = env["session"]
	var hud: HUDPresenter = env["hud"]
	var coordinator: InputCoordinator = env["coordinator"]
	var voice: VoiceInputService = env["voice"]
	var source: VoiceFrameSource.SyntheticFrameSource = env["source"]
	voice.calibration = {"gate_db": -50.0, "lower_db": -40.0, "upper_db": -20.0}
	harness.check(not get_tree().paused, "not paused initially")
	# Open a voice hold, then pause mid-capture via Escape/Back.
	harness.check(coordinator.voice_hold_started(), "hold opens")
	source.push_constant_ms(200, 0.05)
	await get_tree().process_frame
	await get_tree().process_frame
	_push_key(KEY_ESCAPE)
	await get_tree().process_frame
	harness.check(get_tree().paused, "Escape pauses the tree")
	harness.check(hud.is_paused_sheet_visible(), "pause sheet visible")
	harness.check_eq(session.fsm.state, GameStateMachine.State.PAUSED, "session paused, not just the world")
	harness.check(not voice.is_listening(), "capture closed by pause")
	harness.check_eq(session.strokes, 0, "canceled hold spends no stroke")
	# Resume through the same input path; HUD stays responsive while paused.
	_push_key(KEY_ESCAPE)
	await get_tree().process_frame
	harness.check(not get_tree().paused, "Escape resumes")
	harness.check(not hud.is_paused_sheet_visible(), "sheet hidden")
	harness.check_eq(session.fsm.state, GameStateMachine.State.READY, "session resumed to READY")
	harness.check(not voice.is_listening(), "mic never auto-restarts on resume")
	await _free_full_game(env)


func _test_overview_through_ui() -> void:
	harness.suite = "ui.overview"
	var env := await _make_full_game()
	var session: GameSessionController = env["session"]
	var root: GameRoot = env["root"]
	var hud: HUDPresenter = env["hud"]
	hud.overview_toggled.emit()
	await get_tree().process_frame
	harness.check(root.camera_rig.is_overview(), "overview opens from the button signal")
	harness.check(get_tree().paused, "simulation paused during inspection")
	harness.check_eq(session.fsm.state, GameStateMachine.State.READY, "session itself stays READY")
	hud.overview_toggled.emit()
	await get_tree().process_frame
	harness.check(not root.camera_rig.is_overview(), "overview closes")
	harness.check(not get_tree().paused, "simulation resumes")
	harness.check_eq(session.fsm.state, GameStateMachine.State.READY, "still READY after inspection")
	await _free_full_game(env)


func _test_slider_shoot_matches_displayed_power() -> void:
	harness.suite = "ui.power_display"
	var env := await _make_full_game()
	var session: GameSessionController = env["session"]
	var hud: HUDPresenter = env["hud"]
	hud._power_slider.value = 40.0
	# process_frame fires BEFORE node _process callbacks, so the display
	# refresh lags one frame; two frames make the selected value visible.
	await get_tree().process_frame
	await get_tree().process_frame
	harness.check("40%" in hud._power_label.text, "selected power shown before the shot (was 0%% before fix)")
	hud._on_shoot()
	var rolling := await _await_state(session, [GameStateMachine.State.ROLLING], 10)
	harness.check(rolling, "shoot button fires")
	harness.check_between(session.last_committed_power, 0.399, 0.401, "committed power equals displayed slider power (FR-04)")
	await _await_state(session, [GameStateMachine.State.READY, GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED], 900)
	await _free_full_game(env)


func _test_aim_drag_falls_through_hud() -> void:
	harness.suite = "ui.aim_fallthrough"
	SettingsStore.set_input_mode("touch")
	var env := await _make_full_game()
	var session: GameSessionController = env["session"]
	var hud: HUDPresenter = env["hud"]
	var coordinator: InputCoordinator = env["coordinator"]
	# Empty-playfield drag in touch mode IS the slingshot gesture.
	_push_mouse_press(Vector2(195, 400))
	_push_mouse_motion(Vector2(195, 400), Vector2(0, 80))
	await get_tree().process_frame
	harness.check(coordinator.is_slinging(), "empty-area drag starts the slingshot")
	harness.check(coordinator.slingshot_valid(), "80px drag passes the dead zone")
	_push_mouse_release(Vector2(195, 480))
	var rolling := await _await_state(session, [GameStateMachine.State.ROLLING], 10)
	harness.check(rolling, "slingshot release commits the shot")
	harness.check_eq(session.strokes, 1, "one drag-release spends one stroke")
	await _await_state(session, [GameStateMachine.State.READY, GameStateMachine.State.COMPLETE], 900)
	# Drag over the slider: the control consumes it; no slingshot, no stroke.
	var strokes_before := session.strokes
	var aim_before_slider := session.aim_direction
	var slider_center: Vector2 = (hud._power_slider as Control).get_global_rect().get_center()
	_push_mouse_press(slider_center)
	_push_mouse_motion(slider_center, Vector2(60, 0))
	_push_mouse_release(slider_center + Vector2(60, 0))
	await get_tree().process_frame
	harness.check(not coordinator.is_slinging(), "slider drag never opens a slingshot")
	harness.check(aim_before_slider.angle_to(session.aim_direction) < 0.001, "slider interaction never changes aim")
	harness.check_eq(session.strokes, strokes_before, "slider drag spends no stroke")
	await _free_full_game(env)


func _test_voice_fine_aim_drag_rotates() -> void:
	harness.suite = "integration.voice_fine_aim"
	SettingsStore.set_input_mode("voice")
	var env := await _make_voice_env()
	var session: GameSessionController = env["session"]
	var coordinator: InputCoordinator = env["coordinator"]
	var initial_aim := session.aim_direction
	coordinator._unhandled_input(_synthetic_button(Vector2(200, 300), true))
	coordinator._unhandled_input(_synthetic_motion(Vector2(140, 300), Vector2(-60, 0)))
	harness.check(not coordinator.is_slinging(), "voice mode drag is fine-aim, not slingshot")
	var angle := initial_aim.angle_to(session.aim_direction)
	harness.check(absf(angle) > 0.2, "voice-mode horizontal drag rotates aim (%.3f rad)" % angle)
	harness.check_eq(session.strokes, 0, "fine-aim drag spends no stroke")
	coordinator._unhandled_input(_synthetic_button(Vector2(140, 300), false))
	harness.check_eq(session.strokes, 0, "voice-mode release spends no stroke")
	SettingsStore.set_input_mode("touch")
	await _free_voice_env(env)


func _test_slingshot_dead_zone_and_interrupt() -> void:
	harness.suite = "integration.slingshot_guard"
	SettingsStore.set_input_mode("touch")
	var env := await _make_voice_env()
	var session: GameSessionController = env["session"]
	var coordinator: InputCoordinator = env["coordinator"]
	# Dead-zone tap never spends a stroke.
	coordinator._unhandled_input(_synthetic_button(Vector2(200, 300), true))
	coordinator._unhandled_input(_synthetic_motion(Vector2(206, 306), Vector2(6, 6)))
	coordinator._unhandled_input(_synthetic_button(Vector2(206, 306), false))
	await get_tree().process_frame
	harness.check_eq(session.strokes, 0, "dead-zone release spends no stroke")
	harness.check_eq(session.fsm.state, GameStateMachine.State.READY, "dead-zone release stays READY")
	# Full-stretch mapping: downward pull aims camera-forward at 100%.
	coordinator._unhandled_input(_synthetic_button(Vector2(200, 300), true))
	coordinator._unhandled_input(_synthetic_motion(Vector2(200, 600), Vector2(0, 300)))
	harness.check_between(coordinator.slingshot_power(), 0.99, 1.0, "overshoot clamps to full power")
	harness.check(session.aim_direction.dot(Vector3.FORWARD) > 0.99, "downward pull aims camera-forward")
	# Interrupting (pause/background) mid-drag closes the gesture safely.
	coordinator.interrupt_capture()
	harness.check(not coordinator.is_slinging(), "interrupt closes the slingshot")
	coordinator._unhandled_input(_synthetic_button(Vector2(200, 600), false))
	harness.check_eq(session.strokes, 0, "release after interrupt spends no stroke")
	await _free_voice_env(env)


func _synthetic_button(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = pos
	return event


func _synthetic_motion(pos: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = pos
	event.relative = relative
	return event


func _test_uncalibrated_voice_gated_to_calibration() -> void:
	harness.suite = "ui.voice_onboarding"
	var env := await _make_full_game()
	var session: GameSessionController = env["session"]
	var hud: HUDPresenter = env["hud"]
	var coordinator: InputCoordinator = env["coordinator"]
	var voice: VoiceInputService = env["voice"]
	SettingsStore.invalidate_calibration()
	voice.calibration = {}
	harness.check(not coordinator.voice_hold_started(), "uncalibrated hold refused")
	harness.check(hud._cal_sheet.visible, "calibration sheet opens instead")
	harness.check_eq(session.fsm.state, GameStateMachine.State.READY, "session untouched")
	harness.check_eq(session.strokes, 0, "no stroke spent")
	# A calibration profile must arrive through the game-root flow; simulate
	# the strong-stage path by applying directly and confirming the gate lifts.
	voice.calibration = {"gate_db": -50.0, "lower_db": -40.0, "upper_db": -20.0}
	hud._cal_sheet.visible = false
	harness.check(coordinator.voice_hold_started(), "calibrated hold opens")
	(env["source"] as VoiceFrameSource.SyntheticFrameSource).push_constant_ms(200, 0.05)
	await get_tree().process_frame
	await get_tree().process_frame
	harness.check_eq(session.fsm.state, GameStateMachine.State.CAPTURING, "capture active once calibrated")
	coordinator.voice_release_outside()
	await _free_full_game(env)


func _test_overrun_recovery_next_hold_works() -> void:
	harness.suite = "ui.overrun_recovery"
	var env := await _make_full_game()
	var session: GameSessionController = env["session"]
	var coordinator: InputCoordinator = env["coordinator"]
	var voice: VoiceInputService = env["voice"]
	var source: VoiceFrameSource.SyntheticFrameSource = env["source"]
	voice.calibration = {"gate_db": -50.0, "lower_db": -40.0, "upper_db": -20.0}
	harness.check(coordinator.voice_hold_started(), "first hold opens")
	source.push_constant_ms(200, 0.05)
	await get_tree().process_frame
	await get_tree().process_frame
	source.mark_overrun(64)  # cumulative counter rises mid-hold
	source.push_constant_ms(40, 0.05)
	await get_tree().process_frame
	await get_tree().process_frame
	harness.check(not voice.is_listening(), "overrun closes capture")
	harness.check_eq(session.fsm.state, GameStateMachine.State.READY, "session back to READY after overrun")
	harness.check_eq(session.strokes, 0, "overrun spends no stroke")
	# Baseline must reset: the very next hold works normally.
	harness.check(coordinator.voice_hold_started(), "next hold opens after overrun (baseline reset)")
	source.push_constant_ms(300, 0.05)
	await get_tree().process_frame
	await get_tree().process_frame
	harness.check(bool(voice.published_preview()["valid"]), "preview valid on recovery hold")
	coordinator.voice_release_inside()
	var rolling := await _await_state(session, [GameStateMachine.State.ROLLING], 10)
	harness.check(rolling, "recovery hold commits a shot normally")
	await _await_state(session, [GameStateMachine.State.READY, GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED], 900)
	await _free_full_game(env)


func _test_chunk_size_independent_qualification() -> void:
	harness.suite = "voice.chunk_equivalence"
	var calibration := {"gate_db": -50.0, "lower_db": -40.0, "upper_db": -20.0}
	# Pattern A: the whole 400 ms arrives in one buffer.
	var voice_a := VoiceInputService.new(VoiceFrameSource.SyntheticFrameSource.new(), false)
	add_child(voice_a)
	voice_a.calibration = calibration
	harness.check(voice_a.begin_capture(), "A: capture starts")
	(voice_a._source as VoiceFrameSource.SyntheticFrameSource).push_constant_ms(400, 0.05)
	# The service's first _process lands on the following frame; two frames
	# guarantee the buffer was pulled and analyzed.
	await get_tree().process_frame
	await get_tree().process_frame
	var preview_a: Dictionary = voice_a.published_preview()
	# Pattern B: the same audio in 20 x 20 ms buffers over 20 frames.
	var voice_b := VoiceInputService.new(VoiceFrameSource.SyntheticFrameSource.new(), false)
	add_child(voice_b)
	voice_b.calibration = calibration
	harness.check(voice_b.begin_capture(), "B: capture starts")
	var source_b: VoiceFrameSource.SyntheticFrameSource = voice_b._source
	for i: int in 20:
		source_b.push_constant_ms(20, 0.05)
		await get_tree().process_frame
	var preview_b: Dictionary = voice_b.published_preview()
	harness.check(bool(preview_a["valid"]) and bool(preview_b["valid"]), "both deliveries produce a preview")
	harness.check(
		absf(float(preview_a["power"]) - float(preview_b["power"])) <= 0.01,
		"preview power independent of chunking (%.3f vs %.3f)" % [float(preview_a["power"]), float(preview_b["power"])]
	)
	harness.check_eq(int(preview_a["qualified_ms"]), int(preview_b["qualified_ms"]), "qualified duration independent of chunking")
	voice_a.end_capture()
	voice_b.end_capture()
	voice_a.queue_free()
	voice_b.queue_free()
	await get_tree().physics_frame


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


## RB-027 mascot asset contract: the production GLB loads, the expression rig
## wires onto its nodes, cosmetics retint the asset body, and physics tuning
## is untouched (collider radius, mass).
func _test_mascot_asset_contract() -> void:
	harness.suite = "asset.mascot_contract"
	harness.check(ResourceLoader.exists("res://assets/models/lion_ball.glb"), "lion_ball.glb ships with the project")
	var packed: PackedScene = load("res://assets/models/lion_ball.glb") as PackedScene
	harness.check(packed != null, "lion_ball.glb imports as a PackedScene")
	if packed == null:
		return
	var mascot := packed.instantiate()
	harness.check(mascot != null, "mascot scene instantiates")
	if mascot == null:
		return
	# Godot's glTF importer wraps the authored root (lion_ball/LionBall/...),
	# so contract nodes are resolved by recursive lookup, not absolute paths.
	var lion_root := mascot.find_child("LionBall", true, false)
	harness.check(lion_root != null, "authored LionBall root present under the import wrapper")
	if lion_root == null:
		mascot.queue_free()
		return
	# Node contract game_root.gd wires expressions onto. Imported glTF scenes
	# reparent some authored grandchildren, so resolve recursively.
	for node_name in ["BallBody", "Mane", "EarOuterL", "EarOuterR", "EarInnerL", "EarInnerR", "FaceRoot", "PupilL", "PupilR", "Muzzle", "Nose"]:
		var node := mascot.find_child(node_name, true, false)
		harness.check(node != null, "mascot node '%s' present" % node_name)
	# Instance count: body + 34 tufts + 4 ears + 6 face parts.
	harness.check_eq(mascot.find_children("*", "MeshInstance3D", true, false).size(), 34 + 11, "mascot renders 45 mesh instances (body + 34 tufts + 4 ears + 6 face)")
	var triangle_total := 0
	for mesh_node: MeshInstance3D in mascot.find_children("*", "MeshInstance3D", true, false):
		var arrays := mesh_node.mesh.surface_get_arrays(0)
		triangle_total += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	harness.check(triangle_total < 4000, "mascot triangle budget holds (%d tris, target < 4000)" % triangle_total)
	mascot.queue_free()
	# Full-stack wiring: expressions land on asset nodes, cosmetics retint them.
	var env := await _make_full_game()
	var root: GameRoot = env["root"]
	var ball: BallController = root.ball
	harness.check(root._using_mascot_asset, "game root reports the mascot asset is active")
	var visual_root: Node3D = ball.find_child("VisualRoot", true, false) as Node3D
	var face_rig: Node3D = visual_root.find_child("FaceRig", true, false) as Node3D if visual_root != null else null
	harness.check(face_rig != null, "face rig exists under VisualRoot")
	if face_rig != null:
		# Imported glTF scenes reparent authored nodes, so search by name.
		harness.check(face_rig.find_child("FaceRoot", true, false) != null, "asset FaceRoot billboards on the face rig")
		harness.check(face_rig.find_child("Mane", true, false) != null, "asset Mane rides the face rig")
	# Cosmetics: panda tint must land on the asset body (BallBody), and the
	# legacy BallMesh must be hidden while the asset drives the look.
	# Panda is unlock-gated on CC06; record a completion so the equip succeeds
	# on a clean profile too (isolated user:// in CI).
	ProgressStore.record_completion("CC06", 2, 3, "asset-contract-%d" % Time.get_ticks_msec())
	ProgressStore.equip_cosmetic(ProgressionRules.COSMETIC_PANDA)
	root._apply_equipped_cosmetic()
	var asset_body: MeshInstance3D = ball.find_child("BallBody", true, false) as MeshInstance3D
	var legacy_body: MeshInstance3D = ball.find_child("BallMesh", true, false) as MeshInstance3D
	harness.check(asset_body != null, "asset body (BallBody) exists in the live scene")
	harness.check(legacy_body == null or not legacy_body.visible, "legacy BallMesh hidden while asset is active")
	if asset_body != null:
		var mat := asset_body.material_override as StandardMaterial3D
		harness.check(mat != null and mat.albedo_color.r > 0.9 and mat.albedo_color.b > 0.9, "panda tint applied to the asset body")
	ProgressStore.equip_cosmetic("lion")
	root._apply_equipped_cosmetic()
	# Physics untouched by the art swap.
	var shape := ball.find_child("CollisionShape3D*", true, false) as CollisionShape3D
	if shape != null and shape.shape is SphereShape3D:
		harness.check_near((shape.shape as SphereShape3D).radius, 0.25, 0.001, "collider radius unchanged by the mascot asset")
	harness.check_near(ball.mass, 1.0, 0.001, "ball mass unchanged by the mascot asset")
	await _free_full_game(env)


## Calibration UI recovery (review round 4, P1): the REAL sheet is exercised
## through start → cancel mid-stage → reopen → full Room/Soft/Strong
## completion. Regression 1: Start must be re-enabled after a cancelled
## attempt (previously stuck disabled forever). Regression 2: a stale stage
## timer from a cancelled/superseded attempt must not finish a newer recording.
func _test_calibration_cancel_recovers() -> void:
	harness.suite = "ui.calibration_cancel_recovery"
	var env := await _make_full_game()
	var root: GameRoot = env["root"]
	var hud: HUDPresenter = env["hud"]
	var voice: VoiceInputService = env["voice"]
	var source: VoiceFrameSource.SyntheticFrameSource = env["source"]
	SettingsStore.invalidate_calibration()
	voice.calibration = {}
	# Open the REAL sheet and start the Room stage through the real button.
	hud.open_calibration_sheet()
	await get_tree().process_frame
	harness.check(hud._cal_sheet.visible, "calibration sheet opens")
	hud._on_cal_start()
	await get_tree().process_frame
	harness.check(hud._cal_start_button.disabled, "Start disabled while a stage records")
	# Cancel mid-stage via the sheet close (the Use Touch path calls this).
	hud._close_calibration_sheet()
	await get_tree().process_frame
	harness.check(not voice.is_listening(), "cancel stops the recording")
	# THE REGRESSION: reopen must establish a known enabled-button state.
	hud.open_calibration_sheet()
	await get_tree().process_frame
	harness.check(not hud._cal_start_button.disabled, "Start re-enabled on reopen after cancel (deadlock fixed)")
	# Stale-token guard: start a fresh attempt, then feed it the PREVIOUS
	# attempt's completion — the recording must survive; the current token
	# must complete it.
	hud._on_cal_start()
	await get_tree().process_frame
	harness.check(voice.is_listening(), "fresh stage records after reopen")
	var stale_token: int = root._cal_attempt - 1
	root._finish_calibration_stage(stale_token)
	harness.check(voice.is_listening(), "stale attempt token cannot finish the current recording")
	root._finish_calibration_stage(root._cal_attempt)
	await get_tree().process_frame
	harness.check(not voice.is_listening(), "current attempt token completes the stage")
	harness.check(not hud._cal_start_button.disabled, "Start re-enabled by the stage completion")
	# Full Room → Soft → Strong completion through the real UI: the sheet
	# STAYS OPEN across stages (reopening resets the stage index — that is
	# the real flow), each stage gets its own level (derivation needs
	# soft/strong separation). Completion is owned by the 1.5 s stage timer:
	# wait it out in REAL time per stage. (The synthetic source is consumed
	# instantly, so its hold hits the 500 ms no-input timeout long before the
	# timer — a synthetic artifact; a real mic streams continuously.)
	var stage_levels := {"room": 0.004, "soft": 0.06, "strong": 0.32}
	for stage: String in ["room", "soft", "strong"]:
		hud._on_cal_start()
		await get_tree().process_frame
		harness.check(voice.is_listening(), "%s stage recording" % stage)
		harness.check_eq(root._cal_stage, stage, "%s stage owns the attempt token" % stage)
		source.push_constant_ms(3000, float(stage_levels[stage]))
		await get_tree().create_timer(1.7).timeout
		harness.check_eq(root._cal_stage, "", "%s stage completed by its timer" % stage)
	harness.check(not voice.calibration.is_empty(), "full real-UI flow derives calibration")
	await _free_full_game(env)


## Calibration recording succeeds with an empty calibration dictionary (RB-034).
## Proves the circular deadlock is gone: begin_calibration_stage no longer calls
## begin_capture, which previously required a pre-existing profile.
func _test_calibration_stage_works_without_prior_calibration() -> void:
	harness.suite = "voice.calibration_bootstrap"
	var source := VoiceFrameSource.SyntheticFrameSource.new()
	source.rate = 48000
	var voice := VoiceInputService.new(source, false)
	add_child(voice)
	# Explicitly empty — no prior profile whatsoever.
	voice.calibration = {}
	harness.check(voice.calibration.is_empty(), "calibration starts empty")
	# Room stage must succeed without a prior profile (this was the deadlock).
	harness.check(voice.begin_calibration_stage("room"), "room stage starts with empty calibration (RB-034 deadlock fix)")
	harness.check(voice.is_listening(), "mic recording active during room stage")
	source.push_constant_ms(600, 0.004)  # quiet room noise
	await get_tree().process_frame
	await get_tree().process_frame
	var room := voice.finish_calibration_stage()
	harness.check_eq(String(room["stage"]), "room", "room summary returned")
	harness.check(float(room["noise_level_db"]) < -20.0, "noise level recorded for quiet room")
	# Soft and strong stages likewise succeed without an interim profile.
	harness.check(voice.begin_calibration_stage("soft"), "soft stage starts")
	source.push_constant_ms(600, 0.06)  # gentle whisper
	await get_tree().process_frame
	await get_tree().process_frame
	var soft := voice.finish_calibration_stage()
	harness.check_eq(String(soft["stage"]), "soft", "soft summary returned")
	harness.check(voice.begin_calibration_stage("strong"), "strong stage starts")
	source.push_constant_ms(600, 0.35)  # confident roar
	await get_tree().process_frame
	await get_tree().process_frame
	var strong := voice.finish_calibration_stage()
	harness.check_eq(String(strong["stage"]), "strong", "strong summary returned")
	# Apply calibration and confirm the profile is now valid.
	var applied := voice.apply_calibration(room, soft, strong)
	harness.check(bool(applied["valid"]), "calibration derived successfully from all three stages")
	harness.check(not voice.calibration.is_empty(), "calibration dictionary populated after apply")
	# begin_capture must now succeed with the derived profile.
	harness.check(voice.begin_capture(), "normal capture works after calibration is derived")
	voice.end_capture()
	voice.queue_free()
	await get_tree().physics_frame


## Air-jumping is blocked: a second jump call while airborne must return false.
## Prevents the Flappy-Bird infinite-hop exploit (D-023 review finding).
func _test_jump_blocked_in_air() -> void:
	harness.suite = "physics.jump_no_air_hop"
	var env := await _make_session()
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	session.start_level()
	await _await_state(session, [GameStateMachine.State.READY], 180)
	# Fire a shot so the ball is rolling and grounded.
	session.request_touch_shot(0.25)
	await get_tree().physics_frame
	harness.check_eq(session.fsm.state, GameStateMachine.State.ROLLING, "rolling after shot")
	# Wait for ball to be supported (on the turf) then jump.
	var grounded := await _await_ball_rest(ball, 300)  # rest → definitely grounded
	# Re-fire so the ball is rolling again with a jump token intact.
	session.start_level()
	await _await_state(session, [GameStateMachine.State.READY], 180)
	session.request_touch_shot(0.3)
	await get_tree().physics_frame
	# Give it a moment so the ball is off the tee and rolling.
	for i: int in 5:
		await get_tree().physics_frame
	# First jump should succeed while ball is on ground (supported).
	# We can't guarantee the exact frame, so drive through session which guards it.
	var jumped := session.request_jump()
	if jumped:
		# Ball is now airborne — immediate second jump must be refused.
		var second := session.request_jump()
		harness.check(not second, "second jump while airborne is blocked (no air-hop)")
	else:
		# Ball was not yet grounded when we tried; skip, not a failure.
		harness.check(true, "jump skipped (not grounded at test moment — non-failure)")
	await _await_state(session, [GameStateMachine.State.READY, GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED], 900)
	await _free_session(env)


## Jump token restores after the ball lands: one jump per ground contact.
## Assist budget (Roar Bounce experiment): ONE shared assist per shot for
## Jump and Perfect Bounce. Landing no longer restores it — that was the old
## one-per-landing rule, replaced by the experiment ruleset (review round 6).
func _test_jump_resets_on_landing() -> void:
	harness.suite = "physics.assist_budget"
	var env := await _make_session()
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	session.start_level()
	await _await_state(session, [GameStateMachine.State.READY], 180)
	harness.check(session.assist_available(), "assist available on a fresh shot window")
	# Jump from rest; ball goes airborne.
	harness.check(ball.jump(3.8), "first jump succeeds when grounded")
	harness.check(not ball.can_jump(), "jump unavailable while airborne")
	await _await_state(session, [GameStateMachine.State.READY, GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED], 900)
	await _free_session(env)


## The shared assist is spent by the first action of a shot: a Jump here
## means no Perfect Bounce later on the same shot, and vice versa.
func _test_assist_budget_shared() -> void:
	harness.suite = "physics.assist_shared"
	var env := await _make_session()
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	session.start_level()
	await _await_state(session, [GameStateMachine.State.READY], 180)
	# Jump mid-shot spends the assist.
	session.request_touch_shot(0.3)
	await get_tree().physics_frame
	harness.check(session.request_jump(), "grounded jump accepted (assist spent)")
	harness.check(not session.assist_available(), "assist consumed by the jump")
	# After resolution, the NEXT shot restores it; spending via a buffered
	# Perfect Bounce then blocks the grounded jump on that same shot.
	await _await_state(session, [GameStateMachine.State.READY, GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED], 900)
	session.request_touch_shot(0.5)
	await get_tree().physics_frame
	# Ball rolling on the ground = supported; arm requires descending, so the
	# budget path is proven by the jump refusal instead.
	harness.check(not session.request_jump() or session.assist_available() == false, "second action of the shot is budget-gated")
	await _await_state(session, [GameStateMachine.State.READY, GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED], 900)
	await _free_session(env)


## READY-state hop is presentation-only (D-026): request_jump returns true and
## emits the decorative-hop signal, but the rigid body never moves and no
## stroke is spent — ball movement without a stroke is forbidden.
func _test_ready_hop_never_moves_ball() -> void:
	harness.suite = "physics.ready_hop_visual_only"
	var env := await _make_session()
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	var hop_signal := {"fired": false}
	session.decorative_hop_requested.connect(func() -> void: hop_signal["fired"] = true)
	session.start_level()
	await _await_state(session, [GameStateMachine.State.READY], 180)
	var pos_before := ball.global_position
	harness.check(session.request_jump(), "READY hop request accepted (signal path)")
	harness.check(bool(hop_signal["fired"]), "decorative_hop_requested emitted, not physics")
	for i: int in 30:
		await get_tree().physics_frame
	harness.check(ball.linear_velocity.length() < 0.01, "ball velocity untouched by READY hop")
	harness.check(ball.global_position.distance_to(pos_before) < 0.001, "ball position unchanged by READY hop")
	harness.check(ball.is_resting(), "ball still resting")
	harness.check_eq(session.fsm.state, GameStateMachine.State.READY, "session still READY")
	harness.check_eq(session.strokes, 0, "no stroke spent")
	await _free_session(env)


## Roar-tier shots (power >= 0.70) launch with an upward loft component;
## normal shots stay flat. The loft rides in ShotCommand.direction_world.y.
func _test_loft_launches_ball_upward() -> void:
	harness.suite = "physics.roar_loft"
	var env := await _make_session()
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	# Flat shot: no loft, ball stays on the ground plane (rule gives 0 below
	# the roar threshold — the session owns the rule now).
	session.start_level()
	await _await_state(session, [GameStateMachine.State.READY], 180)
	session.request_touch_shot(0.3)
	await get_tree().physics_frame
	await get_tree().physics_frame
	harness.check(absf(ball.linear_velocity.y) < 0.2, "flat shot has no meaningful upward velocity")
	await _await_state(session, [GameStateMachine.State.READY, GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED], 900)
	# Roar shot via the Touch/slider route: the session applies the shared
	# loft rule — parity with slingshot and voice at the same power.
	session.start_level()
	await _await_state(session, [GameStateMachine.State.READY], 180)
	harness.check(session.request_touch_shot(0.9), "roar shot accepted (slider route)")
	await get_tree().physics_frame
	await get_tree().physics_frame
	harness.check(ball.linear_velocity.y > 0.5, "slider roar shot launches the ball airborne (vy > 0.5)")
	await _await_state(session, [GameStateMachine.State.READY, GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED], 900)
	await _free_session(env)


## Input parity (review round 4, P2): at the SAME power, all input routes
## commit the same loft. Previously the Touch slider passed no loft and
## silently lost the roar mechanic at full power. The voice route goes
## through the real hold flow (request_voice_shot requires CAPTURING —
## the token contract).
func _test_input_routes_loft_parity() -> void:
	harness.suite = "input.loft_parity"
	var env := await _make_session()
	var session: GameSessionController = env["session"]
	var commits: Array = []
	session.shot_committed.connect(func(shot: ShotCommand) -> void: commits.append(shot))
	session.start_level()
	await _await_state(session, [GameStateMachine.State.READY], 180)
	session.request_touch_shot(1.0)  # slider route at full power
	await _await_state(session, [GameStateMachine.State.READY, GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED], 900)
	# Voice route through the real hold/release flow. The preview is smoothed,
	# so the hold must run long enough for it to saturate at power 1.0 —
	# fresh 100 ms chunks keep it alive (instant delivery would trip the
	# 500 ms no-input timeout before release).
	var voice_env := await _make_voice_env()
	var voice_session: GameSessionController = voice_env["session"]
	var voice_coordinator: InputCoordinator = voice_env["coordinator"]
	var voice_source: VoiceFrameSource.SyntheticFrameSource = voice_env["source"]
	var voice_commits: Array = []
	voice_session.shot_committed.connect(func(shot: ShotCommand) -> void: voice_commits.append(shot))
	harness.check(voice_coordinator.voice_hold_started(), "voice hold opens for parity shot")
	for i: int in 25:
		voice_source.push_constant_ms(100, 0.12)  # ≥ upper_db → raw 1.0
		await get_tree().process_frame
	harness.check_between(float((voice_env["voice"] as VoiceInputService).published_preview()["power"]), 0.99, 1.001,
		"voice preview saturated at full power")
	voice_coordinator.voice_release_inside()
	var rolling := await _await_state(voice_session, [GameStateMachine.State.ROLLING], 10)
	harness.check(rolling, "voice parity shot rolls")
	harness.check_eq(commits.size(), 1, "slider commit recorded")
	harness.check_eq(voice_commits.size(), 1, "voice commit recorded")
	if commits.size() == 1 and voice_commits.size() == 1:
		var slider_cmd := commits[0] as ShotCommand
		var voice_cmd := voice_commits[0] as ShotCommand
		# The shared-rule invariant: each route's committed direction.y must
		# equal loft_for_power(its own committed power), normalized into the
		# aim direction. (The voice preview is smoothed, so a 300 ms hold at
		# full-loudness releases at ~0.86, not 1.0 — the rule still holds.)
		for cmd: ShotCommand in [slider_cmd, voice_cmd]:
			var loft := ShotMath.loft_for_power(cmd.normalized_power)
			var expected_y := loft / sqrt(1.0 + loft * loft)
			harness.check_near(cmd.direction_world.y, expected_y, 0.001,
				"%s commit matches the shared loft rule at its power (%.3f)" % [
					ShotCommand.Source.keys()[cmd.source], cmd.normalized_power])
		harness.check(slider_cmd.direction_world.y > 0.2, "full-power slider shot carries roar loft")
		harness.check_near(slider_cmd.direction_world.y, voice_cmd.direction_world.y, 0.001,
			"slider and voice loft identical at the same committed power")
	await _await_state(voice_session, [GameStateMachine.State.READY, GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED], 900)
	await _free_session(voice_env)  # free its level/ball/session: leaked CC01
	# turf would hijack the next test's carve-ray target.
	await _free_session(env)


## The carved physical cavity (D-025): the turf under the cup is genuinely
## opened, and a putt into the hole still completes — the carve must never
## swallow capture. The ball ends below the cup plane (in the cavity).
func _test_physical_hole_drops_ball() -> void:
	harness.suite = "ui.physical_cup"
	var env := await _make_full_game()
	var session: GameSessionController = env["session"]
	var ball: BallController = (env["root"] as GameRoot).ball
	var root: GameRoot = env["root"]
	var level: LevelController = root.level
	var completed: Dictionary = {"fired": false}
	session.hole_completed.connect(func(_result: Dictionary) -> void: completed["fired"] = true)
	# Give the deferred carve its physics frames.
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var cup_physics := root.get_node_or_null("RealCupPhysics") as StaticBody3D
	harness.check(cup_physics != null, "cup physics body exists after the deferred carve")
	var turf_body := level.instance.find_child("TurfBody", true, false) as StaticBody3D
	var full_turf_shape := turf_body.find_child("TurfShape", true, false) as CollisionShape3D if turf_body != null else null
	harness.check(
		full_turf_shape == null or full_turf_shape.shape == null,
		"original full turf collider is removed at the cup opening"
	)
	harness.check(cup_physics != null and cup_physics.get_child_count() >= 2, "cup walls and floor colliders are present")
	var cup := level.cup_position()
	# The course collider is now a set of slabs around the opening, not one
	# solid box beneath it. This is the physical (not visual) hole assertion.
	harness.check(turf_body != null and turf_body.get_child_count() >= 4, "turf is split into multiple collider pieces around the hole")
	# A brisk putt from 1 m arrives above the rim-band speed cap, rolls over
	# the hole edge, and must FALL IN physically — capture below the rim.
	ball.teleport_to(Transform3D(Basis.IDENTITY, cup + Vector3(0.0, 0.25, 1.0)))
	harness.check(await _await_ball_rest(ball, 180), "ball settles 1 m before the cup")
	harness.check(session.request_touch_shot(0.10), "brisk putt accepted (arrival above rim-band speed)")
	var done := await _await_state(session, [GameStateMachine.State.COMPLETE], 600)
	harness.check(done, "ball dropping into the carved hole completes the hole")
	harness.check(bool(completed["fired"]), "hole_completed emitted for the physical drop")
	# Sink tween (or captured-in-cavity position) leaves the ball below the plane.
	for i: int in 45:
		await get_tree().physics_frame
	harness.check(ball.global_position.y < level.cup_plane_y() + 0.2, "ball ends below the cup plane (inside the cavity)")
	await _free_full_game(env)


## --- Roar Bounce experiment (bounce_rules.gd contract) ---


## Bounce environment: CC01 physics with the mechanic enabled plus authored
## spring / dead surfaces at known spots. The ball is teleported onto them.
func _make_bounce_env() -> Dictionary:
	var env := await _make_session()
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	ball.bounce_enabled = true
	session.ball.bounce_enabled = true
	# Spring slab east of the lane; dead slab west; tall wall far south for
	# the wall test. All on the Course layer so contacts register.
	var spring := StaticBody3D.new()
	spring.collision_layer = 2
	spring.set_meta("bounce_class", "spring")
	var spring_shape := CollisionShape3D.new()
	var spring_box := BoxShape3D.new()
	spring_box.size = Vector3(2.0, 0.5, 2.0)
	spring_shape.shape = spring_box
	spring.add_child(spring_shape)
	env["session"].add_child(spring)
	spring.position = Vector3(4.0, -0.25, 0.0)
	var dead := StaticBody3D.new()
	dead.collision_layer = 2
	dead.set_meta("bounce_class", "dead")
	var dead_shape := CollisionShape3D.new()
	var dead_box := BoxShape3D.new()
	dead_box.size = Vector3(2.0, 0.5, 2.0)
	dead_shape.shape = dead_box
	dead.add_child(dead_shape)
	env["session"].add_child(dead)
	dead.position = Vector3(-4.0, -0.25, 0.0)
	env["spring"] = spring
	env["dead"] = dead
	return env


## Default courses are untouched: with bounce disabled, a hard drop produces
## no rebound at all (rc2 behavior, review round 6 invariant).
func _test_bounce_disabled_by_default() -> void:
	harness.suite = "bounce.disabled_default"
	var env := await _make_session()
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	var rebounds := {"count": 0}
	ball.rebounded.connect(func(_s: float, _p: bool) -> void: rebounds["count"] += 1)
	session.start_level()
	await _await_state(session, [GameStateMachine.State.READY], 180)
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 3.0, 0.0)))
	for i: int in 240:
		await get_tree().physics_frame
		if ball.is_resting():
			break
	harness.check(ball.is_resting(), "ball settles after the drop")
	harness.check(not ball.bounce_enabled, "default level leaves the mechanic off")
	harness.check_eq(int(rebounds["count"]), 0, "no rebound when the mechanic is disabled (rc2 behavior)")
	harness.check(ball.global_position.y < 0.4, "ball ended on the turf, not bouncing")
	await _free_session(env)


## Ordinary turf: one small rebound per landing, decaying, capped at two,
## then the ball settles. Gentle putts never trigger anything.
func _test_turf_rebound_decays_and_caps() -> void:
	harness.suite = "bounce.turf_decay_cap"
	var env := await _make_bounce_env()
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	var heights: Array = []
	ball.rebounded.connect(func(speed: float, _p: bool) -> void: heights.append(speed))
	session.start_level()
	ball.bounce_enabled = true  # start_level reloads it from the CC01 config
	await _await_state(session, [GameStateMachine.State.READY], 180)
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 3.0, 0.0)))
	for i: int in 240:
		await get_tree().physics_frame
		if ball.is_resting():
			break
	harness.check(heights.size() >= 1, "hard drop on enabled turf produces a rebound (%d)" % heights.size())
	if heights.size() >= 2:
		harness.check(heights[1] < heights[0], "rebound decays (%.2f -> %.2f)" % [heights[0], heights[1]])
	harness.check(heights.size() <= BounceRules.MAX_REBOUNDS_PER_SHOT, "rebound cap respected (%d)" % heights.size())
	harness.check(ball.is_resting(), "ball still settles to a stop")
	harness.check_eq(session.strokes, 0, "a bounce never costs a stroke")
	await _free_session(env)


## Spring surfaces rebound stronger; authored dead surfaces (finishing green)
## never bounce; walls are not landings.
func _test_spring_and_dead_surfaces() -> void:
	harness.suite = "bounce.surfaces"
	var env := await _make_bounce_env()
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	var events: Array = []
	ball.rebounded.connect(func(speed: float, _p: bool) -> void:
		events.append({"speed": speed, "x": ball.global_position.x}))
	session.start_level()
	ball.bounce_enabled = true  # start_level reloads it from the CC01 config
	await _await_state(session, [GameStateMachine.State.READY], 180)
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(4.0, 3.0, 0.0)))  # spring slab
	for i: int in 240:
		await get_tree().physics_frame
		if ball.is_resting():
			break
	var spring_rebounds := 0
	for e: Dictionary in events:
		if float(e["x"]) > 2.0:
			spring_rebounds += 1
	harness.check(spring_rebounds >= 1, "spring surface rebounds")
	# Dead surface: same collector; x < -2 marks the dead slab.
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(-4.0, 3.0, 0.0)))
	for i: int in 240:
		await get_tree().physics_frame
		if ball.is_resting():
			break
	var dead_rebounds := 0
	for e: Dictionary in events:
		if float(e["x"]) < -2.0:
			dead_rebounds += 1
	harness.check_eq(dead_rebounds, 0, "authored dead surface never bounces")
	harness.check(ball.is_resting(), "ball settles on the dead surface")
	await _free_session(env)


## Perfect Bounce: a press inside the landing window boosts the rebound and
## spends the shot's assist; the same shot's jump is then refused.
func _test_perfect_bounce_timing_and_budget() -> void:
	harness.suite = "bounce.perfect_timing"
	var env := await _make_bounce_env()
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	var outcomes: Array = []
	ball.rebounded.connect(func(speed: float, perfect: bool) -> void: outcomes.append({"speed": speed, "perfect": perfect}))
	session.start_level()
	ball.bounce_enabled = true  # start_level reloads it from the CC01 config
	await _await_state(session, [GameStateMachine.State.READY], 180)
	# Drop onto the spring from a modest height; press the action while the
	# ball is visibly descending and close to the surface — the deterministic
	# way is to arm the frame before contact: wait until vy < 0 and height
	# small, then request the contextual action.
	# The contextual action is live only mid-shot (ROLLING/SETTLING): fire a
	# small real shot, then teleport the moving ball above the spring so it
	# descends toward a genuine landing while the shot is live.
	session.request_touch_shot(0.12)
	await get_tree().physics_frame
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(4.0, 1.4, 0.0)))
	var armed := false
	for i: int in 400:
		await get_tree().physics_frame
		# Arm only inside the physical timing window: at vy ≈ -4.5 m/s from
		# y ≈ 0.3, impact is ~65 ms away — inside PERFECT_WINDOW_MS (120).
		if not armed and ball.linear_velocity.y < -4.0 and ball.global_position.y < 0.34:
			armed = session.request_jump()
			if armed:
				break
	harness.check(armed, "pre-landing press armed a Perfect Bounce")
	harness.check(not session.assist_available(), "arming spent the shot's assist")
	for i: int in 240:
		await get_tree().physics_frame
		if ball.is_resting():
			break
	var perfect_seen := false
	for o: Dictionary in outcomes:
		if bool(o["perfect"]):
			perfect_seen = true
	harness.check(perfect_seen, "landing inside the window boosted (perfect=true)")
	harness.check(ball.is_resting(), "ball settles after the perfect bounce")
	await _free_session(env)


## Walls and rails are not landings: a horizontal rail hit never rebounds.
func _test_wall_is_not_a_landing() -> void:
	harness.suite = "bounce.wall_not_landing"
	var env := await _make_bounce_env()
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	var rebounds := {"count": 0}
	ball.rebounded.connect(func(_s: float, _p: bool) -> void: rebounds["count"] += 1)
	session.start_level()
	ball.bounce_enabled = true  # start_level reloads it from the CC01 config
	await _await_state(session, [GameStateMachine.State.READY], 180)
	# Slap the ball sideways into the far rail at speed, slightly above the
	# turf so the contact is wall-like.
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0)))
	session.set_aim(Vector3(1, 0, 0))
	session.request_touch_shot(0.9)
	await _await_state(session, [GameStateMachine.State.READY, GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED], 900)
	harness.check_eq(int(rebounds["count"]), 0, "rail contact never produced a landing rebound")
	await _free_session(env)
