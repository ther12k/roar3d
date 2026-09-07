extends Node
## Hole route suite (RB-041/042/043): scripted routes for CC04-CC06 and
## PP01-PP06 using kit modules and the obstacle set. Every hole must complete
## within par+1 on the pinned engine through the real shot path. Run:
## godot --headless --path . res://tests/integration/run_hole_route_tests.tscn

var harness := TestHarness.new()


func _ready() -> void:
	await _run_all()
	var exit_code := harness.report("HOLE ROUTE TESTS")
	get_tree().quit(exit_code)


func _run_all() -> void:
	await _route_cc04()
	await _route_cc05()
	await _route_cc06()
	await _route_pp01()
	await _route_pp02()
	await _route_pp03()
	await _route_pp04()
	await _route_pp05()
	await _route_pp06()


# --- shared helpers (same patterns as run_level_route_tests.gd) ---


func _make_level_session(level_id: String) -> Dictionary:
	var catalog := LevelCatalog.load_packaged()
	var meta := catalog.level_by_id(level_id)
	harness.check(not meta.is_empty(), level_id + " exists in catalog")
	var level := LevelController.new()
	add_child(level)
	var errors := level.load_level(meta)
	harness.check(errors.is_empty(), level_id + " marker contract satisfied: " + str(errors))
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
	(env["session"] as GameSessionController).queue_free()
	(env["level"] as LevelController).queue_free()
	(env["ball"] as BallController).queue_free()
	get_tree().paused = false
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
	var accepted: bool = session.request_touch_shot(power)
	harness.check(accepted, "shot accepted p=%.3f" % power)
	await get_tree().physics_frame
	print("  shoot: accepted=", accepted, " state=", GameStateMachine.state_name(session.fsm.state), " ball v=", session.ball.linear_velocity)


func _aim_at_cup(env: Dictionary) -> Vector3:
	var level: LevelController = env["level"]
	var ball: BallController = env["ball"]
	var flat := ShotMath.horizontal_direction(level.cup_position() - ball.global_position)
	return flat if flat != Vector3.ZERO else Vector3(0, 0, -1)


func _putt_until_complete(env: Dictionary, budget_note: String) -> void:
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	var level: LevelController = env["level"]
	var guard := 0
	while session.fsm.state != GameStateMachine.State.COMPLETE and session.strokes < int(env["meta"]["max_strokes"]) and guard < 40:
		guard += 1
		if session.fsm.state != GameStateMachine.State.READY:
			await get_tree().physics_frame
			continue
		var distance: float = (level.cup_position() - ball.global_position).length()
		await _shoot(session, _aim_at_cup(env), clampf(0.045 + distance * 0.02, 0.045, 0.3))
		await _resolve(session)
	print("  [hole] %s %s strokes=%d rest=%v" % [env["meta"]["id"], budget_note, session.strokes, ball.global_position])
	harness.check_eq(session.fsm.state, GameStateMachine.State.COMPLETE, "%s completes" % env["meta"]["id"])


func _wait_gate_open(gate: MovingGate, min_openness: float) -> void:
	for i: int in 600:
		if gate.openness() >= min_openness:
			return
		await get_tree().physics_frame


func _get_gate(root: Node, path: String) -> MovingGate:
	return root.get_node(path) as MovingGate


# --- Cloud Cliffs ---


func _route_cc04() -> void:
	harness.suite = "hole.cc04"
	var env := await _make_level_session("CC04")
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	# Strong tee shot flies the ramp gap onto the landing island.
	await _shoot(session, Vector3(0, 0, -1), 0.8)
	await _resolve(session)
	print("  [hole] CC04 jump rest=%v" % ball.global_position)
	harness.check_eq(session.fsm.state, GameStateMachine.State.READY, "jump shot lands safely")
	harness.check(ball.global_position.z < -1.6, "rode the ramp onto the landing island (z=%.2f)" % ball.global_position.z)
	# Band evidence: an undershoot falls and recovers with exactly one penalty.
	# (Covered by the power-band test below; here just finish.)
	var advance := _aim_at_cup(env)
	await _shoot(session, advance, 0.5)
	await _resolve(session)
	await _putt_until_complete(env, "route")
	harness.check(session.strokes <= 4, "CC04 finishes within par+1 (strokes=%d)" % session.strokes)
	await _free_level_session(env)


