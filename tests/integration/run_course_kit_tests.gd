extends Node
## Course-kit seam regression (RB-028). The real BallController rolls across
## module seams at low and high speed through the real shot path
## (ShotCommand -> ShotMath impulse -> one physics-tick impulse), while a
## per-tick observer checks containment: no tunneling, no seam lip, no
## unexpected bounce, no escape. Run:
## godot --headless --path . res://tests/integration/run_course_kit_tests.tscn

var harness := TestHarness.new()
var probe_runner: ProbeRunner


func _ready() -> void:
	probe_runner = ProbeRunner.new()
	add_child(probe_runner)
	await _run_all()
	var exit_code := harness.report("COURSE KIT TESTS")
	get_tree().quit(exit_code)


func _run_all() -> void:
	await _test_modules_own_their_collision()
	await _test_kit_collision_geometry()
	await _test_straight_seam_low_speed()
	await _test_straight_seam_high_speed_no_tunnel()
	await _test_roll_distance_bands()
	await _test_corner_traversal_no_trap()
	await _test_ramp_climb_across_seams()
	await _test_ramp_descent_no_snag()
	await _test_cliff_edge_is_open()
	await _test_green_entry_containment()


# --- helpers ---

const KIT := "res://scenes/course_kit/"


func _make_ball() -> BallController:
	var ball := BallController.new()
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	collision.shape = sphere
	ball.add_child(collision)
	ball.kill_plane_y = -60.0  # bounded fall without a session reset loop
	add_child(ball)
	return ball


func _free_ball(ball: BallController) -> void:
	ball.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _add_module(module_name: String, pos: Vector3, rot_y_deg: float = 0.0) -> Node3D:
	var packed: PackedScene = load(KIT + module_name + ".tscn")
	if packed == null:
		harness.check(false, "module loads: " + module_name)
		return null
	var inst: Node3D = packed.instantiate()
	inst.position = pos
	inst.rotation_degrees = Vector3(0.0, rot_y_deg, 0.0)
	add_child(inst)
	return inst


func _free_modules(modules: Array) -> void:
	for module: Node in modules:
		if is_instance_valid(module):
			module.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _settle(ball: BallController, max_frames: int = 180) -> bool:
	for i: int in max_frames:
		if ball.is_resting():
			return true
		await get_tree().physics_frame
	return ball.is_resting()


## Launch through the production shot path: one impulse from ShotMath on the
## next physics tick, exactly like a player shot (no direct velocity writes).
func _launch(ball: BallController, direction: Vector3, power: float) -> bool:
	var command := ShotCommand.new(
		1, 1, ShotCommand.Source.TOUCH, power, direction, "KIT-TEST", ShotMath.TUNING_VERSION
	)
	return ball.apply_shot(command)


func _run_roll(ball: BallController, observer: RollObserver, max_frames: int) -> void:
	for i: int in max_frames:
		observer.sample(ball)
		if ball.is_resting() or ball.global_position.y < -5.0:
			break
		await get_tree().physics_frame
	observer.sample(ball)


## Ramp surface height at local z (module centered at z=0): 0 at entry edge,
## 1.0 at exit edge (5 m run, 1 m rise). Ball center rides 0.245 above it.
func _ramp_surface_y(z: float) -> float:
	return clampf((2.5 - z) / 5.0, 0.0, 1.0)


func _probe_points(points: Array) -> Array:
	var probes: Array = []
	for point: Vector3 in points:
		probes.append({"from": point, "hit": {}})
	probe_runner.probes = probes
	probe_runner.run_requested = true
	var guard := 0
	while probe_runner.run_requested and guard < 120:
		await get_tree().physics_frame
		guard += 1
	return probes


func _geometry_points(probe_cases: Array) -> Array:
	var points: Array = []
	for probe_case: Array in probe_cases:
		points.append(probe_case[0])
	return points


func _check_surface_hit(probe: Dictionary, expected_y: float, label: String, tolerance := 0.03) -> void:
	var hit: Dictionary = probe["hit"]
	harness.check(not hit.is_empty(), label + " (ray hit something)")
	if hit.is_empty():
		return
	harness.check_near((hit["position"] as Vector3).y, expected_y, tolerance, label)


# --- structure: wrappers own collision + connection pivots (docs/07 §3) ---


