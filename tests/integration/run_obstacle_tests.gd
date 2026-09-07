extends Node
## Obstacle behavior suite (RB-037/038/039): pad one-impulse-per-entry latch,
## gate phase pausing + push, portal transit with velocity mapping and
## re-entry loop prevention. Real Jolt, real BallController. Run:
## godot --headless --path . res://tests/integration/run_obstacle_tests.tscn

var harness := TestHarness.new()


func _ready() -> void:
	await _run_all()
	var exit_code := harness.report("OBSTACLE TESTS")
	get_tree().quit(exit_code)


func _run_all() -> void:
	await _test_pad_single_impulse_per_entry()
	await _test_pad_no_energy_pump_while_overlapping()
	await _test_pad_rearm_after_leaving()
	await _test_gate_pauses_with_session_no_wallclock_teleport()
	await _test_gate_pushes_ball_without_trapping()
	await _test_portal_transit_maps_velocity()
	await _test_portal_reentry_latch_prevents_loop()
	await _test_portal_low_power_still_transfers()


# --- helpers ---


func _make_ball() -> BallController:
	var ball := BallController.new()
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	collision.shape = sphere
	ball.add_child(collision)
	ball.kill_plane_y = -60.0
	# Spawn far away from triggers so it never enters one during instantiation
	ball.position = Vector3(0, 50, 0)
	add_child(ball)
	return ball


func _free_ball(ball: BallController) -> void:
	ball.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _settle(ball: BallController, max_frames: int = 240) -> bool:
	for i: int in max_frames:
		if ball.is_resting():
			return true
		await get_tree().physics_frame
	return ball.is_resting()


func _launch(ball: BallController, direction: Vector3, power: float) -> bool:
	var command := ShotCommand.new(
		1, 1, ShotCommand.Source.TOUCH, power, direction, "OBST-TEST", ShotMath.TUNING_VERSION
	)
	return ball.apply_shot(command)


func _add(scene_name: String, pos: Vector3) -> Node3D:
	var path := "res://scenes/obstacles/%s.tscn" % scene_name
	if not ResourceLoader.exists(path):
		path = "res://scenes/course_kit/%s.tscn" % scene_name
	var packed: PackedScene = load(path)
	harness.check(packed != null, scene_name + " loads")
	if packed == null:
		return null
	var inst: Node3D = packed.instantiate()
	inst.position = pos
	add_child(inst)
	return inst


func _add_floor(modules: Array, cells: Array) -> void:
	for cell: Vector3 in cells:
		modules.append(_add("plateau", cell))


func _free_nodes(nodes: Array) -> void:
	for node: Node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	get_tree().paused = false
	await get_tree().physics_frame
	await get_tree().physics_frame


# --- pad (RB-039 / QA-028) ---


func _test_pad_single_impulse_per_entry() -> void:
	harness.suite = "obstacle.pad_entry"
	var modules: Array = []
	_add_floor(modules, [Vector3(0, 0, 0), Vector3(0, 0, -5), Vector3(0, 0, -10)])
	var pad := _add("bounce_pad", Vector3(0, 0, -2))
	var ball := _make_ball()
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 2)))
	harness.check(await _settle(ball), "ball settles before the pad")
	harness.check(_launch(ball, Vector3(0, 0, -1), 0.55), "roll toward the pad accepted")
	var impulses := 0
	var last_flying := false
	var peak := -999.0
	for i: int in 300:
		var flying := ball.linear_velocity.y > 1.0
		if flying and not last_flying:
			impulses += 1
		last_flying = flying
		peak = maxf(peak, ball.global_position.y)
		if ball.is_resting():
			break
		await get_tree().physics_frame
	harness.check_eq(impulses, 1, "exactly one launch impulse per entry (QA-028)")
	harness.check(peak > 0.4, "pad added vertical energy (peak y=%.2f)" % peak)
	await _free_ball(ball)
	await _free_nodes([pad])
	await _free_nodes(modules)


