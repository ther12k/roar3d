class_name LevelCatalog
extends RefCounted
## Loads and validates the packaged level catalog
## (resources/catalog/level_catalog.json). Schema + semantic validation per
## docs/08_CONTENT_AND_SAVE_DATA.md §2: unique ids, contiguous order, exactly
## six levels per world in this release, twelve total, known mechanics,
## scene_path matching the id, max_strokes >= par + 2.
##
## Catalog metadata is a design brief, never proof that a scene exists or is
## solvable. `is_playable` additionally requires a non-design_only status and
## the scene file to exist on disk.

const PACKAGED_PATH := "res://resources/catalog/level_catalog.json"
const KNOWN_MECHANICS: Array[String] = [
	"turf", "rail", "ramp", "moving_gate", "portal", "bounce_pad", "void", "cup",
]
const KNOWN_STATUSES: Array[String] = ["design_only", "graybox", "playtest_ready", "validated"]
const LEVELS_PER_WORLD := 6
const TOTAL_LEVELS := 12


class CatalogData extends RefCounted:
	var valid := false
	var errors: Array[String] = []
	var content_version := ""
	var worlds: Array = []  # [{id, name, order}] ordered
	var levels: Array = []  # validated level dicts in global order
	var ordered_ids: Array[String] = []

	func level_by_id(level_id: String) -> Dictionary:
		for level: Dictionary in levels:
			if String(level["id"]) == level_id:
				return level
		return {}

	func world_level_ids(world_id: String) -> Array[String]:
		var ids: Array[String] = []
		for level: Dictionary in levels:
			if String(level["world_id"]) == world_id:
				ids.append(String(level["id"]))
		return ids

	func is_playable(level_id: String) -> bool:
		var level := level_by_id(level_id)
		if level.is_empty():
			return false
		if String(level["status"]) == "design_only":
			return false
		return ResourceLoader.exists(String(level["scene_path"]))


