extends RefCounted
## Domain unit tests: shot math, scoring, progression, catalog, save schema.
## Mirrors the reference-code contracts in handoff/reference_code/*.gd.


func run(h: TestHarness) -> void:
	h.suite = "shot_math"
	_shot_math(h)
	h.suite = "scoring_rules"
	_scoring(h)
	h.suite = "progression_rules"
	_progression(h)
	h.suite = "voice_analysis"
	_voice_math(h)
	h.suite = "save_schema"
	_save_schema(h)
	h.suite = "level_catalog"
	_catalog(h)
	h.suite = "shot_command"
	_shot_command(h)


func _shot_math(h: TestHarness) -> void:
	h.check(ShotMath.is_valid_power(0.01), "small positive power valid")
	h.check(ShotMath.is_valid_power(1.0), "power 1.0 valid")
	h.check(not ShotMath.is_valid_power(0.0), "zero power invalid (never fires)")
	h.check(not ShotMath.is_valid_power(-0.2), "negative power invalid")
	h.check(not ShotMath.is_valid_power(1.2), "power above 1 invalid")
	h.check(not ShotMath.is_valid_power(NAN), "NaN power invalid")
	h.check_near(ShotMath.impulse_for_power(1.0), 10.0, 1e-6, "max impulse 10 N·s")
	h.check_near(ShotMath.impulse_for_power(0.0001), 1.5, 0.001, "min impulse ~1.5 N·s")
	h.check_eq(ShotMath.impulse_for_power(0.0), 0.0, "zero power yields zero impulse")
	var half := ShotMath.impulse_for_power(0.5)
	h.check_between(half, 1.5, 10.0, "mid power within impulse range")
	h.check_near(half, 1.5 + 8.5 * pow(0.5, 1.6), 1e-6, "curve matches 1.5+8.5·p^1.6")
	h.check(
		ShotMath.impulse_for_power(0.9) > ShotMath.impulse_for_power(0.5)
			and ShotMath.impulse_for_power(0.5) > ShotMath.impulse_for_power(0.2),
		"impulse monotonic in power"
	)
	var dir := ShotMath.horizontal_direction(Vector3(0.3, 5.0, -0.4))
	h.check_near(dir.y, 0.0, 1e-9, "direction is horizontal")
	h.check_near(dir.length(), 1.0, 1e-6, "direction normalized")
	h.check_eq(ShotMath.horizontal_direction(Vector3(0.0, 3.0, 0.0)), Vector3.ZERO, "vertical-only direction rejected")
	h.check_near(ShotMath.relative_power(-30.0, -40.0, -20.0), 0.5, 1e-6, "relative power midpoint")
	h.check_eq(ShotMath.relative_power(-30.0, -20.0, -40.0), -1.0, "invalid calibration sentinel")
	h.check_eq(ShotMath.relative_power(-50.0, -40.0, -20.0), 0.0, "below range clamps to 0")


func _scoring(h: TestHarness) -> void:
	h.check_eq(ScoringRules.stars_for_result(true, 2, 2, 12), 3, "par → 3 stars")
	h.check_eq(ScoringRules.stars_for_result(true, 3, 2, 12), 2, "par+1 → 2 stars")
	h.check_eq(ScoringRules.stars_for_result(true, 4, 2, 12), 1, "par+2 → 1 star")
	h.check_eq(ScoringRules.stars_for_result(true, 12, 5, 12), 1, "stroke-limit completion still earns 1 star")
	h.check_eq(ScoringRules.stars_for_result(true, 13, 5, 12), 0, "completion beyond limit earns nothing")
	h.check_eq(ScoringRules.stars_for_result(false, 2, 2, 12), 0, "failed attempt → 0 stars")
	h.check(ScoringRules.can_take_shot(11, 12), "11/12 may shoot")
	h.check(not ScoringRules.can_take_shot(12, 12), "12/12 may not shoot")
	h.check(not ScoringRules.attempt_finished(11, 12, false), "11 strokes unresolved keeps playing")
	h.check(ScoringRules.attempt_finished(12, 12, false), "12 strokes unresolved fails")
	h.check(not ScoringRules.attempt_finished(12, 12, true), "12 strokes completed succeeds")
	var merged := ScoringRules.merge_best({"best_strokes": 4, "best_stars": 2}, 3, 3)
	h.check_eq(merged["best_strokes"], 3, "better strokes kept")
	h.check_eq(merged["best_stars"], 3, "better stars kept")
	h.check(bool(merged["improved_strokes"]), "improvement flagged")
	var worse := ScoringRules.merge_best({"best_strokes": 2, "best_stars": 3}, 5, 1)
	h.check_eq(worse["best_strokes"], 2, "worse replay never worsens strokes")
	h.check_eq(worse["best_stars"], 3, "worse replay never worsens stars")
	h.check(not bool(worse["improved_strokes"]), "no false improvement")


