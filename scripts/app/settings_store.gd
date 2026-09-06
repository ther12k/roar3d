extends Node
## SettingsStore autoload (RB-045). Versioned settings with strict validation,
## last-good backup, and atomic-ish replace. Calibration stores numbers only.
## A settings write failure must never revert progress (separate files).

const SETTINGS_PATH := "user://settings.json"
const BACKUP_PATH := "user://settings.json.bak"

signal settings_changed(settings: Dictionary)

var settings: Dictionary = {}
var last_error := ""


func _ready() -> void:
	_load()


func input_mode() -> String:
	return String(settings.get("input_mode", "touch"))


func is_voice_mode() -> bool:
	return input_mode() == "voice"


func calibration() -> Dictionary:
	var cal: Variant = settings.get("calibration", null)
	return cal if typeof(cal) == TYPE_DICTIONARY else {}


func has_valid_calibration() -> bool:
	var cal := calibration()
	return cal.has("lower_db") and cal.has("upper_db") and float(cal["upper_db"]) > float(cal["lower_db"])


func set_input_mode(mode: String) -> void:
	if mode != "touch" and mode != "voice":
		return
	_update({"input_mode": mode})


func set_calibration(calibration: Dictionary) -> void:
	_update({"calibration": calibration})


func set_volumes(music: float, effects: float) -> void:
	_update({"music_volume": clampf(music, 0.0, 1.0), "effects_volume": clampf(effects, 0.0, 1.0)})


func set_flag(key: String, value: bool) -> void:
	if key in ["haptics", "reduced_motion"]:
		_update({key: value})


func set_quality(quality: String) -> void:
	if quality in ["low", "medium", "high"]:
		_update({"quality": quality})


## Route change marks calibration stale (invalidates numbers) without
## deleting any other settings or progress (docs/06 UI-04).
func invalidate_calibration() -> void:
	_update({"calibration": null})


func _update(partial: Dictionary) -> void:
	var next := settings.duplicate(true)
	for key: String in partial:
		next[key] = partial[key]
	var result := SaveSchema.validate_settings(next)
	if not result.valid:
		last_error = ";".join(result.errors)
		push_error("Settings rejected by schema: " + last_error)
		return
	settings = result.value
	save()
	settings_changed.emit(settings)


# --- Persistence: validate -> temp write -> verify -> replace, with backup ---


func save() -> bool:
	return _atomic_write(SETTINGS_PATH, BACKUP_PATH, settings)


func _load() -> void:
	var primary := _read_validated(SETTINGS_PATH)
	if primary.has("ok"):
		settings = primary["value"]
		return
	var backup := _read_validated(BACKUP_PATH)
	if backup.has("ok"):
		settings = backup["value"]
		save()  # heal primary from backup
		return
	settings = SaveSchema.validate_settings({}).value  # defaults
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
	var result := SaveSchema.validate_settings(parsed["value"])
	if not result.valid:
		return {"error": ";".join(result.errors)}
	return {"ok": true, "value": result.value}


func _atomic_write(path: String, backup_path: String, data: Dictionary) -> bool:
	var text := JSON.stringify(data, "  ")
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		last_error = "open_failed"
		return false
	file.store_string(text)
	file.flush()
	file = null  # close
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
