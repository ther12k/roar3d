extends SceneTree
## Scratch probe: measure effective flat-turf deceleration on the kit straight
## module (per-tick linear speed), to reconcile the authored 0.55 m/s^2 model
## with measured stopping distances. Run:
##   godot --headless --path . -s tools/roll_decel_probe.gd


func _initialize() -> void:
	_run()


func _run() -> void:
	var packed: PackedScene = load("res://scenes/course_kit/straight.tscn")
	var module: Node3D = packed.instantiate()
	root.add_child(module)

	var ball := BallController.new()
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	collision.shape = sphere
	ball.add_child(collision)
	ball.kill_plane_y = -60.0
	root.add_child(ball)
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 2)))

	for i: int in 180:
		if ball.is_resting():
			break
		await physics_frame

	print("resting=", ball.is_resting(), " angular_damp=", ball.angular_damp, " linear_damp=", ball.linear_damp)
	print("ball friction=", ball.physics_material_override.friction, " bounce=", ball.physics_material_override.bounce)
	ball.apply_central_impulse(Vector3(0, 0, -2.425))  # same as p=0.25 impulse
	await physics_frame  # let the impulse integrate and clear the rest flag
	var last_v := 0.0
	for i: int in 600:
		var v := ball.linear_velocity.length()
		if i % 30 == 0:
			var dec := 0.0
			if i > 0:
				dec = (last_v - v) / 0.5  # 30 ticks = 0.5 s
			print("t=%.2fs v=%.3f z=%.3f supported=%s decel=%.3f" % [i / 60.0, v, ball.global_position.z, ball.is_supported(), dec])
			last_v = v
		if ball.is_resting():
			print("rested at tick %d z=%.3f" % [i, ball.global_position.z])
			break
		await physics_frame
	quit(0)