func _test_modules_own_their_collision() -> void:
	harness.suite = "kit.structure"
	var expectations := {
		"straight": {"connect_out": true, "bodies_min": 3},
		"corner": {"connect_out": true, "bodies_min": 3},
		"green": {"connect_out": false, "bodies_min": 4},
		"ramp": {"connect_out": true, "bodies_min": 3},
		"rail": {"connect_out": false, "bodies_min": 1},
		"cliff_edge": {"connect_out": false, "bodies_min": 3},
	}
	for module_name: String in expectations:
		var packed: PackedScene = load(KIT + module_name + ".tscn")
		harness.check(packed != null, module_name + ".tscn loads")
		if packed == null:
			continue
		var inst: Node3D = packed.instantiate()
		add_child(inst)
		var static_root := inst.find_child("StaticCollision", true, false)
		harness.check(static_root != null, module_name + " has StaticCollision wrapper")
		if static_root != null:
			var bodies := static_root.find_children("*", "StaticBody3D", true, false)
			harness.check(
				bodies.size() >= int(expectations[module_name]["bodies_min"]),
				"%s wraps %d course bodies (>= %d)" % [module_name, bodies.size(), expectations[module_name]["bodies_min"]]
			)
			var all_course_layer := true
			for body: Node in bodies:
				if (body as StaticBody3D).collision_layer != 2 or (body as StaticBody3D).collision_mask != 0:
					all_course_layer = false
			harness.check(all_course_layer, module_name + " bodies on Course layer 2, mask 0")
		var connect_root := inst.find_child("Connect", true, false)
		var want_connect: bool = module_name != "rail"
		harness.check(
			(connect_root != null) == want_connect,
			module_name + " connection pivots " + ("present" if want_connect else "absent")
		)
		if connect_root != null:
			harness.check(inst.find_child("In", true, false) is Marker3D, module_name + " has Connect/In")
			var has_out := inst.find_child("Out", true, false) is Marker3D
			harness.check(has_out == bool(expectations[module_name]["connect_out"]), module_name + " Connect/Out contract")
		inst.queue_free()
	await get_tree().physics_frame


# --- geometry: ray probes pin the seam contract of every module edge ---


func _test_kit_collision_geometry() -> void:
	harness.suite = "kit.geometry"
	var cases := [
		{"module": "straight", "at": Vector3.ZERO, "probes": [
			[Vector3(0, 5, 2.4), 0.0], [Vector3(0, 5, -2.4), 0.0],
			[Vector3(-2.65, 5, 0), 0.4], [Vector3(2.65, 5, 0), 0.4],
		], "open": [
			Vector3(0, 5, 2.6), Vector3(0, 5, -2.6), Vector3(2.9, 5, 0),
		]},
		{"module": "corner", "at": Vector3.ZERO, "probes": [
			[Vector3(0, 5, 2.4), 0.0], [Vector3(0, 5, -2.4), 0.0],
			[Vector3(-2.4, 5, 0), 0.0], [Vector3(2.4, 5, 0), 0.0],
			[Vector3(0, 5, -2.65), 0.4], [Vector3(-2.65, 5, 0), 0.4],
		], "open": [
			Vector3(0, 5, 2.6), Vector3(2.6, 5, 0),
		]},
		{"module": "green", "at": Vector3.ZERO, "probes": [
			[Vector3(0, 5, 2.4), 0.0], [Vector3(-4.9, 5, 0), 0.0], [Vector3(4.9, 5, 0), 0.0],
			[Vector3(-5.15, 5, 0), 0.4], [Vector3(5.15, 5, 0), 0.4], [Vector3(0, 5, -2.65), 0.4],
		], "open": [
			Vector3(0, 5, 2.6), Vector3(5.45, 5, 0),
		]},
		{"module": "ramp", "at": Vector3.ZERO, "probes": [
			[Vector3(0, 5, 2.4), _ramp_surface_y(2.4)],
			[Vector3(0, 5, 0.0), _ramp_surface_y(0.0)],
			[Vector3(0, 5, -2.4), _ramp_surface_y(-2.4)],
		], "open": []},
		{"module": "rail", "at": Vector3.ZERO, "probes": [
			[Vector3(0, 5, 0), 0.4], [Vector3(0, 5, 2.4), 0.4], [Vector3(0, 5, -2.4), 0.4],
		], "open": [
			Vector3(0.25, 5, 0), Vector3(2.6, 5, 0),
		]},
		{"module": "cliff_edge", "at": Vector3.ZERO, "probes": [
			[Vector3(0, 5, 0), 0.0], [Vector3(0, 5, -2.4), 0.0],
			[Vector3(-2.65, 5, 0), 0.4], [Vector3(2.65, 5, 0), 0.4],
		], "open": [
			Vector3(0, 5, -2.8), Vector3(0, 5, 2.6),
		]},
	]
	for case: Dictionary in cases:
		var module: Node3D = _add_module(case["module"], case["at"])
		harness.check(module != null, case["module"] + " instanced for geometry probe")
		if module == null:
			continue
		await get_tree().physics_frame
		await get_tree().physics_frame
		var probes := await _probe_points(_geometry_points(case["probes"]))
		for i: int in probes.size():
			var expected: float = case["probes"][i][1]
			_check_surface_hit(
				probes[i], expected,
				"%s surface at %s == %.2f" % [case["module"], case["probes"][i][0], expected]
			)
		for open_point: Vector3 in case["open"]:
			var open_probes := await _probe_points([open_point])
			harness.check(
				(open_probes[0]["hit"] as Dictionary).is_empty(),
				"%s edge open beyond geometry at %s" % [case["module"], open_point]
			)
		module.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame


# --- seam rolls ---


func _test_straight_seam_low_speed() -> void:
	harness.suite = "kit.seam_low"
	var a := _add_module("straight", Vector3.ZERO)
	var b := _add_module("straight", Vector3(0, 0, -5))
	var ball := _make_ball()
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 2)))
	harness.check(await _settle(ball), "ball settles on module A")
	harness.check(_launch(ball, Vector3(0, 0, -1), 0.3), "low-power shot accepted")
	var observer := RollObserver.new()
	await _run_roll(ball, observer, 600)
	harness.check(ball.is_resting(), "ball comes to rest on module B")
	harness.check_between(ball.global_position.z, -5.5, -2.6, "rest past the seam on module B")
	harness.check_between(ball.global_position.y, 0.15, 0.4, "rest height on turf")
	harness.check(observer.max_y < 0.32, "no seam lip hop (max y %.3f)" % observer.max_y)
	harness.check(observer.supported_min_y > 0.18, "never sank into the seam (min supported y %.3f)" % observer.supported_min_y)
	await _free_ball(ball)
	await _free_modules([a, b])


func _test_straight_seam_high_speed_no_tunnel() -> void:
	harness.suite = "kit.seam_high"
	var a := _add_module("straight", Vector3.ZERO)
	var b := _add_module("straight", Vector3(0, 0, -5))
	var ball := _make_ball()
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 2)))
	harness.check(await _settle(ball), "ball settles on module A")
	harness.check(_launch(ball, Vector3(0, 0, -1), 1.0), "max-power shot accepted")
	var observer := RollObserver.new()
	await _run_roll(ball, observer, 400)
	harness.check(observer.supported_min_z < -7.2, "crossed module B at speed (last supported z %.2f)" % observer.supported_min_z)
	harness.check(observer.supported_min_y > 0.18, "CCD held at the seam: no tunneling (min supported y %.3f)" % observer.supported_min_y)
	harness.check(observer.max_y < 0.6, "no seam eject at speed (max y %.3f)" % observer.max_y)
	harness.check(ball.global_position.y < -5.0, "open module end: ball fell into the void, no invisible floor")
	await _free_ball(ball)
	await _free_modules([a, b])


func _test_roll_distance_bands() -> void:
	harness.suite = "kit.roll_bands"
	var a := _add_module("straight", Vector3.ZERO)
	var b := _add_module("straight", Vector3(0, 0, -5))
	var c := _add_module("straight", Vector3(0, 0, -10))
	var distances: Dictionary = {}
	for power: float in [0.25, 0.5]:
		var ball := _make_ball()
		ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 2)))
		harness.check(await _settle(ball), "settled before p=%.2f roll" % power)
		harness.check(_launch(ball, Vector3(0, 0, -1), power), "shot accepted at p=%.2f" % power)
		var observer := RollObserver.new()
		await _run_roll(ball, observer, 700)
		distances[power] = 2.0 - observer.supported_min_z
		harness.check(observer.supported_min_y > 0.18, "p=%.2f roll stayed on turf" % power)
		await _free_ball(ball)
	# QA-021 preview: bands must be ordered and the low band stable; the full
	# tolerance-band sweep is tracked separately. Measured on the pinned engine
	# build (tools/roll_decel_probe.gd): flat-turf deceleration is
	# velocity-dependent, ~0.55 + 0.08*v m/s^2 (authored term + engine rolling
	# losses from angular_damp), giving d(p=0.25) ~= 4.2 m, not the constant-
	# 0.55 ideal of 5.35 m. Band guards against gross friction regressions.
	harness.check_between(distances[0.25], 3.6, 4.8, "p=0.25 stopping distance in stable band (%.2f m)" % distances[0.25])
	harness.check(
		distances[0.5] > distances[0.25] + 2.0,
		"p=0.5 clearly out-rolls p=0.25 (%.2f vs %.2f m)" % [distances[0.5], distances[0.25]]
	)
	await _free_modules([a, b, c])