func _progression(h: TestHarness) -> void:
	var ids: Array = ["CC01", "CC02", "CC03", "CC04", "CC05", "CC06", "PP01", "PP02", "PP03", "PP04", "PP05", "PP06"]
	var none: Dictionary = {}
	h.check(ProgressionRules.is_level_unlocked("CC01", ids, none), "first level unlocked")
	h.check(not ProgressionRules.is_level_unlocked("CC02", ids, none), "second level locked")
	h.check(not ProgressionRules.is_level_unlocked("PP01", ids, {"CC01": true}), "PP01 needs CC06 not stars")
	var through_cc: Dictionary = {"CC06": true}
	h.check(ProgressionRules.is_level_unlocked("PP01", ids, through_cc), "PP01 unlocks after CC06")
	h.check_eq(ProgressionRules.next_playable(ids, none, ""), "CC01", "fresh profile plays CC01")
	h.check_eq(ProgressionRules.next_playable(ids, {"CC01": true}, ""), "CC02", "resume next uncompleted")
	var all_done: Dictionary = {}
	for id: String in ids:
		all_done[id] = true
	h.check_eq(ProgressionRules.next_playable(ids, all_done, "CC03"), "CC03", "full completion resumes last played")
	h.check(ProgressionRules.is_cosmetic_unlocked("lion", none), "lion always unlocked")
	h.check(not ProgressionRules.is_cosmetic_unlocked("panda", {"CC01": true}), "panda locked before CC06")
	h.check(ProgressionRules.is_cosmetic_unlocked("panda", {"CC06": true}), "panda unlocks after CC06")
	h.check(ProgressionRules.is_cosmetic_unlocked("robot", {"PP06": true}), "robot unlocks after PP06")
	h.check(not ProgressionRules.is_cosmetic_unlocked("robot", {"CC06": true}), "robot still locked after CC06")
	h.check_eq(
		ProgressionRules.world_stars({"CC01": {"best_stars": 3}, "CC02": {"best_stars": 2}}, ["CC01", "CC02", "CC03"]),
		5,
		"world stars sum"
	)


