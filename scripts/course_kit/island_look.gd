class_name IslandLook
extends Node3D
## Floating-island underside in the asset-pack style (M5 art pass): a grass
## crust overhanging the turf edge, an earthy tapered body, and a jagged rock
## keel narrowing to a point — the classic floating-island silhouette.
## The footprint is an ELLIPSE hugging the module rectangle (non-uniform
## scale on a low-poly cylinder): wide enough to swallow the corners, never
## so wide that it bulges past the rails into the corridor view. Purely
## decorative — adds no collision, so course behavior and the seam-regression
## suite are untouched.

@export var turf_size := Vector3(5.0, 0.5, 5.0)

const GRASS_LIP := Color("4fae3e")
const DIRT := Color("8a5c38")
const ROCK := Color("7a6f63")
const ROCK_DARK := Color("635a50")
const RADIAL := 8  # low-poly segment count: reads stylized, costs almost nothing


func _ready() -> void:
	var long_side := maxf(turf_size.x, turf_size.z)
	var short_side := minf(turf_size.x, turf_size.z)
	# Elliptical footprint: base radius covers the long axis with a small
	# overhang; z-scale squashes it onto the short axis so the silhouette
	# hugs rectangles of any aspect (5×5 strips, 10×5 greens).
	var base_r := 0.5 * long_side + 0.12
	var z_fit := short_side / long_side
	# Grass crust: slight overhang, top just under the walk surface so it
	# never reads as a ridge from above.
	_add_cylinder(base_r + 0.14, base_r + 0.02, 0.30,
		Vector3(0, -0.17, 0), GRASS_LIP, z_fit)
	# Earth body: tapering hard (radius ÷2 over ~1 m) for the island pull.
	_add_cylinder(base_r - 0.08, base_r * 0.52, 1.05,
		Vector3(0, -0.78, 0), DIRT, z_fit)
	# Rock shelf between earth and keel.
	_add_cylinder(base_r * 0.52, base_r * 0.34, 0.7,
		Vector3(0, -1.60, 0), ROCK, z_fit)
	# Keel: narrowing to a rough point, slightly off-axis so it feels grown.
	_add_cylinder(base_r * 0.34, 0.05, 1.35,
		Vector3(0.12, -2.60, -0.08), ROCK_DARK, z_fit)
	# Jagged keystone chunks clinging to the keel for a hand-carved edge.
	_add_chunk(base_r * 0.21, Vector3(-0.55, -2.0, 0.30), ROCK, 34.0, z_fit)
	_add_chunk(base_r * 0.16, Vector3(0.62, -2.25, -0.40), ROCK_DARK, -51.0, z_fit)
	_add_chunk(base_r * 0.13, Vector3(0.20, -1.35, 0.62), ROCK_DARK, 12.0, z_fit)


func _add_cylinder(top_r: float, bottom_r: float, height: float, pos: Vector3, color: Color, z_fit: float) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = top_r
	cyl.bottom_radius = bottom_r
	cyl.height = height
	cyl.radial_segments = RADIAL
	cyl.cap_top = false  # hidden under the module above
	mesh.mesh = cyl
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh.material_override = material
	mesh.position = pos
	mesh.rotation_degrees = Vector3(0, _seeded_yaw(pos), 0)
	mesh.scale = Vector3(1.0, 1.0, z_fit)
	add_child(mesh)


func _add_chunk(size: float, pos: Vector3, color: Color, roll_deg: float, z_fit: float) -> void:
	var mesh := MeshInstance3D.new()
	var chunk := SphereMesh.new()
	chunk.radius = size * 0.5
	chunk.height = size
	chunk.radial_segments = 6
	chunk.rings = 4
	mesh.mesh = chunk
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh.material_override = material
	mesh.position = Vector3(pos.x, pos.y, pos.z * z_fit)
	mesh.rotation_degrees = Vector3(roll_deg * 0.4, _seeded_yaw(pos), roll_deg)
	mesh.scale = Vector3(1.0, 0.8, 1.25)
	add_child(mesh)


func _seeded_yaw(pos: Vector3) -> float:
	# Deterministic per-position yaw so every island rotates its facets
	# differently but replays identically.
	return float(fmod(absf(pos.x * 53.0 + pos.z * 97.0 + pos.y * 29.0), 360.0))
