extends Node
## Level route regression (RB-040): CC02 "Soft Landing" and CC03 "Bank Buddy"
## are authored from course-kit modules. Verifies marker contracts, staged
## newcomer routes, forgiving power bands (sweeps, not single values),
## visible-risk recovery, bank-wall routing, and full-stack scene smokes.
## Run: godot --headless --path . res://tests/integration/run_level_route_tests.tscn

var harness := TestHarness.new()


func _ready() -> void:
	await _run_all()
	var exit_code := harness.report("LEVEL ROUTE TESTS")
	get_tree().quit(exit_code)


func _run_all() -> void:
	await _test_marker_contracts()
	await _test_cc02_newcomer_route()
	await _test_cc02_finishing_band()
	await _test_cc02_risk_edge_recovers()
	await _test_cc02_long_route()
	await _test_cc03_bank_route()
	await _test_cc03_bank_band()
	await _test_cc03_two_turn_route()
	await _test_full_stack_smokes()


# --- shared helpers (same patterns as run_integration_tests.gd) ---


func _make_level_session(level_id: String) -> Dictionary:
	var catalog := LevelCatalog.load_packaged()
	var meta := catalog.level_by_id(level_id)
	harness.check(not meta.is_empty(), level_id + " exists in catalog")
	var level := LevelController.new()
	add_child(level)
	var errors := level.load_level(meta)
	harness.check(errors.is_empty(), level_id + " marker contract satisfied: " + str(errors))
	harness.check(catalog.is_playable(level_id), level_id + " catalog-playable (non-design_only + scene exists)")
	var ball := BallController.new()
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	collision.shape = sphere
	ball.add_child(collision)
	add_child(ball)
	var session := GameSessionController.new()
	add_child(session)
	session.setup(ball, level, level_id, int(meta["par"]), int(meta["max_strokes"]))
	session.start_level()
	var ready := await _await_state(session, [GameStateMachine.State.READY], 240)
	harness.check(ready, level_id + " spawn settles to READY")
	return {"catalog": catalog, "meta": meta, "level": level, "ball": ball, "session": session}


func _free_level_session(env: Dictionary) -> void:
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


func _resolve(session: GameSessionController) -> void:
	await _await_state(
		session,
		[GameStateMachine.State.READY, GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED],
		1500
	)


func _shoot(session: GameSessionController, direction: Vector3, power: float) -> void:
	session.set_aim(direction)
	harness.check(session.request_touch_shot(power), "shot accepted p=%.3f" % power)
	await get_tree().physics_frame


func _aim_at_cup(env: Dictionary) -> Vector3:
	var level: LevelController = env["level"]
	var ball: BallController = env["ball"]
	var flat := ShotMath.horizontal_direction(level.cup_position() - ball.global_position)
	return flat if flat != Vector3.ZERO else Vector3(0, 0, -1)


## Distance-scaled finishing putt; the impulse floor dominates short taps.
## Base + slope tuned so putts arrive inside the capture band or slow down
## within the overrun room behind the cup (cup sits >=1.2 m off the back rail).
func _finish_putt_power(distance: float) -> float:
	return clampf(0.045 + distance * 0.02, 0.045, 0.2)


func _putt_until_complete(env: Dictionary, max_extra_strokes: int) -> void:
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	var level: LevelController = env["level"]
	while session.fsm.state != GameStateMachine.State.COMPLETE and session.strokes < int(env["meta"]["max_strokes"]):
		var distance: float = (level.cup_position() - ball.global_position).length()
		await _shoot(session, _aim_at_cup(env), _finish_putt_power(distance))
		await _resolve(session)
		print("  [route] %s stroke %d rest %v" % [env["meta"]["id"], session.strokes, ball.global_position])
	harness.check_eq(session.fsm.state, GameStateMachine.State.COMPLETE, "%s hole completes" % env["meta"]["id"])


# --- contracts ---


func _test_marker_contracts() -> void:
	harness.suite = "route.contracts"
	for level_id: String in ["CC02", "CC03"]:
		var env := await _make_level_session(level_id)
		var level: LevelController = env["level"]
		harness.check(level.has_level(), level_id + " scene instanced")
		harness.check(level.cup_position() != Vector3.ZERO, level_id + " cup position resolved")
		await _free_level_session(env)


