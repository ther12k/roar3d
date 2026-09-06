extends RefCounted
## SaveFile write/read algorithm with failure injection at each file
## operation (review round 1: replacement failures were unchecked and could
## be reported as success).


class FailingRename extends SaveFile:
	func _rename(_from: String, _to: String) -> Error:
		return FAILED


class FailingCopy extends SaveFile:
	func _copy(_from: String, _to: String) -> Error:
		return FAILED


const PATH := "user://test_savefile.json"
const BACKUP := "user://test_savefile.json.bak"


func run(h: TestHarness) -> void:
	h.suite = "save_file"
	_cleanup()
	var validator := func(d: Variant) -> SaveSchema.ValidationResult:
		return SaveSchema.validate_settings(d)

	# Baseline: a good write lands and reads back.
	var saver := SaveFile.new()
	var payload := {"schema_version": 1, "input_mode": "touch", "music_volume": 0.5, "effects_volume": 0.5}
	var first: Dictionary = saver.write_object(PATH, BACKUP, payload, validator)
	h.check(bool(first["ok"]), "normal write succeeds: " + String(first["error"]))
	var read: Dictionary = saver.read_object(PATH, validator)
	h.check(bool(read["ok"]) and float(read["value"]["music_volume"]) == 0.5, "round trip preserves value")

	# Rename failure: must be reported, and the previous primary must survive.
	var failing_rename := FailingRename.new()
	var updated := payload.duplicate(true)
	updated["music_volume"] = 0.9
	var second: Dictionary = failing_rename.write_object(PATH, BACKUP, updated, validator)
	h.check(not bool(second["ok"]), "rename failure is not reported as success")
	h.check(String(second["error"]).begins_with("rename_failed"), "rename failure error code")
	var after_failure: Dictionary = saver.read_object(PATH, validator)
	h.check(bool(after_failure["ok"]) and float(after_failure["value"]["music_volume"]) == 0.5, "old primary intact after failed replacement (QA-038)")

	# Backup-copy failure: primary still replaced; durability warning surfaced.
	var failing_copy := FailingCopy.new()
	var third: Dictionary = failing_copy.write_object(PATH, BACKUP, updated, validator)
	h.check(bool(third["ok"]), "write succeeds despite backup copy failure")
	h.check(String(third["warning"]).begins_with("backup_copy_failed"), "backup failure surfaced as warning")
	var after_copy: Dictionary = saver.read_object(PATH, validator)
	h.check(bool(after_copy["ok"]) and float(after_copy["value"]["music_volume"]) == 0.9, "primary updated when only backup failed")

	# Schema rejection: nothing touches disk.
	var rejecting := SaveFile.new()
	var bad: Dictionary = rejecting.write_object(PATH, BACKUP, {"schema_version": 99}, validator)
	h.check(not bool(bad["ok"]) and String(bad["error"]).begins_with("schema_rejected"), "invalid payload rejected before writing")

	# Malformed read.
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("{truncated")
	file = null
	var malformed: Dictionary = saver.read_object(PATH, validator)
	h.check(not bool(malformed["ok"]) and String(malformed["error"]) == "malformed_json", "truncated primary detected on read")
	_cleanup()


func _cleanup() -> void:
	var dir := DirAccess.open("user://")
	for path: String in [PATH, BACKUP, PATH + ".tmp"]:
		if dir.file_exists(path):
			dir.remove(path)
