class_name IslandLook
extends Node3D
## Floating-island underside decoration in the asset-pack style: a grass lip
## hugging the turf edge, an earthy dirt body, and a rocky base with keystone
## chunks. Purely decorative — adds no collision, so course behavior and the
## seam-regression suite are untouched.

@export var turf_size := Vector3(5.0, 0.5, 5.0)

const GRASS_LIP := Color("4fae3e")
const DIRT := Color("9a6a42")
const ROCK := Color("7a6f63")
const ROCK_DARK := Color("655c51")


func _ready() -> void:
	# Grass lip overhanging the turf edge (reads as the island's top crust)
	_add_box(Vector3(turf_size.x + 0.36, 0.2, turf_size.z + 0.36), Vector3(0, -0.08, 0), GRASS_LIP, 0.0)
	# Dirt body
	_add_box(Vector3(turf_size.x - 0.7, 0.85, turf_size.z - 0.7), Vector3(0, -0.68, 0), DIRT, 0.0)
	# Rock base
	_add_box(Vector3(turf_size.x - 1.9, 0.95, turf_size.z - 1.9), Vector3(0, -1.5, 0), ROCK, 0.0)
	# Keystone chunks for a hand-carved silhouette
	_add_box(Vector3(1.2, 0.8, 1.2), Vector3(-0.5, -2.25, 0.35), ROCK_DARK, 18.0)
	_add_box(Vector3(0.9, 0.7, 0.9), Vector3(0.65, -2.1, -0.45), ROCK_DARK, -22.0)


func _add_box(size: Vector3, pos: Vector3, color: Color, yaw_deg: float) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh.material_override = material
	mesh.position = pos
	mesh.rotation_degrees = Vector3(0, yaw_deg, 0)
	add_child(mesh)
