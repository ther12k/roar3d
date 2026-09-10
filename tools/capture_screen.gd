extends Node
## Dev tool: capture an app screen (map/collection) at 390x844.
##   SCREEN=map godot --path . --resolution 390x844 res://tools/capture_screen.tscn
## Env: SCREEN (map|collection), OUT (default /tmp/roar3d_<screen>.png)

func _ready() -> void:
	var which := OS.get_environment("SCREEN")
	var path := "res://scenes/app/world_map.tscn" if which == "map" else "res://scenes/app/collection.tscn"
	var packed: PackedScene = load(path)
	if packed == null:
		printerr("failed to load " + path)
		get_tree().quit(1)
		return
	add_child(packed.instantiate())
	for i: int in 30:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = "/tmp/roar3d_%s.png" % which
	img.save_png(out)
	print("SCREEN_CAPTURED: ", out)
	get_tree().quit(0)