# --- CC02: restraint (broad approach, open risky edges, short final green) ---


func _test_cc02_newcomer_route() -> void:
	harness.suite = "route.cc02_newcomer"
	var env := await _make_level_session("CC02")
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	# Shot 1: medium tee shot stops on the broad approach.
	await _shoot(session, Vector3(0, 0, -1), 0.4)
	await _resolve(session)
	print("  [route] CC02 shot1 rest %v" % ball.global_position)
	harness.check_eq(session.fsm.state, GameStateMachine.State.READY, "shot1 resolves safely on the approach")
	harness.check_between(ball.global_position.z, 2.6, 7.4, "shot1 rests on the approach plateau")
	# Shot 2: gentle carry onto the front of the final green.
	await _shoot(session, Vector3(0, 0, -1), 0.2)
	await _resolve(session)
	print("  [route] CC02 shot2 rest %v" % ball.global_position)
	harness.check_eq(session.fsm.state, GameStateMachine.State.READY, "shot2 resolves on the green")
	harness.check_between(ball.global_position.z, -0.8, 1.6, "shot2 rests on the green front")
	# Shot 3: finishing putt completes at par.
	await _putt_until_complete(env, 1)
	harness.check(session.strokes <= 3, "newcomer route finishes at par (strokes=%d)" % session.strokes)
	await _free_level_session(env)


func _test_cc02_finishing_band() -> void:
	harness.suite = "route.cc02_band"
	# Forgiving band: from the green front, several powers complete — not a
	# single exact value (acceptance criterion).
	for power: float in [0.05, 0.065, 0.08]:
		var env := await _make_level_session("CC02")
		var session: GameSessionController = env["session"]
		var ball: BallController = env["ball"]
		ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)))
		for i: int in 240:
			if ball.is_resting():
				break
			await get_tree().physics_frame
		await _shoot(session, Vector3(0, 0, -1), power)
		await _resolve(session)
		var completed := session.fsm.state == GameStateMachine.State.COMPLETE
		print("  [band] CC02 finish p=%.3f -> %s rest %v" % [power, "COMPLETE" if completed else session.fsm.state, ball.global_position])
		harness.check(completed, "CC02 finishing putt completes at p=%.3f (band member)" % power)
		await _free_level_session(env)


func _test_cc02_risk_edge_recovers() -> void:
	harness.suite = "route.cc02_risk"
	var env := await _make_level_session("CC02")
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	# Overpower failure is visible and recoverable (validation check). From the
	# approach, a sideways-overpowered shot falls off the open right plateau
	# edge: exactly one penalty, then play continues.
	await _shoot(session, Vector3(0, 0, -1), 0.4)
	await _resolve(session)
	await _shoot(session, Vector3(0.97, 0, -0.242).normalized(), 0.5)
	var ready_again := await _await_state(session, [GameStateMachine.State.READY], 1200)
	harness.check(ready_again, "edge fall returns to READY (recoverable)")
	harness.check_eq(session.strokes, 3, "two shots + exactly one penalty stroke")
	harness.check(ball.is_resting(), "ball reset and resting")
	await _free_level_session(env)


func _test_cc02_long_route() -> void:
	harness.suite = "route.cc02_long"
	var env := await _make_level_session("CC02")
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	# Strong tee shot crosses the whole approach, bumps the safe outer rail
	# behind the cup, and stops in putt range ("stronger shot banks safely").
	await _shoot(session, Vector3(0, 0, -1), 0.75)
	await _resolve(session)
	print("  [route] CC02 strong shot rest %v" % ball.global_position)
	harness.check_eq(session.fsm.state, GameStateMachine.State.READY, "strong tee shot stays in play (outer rail)")
	harness.check_between(ball.global_position.z, -2.45, -0.8, "strong shot stops near the back rail, not out")
	await _putt_until_complete(env, 1)
	harness.check(session.strokes <= 3, "long route finishes within par (strokes=%d)" % session.strokes)
	await _free_level_session(env)


# --- CC03: bank wall (L-shape) ---


