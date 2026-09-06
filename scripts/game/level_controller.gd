class_name LevelController
extends Node3D
## Loads one allowlisted level scene and enforces the marker contract
## (RB-009): Spawn, Cup, SafeAnchors, KillVolume, LevelConfig, StaticCollision.
## Saves reference catalog IDs only — never arbitrary scene paths from data.
## Owns win/fall routing surfaces; the session owns the decisions.

signal kill_zone_entered()

var level_meta: Dictionary = {}
var instance: Node3D = null
## True while the ball overlaps the cup trigger; the session polls eligibility
## (distance, height band, speed) rather than trusting entry alone (QA-024).
var ball_in_cup_zone := false

var _spawn: Marker3D = null
var _cup_area: Area3D = null
var _cup_position := Vector3.ZERO
var _safe_anchors: Array[Marker3D] = []
var _kill_volume: Area3D = null
var _config: LevelConfig = null


func load_level(meta: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	unload()
	level_meta = meta
	var scene_path := String(meta.get("scene_path", ""))
	var packed: PackedScene = load(scene_path) if ResourceLoader.exists(scene_path) else null
	if packed == null:
		errors.append("scene_missing:" + scene_path)
		return errors
	instance = packed.instantiate()
	add_child(instance)
	instance.owner = null  # runtime-only instance, never saved back

	_spawn = _find_marker(instance, "Spawn")
	if _spawn == null:
		errors.append("marker:Spawn")
	_config = _find_config(instance)
	if _config == null:
		errors.append("marker:LevelConfig")
	_cup_area = _find_cup(instance)
	if _cup_area == null:
		errors.append("marker:Cup")
	else:
		_cup_position = _cup_area.global_position
	_kill_volume = instance.find_child("KillVolume", true, false)
	if _kill_volume == null and (_config == null or _config.kill_plane_y <= -99.0):
		errors.append("marker:KillVolume")
	var anchors_root := instance.find_child("SafeAnchors", true, false)
	if anchors_root == null:
		errors.append("marker:SafeAnchors")
	else:
		for child in anchors_root.get_children():
			if child is Marker3D:
				_safe_anchors.append(child as Marker3D)
		if _safe_anchors.is_empty():
			errors.append("marker:SafeAnchors.empty")
	if instance.find_child("StaticCollision", true, false) == null:
		errors.append("marker:StaticCollision")

	if _cup_area != null:
		if not _cup_area.body_entered.is_connected(_on_cup_entered):
			_cup_area.body_entered.connect(_on_cup_entered)
		if not _cup_area.body_exited.is_connected(_on_cup_exited):
			_cup_area.body_exited.connect(_on_cup_exited)
	if _kill_volume != null:
		if not _kill_volume.body_entered.is_connected(_on_kill_entered):
			_kill_volume.body_entered.connect(_on_kill_entered)
	return errors


func unload() -> void:
	if _cup_area != null:
		if _cup_area.body_entered.is_connected(_on_cup_entered):
			_cup_area.body_entered.disconnect(_on_cup_entered)
		if _cup_area.body_exited.is_connected(_on_cup_exited):
			_cup_area.body_exited.disconnect(_on_cup_exited)
	if _kill_volume != null and _kill_volume.body_entered.is_connected(_on_kill_entered):
		_kill_volume.body_entered.disconnect(_on_kill_entered)
	_cup_area = null
	_kill_volume = null
	_spawn = null
	_config = null
	_safe_anchors.clear()
	if instance != null:
		instance.queue_free()
		instance = null


func has_level() -> bool:
	return instance != null


func spawn_transform() -> Transform3D:
	return _spawn.global_transform if _spawn != null else Transform3D.IDENTITY


func initial_aim_direction() -> Vector3:
	# Face the cup from spawn; levels with a portal first shot may override.
	if _spawn == null:
		return Vector3(0.0, 0.0, -1.0)
	var to_cup := _cup_position - _spawn.global_position
	var flat := ShotMath.horizontal_direction(to_cup)
	return flat if flat != Vector3.ZERO else Vector3(0.0, 0.0, -1.0)


func cup_position() -> Vector3:
	return _cup_position


func cup_plane_y() -> float:
	return _config.cup_plane_y if _config != null else 0.0


func turf_resistance() -> float:
	return _config.turf_resistance if _config != null else 0.55


func kill_plane_y() -> float:
	return _config.kill_plane_y if _config != null else -100.0


func course_bounds() -> AABB:
	return _config.course_bounds if _config != null else AABB(Vector3(-6, -2, -10), Vector3(12, 5, 20))


func cup_anchor_exclusion_radius() -> float:
	return _config.cup_anchor_exclusion_radius if _config != null else 0.6


## First authored fallback anchor (Spawn is always acceptable last resort).
func fallback_anchor() -> Transform3D:
	if not _safe_anchors.is_empty():
		return _safe_anchors[0].global_transform
	return spawn_transform()


func anchor_near_cup(position: Vector3) -> bool:
	var flat_delta := Vector3(position.x - _cup_position.x, 0.0, position.z - _cup_position.z)
	return flat_delta.length() < cup_anchor_exclusion_radius()


## Sphere-overlap check that a reset position is actually free (docs/05 §3).
func anchor_blocked(candidate: Transform3D, query_radius: float = 0.28) -> bool:
	if instance == null:
		return true
	var shape := SphereShape3D.new()
	shape.radius = query_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = candidate
	params.collision_mask = 0b0000_0000_0110  # Course | MovingObstacle
	var space := get_world_3d().direct_space_state
	return space.intersect_shape(params, 1).size() > 0


func _find_marker(root: Node, marker_name: String) -> Marker3D:
	var found := root.find_child(marker_name, true, false)
	return found as Marker3D if found is Marker3D else null


func _find_config(root: Node) -> LevelConfig:
	var found := root.find_child("LevelConfig", true, false)
	return found as LevelConfig if found is LevelConfig else null


func _find_cup(root: Node) -> Area3D:
	var found := root.find_child("Cup", true, false)
	if found is Area3D:
		return found as Area3D
	# The Cup Area3D may be grouped under a "Cup" visual wrapper node.
	if found is Node3D:
		for child in (found as Node).find_children("*", "Area3D", true, false):
			return child as Area3D
	return null


func _on_cup_entered(body: Node3D) -> void:
	if body is BallController:
		ball_in_cup_zone = true


func _on_cup_exited(body: Node3D) -> void:
	if body is BallController:
		ball_in_cup_zone = false


func _on_kill_entered(body: Node3D) -> void:
	if body is BallController:
		kill_zone_entered.emit()
