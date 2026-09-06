class_name PlatformAdapter
extends RefCounted
## Platform seams kept in one place. Android microphone permission behavior
## (RECORD_AUDIO prompt timing, OS privacy indicator after release) is NOT
## yet verified on a physical device — see docs/IMPLEMENTATION_STATUS.md
## (open M0 spike RB-005) before shipping any copy that claims "Mic off".


## Whether the OS reports microphone permission as granted. Desktop
## platforms have no such permission gate.
static func has_microphone_permission() -> bool:
	if OS.get_name() == "Android":
		return "android.permission.RECORD_AUDIO" in OS.get_granted_permissions()
	return true


## Best-effort in-context permission request before calibration/first hold
## (FR-02). Godot 4.7 exposes OS.request_permission; whether the prompt
## timing and result callback behave correctly on Android is part of the
## still-open device spike (RB-005) — do not assume this works until tested
## on hardware. Returns true when permission is (already) available.
static func try_request_microphone_permission() -> bool:
	if has_microphone_permission():
		return true
	if OS.get_name() == "Android" and ClassDB.class_has_method("OS", "request_permission"):
		var requested: bool = OS.request_permission("RECORD_AUDIO")
		if requested:
			return has_microphone_permission()  # may still be pending/denied
	return false


## Non-sensitive audio route category (docs/04 §4). Kept coarse on purpose:
## no hardware identifiers are ever stored. Real route-change detection is
## deferred until the device spike (RB-005) documents observable behavior.
static func route_category() -> String:
	return "unknown"


static func is_desktop() -> bool:
	return OS.get_name() in ["Windows", "macOS", "Linux"]