static func validate(data: Variant) -> CatalogData:
	var catalog := CatalogData.new()
	if typeof(data) != TYPE_DICTIONARY:
		catalog.errors.append("catalog_not_object")
		return catalog
	var d: Dictionary = data
	if int(d.get("schema_version", 0)) != 1:
		catalog.errors.append("schema_version")
		return catalog
	catalog.content_version = String(d.get("content_version", ""))
	if catalog.content_version.is_empty():
		catalog.errors.append("content_version")

	var worlds: Variant = d.get("worlds", [])
	if typeof(worlds) != TYPE_ARRAY or worlds.size() != 2:
		catalog.errors.append("worlds_must_be_two")
		return catalog
	var world_order: Array = []
	for world: Variant in worlds:
		if typeof(world) != TYPE_DICTIONARY:
			catalog.errors.append("world_not_object")
			continue
		var world_id := String(world.get("id", ""))
		if world_id.is_empty() or catalog.worlds.any(func(w: Dictionary) -> bool: return String(w["id"]) == world_id):
			catalog.errors.append("world_id:" + world_id)
		world_order.append(int(world.get("order", -1)))
		catalog.worlds.append({
			"id": world_id,
			"name": String(world.get("name", world_id)),
			"order": int(world.get("order", -1)),
		})
	world_order.sort()
	if world_order != [1, 2]:
		catalog.errors.append("world_order_not_1_2")
	if not catalog.errors.is_empty():
		return catalog
	catalog.worlds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))

	var levels: Variant = d.get("levels", [])
	if typeof(levels) != TYPE_ARRAY:
		catalog.errors.append("levels_not_array")
		return catalog
	if levels.size() != TOTAL_LEVELS:
		catalog.errors.append("levels_count:" + str(levels.size()))

	var seen_ids: Dictionary = {}
	var per_world: Dictionary = {}
	for level: Variant in levels:
		if typeof(level) != TYPE_DICTIONARY:
			catalog.errors.append("level_not_object")
			continue
		var id := String(level.get("id", ""))
		if id.is_empty() or seen_ids.has(id):
			catalog.errors.append("level_id:" + id)
			continue
		seen_ids[id] = true
		var world_id := String(level.get("world_id", ""))
		var world_known := false
		for world: Dictionary in catalog.worlds:
			if String(world["id"]) == world_id:
				world_known = true
		if not world_known:
			catalog.errors.append("level_world:" + id)
		var par := int(level.get("par", 0))
		var max_strokes := int(level.get("max_strokes", 0))
		if par < 1 or max_strokes < par + 2:
			catalog.errors.append("level_par:" + id)
		var scene_path := String(level.get("scene_path", ""))
		if scene_path != "res://scenes/levels/" + id + ".tscn":
			catalog.errors.append("level_scene_path:" + id)
		var mechanics: Variant = level.get("mechanics", [])
		if typeof(mechanics) != TYPE_ARRAY or (mechanics as Array).is_empty():
			catalog.errors.append("level_mechanics:" + id)
		else:
			for mechanic: Variant in mechanics:
				if not KNOWN_MECHANICS.has(String(mechanic)):
					catalog.errors.append("level_mechanic:" + id + ":" + String(mechanic))
		var status := String(level.get("status", ""))
		if not KNOWN_STATUSES.has(status):
			catalog.errors.append("level_status:" + id)
		var title := String(level.get("title", ""))
		if title.is_empty():
			catalog.errors.append("level_title:" + id)
		per_world[world_id] = int(per_world.get(world_id, 0)) + 1
		catalog.levels.append({
			"id": id,
			"world_id": world_id,
			"order": int(level.get("order", 0)),
			"world_index": int(level.get("world_index", 0)),
			"title": title,
			"scene_path": scene_path,
			"par": par,
			"max_strokes": max_strokes,
			"mechanics": (mechanics as Array).map(func(m: Variant) -> String: return String(m)),
			"teaching_goal": String(level.get("teaching_goal", "")),
			"layout_brief": String(level.get("layout_brief", "")),
			"solution_brief": String(level.get("solution_brief", "")),
			"validation_checks": level.get("validation_checks", []),
			"status": status,
		})

	for world: Dictionary in catalog.worlds:
		var count := int(per_world.get(String(world["id"]), 0))
		if count != LEVELS_PER_WORLD:
			catalog.errors.append("world_count:" + String(world["id"]) + ":" + str(count))
	# `order` is the global 1..12 rank; `world_index` is the per-world 1..6
	# position. Both must be unique and contiguous.
	var global_orders: Array = []
	for level: Dictionary in catalog.levels:
		global_orders.append(int(level["order"]))
	global_orders.sort()
	var expected_orders: Array = []
	for i: int in TOTAL_LEVELS:
		expected_orders.append(i + 1)
	if global_orders != expected_orders:
		catalog.errors.append("global_order_not_contiguous")
	for world: Dictionary in catalog.worlds:
		var indexes: Array = []
		for level: Dictionary in catalog.levels:
			if String(level["world_id"]) == String(world["id"]):
				indexes.append(int(level["world_index"]))
		indexes.sort()
		if indexes != [1, 2, 3, 4, 5, 6]:
			catalog.errors.append("world_order:" + String(world["id"]))

	if not catalog.errors.is_empty():
		return catalog
	catalog.levels.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["order"]) != int(b["order"]):
				return int(a["order"]) < int(b["order"])
			return int(a["world_index"]) < int(b["world_index"])
	)
	# Global play order: Cloud Cliffs 1-6 then Portal Peaks 1-6.
	catalog.levels.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var world_a := 0
			var world_b := 0
			for i: int in catalog.worlds.size():
				if String(catalog.worlds[i]["id"]) == String(a["world_id"]):
					world_a = i
				if String(catalog.worlds[i]["id"]) == String(b["world_id"]):
					world_b = i
			if world_a != world_b:
				return world_a < world_b
			return int(a["order"]) < int(b["order"])
	)
	for level: Dictionary in catalog.levels:
		catalog.ordered_ids.append(String(level["id"]))
	catalog.valid = true
	return catalog


## Load the packaged catalog. A catalog that fails validation is a build
## error: the caller must show a loading error, not unlocked content.
static func load_packaged() -> CatalogData:
	if not FileAccess.file_exists(PACKAGED_PATH):
		var missing := CatalogData.new()
		missing.errors.append("catalog_missing")
		return missing
	var file := FileAccess.open(PACKAGED_PATH, FileAccess.READ)
	if file == null:
		var unreadable := CatalogData.new()
		unreadable.errors.append("catalog_unreadable")
		return unreadable
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file = null
	return validate(parsed)
