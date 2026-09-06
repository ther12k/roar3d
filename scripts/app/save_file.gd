class_name SaveFile
extends RefCounted
## Shared durable-write/read helper for progress and settings
## (docs/08_CONTENT_AND_SAVE_DATA.md §4): build an immutable snapshot,
## validate it, write a temp file, re-read and verify, keep the previous
## validated primary as backup, replace via checked rename.
##
## Review round 1: copy/rename results must be checked — a verified temp
## file is NOT proof the primary was replaced. File operations are instance
## methods (seams) so tests can inject failures at each step.


var last_error := ""


## Virtual seams (subclasses inject failures in tests).
func _open_dir() -> DirAccess:
	return DirAccess.open("user://")


func _copy(from: String, to: String) -> Error:
	return _open_dir().copy(from, to)


func _rename(from: String, to: String) -> Error:
	return _open_dir().rename(from, to)


## Validate → write → verify → backup → replace. `validator` takes a parsed
## object and returns a SaveSchema.ValidationResult-compatible Dictionary
## {valid: bool, value: Dictionary, errors: Array}. Returns
## {ok: bool, error: String, warning: String}.
func write_object(path: String, backup_path: String, payload: Dictionary, validator: Callable) -> Dictionary:
	last_error = ""
	var check: Dictionary = _validate(payload, validator)
	if not check["valid"]:
		return {"ok": false, "error": "schema_rejected: " + String(check["error"]), "warning": ""}
	var text := JSON.stringify(payload, "  ")
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		last_error = "open_failed"
		return {"ok": false, "error": last_error, "warning": ""}
	file.store_string(text)
	file.flush()
	file = null
	var verify := FileAccess.open(temp_path, FileAccess.READ)
	if verify == null:
		last_error = "verify_unreadable"
		return {"ok": false, "error": last_error, "warning": ""}
	var verified_text := verify.get_as_text()
	verify = null
	if verified_text != text:
		last_error = "verify_mismatch"
		return {"ok": false, "error": last_error, "warning": ""}
	var verified := _validate(JSON.parse_string(verified_text), validator)
	if not verified["valid"]:
		last_error = "verify_schema"
		return {"ok": false, "error": last_error, "warning": ""}
	# Keep the previous validated primary as last-good backup. A backup copy
	# failure is a durability warning; a rename failure is a hard error and
	# leaves the old primary intact.
	var warning := ""
	if FileAccess.file_exists(path):
		var copy_err := _copy(path, backup_path)
		if copy_err != OK:
			warning = "backup_copy_failed:%d" % copy_err
	var rename_err := _rename(temp_path, path)
	if rename_err != OK:
		last_error = "rename_failed:%d" % rename_err
		return {"ok": false, "error": last_error, "warning": warning}
	return {"ok": true, "error": "", "warning": warning}


## Validated read: {ok, value, error}; missing → ok=false, error="missing".
func read_object(path: String, validator: Callable) -> Dictionary:
	last_error = ""
	if not FileAccess.file_exists(path):
		return {"ok": false, "value": {}, "error": "missing"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "unreadable"
		return {"ok": false, "value": {}, "error": last_error}
	var text := file.get_as_text()
	file = null
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		last_error = "malformed_json"
		return {"ok": false, "value": {}, "error": last_error}
	var check: Dictionary = _validate(parsed, validator)
	if not check["valid"]:
		last_error = String(check["error"])
		return {"ok": false, "value": {}, "error": last_error}
	return {"ok": true, "value": check["value"], "error": ""}


func _validate(data: Variant, validator: Callable) -> Dictionary:
	var result: Variant = validator.call(data)
	if typeof(result) == TYPE_DICTIONARY:
		var as_dict: Dictionary = result
		if as_dict.has("valid"):
			return as_dict
	# SaveSchema.ValidationResult object → convert.
	if result is SaveSchema.ValidationResult:
		var vr: SaveSchema.ValidationResult = result
		return {"valid": vr.valid, "value": vr.value, "error": ";".join(vr.errors)}
	return {"valid": false, "value": {}, "error": "validator_invalid"}