func _test_corner_traversal_no_trap() -> void:
	harness.suite = "kit.corner"
	var a := _add_module("straight", Vector3.ZERO)
	var corner := _add_module("corner", Vector3(0, 0, -5))
	var c := _add_module("straight", Vector3(5, 0, -5), -90.0)
	var ball := _make_ball()
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 2)))
	harness.check(await _settle(ball), "ball settles on module A")
	harness.check(
		_launch(ball, Vector3(0.35, 0, -0.937).normalized(), 0.6),
		"diagonal shot accepted into the corner"
	)
	var observer := RollObserver.new()
	await _run_roll(ball, observer, 900)
	harness.check(ball.is_resting(), "ball comes to rest after the corner")
	var rest := ball.global_position
	harness.check_between(rest.x, 2.6, 7.4, "rested past the corner exit, inside module C (x=%.2f)" % rest.x)
	harness.check_between(rest.z, -7.4, -2.6, "rest z stayed in the C corridor (z=%.2f)" % rest.z)
	harness.check_between(rest.y, 0.15, 0.4, "rest height on turf")
	harness.check(observer.min_x > -2.6, "never escaped the left rail (min x %.2f)" % observer.min_x)
	harness.check(observer.supported_min_z > -7.6, "never escaped the far rail (min z %.2f)" % observer.supported_min_z)
	harness.check(observer.supported_min_y > 0.18, "no sink at A/corner/C seams")
	harness.check(observer.max_y < 0.45, "no corner lip bounce (max y %.3f)" % observer.max_y)
	await _free_ball(ball)
	await _free_modules([a, corner, c])


func _test_ramp_climb_across_seams() -> void:
	harness.suite = "kit.ramp_up"
	var a := _add_module("straight", Vector3.ZERO)
	var ramp := _add_module("ramp", Vector3(0, 0, -5))
	var c := _add_module("straight", Vector3(0, 1, -10))
	var wall := _add_module("rail", Vector3(0, 1, -12.55), 90.0)
	var ball := _make_ball()
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 2)))
	harness.check(await _settle(ball), "ball settles on module A")
	harness.check(_launch(ball, Vector3(0, 0, -1), 0.75), "strong shot accepted for the climb")
	var observer := RollObserver.new()
	await _run_roll(ball, observer, 900)
	harness.check(ball.is_resting(), "ball rests after crossing ramp + raised module")
	var rest := ball.global_position
	harness.check_between(rest.z, -12.3, -7.6, "crossed both ramp seams onto module C (z=%.2f)" % rest.z)
	harness.check_between(rest.y, 1.05, 1.6, "rests on the raised turf (y=%.2f)" % rest.y)
	harness.check(observer.max_y < 2.2, "no crest launch anomaly (max y %.3f)" % observer.max_y)
	harness.check(observer.clamp_violations == 0, "never below the ramp surface while over it (%d violations)" % observer.clamp_violations)
	await _free_ball(ball)
	await _free_modules([a, ramp, c, wall])


func _test_ramp_descent_no_snag() -> void:
	harness.suite = "kit.ramp_down"
	var a := _add_module("straight", Vector3.ZERO)
	var ramp := _add_module("ramp", Vector3(0, 0, -5))
	var c := _add_module("straight", Vector3(0, 1, -10))
	var ball := _make_ball()
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 1.25, -9)))
	harness.check(await _settle(ball), "ball settles on the raised module C")
	harness.check(_launch(ball, Vector3(0, 0, 1), 0.4), "gentle downhill shot accepted")
	var observer := RollObserver.new()
	await _run_roll(ball, observer, 700)
	harness.check(observer.supported_max_z > -2.0, "descended the full ramp, crossed the base seam (z=%.2f)" % observer.supported_max_z)
	harness.check(observer.max_y < 1.8, "no snag pop at the base seam (max y %.3f)" % observer.max_y)
	harness.check(observer.clamp_violations == 0, "never fell below the ramp surface while over it")
	harness.check(observer.supported_min_y > 0.18, "never tunneled through the ramp")
	await _free_ball(ball)
	await _free_modules([a, ramp, c])


