extends Node
## ProgressStore autoload (RB-045). Local durable progress with the write
## algorithm from docs/08 §4: immutable snapshot -> temp file -> verify ->
## backed-up replace. Completion IDs are idempotence keys; bests never
## worsen; unlocks derive from completed IDs, never trusted booleans.

const PROGRESS_PATH := "user://progress.json"
const BACKUP_PATH := "user://progress.json.bak"

signal progress_changed()

var data: Dictionary = {}
var catalog: LevelCatalog.CatalogData = null
var last_error := ""


func _ready() -> void:
	catalog = LevelCatalog.load_packaged()
	if not catalog.valid:
		push_error("Level catalog invalid: " + ", ".join(catalog.errors))
	_load()


func ordered_ids() -> Array[String]:
	return catalog.ordered_ids if catalog != null else ([] as Array[String])


func is_completed(level_id: String) -> bool:
	return (data.get("completed_levels", []) as Array).has(level_id)


func is_unlocked(level_id: String) -> bool:
	return ProgressionRules.is_level_unlocked(level_id, ordered_ids(), completed_set())


func completed_set() -> Dictionary:
	var out: Dictionary = {}
	for id: Variant in data.get("completed_levels", []):
		out[String(id)] = true
	return out


func best_for(level_id: String) -> Dictionary:
	var best: Variant = data.get("best_results", {}).get(level_id, {})
	return best if typeof(best) == TYPE_DICTIONARY else {}


func equipped_cosmetic() -> String:
	return String(data.get("equipped_cosmetic", "lion"))


func equip_cosmetic(cosmetic_id: String) -> bool:
	if not ProgressionRules.is_cosmetic_unlocked(cosmetic_id, completed_set()):
		return false
	var next := data.duplicate(true)
	next["equipped_cosmetic"] = cosmetic_id
	return _commit(next)


func last_played_level() -> String:
	return String(data.get("last_played_level", ""))


func set_last_played(level_id: String) -> void:
	if not ordered_ids().has(level_id):
		return
	var next := data.duplicate(true)
	next["last_played_level"] = level_id
	_commit(next)


## Record one completion attempt result. Duplicate completion IDs apply once;
## a worse replay never replaces a better stored best (docs/08 §5).
func record_completion(level_id: String, strokes: int, stars: int, completion_id: String) -> Dictionary:
	if not ordered_ids().has(level_id):
		return {}
	if (data.get("applied_completion_ids", []) as Array).has(completion_id):
		return best_for(level_id)
	var next := data.duplicate(true)
	var stored: Dictionary = next["best_results"].get(level_id, {})
	var merged := ScoringRules.merge_best(stored, strokes, stars)
	next["best_results"][level_id] = {
		"best_strokes": merged["best_strokes"],
		"best_stars": merged["best_stars"],
	}
	if not (next["completed_levels"] as Array).has(level_id):
		(next["completed_levels"] as Array).append(level_id)
	var ids: Array = next["applied_completion_ids"]
	ids.append(completion_id)
	if ids.size() > SaveSchema.MAX_COMPLETION_IDS:
		next["applied_completion_ids"] = ids.slice(ids.size() - SaveSchema.MAX_COMPLETION_IDS)
	var ok := _commit(next)
	if not ok:
		# Keep the accepted result in memory even though durability failed;
		# the session surfaces a Save Warning and offers Retry Save.
		data = next
	return merged


## The hole "Play" resumes: first playable unlocked-uncompleted level, else
## last played. Never resolves to a catalog entry whose scene is missing.
func next_playable_level() -> String:
	var playable: Array[String] = []
	for id: String in ordered_ids():
		if catalog != null and catalog.is_playable(id):
			playable.append(id)
	if playable.is_empty():
		return ""
	var candidate := ProgressionRules.next_playable(playable, completed_set(), last_played_level())
	if playable.has(candidate):
		return candidate
	return playable[0]


# --- Persistence (docs/08 §4) ---


func save() -> bool:
	return _atomic_write(PROGRESS_PATH, BACKUP_PATH, data)


func retry_save() -> bool:
	return save()


func _load() -> void:
	var primary := _read_validated(PROGRESS_PATH)
	if primary.has("ok"):
		data = primary["value"]
		return
	var backup := _read_validated(BACKUP_PATH)
	if backup.has("ok"):
		data = backup["value"]
		save()  # heal primary from last-good backup
		return
	# Neither valid: fresh local profile. Informative only; no silent unlock.
	data = SaveSchema.validate_progress(
		{"schema_version": 1, "content_version": SaveSchema.CONTENT_VERSION}, ordered_ids()
	).value
	save()


func _read_validated(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "missing"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "unreadable"}
	var text := file.get_as_text()
	file = null
	var parsed := SaveSchema.parse_object(text)
	if not parsed["ok"]:
		return {"error": "malformed"}
	var result := SaveSchema.validate_progress(parsed["value"], ordered_ids())
	if not result.valid:
		return {"error": ";".join(result.errors)}
	return {"ok": true, "value": result.value}


func _commit(next: Dictionary) -> bool:
	var result := SaveSchema.validate_progress(next, ordered_ids())
	if not result.valid:
		last_error = ";".join(result.errors)
		push_error("Progress rejected by schema: " + last_error)
		return false
	data = result.value
	var ok := save()
	if ok:
		progress_changed.emit()
	return ok


func _atomic_write(path: String, backup_path: String, payload: Dictionary) -> bool:
	var text := JSON.stringify(payload, "  ")
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		last_error = "open_failed"
		return false
	file.store_string(text)
	file.flush()
	file = null
	var verify := FileAccess.open(temp_path, FileAccess.READ)
	if verify == null or verify.get_as_text() != text:
		last_error = "verify_failed"
		return false
	verify = null
	var dir := DirAccess.open("user://")
	if dir == null:
		last_error = "dir_failed"
		return false
	if FileAccess.file_exists(path):
		dir.copy(path, backup_path)
	dir.rename(temp_path, path)
	return true