func _voice_math(h: TestHarness) -> void:
	# Constant amplitude → analytic dBFS.
	var frames := PackedVector2Array()
	for i: int in 100:
		frames.append(Vector2(0.5, 0.5))
	h.check_near(VoiceAnalysis.window_dbfs(frames).dbfs, -6.0206, 0.001, "0.5 amplitude → -6.02 dBFS")
	# Opposite-phase stereo must not cancel (QA-008).
	var anti := PackedVector2Array()
	for i: int in 100:
		anti.append(Vector2(0.5, -0.5))
	h.check_near(VoiceAnalysis.window_dbfs(anti).dbfs, -6.0206, 0.001, "anti-phase channels do not cancel")
	# Silence clamps at the floor.
	var silence := PackedVector2Array()
	for i: int in 100:
		silence.append(Vector2.ZERO)
	h.check_near(VoiceAnalysis.window_dbfs(silence).dbfs, -120.0, 0.001, "silence clamps to -120")
	# Non-finite rejects the window.
	var broken := PackedVector2Array()
	broken.append(Vector2(NAN, 0.1))
	h.check(not VoiceAnalysis.window_dbfs(broken).valid, "NaN rejects window")
	# Clipping counted at >= 0.98.
	var clipped := PackedVector2Array()
	clipped.append(Vector2(0.99, 0.99))
	clipped.append(Vector2(0.1, 0.1))
	h.check_eq(VoiceAnalysis.window_dbfs(clipped).clip_count, 1, "clip counted once per window")
	# Frame-time-aware smoothing.
	h.check_near(VoiceAnalysis.smooth_power(0.0, 1.0, 100.0), 1.0, 0.001, "huge dt reaches target")
	var tiny := VoiceAnalysis.smooth_power(0.0, 1.0, 0.001)
	h.check_between(tiny, 0.0, 0.02, "tiny dt barely moves")
	h.check_near(VoiceAnalysis.smooth_power(0.5, 0.5, 0.016), 0.5, 1e-9, "equal values stable")
	h.check_eq(VoiceAnalysis.smooth_power(2.0, 0.0, 0.02), 1.0, "output clamped to [0,1]")
	# Percentile (nearest rank).
	h.check_near(VoiceAnalysis.percentile([1.0, 2.0, 3.0, 4.0], 0.75), 3.0, 1e-9, "p75 of 4 values")
	h.check_near(VoiceAnalysis.percentile([1.0, 2.0, 3.0, 4.0], 0.5), 2.0, 1e-9, "p50 nearest rank")
	h.check_near(VoiceAnalysis.percentile([], 0.75), 0.0, 1e-9, "empty percentile safe")
	# Calibration derivation.
	var good := VoiceAnalysis.derive_calibration(-60.0, -46.0, -30.0, 0.0, 1.0, 1.0)
	h.check(good.valid, "valid calibration accepted")
	h.check_near(good.gate_db, -56.0, 1e-6, "gate = noise + 4")
	h.check_near(good.lower_db, -49.0, 1e-6, "lower = max(noise+6, soft-3)")
	h.check_near(good.upper_db, -30.0, 1e-6, "upper = strong")
	h.check_eq(VoiceAnalysis.calibration_error(-60.0, -56.0, -30.0, 0.0, 1.0, 1.0), "soft_too_quiet", "soft too quiet")
	h.check_eq(VoiceAnalysis.calibration_error(-60.0, -46.0, -42.0, 0.0, 1.0, 1.0), "range_too_small", "range too small")
	h.check_eq(VoiceAnalysis.calibration_error(-60.0, -46.0, -30.0, 0.2, 1.0, 1.0), "clipping", "excess clipping")
	h.check_eq(VoiceAnalysis.calibration_error(-60.0, -46.0, -30.0, 0.0, 0.1, 1.0), "insufficient_data", "not enough soft data")
	# Preview selection: p75 of qualified smoothed windows in last 250 ms.
	var ring: Array = []
	for i: int in 10:
		ring.append(VoiceAnalysis.VoiceWindow.new(i * 20, -30.0, 0.6, 0.6, true))
	var preview := VoiceAnalysis.preview_power(ring, 200)
	h.check(bool(preview["valid"]), "qualified ring produces preview")
	h.check_near(float(preview["power"]), 0.6, 1e-6, "preview equals converged smooth")
	var stale := VoiceAnalysis.preview_power(ring, 5000)
	h.check(not bool(stale["valid"]), "stale windows expire")
	var short_ring: Array = [VoiceAnalysis.VoiceWindow.new(0, -30.0, 0.5, 0.5, true)]
	h.check(not bool(VoiceAnalysis.preview_power(short_ring, 100)["valid"]), "below 150 ms no preview")
	h.check_near(VoiceAnalysis.recent_qualified_duration(ring, 200), 0.2, 1e-6, "qualified duration sums windows")