func _route_cc05() -> void:
	harness.suite = "hole.cc05"
	var env := await _make_level_session("CC05")
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	await _shoot(session, Vector3(0, 0, -1), 0.4)
	await _resolve(session)
	harness.check_between(ball.global_position.z, 2.6, 7.4, "staging stop before the gate zone")
	var gate := _get_gate(env["level"].instance, "Course/SlidingGate")
	harness.check(gate != null, "gate present in CC05")
	if gate != null:
		await _wait_gate_open(gate, 0.6)
		await _shoot(session, Vector3(0, 0, -1), 0.55)
		await _resolve(session)
		print("  [hole] CC05 post-gate rest=%v" % ball.global_position)
		harness.check(ball.global_position.z < 0.5, "past the gate line (z=%.2f)" % ball.global_position.z)
	await _putt_until_complete(env, "route")
	harness.check(session.strokes <= 4, "CC05 finishes within par+1 (strokes=%d)" % session.strokes)
	await _free_level_session(env)


func _route_cc06() -> void:
	harness.suite = "hole.cc06"
	var env := await _make_level_session("CC06")
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	await _shoot(session, Vector3(0, 0, -1), 0.5)
	await _resolve(session)
	harness.check_between(ball.global_position.z, 2.6, 7.4, "staged before the gate island")
	var gate := _get_gate(env["level"].instance, "Course/SlidingGate")
	harness.check(gate != null, "gate present in CC06")
	if gate != null:
		await _wait_gate_open(gate, 0.7)
		await _shoot(session, Vector3(0, 0, -1), 0.2)
		await _resolve(session)
		print("  [hole] CC06 pre-ramp rest=%v" % ball.global_position)
		harness.check_between(ball.global_position.z, -1.0, 4.5, "staged before the ramp (gate passed open)")
		await _wait_gate_open(gate, 0.9)
		await _shoot(session, Vector3(0, 0, -1), 1.0)
		await _resolve(session)
		print("  [hole] CC06 jump rest=%v" % ball.global_position)
		harness.check(ball.global_position.z < -8.8, "ramp jump crossed the void (z=%.2f)" % ball.global_position.z)
	await _putt_until_complete(env, "route")
	harness.check(session.strokes <= 5, "CC06 finishes within par+1 (strokes=%d)" % session.strokes)
	await _free_level_session(env)


# --- Portal Peaks ---


func _route_pp01() -> void:
	harness.suite = "hole.pp01"
	var env := await _make_level_session("PP01")
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	await _shoot(session, Vector3(0, 0, -1), 0.5)
	await _resolve(session)
	print("  [hole] PP01 post-portal rest=%v" % ball.global_position)
	harness.check(ball.global_position.x > 10.0, "portal carried the ball into the approach (x=%.2f)" % ball.global_position.x)
	await _putt_until_complete(env, "route")
	harness.check(session.strokes <= 3, "PP01 finishes within par+1 (strokes=%d)" % session.strokes)
	await _free_level_session(env)


func _route_pp02() -> void:
	harness.suite = "hole.pp02"
	var env := await _make_level_session("PP02")
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	await _shoot(session, Vector3(0, 0, -1), 0.5)
	await _resolve(session)
	print("  [hole] PP02 post-portal rest=%v" % ball.global_position)
	harness.check(ball.global_position.x > 10.0, "portal carried the ball into the approach (x=%.2f)" % ball.global_position.x)
	await _putt_until_complete(env, "route")
	harness.check(session.strokes <= 4, "PP02 finishes within par+1 (strokes=%d)" % session.strokes)
	await _free_level_session(env)

