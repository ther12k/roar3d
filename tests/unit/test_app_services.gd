extends RefCounted
class_name TestAppServices
## App-service unit tests (RB-025 audio, RB-029 quality tiers): bus routing,
## ducking math, effect library, and quality-tier application. Headless-safe.

var harness: TestHarness


func run(h: TestHarness) -> void:
	harness = h
	harness.suite = "unit.audio"
	_audio_tests()
	harness.suite = "unit.quality"
	_quality_tests()


func _audio_tests() -> void:
	# Buses exist and volumes apply (0..1 linear, muted to -80 dB).
	AudioDirector.apply_volumes(0.5, 0.8)
	harness.check_near(
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioDirector.MUSIC_BUS)),
		linear_to_db(0.5), 0.01, "music bus volume follows linear setting")
	AudioDirector.apply_volumes(0.0, 0.8)
	harness.check_near(
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioDirector.MUSIC_BUS)),
		-80.0, 0.01, "zero music volume mutes the bus")
	AudioDirector.apply_volumes(0.7, 0.8)

	# Capture ducking lowers buses by the duck amount and restores exactly.
	var music_bus := AudioServer.get_bus_index(AudioDirector.MUSIC_BUS)
	var before := AudioServer.get_bus_volume_db(music_bus)
	AudioDirector.duck_for_capture(true)
	harness.check_near(AudioServer.get_bus_volume_db(music_bus), before - AudioDirector.DUCK_DB, 0.01,
		"duck lowers the music bus by the duck amount")
	AudioDirector.duck_for_capture(false)
	harness.check_near(AudioServer.get_bus_volume_db(music_bus), before, 0.01,
		"un-duck restores the exact prior bus volume")

	# Effect library: known cues play, unknown names rejected.
	harness.check(AudioDirector.play_effect("putt"), "putt cue plays")
	harness.check(AudioDirector.play_effect("cup"), "cup cue plays")
	harness.check(AudioDirector.play_effect("fall"), "fall cue plays")
	harness.check(AudioDirector.play_effect("click"), "click cue plays")
	harness.check(not AudioDirector.play_effect("does_not_exist"), "unknown effect rejected")
	harness.check(AudioServer.get_bus_index(AudioDirector.EFFECTS_BUS) >= 0, "effects bus exists")

	# Effects bus never feeds the microphone capture path.
	var fx_bus := AudioServer.get_bus_index(AudioDirector.EFFECTS_BUS)
	harness.check_eq(String(AudioServer.get_bus_send(fx_bus)), "Master", "effects bus sends to Master, not the mic path")


func _quality_tests() -> void:
	var viewport: Viewport = Engine.get_main_loop().root
	SettingsStore.set_quality("low")
	QualityDirector.apply("low")
	harness.check_near(viewport.scaling_3d_scale, 0.7, 0.001, "low tier scales 3D resolution to 0.7")
	harness.check_eq(viewport.msaa_3d, Viewport.MSAA_DISABLED, "low tier disables MSAA")
	SettingsStore.set_quality("high")
	QualityDirector.apply("high")
	harness.check_near(viewport.scaling_3d_scale, 1.0, 0.001, "high tier restores full resolution")
	harness.check_eq(viewport.msaa_3d, Viewport.MSAA_2X, "high tier enables 2x MSAA")
	SettingsStore.set_quality("high")
	harness.check_eq(SettingsStore.quality(), "high", "set_quality persists through the store (first-run bootstrap fixed)")
	SettingsStore.set_quality("medium")
	QualityDirector.apply("medium")
	harness.check_near(viewport.scaling_3d_scale, 1.0, 0.001, "medium tier keeps full resolution")
	harness.check_eq(viewport.msaa_3d, Viewport.MSAA_DISABLED, "medium tier disables MSAA")
	# Unknown tier falls back to medium behavior (full resolution).
	QualityDirector.apply("bogus")
	harness.check_near(viewport.scaling_3d_scale, 1.0, 0.001, "unknown tier falls back safely")
	SettingsStore.set_quality("medium")
