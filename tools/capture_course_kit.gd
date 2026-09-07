extends SceneTree
## Dev tool: renders the course-kit showcase and saves a PNG evidence capture.
## Run with the full (non-headless) engine:
##   godot --path . --resolution 720x1600 -s tools/capture_course_kit.gd
## Optional env: KIT_CAPTURE_OUT (default /tmp/roar3d_course_kit_showcase.png)

const CAMERA_POS := Vector3(21.0, 17.0, 6.0)
const LOOK_AT := Vector3(4.0, -0.5, -12.0)
const SETTLE_FRAMES := 24


func _initialize() -> void:
	_run()


func _run() -> void:
	var packed: PackedScene = load("res://scenes/course_kit/kit_showcase.tscn")
	if packed == null:
		printerr("kit showcase scene failed to load")
		quit(1)
		return
	var showcase: Node3D = packed.instantiate()
	root.add_child(showcase)
	var camera := Camera3D.new()
	camera.fov = 60.0
	# Tree-independent aim: look_at() needs an in-tree node, which is not
	# guaranteed during SceneTree._initialize.
	var forward := (LOOK_AT - CAMERA_POS).normalized()
	camera.transform = Transform3D(Basis.looking_at(forward, Vector3.UP), CAMERA_POS)
	root.add_child(camera)
	camera.current = true
	for i: int in SETTLE_FRAMES:
		await process_frame
	var image: Image = root.get_viewport().get_texture().get_image()
	var out_path := OS.get_environment("KIT_CAPTURE_OUT")
	if out_path.is_empty():
		out_path = "/tmp/roar3d_course_kit_showcase.png"
	var err := image.save_png(out_path)
	if err != OK:
		printerr("PNG save failed: %s" % error_string(err))
		quit(1)
		return
	print("KIT_CAPTURE_SAVED %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	quit(0)
