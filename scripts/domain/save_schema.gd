class_name SaveSchema
extends RefCounted
## Strict validation for local progress/settings JSON (schema version 1).
## A validated result is the only thing stores may keep in memory; corrupt or
## future-version data must surface a recovery path, never a crash or a
## silently-unlocked hole (docs/08_CONTENT_AND_SAVE_DATA.md).

const SUPPORTED_PROGRESS_VERSION := 1
const SUPPORTED_SETTINGS_VERSION := 1
const CONTENT_VERSION := "mvp-1"
const KNOWN_COSMETICS: Array[String] = ["lion", "panda", "robot", "classic", "gold", "tiger", "leaf"]
const KNOWN_QUALITIES: Array[String] = ["low", "medium", "high"]
const KNOWN_INPUT_MODES: Array[String] = ["touch", "voice"]
const KNOWN_ROUTE_CATEGORIES: Array[String] = ["built_in", "wired", "bluetooth", "unknown"]
const MAX_COMPLETION_IDS := 100


class ValidationResult extends RefCounted:
	var valid := false
	var errors: Array[String] = []
	var value: Dictionary = {}

	func fail(reason: String) -> ValidationResult:
		valid = false
		errors.append(reason)
		return self


## Parse JSON text into a Dictionary, or fail with a stable code.
static func parse_object(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "value": {}, "error": "malformed_json"}
	return {"ok": true, "value": parsed, "error": ""}


static func _require_int(data: Dictionary, key: String, result: ValidationResult, minimum: int = 0) -> bool:
	if not data.has(key):
		result.fail("missing:" + key)
		return false
	var v: Variant = data[key]
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		result.fail("type:" + key)
		return false
	var i := int(v)
	if i < minimum:
		result.fail("range:" + key)
		return false
	return true


static func _require_float(data: Dictionary, key: String, result: ValidationResult, lo: float, hi: float) -> bool:
	if not data.has(key):
		result.fail("missing:" + key)
		return false
	var v: Variant = data[key]
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		result.fail("type:" + key)
		return false
	var f := float(v)
	if not is_finite(f) or f < lo or f > hi:
		result.fail("range:" + key)
		return false
	return true


static func _require_string_in(data: Dictionary, key: String, allowed: Array, result: ValidationResult) -> bool:
	if not data.has(key) or typeof(data[key]) != TYPE_STRING or not allowed.has(String(data[key])):
		result.fail("value:" + key)
		return false
	return true


## Validate progress. known_level_ids comes from the packaged, validated
## catalog. Unknown top-level keys are dropped (explicit policy for v1: we
## never blind-merge future data).
static func validate_progress(data: Variant, known_level_ids: Array) -> ValidationResult:
	var result := ValidationResult.new()
	if typeof(data) != TYPE_DICTIONARY:
		return result.fail("not_object")
	var d: Dictionary = data
	if not _require_int(d, "schema_version", result, SUPPORTED_PROGRESS_VERSION):
		if result.errors.size() == 1 and result.errors[0].begins_with("range:"):
			return result.fail("unsupported_schema_version")
		return result
	if int(d["schema_version"]) != SUPPORTED_PROGRESS_VERSION:
		return result.fail("unsupported_schema_version")
	if typeof(d.get("content_version", "")) != TYPE_STRING or String(d["content_version"]).is_empty():
		return result.fail("value:content_version")

	var out: Dictionary = {
		"schema_version": SUPPORTED_PROGRESS_VERSION,
		"content_version": String(d["content_version"]),
		"best_results": {},
		"completed_levels": [],
		"equipped_cosmetic": ProgressionRules.COSMETIC_LION,
		"last_played_level": "",
		"applied_completion_ids": [],
	}

	var best: Variant = d.get("best_results", {})
	if typeof(best) != TYPE_DICTIONARY:
		return result.fail("type:best_results")
	for level_id: String in best:
		if not known_level_ids.has(level_id):
			result.fail("unknown_level:" + level_id)
			continue
		var entry: Variant = best[level_id]
		if typeof(entry) != TYPE_DICTIONARY:
			result.fail("type:best_results." + level_id)
			continue
		var entry_result := ValidationResult.new()
		if not _require_int(entry, "best_strokes", entry_result, 1):
			result.fail("range:best_results." + level_id)
			continue
		if not _require_int(entry, "best_stars", entry_result, 1) or int(entry["best_stars"]) > 3:
			result.fail("range:best_results." + level_id)
			continue
		out["best_results"][level_id] = {
			"best_strokes": int(entry["best_strokes"]),
			"best_stars": int(entry["best_stars"]),
		}

	var completed: Variant = d.get("completed_levels", [])
	if typeof(completed) != TYPE_ARRAY:
		return result.fail("type:completed_levels")
	var seen: Dictionary = {}
	for id: Variant in completed:
		var level_id := String(id)
		if not known_level_ids.has(level_id) or seen.has(level_id):
			result.fail("invalid:completed_levels")
			continue
		seen[level_id] = true
		(out["completed_levels"] as Array).append(level_id)

	# Equipped cosmetic must be known AND earned; otherwise fall back to lion
	# rather than rejecting the whole save (recovery, not data loss).
	var cosmetic := String(d.get("equipped_cosmetic", ProgressionRules.COSMETIC_LION))
	if not KNOWN_COSMETICS.has(cosmetic) or not ProgressionRules.is_cosmetic_unlocked(cosmetic, seen):
		cosmetic = ProgressionRules.COSMETIC_LION
	out["equipped_cosmetic"] = cosmetic

	var last_played := String(d.get("last_played_level", ""))
	if not last_played.is_empty() and not known_level_ids.has(last_played):
		last_played = ""
	out["last_played_level"] = last_played

	var completion_ids: Variant = d.get("applied_completion_ids", [])
	if typeof(completion_ids) != TYPE_ARRAY:
		return result.fail("type:applied_completion_ids")
	var ids_seen: Dictionary = {}
	for completion_id: Variant in completion_ids:
		var as_text := String(completion_id)
		if as_text.is_empty() or ids_seen.has(as_text):
			continue
		ids_seen[as_text] = true
		(out["applied_completion_ids"] as Array).append(as_text)
	if (out["applied_completion_ids"] as Array).size() > MAX_COMPLETION_IDS:
		var trimmed: Array = out["applied_completion_ids"]
		trimmed = trimmed.slice(trimmed.size() - MAX_COMPLETION_IDS)
		out["applied_completion_ids"] = trimmed

	if not result.errors.is_empty():
		return result
	result.valid = true
	result.value = out
	return result


