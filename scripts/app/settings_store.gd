extends Node
## SettingsStore autoload (RB-045). Versioned settings with strict validation,
## last-good backup, and atomic-ish replace. Calibration stores numbers only.
## A settings write failure must never revert progress (separate files).

const SETTINGS_PATH := "user://settings.json"
const BACKUP_PATH := "user://settings.json.bak"

signal settings_changed(settings: Dictionary)

var settings: Dictionary = {}
var last_error := ""
var _saver := SaveFile.new()


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


func reduced_motion() -> bool:
	return bool(settings.get("reduced_motion", false))


func quality() -> String:
	return String(settings.get("quality", "medium"))


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


# --- Persistence via the shared, operation-checked SaveFile ---


func save() -> bool:
	var result := _saver.write_object(
		SETTINGS_PATH, BACKUP_PATH, settings,
		func(d: Variant) -> SaveSchema.ValidationResult: return SaveSchema.validate_settings(d)
	)
	if not result["ok"]:
		last_error = _saver.last_error
		return false
	return true


func _load() -> void:
	var validator := func(d: Variant) -> SaveSchema.ValidationResult:
		return SaveSchema.validate_settings(d)
	var primary := _saver.read_object(SETTINGS_PATH, validator)
	if primary["ok"]:
		settings = primary["value"]
		return
	var backup := _saver.read_object(BACKUP_PATH, validator)
	if backup["ok"]:
		settings = backup["value"]
		save()  # heal primary from backup
		return
# Fresh profile: the schema requires schema_version in the input, so seed it
# — validating an empty dict fails and would poison every later write.
	settings = SaveSchema.validate_settings({"schema_version": SaveSchema.SUPPORTED_SETTINGS_VERSION}).value  # defaults
	save()
