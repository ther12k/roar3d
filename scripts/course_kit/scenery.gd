class_name Scenery
extends Node3D
## Asset-pack style scenery: small floating islands with trees, rocks, and
## bushes placed OUTSIDE the course bounds. Purely decorative — no collision,
## never inside CourseBounds, so gameplay and tests are untouched (docs/07:
## "distant islands are scenery, not mandatory simulated geometry").

const GRASS := Color("4fae3e")
const DIRT := Color("9a6a42")
const ROCK := Color("7a6f63")
const TRUNK := Color("7a5230")
const PINE := Color("2f7a3d")
const LEAFY := Color("55b04a")
const BUSH_GREEN := Color("4a9a42")


## Builds one scenery cluster. variant 0 = pine island, 1 = leafy island,
## 2 = rock cluster, 3 = bush meadow.
static func build(variant: int, scale_factor: float) -> Scenery:
	var scenery := Scenery.new()
	scenery._variant = variant % 4
	scenery._scale_factor = scale_factor
	return scenery

var _variant := 0
var _scale_factor := 1.0


func _ready() -> void:
	match _variant:
		0:
			_island()
			_pine(Vector3(0, 0.55, 0), 1.0)
		1:
			_island()
			_round_tree(Vector3(-0.3, 0.55, 0.2), 1.0)
			_round_tree(Vector3(0.45, 0.5, -0.25), 0.7)
		2:
			_island(0.7)
			_rock(Vector3(0, 0.42, 0), 1.1)
			_rock(Vector3(0.5, 0.38, 0.3), 0.7)
		3:
			_island(0.85)
			_bush(Vector3(-0.25, 0.48, 0.1))
			_bush(Vector3(0.35, 0.46, -0.2))
			_flower(Vector3(0.05, 0.46, 0.4))
	scale = Vector3.ONE * _scale_factor


func _island(size_factor := 1.0) -> void:
	# Floating-island silhouette (asset-pack look): a squashed grass dome on
	# top and a tapered rock cone underneath. Stacked boxes readed as plain
	# cubes from the play camera; this silhouette reads as an island from any
	# angle.
	var dome := MeshInstance3D.new()
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 1.1 * size_factor
	dome_mesh.height = 2.2 * size_factor
	dome.mesh = dome_mesh
	dome.scale = Vector3(1.0, 0.4, 1.0)
	var grass := StandardMaterial3D.new()
	grass.albedo_color = GRASS
	grass.roughness = 1.0
	dome.material_override = grass
	dome.position = Vector3(0, 0, 0)
	add_child(dome)
	var cone := MeshInstance3D.new()
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 1.02 * size_factor
	cone_mesh.bottom_radius = 0.08 * size_factor
	cone_mesh.height = 1.3 * size_factor
	cone.mesh = cone_mesh
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = DIRT
	dirt.roughness = 1.0
	cone.material_override = dirt
	cone.position = Vector3(0, -0.62 * size_factor, 0)
	add_child(cone)
	var tip := MeshInstance3D.new()
	var tip_mesh := SphereMesh.new()
	tip_mesh.radius = 0.16 * size_factor
	tip_mesh.height = 0.32 * size_factor
	tip.mesh = tip_mesh
	var rock := StandardMaterial3D.new()
	rock.albedo_color = ROCK
	rock.roughness = 1.0
	tip.material_override = rock
	tip.position = Vector3(0, -1.28 * size_factor, 0)
	add_child(tip)


func _pine(pos: Vector3, size_factor: float) -> void:
	_box(Vector3(0.14, 0.5, 0.14), pos + Vector3(0, 0.1, 0), TRUNK)
	_cone(pos + Vector3(0, 0.75, 0), 0.55 * size_factor, 0.9 * size_factor, PINE)
	_cone(pos + Vector3(0, 1.25, 0), 0.4 * size_factor, 0.7 * size_factor, PINE)


func _round_tree(pos: Vector3, size_factor: float) -> void:
	_box(Vector3(0.14, 0.55, 0.14), pos + Vector3(0, 0.12, 0), TRUNK)
	_ball(pos + Vector3(0, 0.85 * size_factor, 0), 0.55 * size_factor, LEAFY)


func _rock(pos: Vector3, size_factor: float) -> void:
	_ball(pos, 0.32 * size_factor, ROCK)


func _bush(pos: Vector3) -> void:
	_ball(pos, 0.3, BUSH_GREEN)


func _flower(pos: Vector3) -> void:
	_box(Vector3(0.04, 0.22, 0.04), pos + Vector3(0, 0.08, 0), TRUNK)
	_ball(pos + Vector3(0, 0.22, 0), 0.09, Color("ff8fb0"))


func _box(size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh.material_override = material
	mesh.position = pos
	add_child(mesh)


func _ball(pos: Vector3, radius: float, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh.material_override = material
	mesh.position = pos
	add_child(mesh)


func _cone(pos: Vector3, radius: float, height: float, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = radius
	cone.height = height
	mesh.mesh = cone
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh.material_override = material
	mesh.position = pos
	add_child(mesh)