func _test_cliff_edge_is_open() -> void:
	harness.suite = "kit.cliff"
	var cliff := _add_module("cliff_edge", Vector3.ZERO)
	var ball := _make_ball()
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 2)))
	harness.check(await _settle(ball), "ball settles on the cliff module")
	harness.check(_launch(ball, Vector3(0, 0, -1), 0.6), "shot toward the open edge accepted")
	var observer := RollObserver.new()
	await _run_roll(ball, observer, 300)
	harness.check_between(observer.supported_min_z, -2.5, -1.8, "rolled off exactly at the authored edge (z=%.2f)" % observer.supported_min_z)
	harness.check(observer.max_y < 0.32, "no invisible lip bounce at the edge (max y %.3f)" % observer.max_y)
	harness.check(ball.global_position.y < -0.5, "ball falls past the cliff face (decor skirt has no collision)")
	harness.check(absf(ball.global_position.x) < 0.5, "fell straight, no lateral defect")
	await _free_ball(ball)
	await _free_modules([cliff])


func _test_green_entry_containment() -> void:
	harness.suite = "kit.green"
	var approach := _add_module("straight", Vector3(0, 0, 5))
	var green := _add_module("green", Vector3.ZERO)
	var ball := _make_ball()
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 7)))
	harness.check(await _settle(ball), "ball settles on the approach straight")
	harness.check(_launch(ball, Vector3(0, 0, -1), 0.5), "entry putt accepted")
	var observer := RollObserver.new()
	await _run_roll(ball, observer, 600)
	harness.check(ball.is_resting(), "ball rests on the green after crossing the entry seam")
	harness.check_between(ball.global_position.z, -2.45, -0.5, "stopped near the back rail (z=%.2f)" % ball.global_position.z)
	harness.check_between(ball.global_position.y, 0.15, 0.4, "rest height on turf")
	harness.check(absf(observer.max_abs_x) < 5.2, "green rails contained the ball (|x| max %.2f)" % observer.max_abs_x)
	harness.check(observer.supported_min_y > 0.18, "no sink at the entry seam")
	harness.check(observer.max_y < 0.32, "no entry seam hop (max y %.3f)" % observer.max_y)
	await _free_ball(ball)
	await _free_modules([green])


## Per-tick sampler: records extremes and counts surface-clamp violations for
## ramp rolls (ball center must never dip under the authored surface).
class RollObserver extends RefCounted:
	var max_y := -999.0
	var min_x := 999.0
	var max_abs_x := 0.0
	var supported_min_y := 999.0
	var supported_min_z := 999.0
	var supported_max_z := -999.0
	var clamp_violations := 0
	var _frames := 0

	func sample(ball: BallController) -> void:
		_frames += 1
		var position := ball.global_position
		max_y = maxf(max_y, position.y)
		min_x = minf(min_x, position.x)
		max_abs_x = maxf(max_abs_x, absf(position.x))
		if ball.is_supported():
			supported_min_y = minf(supported_min_y, position.y)
			supported_min_z = minf(supported_min_z, position.z)
			supported_max_z = maxf(supported_max_z, position.z)
			# Ramp containment: while over the ramp module (local |x| <= 2.5,
			# z in [-7.5, -2.5] world when ramp sits at z=-5) the ball center
			# must stay above the authored surface band.
			if position.z > -7.5 and position.z < -2.5 and absf(position.x) <= 2.5:
				var surface := (-position.z - 2.5) / 5.0
				if position.y < surface + 0.15:
					clamp_violations += 1


## Runs ray probes inside _physics_process (space-state queries are only safe
## while the physics server is not flushing).
class ProbeRunner extends Node3D:
	var probes: Array = []
	var run_requested := false

	func _physics_process(_delta: float) -> void:
		if not run_requested or probes.is_empty():
			return
		var space := get_world_3d().direct_space_state
		for probe: Dictionary in probes:
			var params := PhysicsRayQueryParameters3D.create(
				probe["from"], (probe["from"] as Vector3) + Vector3(0, -10, 0)
			)
			probe["hit"] = space.intersect_ray(params)
		run_requested = false
		probes = []