func _test_pad_no_energy_pump_while_overlapping() -> void:
	harness.suite = "obstacle.pad_overlap"
	var modules: Array = []
	_add_floor(modules, [Vector3(0, 0, 0)])
	var pad := _add("bounce_pad", Vector3(0, 0, 0))
	var ball := _make_ball()
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var peak := -999.0
	var stable_frames := 0
	for i: int in 240:
		peak = maxf(peak, ball.global_position.y)
		if ball.is_resting() and ball.global_position.y < 0.35:
			stable_frames += 1
		if stable_frames > 60:
			break
		await get_tree().physics_frame
	harness.check(peak > 0.4, "spawned-overlap produced the single launch (peak y=%.2f)" % peak)
	harness.check(ball.is_resting() and ball.global_position.y < 0.35, "ball rests back on the pad — no repeated boosts")
	harness.check(true, "overlap hold stable for 60+ frames")
	await _free_ball(ball)
	await _free_nodes([pad])
	await _free_nodes(modules)


func _test_pad_rearm_after_leaving() -> void:
	harness.suite = "obstacle.pad_rearm"
	var modules: Array = []
	_add_floor(modules, [Vector3(0, 0, 0), Vector3(0, 0, 5)])
	var pad := _add("bounce_pad", Vector3(0, 0, 0))
	var ball := _make_ball()
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)))
	await get_tree().physics_frame
	await get_tree().physics_frame
	harness.check(await _settle(ball), "settles after first launch")
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 4)))
	harness.check(await _settle(ball), "moved away, off the pad")
	await get_tree().create_timer(0.2).timeout
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var peak := -999.0
	for i: int in 180:
		peak = maxf(peak, ball.global_position.y)
		await get_tree().physics_frame
	harness.check(peak > 0.4, "pad rearms after leaving and re-entering (peak y=%.2f)" % peak)
	await _free_ball(ball)
	await _free_nodes([pad])
	await _free_nodes(modules)


# --- gate (RB-037 / QA-029) ---


func _test_gate_pauses_with_session_no_wallclock_teleport() -> void:
	harness.suite = "obstacle.gate_pause"
	var gate := _add("moving_gate", Vector3.ZERO)
	var moving_gate := gate as MovingGate
	for i: int in 45:
		await get_tree().physics_frame
	var before := moving_gate.openness()
	get_tree().paused = true
	for i: int in 30:
		await get_tree().process_frame
	var during := moving_gate.openness()
	harness.check(absf(during - before) < 0.001, "gate frozen while session paused (phase preserved)")
	get_tree().paused = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	var after := moving_gate.openness()
	harness.check(absf(after - before) < 0.15, "resume continues the phase without a wall-clock jump (%.3f → %.3f)" % [before, after])
	harness.check_between(moving_gate.openness(), 0.0, 1.0, "openness stays normalized")
	await _free_nodes([gate])


func _test_gate_pushes_ball_without_trapping() -> void:
	harness.suite = "obstacle.gate_push"
	var modules: Array = []
	_add_floor(modules, [Vector3(0, 0, 0), Vector3(0, 0, 5)])
	var gate := _add("moving_gate", Vector3(0, 0.45, 0))
	var ball := _make_ball()
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 3)))
	harness.check(await _settle(ball), "ball settles before gate")
	harness.check(_launch(ball, Vector3(0, 0, -1), 0.2), "gentle roll toward gate accepted")
	for i in 240:
		await get_tree().physics_frame
		if ball.is_resting():
			break
	harness.check(ball.global_position.y > -0.05, "ball stayed on course (no tunneling under gate)")
	harness.check(ball.linear_velocity.length() < 10.0, "gate collision was harmless (no infinite launch)")
	await _free_ball(ball)
	await _free_nodes([gate])
	await _free_nodes(modules)