func _save_schema(h: TestHarness) -> void:
	var ids: Array = ["CC01", "CC02", "PP06"]
	var good := {
		"schema_version": 1,
		"content_version": "mvp-1",
		"best_results": {"CC01": {"best_strokes": 2, "best_stars": 3}},
		"completed_levels": ["CC01"],
		"equipped_cosmetic": "lion",
		"last_played_level": "CC02",
		"applied_completion_ids": ["s:CC01:1"],
	}
	var ok := SaveSchema.validate_progress(good, ids)
	h.check(ok.valid, "handoff example progress validates")
	h.check_eq(ok.value["best_results"]["CC01"]["best_strokes"], 2, "bests preserved")
	var future := SaveSchema.validate_progress({"schema_version": 2}, ids)
	h.check(not future.valid, "future schema version rejected")
	h.check(future.errors.has("unsupported_schema_version"), "unsupported version error code")
	var truncated := SaveSchema.parse_object('{"schema_version": 1,')
	h.check(not truncated["ok"], "truncated JSON fails parse")
	var unearned := good.duplicate(true)
	unearned["equipped_cosmetic"] = "robot"
	var fallen_back := SaveSchema.validate_progress(unearned, ids)
	h.check(fallen_back.valid, "unearned cosmetic does not reject save")
	h.check_eq(fallen_back.value["equipped_cosmetic"], "lion", "unearned cosmetic falls back to lion")
	var bad_stars := good.duplicate(true)
	bad_stars["best_results"]["CC01"] = {"best_strokes": 1, "best_stars": 5}
	h.check(not SaveSchema.validate_progress(bad_stars, ids).valid, "stars outside 1..3 rejected")
	var unknown := good.duplicate(true)
	unknown["completed_levels"] = ["XX99"]
	h.check(not SaveSchema.validate_progress(unknown, ids).valid, "unknown level id rejected")
	# Settings.
	var defaults := SaveSchema.validate_settings({"schema_version": 1})
	h.check(defaults.valid, "minimal settings validate")
	h.check_eq(defaults.value["input_mode"], "touch", "default input mode is touch")
	var with_cal := {
		"schema_version": 1,
		"input_mode": "voice",
		"music_volume": 0.5,
		"effects_volume": 0.5,
		"haptics": false,
		"reduced_motion": true,
		"quality": "high",
		"calibration": {
			"algorithm_version": "amplitude_v1",
			"gate_db": -56.0,
			"lower_db": -49.0,
			"upper_db": -30.0,
			"route_category": "built_in",
		},
	}
	var settings_ok := SaveSchema.validate_settings(with_cal)
	h.check(settings_ok.valid, "full settings validate")
	h.check_eq(settings_ok.value["calibration"]["upper_db"], -30.0, "calibration numbers kept")
	var loud := with_cal.duplicate(true)
	loud["music_volume"] = 2.0
	h.check(not SaveSchema.validate_settings(loud).valid, "volume out of range rejected")
	var pcm := with_cal.duplicate(true)
	pcm["calibration"]["waveform"] = [0.1, 0.2, 0.3]
	var stripped := SaveSchema.validate_settings(pcm)
	h.check(stripped.valid, "unknown calibration keys dropped")
	h.check(not (stripped.value["calibration"] as Dictionary).has("waveform"), "PCM-like payload never stored")


func _catalog(h: TestHarness) -> void:
	var packaged := LevelCatalog.load_packaged()
	h.check(packaged.valid, "packaged catalog validates")
	h.check_eq(packaged.levels.size(), 12, "twelve levels")
	h.check_eq(packaged.ordered_ids[0], "CC01", "first level CC01")
	h.check_eq(packaged.ordered_ids[6], "PP01", "world two starts at index 6")
	h.check(packaged.is_playable("CC01"), "CC01 graybox playable (scene exists)")
	h.check(not packaged.is_playable("PP01"), "design_only level not playable")
	var cc01 := packaged.level_by_id("CC01")
	h.check_eq(cc01["par"], 2, "CC01 par 2")
	var broken := {
		"schema_version": 1,
		"content_version": "x",
		"worlds": packaged.worlds.duplicate(true),
		"levels": [packaged.levels[0].duplicate(true)],
	}
	h.check(not LevelCatalog.validate(broken).valid, "one level fails six-per-world rule")
	var dup := broken.duplicate(true)
	var levels: Array = []
	for level: Dictionary in packaged.levels:
		levels.append(level.duplicate(true))
	levels[1] = levels[0].duplicate(true)
	levels[1]["id"] = "CC01"
	dup["levels"] = levels
	h.check(not LevelCatalog.validate(dup).valid, "duplicate id rejected")
	var bad_par := broken.duplicate(true)
	bad_par["levels"] = [packaged.levels[0].duplicate(true)]
	bad_par["levels"][0]["max_strokes"] = 3  # par 2 → needs >= 4
	bad_par["levels"][0]["par"] = 2
	h.check(not LevelCatalog.validate(bad_par).valid, "max_strokes < par+2 rejected")


func _shot_command(h: TestHarness) -> void:
	var good := ShotCommand.new(1, 1, ShotCommand.Source.TOUCH, 0.5, Vector3(0, 0, -1), "CC01", "mvp-1")
	h.check(good.is_valid(), "well-formed command valid")
	var zero_power := ShotCommand.new(1, 2, ShotCommand.Source.VOICE, 0.0, Vector3(0, 0, -1), "CC01", "mvp-1")
	h.check(not zero_power.is_valid(), "zero power command invalid")
	var no_dir := ShotCommand.new(1, 3, ShotCommand.Source.TOUCH, 0.5, Vector3.ZERO, "CC01", "mvp-1")
	h.check(not no_dir.is_valid(), "directionless command invalid")
