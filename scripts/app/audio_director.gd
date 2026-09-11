extends Node
## AudioDirector autoload: music/effects bus volumes, capture ducking, and a
## small library of original synthesized nonverbal feedback sounds (RB-025).
## Owns buses only — never microphone permission or capture state (docs/03 §3).
## Effects are extremely short synthesized tones, generated for this repo
## (see docs/ASSET_INVENTORY.md); no recorded player audio ever plays here.

const MUSIC_BUS := "Music"
const EFFECTS_BUS := "Effects"
const DUCK_DB := 18.0

# Loaded at boot (not `const preload`) so the streams release with this node
# instead of living in the script constant table past the exit-time resource
# check (which flagged them as leaked at shutdown).
const EFFECT_NAMES := ["putt", "cup", "fall", "click", "bounce", "stretch"]
const MUSIC_TRACKS := {
	"sunny": "res://assets/audio/music_sunny.wav",
	"sunset": "res://assets/audio/music_sunset.wav",
}
const PLAYERS := 4  # round-robin so overlapping short cues never cut each other

var _streams: Dictionary = {}
var _music_volume := 0.7
var _effects_volume := 0.8
var _ducked_for_capture := false
var _pool: Array[AudioStreamPlayer] = []
var _next_player := 0
var _music_player: AudioStreamPlayer
var _current_track := ""


func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(EFFECTS_BUS)
	for effect_name: String in EFFECT_NAMES:
		_streams[effect_name] = load("res://assets/audio/%s.wav" % effect_name)
	# Saved volumes apply at boot and on every settings change.
	apply_volumes(
		float(SettingsStore.settings.get("music_volume", 0.7)),
		float(SettingsStore.settings.get("effects_volume", 0.8))
	)
	SettingsStore.settings_changed.connect(func(_s: Dictionary) -> void:
		apply_volumes(
			float(SettingsStore.settings.get("music_volume", 0.7)),
			float(SettingsStore.settings.get("effects_volume", 0.8))
		))
	for i: int in PLAYERS:
		var player := AudioStreamPlayer.new()
		player.bus = EFFECTS_BUS
		add_child(player)
		_pool.append(player)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = MUSIC_BUS
	add_child(_music_player)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")


func apply_volumes(music: float, effects: float) -> void:
	_music_volume = clampf(music, 0.0, 1.0)
	_effects_volume = clampf(effects, 0.0, 1.0)
	_refresh_bus_db(MUSIC_BUS, _music_volume)
	_refresh_bus_db(EFFECTS_BUS, _effects_volume)


func _refresh_bus_db(bus_name: String, base_linear: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		return
	var base_db := linear_to_db(base_linear) if base_linear > 0.0 else -80.0
	if _ducked_for_capture:
		base_db = (base_db - DUCK_DB) if base_db > -80.0 else -80.0
	AudioServer.set_bus_volume_db(bus, base_db)


## Duck game audio while a voice capture hold is open so the game cannot
## power itself (docs/02 §7). Restores on capture close.
func duck_for_capture(duck: bool) -> void:
	if _ducked_for_capture == duck:
		return
	_ducked_for_capture = duck
	_refresh_bus_db(MUSIC_BUS, _music_volume)
	_refresh_bus_db(EFFECTS_BUS, _effects_volume)


## Release playback objects at shutdown: AudioServer keeps the last
## AudioStreamPlayback alive past the exit-time resource check otherwise,
## which reads as a leak. _exit_tree runs before that check.
func _exit_tree() -> void:
	for player: AudioStreamPlayer in _pool:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	if is_instance_valid(_music_player):
		_music_player.stop()
		_music_player.stream = null


## Start a named looping background track (original, synthesized — see
## tools/make_music.py). Requesting the track that is already playing is a
## no-op, so scene changes never restart the music. The Music bus ducking
## during voice capture applies automatically (docs/02 §7).
func play_music(track: String) -> bool:
	if not MUSIC_TRACKS.has(track):
		return false
	if _current_track == track and _music_player.playing:
		return true
	var stream: AudioStreamWAV = load(String(MUSIC_TRACKS[track]))
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	# 16-bit stereo: 4 bytes per frame.
	stream.loop_end = stream.data.size() / 4
	_music_player.stream = stream
	_music_player.play()
	_current_track = track
	return true


func stop_music() -> void:
	_current_track = ""
	_music_player.stop()
	_music_player.stream = null


func current_music_track() -> String:
	return _current_track


## Play a named nonverbal feedback cue. `volume` (0..1) maps to the pool
## player's gain so impact-strength cues (bounce) can scale down softly.
## Returns false for unknown names. Never plays through the microphone
## capture path (effects live on the Effects bus, which sends to Master, not
## to MicCapture).
func play_effect(effect_name: String, volume := 1.0) -> bool:
	if not _streams.has(effect_name):
		return false
	var player := _pool[_next_player]
	_next_player = (_next_player + 1) % PLAYERS
	player.volume_db = linear_to_db(clampf(volume, 0.05, 1.0))
	player.stream = _streams[effect_name]
	player.play()
	return true