func _test_cc03_bank_route() -> void:
	harness.suite = "route.cc03_bank"
	var env := await _make_level_session("CC03")
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	# Bank: diagonal shot into the corner wall redirects into the corridor and
	# carries all the way onto the bank green in one stroke. The line must be
	# shallow enough to clear the tee's side-rail end (z=-2.5) before the
	# corner, exactly like the kit corner traversal.
	await _shoot(session, Vector3(0.35, 0, -0.937).normalized(), 0.9)
	await _resolve(session)
	print("  [route] CC03 bank shot rest %v" % ball.global_position)
	harness.check_eq(session.fsm.state, GameStateMachine.State.READY, "bank shot resolves safely")
	harness.check(ball.global_position.x > 7.6, "bank shot reached the final green (x=%.2f)" % ball.global_position.x)
	await _putt_until_complete(env, 1)
	harness.check(session.strokes <= 3, "bank route finishes within par (strokes=%d)" % session.strokes)
	await _free_level_session(env)


func _test_cc03_bank_band() -> void:
	harness.suite = "route.cc03_band"
	# Forgiving band: across this power range the bank redirect always carries
	# the ball out of the corner into the corridor; the full carry to the
	# green is the high-power end (measured 7.66 at p=0.9).
	for power: float in [0.8, 0.85, 0.9]:
		var env := await _make_level_session("CC03")
		var session: GameSessionController = env["session"]
		var ball: BallController = env["ball"]
		await _shoot(session, Vector3(0.35, 0, -0.937).normalized(), power)
		await _resolve(session)
		var redirected := ball.global_position.x > 4.5 and session.fsm.state == GameStateMachine.State.READY
		print("  [band] CC03 bank p=%.2f rest %v" % [power, ball.global_position])
		harness.check(redirected, "bank shot redirects into the corridor at p=%.2f (band member)" % power)
		await _free_level_session(env)


func _test_cc03_two_turn_route() -> void:
	harness.suite = "route.cc03_twoturn"
	var env := await _make_level_session("CC03")
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	# Deliberate alternate route: stop in the corner square, run the corridor,
	# then finish (validation check: multiple approaches remain solvable).
	await _shoot(session, Vector3(0, 0, -1), 0.3)
	await _resolve(session)
	print("  [route] CC03 turn1 rest %v" % ball.global_position)
	harness.check_between(ball.global_position.z, -7.4, -2.6, "turn1 stops in the corner square")
	harness.check(absf(ball.global_position.x) < 2.55, "turn1 stays in the corner square")
	await _shoot(session, Vector3(1, 0, 0), 0.4)
	await _resolve(session)
	print("  [route] CC03 turn2 rest %v" % ball.global_position)
	harness.check(ball.global_position.x > 3.5, "turn2 advances along the corridor")
	await _putt_until_complete(env, 2)
	harness.check(session.strokes <= 5, "two-turn route completes within par+2 (strokes=%d)" % session.strokes)
	await _free_level_session(env)


# --- full stack: real game_root per level (camera rig + HUD + session) ---


func _test_full_stack_smokes() -> void:
	harness.suite = "route.smokes"
	for level_id: String in ["CC02", "CC03"]:
		AppRouter.current_level_id = level_id
		var packed: PackedScene = load("res://scenes/game/game_root.tscn")
		harness.check(packed != null, level_id + " game_root loads")
		var root: GameRoot = packed.instantiate()
		add_child(root)
		await get_tree().physics_frame
		var ok := false
		for i: int in 300:
			if root.session.fsm.state == GameStateMachine.State.READY:
				ok = true
				break
			await get_tree().physics_frame
		harness.check(ok, level_id + " full stack reaches READY (camera + HUD + session)")
		var session: GameSessionController = root.session
		session.request_touch_shot(0.3)
		await get_tree().physics_frame
		harness.check_eq(session.strokes, 1, level_id + " touch shot fires through the full stack")
		await _await_state(
			session,
			[GameStateMachine.State.READY, GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED],
			1200
		)
		var level_ref: LevelController = root.level
		root.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame
		harness.check(not is_instance_valid(level_ref) or level_ref.instance == null, level_id + " level torn down on exit")
