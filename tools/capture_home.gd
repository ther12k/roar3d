extends Node
## Dev tool scene: captures the Home Screen at 390x844 mobile resolution.

func _ready() -> void:
	var packed: PackedScene = load("res://scenes/app/home.tscn")
	var home := packed.instantiate()
	add_child(home)
	for i in 20:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := "/tmp/roar3d_new_home.png"
	img.save_png(path)
	print("HOME_CAPTURED: ", path)
	get_tree().quit(0)