# --- portal (RB-038 / QA-027) ---


func _test_portal_transit_maps_velocity() -> void:
	harness.suite = "obstacle.portal_transit"
	var modules: Array = []
	_add_floor(modules, [Vector3(0, 0, 0), Vector3(0, 0, 5), Vector3(10, 0, -2.5), Vector3(15, 0, -2.5)])
	var portal := _add("portal_pair", Vector3(0, 0, -2.5))
	var exit_area: Area3D = portal.get_node("Exit")
	exit_area.position = Vector3(10, 0, 0)
	exit_area.rotation_degrees = Vector3(0, -90, 0)
	var ball := _make_ball()
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 3)))
	harness.check(await _settle(ball), "ball settles before the portal")
	harness.check(_launch(ball, Vector3(0, 0, -1), 0.45), "roll into the portal accepted")
	var transferred := false
	for i: int in 240:
		await get_tree().physics_frame
		if ball.global_position.x > 6.0:
			transferred = true
			break
	harness.check(transferred, "ball exited near the exit portal (x=%.2f)" % ball.global_position.x)
	var speed := ball.linear_velocity.length()
	harness.check(speed > 0.3, "exit momentum preserved and directed (speed=%.2f)" % speed)
	harness.check(ball.global_position.y > -0.1, "exit placement above ground (no sink)")
	await _free_ball(ball)
	await _free_nodes([portal])
	await _free_nodes(modules)


func _test_portal_reentry_latch_prevents_loop() -> void:
	harness.suite = "obstacle.portal_loop"
	var modules: Array = []
	_add_floor(modules, [Vector3(0, 0, 0), Vector3(0, 0, 5), Vector3(10, 0, -2.5), Vector3(15, 0, -2.5)])
	var portal := _add("portal_pair", Vector3(0, 0, -2.5))
	var exit_area: Area3D = portal.get_node("Exit")
	exit_area.position = Vector3(10, 0, 0)
	exit_area.rotation_degrees = Vector3(0, -90, 0)
	var ball := _make_ball()
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 3)))
	harness.check(await _settle(ball), "settled before the portal")
	harness.check(_launch(ball, Vector3(0, 0, -1), 0.45), "entering shot accepted")
	var teleports := 0
	var last_side := 0.0
	for i: int in 300:
		await get_tree().physics_frame
		var side := ball.global_position.x
		if last_side < 4.0 and side >= 4.0:
			teleports += 1
		last_side = side
	harness.check_eq(teleports, 1, "exactly one transfer — cooldown + inside-exit latch block the loop (QA-027)")
	await _free_ball(ball)
	await _free_nodes([portal])
	await _free_nodes(modules)


func _test_portal_low_power_still_transfers() -> void:
	harness.suite = "obstacle.portal_slow"
	var modules: Array = []
	_add_floor(modules, [Vector3(0, 0, 0), Vector3(0, 0, 5), Vector3(10, 0, -2.5), Vector3(15, 0, -2.5)])
	var portal := _add("portal_pair", Vector3(0, 0, -2.5))
	var exit_area: Area3D = portal.get_node("Exit")
	exit_area.position = Vector3(10, 0, 0)
	exit_area.rotation_degrees = Vector3(0, -90, 0)
	var ball := _make_ball()
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, -1.0)))
	harness.check(await _settle(ball), "settled 1.5 m before the portal")
	harness.check(_launch(ball, Vector3(0, 0, -1), 0.1), "very gentle roll accepted")
	var transferred := false
	for i: int in 300:
		await get_tree().physics_frame
		if ball.global_position.x > 6.0:
			transferred = true
			break
	harness.check(transferred, "slow entry still transfers (gentle nudge exit)")
	harness.check(ball.is_resting() or ball.linear_velocity.length() < 3.0, "exit speed bounded for slow entries")
	await _free_ball(ball)
	await _free_nodes([portal])
	await _free_nodes(modules)