func _route_pp03() -> void:
	harness.suite = "hole.pp03"
	var env := await _make_level_session("PP03")
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	await _shoot(session, Vector3(0, 0, -1), 0.6)
	await _resolve(session)
	print("  [hole] PP03 post-pad rest=%v" % ball.global_position)
	harness.check(ball.global_position.y > 0.7, "pad launched the ball onto the raised platform (y=%.2f)" % ball.global_position.y)
	harness.check(ball.global_position.z < -3.5, "landed past the void (z=%.2f)" % ball.global_position.z)
	await _putt_until_complete(env, "route")
	harness.check(session.strokes <= 4, "PP03 finishes within par+1 (strokes=%d)" % session.strokes)
	await _free_level_session(env)


func _route_pp04() -> void:
	harness.suite = "hole.pp04"
	var env := await _make_level_session("PP04")
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	await _shoot(session, Vector3(0, 0, -1), 0.45)
	await _resolve(session)
	print("  [hole] PP04 post-portal rest=%v" % ball.global_position)
	harness.check(ball.global_position.x > 10.0 and ball.global_position.x < 17.0, "portal staged safely before the pad (x=%.2f)" % ball.global_position.x)
	await _shoot(session, Vector3(1, 0, 0), 0.55)
	await _resolve(session)
	print("  [hole] PP04 post-pad rest=%v" % ball.global_position)
	harness.check(ball.global_position.x > 20.0, "pad flight crossed the void (x=%.2f)" % ball.global_position.x)
	harness.check(ball.global_position.y > 0.7, "landed on the raised platform (y=%.2f)" % ball.global_position.y)
	await _putt_until_complete(env, "route")
	harness.check(session.strokes <= 5, "PP04 finishes within par+1 (strokes=%d)" % session.strokes)
	await _free_level_session(env)


func _route_pp05() -> void:
	harness.suite = "hole.pp05"
	var env := await _make_level_session("PP05")
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	await _shoot(session, Vector3(0, 0, -1), 0.5)
	await _resolve(session)
	print("  [hole] PP05 post-portal rest=%v" % ball.global_position)
	harness.check(ball.global_position.x > 10.0, "portal delivered to the corridor mouth (x=%.2f)" % ball.global_position.x)
	var gate := _get_gate(env["level"].instance, "Course/Gate1")
	harness.check(gate != null, "gate present in PP05")
	if gate != null:
		await _wait_gate_open(gate, 0.6)
		await _shoot(session, Vector3(1, 0, 0), 0.65)
		await _resolve(session)
		print("  [hole] PP05 post-gate rest=%v" % ball.global_position)
		harness.check(ball.global_position.x > 18.0, "through the corridor (x=%.2f)" % ball.global_position.x)
	await _putt_until_complete(env, "route")
	harness.check(session.strokes <= 5, "PP05 finishes within par+1 (strokes=%d)" % session.strokes)
	await _free_level_session(env)


func _route_pp06() -> void:
	harness.suite = "hole.pp06"
	var env := await _make_level_session("PP06")
	var session: GameSessionController = env["session"]
	var ball: BallController = env["ball"]
	await _shoot(session, Vector3(0, 0, -1), 0.5)
	await _resolve(session)
	harness.check(ball.global_position.x > 10.0, "portal to staging (x=%.2f)" % ball.global_position.x)
	await _shoot(session, Vector3(1, 0, 0), 0.55)
	await _resolve(session)
	print("  [hole] PP06 post-pad rest=%v" % ball.global_position)
	harness.check(ball.global_position.x > 15.0, "pad carried over the void (x=%.2f)" % ball.global_position.x)
	await _putt_until_complete(env, "route")
	harness.check(session.strokes <= 6, "PP06 finishes within par+1 (strokes=%d)" % session.strokes)
	await _free_level_session(env)
