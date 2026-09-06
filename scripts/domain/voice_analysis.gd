class_name VoiceAnalysis
extends RefCounted
## Pure voice math per docs/04_VOICE_INPUT_SPEC.md §3–§5. Relative digital
## amplitude only — never presented as real-world dB SPL, never persisted as
## audio. All constants are proposal defaults; the service owns timing state.

const DBFS_MIN := -120.0
const DBFS_MAX := 0.0
const CLIP_THRESHOLD := 0.98
const SMOOTH_TIME_CONSTANT_SEC := 0.08
const PREVIEW_WINDOW_MS := 250
const PREVIEW_MIN_QUALIFIED_MS := 150
const PREVIEW_PERCENTILE := 0.75
const MIN_QUALIFIED_DURATION_SEC := 0.15


class WindowAnalysis extends RefCounted:
	var dbfs := DBFS_MIN
	var clip_count := 0
	var valid := true  ## false when any sample is non-finite; window is rejected


## Window RMS across stereo frames. Energy is (l^2 + r^2) / 2 per frame so
## opposite-phase channels cannot cancel (QA-008); squaring happens before
## any averaging across channels.
static func window_dbfs(frames: PackedVector2Array) -> WindowAnalysis:
	var out := WindowAnalysis.new()
	if frames.is_empty():
		out.valid = false
		return out
	var energy := 0.0
	for frame: Vector2 in frames:
		if not is_finite(frame.x) or not is_finite(frame.y):
			out.valid = false
			return out
		energy += (frame.x * frame.x + frame.y * frame.y) * 0.5
		if absf(frame.x) >= CLIP_THRESHOLD or absf(frame.y) >= CLIP_THRESHOLD:
			out.clip_count += 1
	var rms := sqrt(energy / float(frames.size()))
	out.dbfs = clampf(20.0 * log(maxf(rms, 0.000001)) / log(10.0), DBFS_MIN, DBFS_MAX)
	return out


## Frame-time-aware exponential smoothing. A long frame must not make the
## control radically slower or faster than many short frames (QA-010).
static func smooth_power(previous: float, target: float, dt: float) -> float:
	if not is_finite(previous) or not is_finite(target) or not is_finite(dt):
		return clampf(previous, 0.0, 1.0)
	var alpha := 1.0 - exp(-maxf(dt, 0.0) / SMOOTH_TIME_CONSTANT_SEC)
	return clampf(previous + alpha * (target - previous), 0.0, 1.0)


## Nearest-rank percentile over a copy (input order untouched).
static func percentile(values: Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted_values: Array = values.duplicate()
	sorted_values.sort()
	var rank := int(ceil(clampf(fraction, 0.0, 1.0) * float(sorted_values.size())))
	var index: int = clampi(rank - 1, 0, sorted_values.size() - 1)
	return float(sorted_values[index])


class CalibrationProfile extends RefCounted:
	var valid := false
	var gate_db := 0.0
	var lower_db := 0.0
	var upper_db := 0.0
	var error_code := ""


## gate = noise + 4; lower = max(noise + 6, soft - 3); upper = strong.
## Quality gates: soft >= noise + 6, strong >= soft + 8, clip fraction <= 5%,
## >= 0.3 s qualified data for both soft and strong stages.
static func derive_calibration(
	noise_db: float,
	soft_db: float,
	strong_db: float,
	clip_fraction: float = 0.0,
	soft_qualified_sec: float = 1.0,
	strong_qualified_sec: float = 1.0,
) -> CalibrationProfile:
	var profile := CalibrationProfile.new()
	var error := calibration_error(
		noise_db, soft_db, strong_db, clip_fraction, soft_qualified_sec, strong_qualified_sec
	)
	if not error.is_empty():
		profile.error_code = error
		return profile
	profile.gate_db = noise_db + 4.0
	profile.lower_db = maxf(noise_db + 6.0, soft_db - 3.0)
	profile.upper_db = strong_db
	# lower must stay strictly below upper for relative_power to be usable.
	if profile.upper_db <= profile.lower_db + 1.0:
		profile.error_code = "range_too_small"
		return profile
	profile.valid = true
	return profile


static func calibration_error(
	noise_db: float,
	soft_db: float,
	strong_db: float,
	clip_fraction: float,
	soft_qualified_sec: float,
	strong_qualified_sec: float
) -> String:
	for value: float in [noise_db, soft_db, strong_db]:
		if not is_finite(value):
			return "invalid_signal"
	if soft_db < noise_db + 6.0:
		return "soft_too_quiet"
	if strong_db < soft_db + 8.0:
		return "range_too_small"
	if clip_fraction > 0.05:
		return "clipping"
	if soft_qualified_sec < 0.3 or strong_qualified_sec < 0.3:
		return "insufficient_data"
	return ""


## One analysis window as kept in the service's bounded ring. `smooth` is the
## smoothed relative power after this window was folded in; `qualified` means
## the window cleared the noise gate for the required duration.
class VoiceWindow extends RefCounted:
	var t_msec := 0
	var dbfs := DBFS_MIN
	var raw_power := 0.0
	var smooth_power_value := 0.0
	var qualified := false

	func _init(p_t_msec: int = 0, p_dbfs: float = DBFS_MIN, p_raw: float = 0.0, p_smooth: float = 0.0, p_qualified: bool = false) -> void:
		t_msec = p_t_msec
		dbfs = p_dbfs
		raw_power = p_raw
		smooth_power_value = p_smooth
		qualified = p_qualified


## Shot power preview: 75th percentile of qualified smoothed windows in the
## most recent 250 ms, requiring >= 150 ms of qualified windows and a value
## above zero. Qualified samples age out so an old maximum never lingers.
static func preview_power(ring: Array, now_msec: int) -> Dictionary:
	var recent: Array = []
	var qualified_ms := 0
	const WINDOW_MS := 20
	for item in ring:
		var window: VoiceWindow = item as VoiceWindow
		if window == null or not window.qualified:
			continue
		if now_msec - window.t_msec > PREVIEW_WINDOW_MS:
			continue
		recent.append(window.smooth_power_value)
		qualified_ms += WINDOW_MS
	if qualified_ms < PREVIEW_MIN_QUALIFIED_MS:
		return {"valid": false, "power": 0.0, "qualified_ms": qualified_ms}
	var power := percentile(recent, PREVIEW_PERCENTILE)
	if power <= 0.0:
		return {"valid": false, "power": 0.0, "qualified_ms": qualified_ms}
	return {"valid": true, "power": power, "qualified_ms": qualified_ms}


## Total qualified coverage in the recent window, used by the minimum
## qualified-duration gate that rejects a phone tap or single clap (QA-006).
static func recent_qualified_duration(ring: Array, now_msec: int) -> float:
	var qualified_ms := 0
	const WINDOW_MS := 20
	for item in ring:
		var window: VoiceWindow = item as VoiceWindow
		if window != null and window.qualified and now_msec - window.t_msec <= PREVIEW_WINDOW_MS:
			qualified_ms += WINDOW_MS
	return float(qualified_ms) / 1000.0
