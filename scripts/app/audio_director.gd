extends Node
## AudioDirector autoload: music/effects bus volumes and capture ducking.
## Owns buses only — never microphone permission or capture state (docs/03 §3).

const MUSIC_BUS := "Music"
const EFFECTS_BUS := "Effects"

var _music_volume := 0.7
var _effects_volume := 0.8
var _ducked_for_capture := false


func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(EFFECTS_BUS)
	apply_volumes(_music_volume, _effects_volume)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")


func apply_volumes(music: float, effects: float) -> void:
	_music_volume = clampf(music, 0.0, 1.0)
	_effects_volume = clampf(effects, 0.0, 1.0)
	var music_bus := AudioServer.get_bus_index(MUSIC_BUS)
	var effects_bus := AudioServer.get_bus_index(EFFECTS_BUS)
	if music_bus >= 0:
		AudioServer.set_bus_volume_db(music_bus, linear_to_db(_music_volume) if _music_volume > 0.0 else -80.0)
	if effects_bus >= 0:
		AudioServer.set_bus_volume_db(effects_bus, linear_to_db(_effects_volume) if _effects_volume > 0.0 else -80.0)


## Duck game audio while a voice capture hold is open so the game cannot
## power itself (docs/02 §7). Restores on capture close.
func duck_for_capture(duck: bool) -> void:
	if _ducked_for_capture == duck:
		return
	_ducked_for_capture = duck
	for bus_name: String in [MUSIC_BUS, EFFECTS_BUS]:
		var bus := AudioServer.get_bus_index(bus_name)
		if bus >= 0:
			var base_db := linear_to_db(_music_volume if bus_name == MUSIC_BUS else _effects_volume)
			if _music_volume <= 0.0 or _effects_volume <= 0.0:
				base_db = -80.0
			AudioServer.set_bus_volume_db(bus, base_db - 18.0 if duck else base_db)