## Validate settings. `calibration` may be null; when present it must hold
## only the calibration numbers — never PCM, transcripts, or device ids.
static func validate_settings(data: Variant) -> ValidationResult:
	var result := ValidationResult.new()
	if typeof(data) != TYPE_DICTIONARY:
		return result.fail("not_object")
	var d: Dictionary = data
	if not _require_int(d, "schema_version", result, SUPPORTED_SETTINGS_VERSION):
		if result.errors.size() == 1 and result.errors[0].begins_with("range:"):
			return result.fail("unsupported_schema_version")
		return result
	if int(d["schema_version"]) != SUPPORTED_SETTINGS_VERSION:
		return result.fail("unsupported_schema_version")

	var out: Dictionary = {
		"schema_version": SUPPORTED_SETTINGS_VERSION,
		"input_mode": "touch",
		"music_volume": 0.7,
		"effects_volume": 0.8,
		"haptics": true,
		"reduced_motion": false,
		"quality": "medium",
		"calibration": null,
	}
	if d.has("input_mode") and not _require_string_in(d, "input_mode", KNOWN_INPUT_MODES, result):
		return result
	if d.has("input_mode"):
		out["input_mode"] = String(d["input_mode"])
	if d.has("music_volume"):
		if not _require_float(d, "music_volume", result, 0.0, 1.0):
			return result
		out["music_volume"] = float(d["music_volume"])
	if d.has("effects_volume"):
		if not _require_float(d, "effects_volume", result, 0.0, 1.0):
			return result
		out["effects_volume"] = float(d["effects_volume"])
	if d.has("haptics"):
		if typeof(d["haptics"]) != TYPE_BOOL:
			return result.fail("type:haptics")
		out["haptics"] = bool(d["haptics"])
	if d.has("reduced_motion"):
		if typeof(d["reduced_motion"]) != TYPE_BOOL:
			return result.fail("type:reduced_motion")
		out["reduced_motion"] = bool(d["reduced_motion"])
	if d.has("quality") and not _require_string_in(d, "quality", KNOWN_QUALITIES, result):
		return result
	if d.has("quality"):
		out["quality"] = String(d["quality"])

	var calibration: Variant = d.get("calibration", null)
	if calibration != null:
		if typeof(calibration) != TYPE_DICTIONARY:
			return result.fail("type:calibration")
		var cal: Dictionary = calibration
		var cal_result := ValidationResult.new()
		if not _require_string_in(cal, "algorithm_version", ["amplitude_v1"], cal_result):
			return result.fail("value:calibration.algorithm_version")
		if not _require_string_in(cal, "route_category", KNOWN_ROUTE_CATEGORIES, cal_result):
			return result.fail("value:calibration.route_category")
		for key: String in ["gate_db", "lower_db", "upper_db"]:
			if not _require_float(cal, key, cal_result, -120.0, 0.0):
				return result.fail("range:calibration." + key)
		if float(cal["upper_db"]) <= float(cal["lower_db"]) + 1.0:
			return result.fail("range:calibration.range")
		out["calibration"] = {
			"algorithm_version": String(cal["algorithm_version"]),
			"gate_db": float(cal["gate_db"]),
			"lower_db": float(cal["lower_db"]),
			"upper_db": float(cal["upper_db"]),
			"route_category": String(cal["route_category"]),
		}

	if not result.errors.is_empty():
		return result
	result.valid = true
	result.value = out
	return result
