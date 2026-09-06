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


## Non-sensitive audio route category (docs/04 §4). Kept coarse on purpose:
## no hardware identifiers are ever stored. Real route-change detection is
## deferred until the device spike (RB-005) documents observable behavior.
static func route_category() -> String:
	return "unknown"


static func is_desktop() -> bool:
	return OS.get_name() in ["Windows", "macOS", "Linux"]
