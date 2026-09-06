class_name VoiceInputService
extends Node
## Bounded voice capture (RB-020/RB-022). Owns the frame source, capture
## tokens, the ring of recent analysis windows, and the published Shot power
## preview. Never plays mic audio to the speakers (the MicCapture bus chain
## routes into a muted sink), never persists PCM, and only the preview value
## from the active token can become a shot (docs/04_VOICE_INPUT_SPEC.md).

signal status_updated(status: Dictionary)  # VoiceStatus contract, §6

const WARMUP_DISCARD_MS := 100
const WINDOW_MS := 20
const RING_CAPACITY_MS := 500  # bounded: only what the algorithm needs
const MAX_HOLD_MS := 3000
const NO_FRESH_TIMEOUT_MS := 500
const GATE_FALLBACK_DB := -60.0

enum Phase { IDLE, STARTING, LISTENING }

var calibration: Dictionary = {}  # {gate_db, lower_db, upper_db, algorithm_version, route_category}

var _source: VoiceFrameSource = null
var _is_real_mic := false
var _phase: int = Phase.IDLE
var _capture_token := -1
var _token_seq := 0
var _ring: Array = []  # VoiceWindow, bounded to RING_CAPACITY_MS/WINDOW_MS
var _ring_cursor := 0
var _hold_started_msec := 0
var _last_fresh_msec := 0
var _smoothed := 0.0
var _warmup_frames_discarded := 0
var _preview := {"valid": false, "power": 0.0, "qualified_ms": 0}
var _last_status := {}


func _init(p_source: VoiceFrameSource = null, p_real_mic := false) -> void:
	if p_source != null:
		_source = p_source
		_is_real_mic = p_real_mic


func _ready() -> void:
	if _source == null:
		# Real device default; tests inject a synthetic source before add_child.
		_source = VoiceFrameSource.MicFrameSource.create(self)
		_is_real_mic = true
		_ensure_mic_bus_chain()


## Build MicCapture (measured, first effect) -> MicSilence (muted sink) so the
## microphone is never monitored through Master (docs/04 §2).
func _ensure_mic_bus_chain() -> void:
	for bus_name: String in ["MicCapture", "MicSilence"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var bus := AudioServer.bus_count - 1
			AudioServer.set_bus_name(bus, bus_name)
			AudioServer.set_bus_send(bus, "MicSilence" if bus_name == "MicCapture" else "Master")
	if AudioServer.get_bus_index("MicCapture") >= 0:
		AudioServer.set_bus_mute(AudioServer.get_bus_index("MicSilence"), true)


func is_listening() -> bool:
	return _phase != Phase.IDLE


func current_token() -> int:
	return _capture_token


func phase_name() -> String:
	return Phase.keys()[_phase]


func published_preview() -> Dictionary:
	return _preview.duplicate()


## Begin a capture hold. Fails without side effects when permission is
## missing (QA-001/QA-003) or the source cannot start.
func begin_capture() -> bool:
	if _phase != Phase.IDLE:
		return false
	if _is_real_mic and not PlatformAdapter.has_microphone_permission():
		_publish_status("permission_denied")
		return false
	_token_seq += 1
	_capture_token = _token_seq
	_ring.clear()
	_smoothed = 0.0
	_warmup_frames_discarded = 0
	_preview = {"valid": false, "power": 0.0, "qualified_ms": 0}
	_source.clear_buffer()
	if not _source.start():
		_capture_token = -1
		_publish_status("no_input")
		return false
	_phase = Phase.STARTING
	var now := Time.get_ticks_msec()
	_hold_started_msec = now
	_last_fresh_msec = now
	AudioDirector.duck_for_capture(true)
	_publish_status("")
	return true


## Close capture unconditionally: stop playback, stop processing, clear the
## ring and level history, invalidate the token, restore audio. Called on
## release, cancel, pause, background, and route change (docs/04 §2).
func end_capture() -> void:
	if _phase == Phase.IDLE:
		return
	_phase = Phase.IDLE
	_source.stop()
	_source.clear_buffer()
	_ring.clear()
	_preview = {"valid": false, "power": 0.0, "qualified_ms": 0}
	_capture_token = -1
	AudioDirector.duck_for_capture(false)
	_publish_status("")


func _process(_delta: float) -> void:
	if _phase == Phase.IDLE:
		return
	var now := Time.get_ticks_msec()
	if now - _hold_started_msec > MAX_HOLD_MS:
		end_capture()
		_publish_status("timeout")
		return
	var frames := _source.pull_frames()
	if frames.is_empty():
		if now - _last_fresh_msec > NO_FRESH_TIMEOUT_MS:
			end_capture()
			_publish_status("no_input")
		return
	_last_fresh_msec = now
	if _phase == Phase.STARTING:
		_phase = Phase.LISTENING
		_publish_status("")
	_ingest_frames(frames, now)


func _ingest_frames(frames: PackedVector2Array, now_msec: int) -> void:
	var rate := _source.sample_rate()
	if rate <= 0:
		return
	var frames_per_window: int = maxi(1, int(round(float(rate) * WINDOW_MS / 1000.0)))
	for start: int in range(0, frames.size(), frames_per_window):
		var end: int = mini(start + frames_per_window, frames.size())
		var window_frames := PackedVector2Array()
		for i: int in range(start, end):
			window_frames.append(frames[i])
		if _warmup_frames_discarded < int(round(float(rate) * WARMUP_DISCARD_MS / 1000.0)):
			_warmup_frames_discarded += window_frames.size()
			continue
		_analyze_window(window_frames, now_msec)
	if _source.frames_discarded() > 0:
		# Overrun invalidates the current shot rather than passing stale audio
		# off as current (docs/04 §3).
		end_capture()
		_publish_status("buffer_overrun")
		return
	_preview = VoiceAnalysis.preview_power(_ring, now_msec)
	_publish_status("")


func _analyze_window(window_frames: PackedVector2Array, now_msec: int) -> void:
	var analysis := VoiceAnalysis.window_dbfs(window_frames)
	if not analysis.valid:
		return
	var gate := GATE_FALLBACK_DB
	var lower := 0.0
	var upper := 0.0
	var have_calibration := calibration.has("lower_db") and calibration.has("upper_db") and calibration.has("gate_db")
	if have_calibration:
		gate = float(calibration["gate_db"])
		lower = float(calibration["lower_db"])
		upper = float(calibration["upper_db"])
	var qualified := analysis.dbfs > gate
	var raw := 0.0
	if qualified and have_calibration:
		var mapped := ShotMath.relative_power(analysis.dbfs, lower, upper)
		raw = 0.0 if mapped < 0.0 else mapped
	_smoothed = VoiceAnalysis.smooth_power(_smoothed, raw, float(WINDOW_MS) / 1000.0)
	_calibration_window_hook(analysis, window_frames.size(), qualified)
	var window := VoiceAnalysis.VoiceWindow.new(now_msec, analysis.dbfs, raw, _smoothed, qualified)
	_ring.append(window)
	while _ring.size() > RING_CAPACITY_MS / WINDOW_MS:
		_ring.pop_front()


## Qualified duration inside the recent window; below ~150 ms a clap cannot
## become a shot (QA-006).
func qualified_hold_duration() -> float:
	return VoiceAnalysis.recent_qualified_duration(_ring, Time.get_ticks_msec())


## Consume the preview for a shot release. Returns {token, power} only when
## the preview is valid, from the still-active token, with enough qualified
## duration. One call closes capture; the caller can only use the returned
## value (a second release finds IDLE and gets nothing).
func release_capture_for_shot() -> Dictionary:
	if _phase != Phase.LISTENING:
		end_capture()
		return {"valid": false, "error": "not_listening"}
	var token := _capture_token
	var preview := _preview
	var qualified := VoiceAnalysis.recent_qualified_duration(_ring, Time.get_ticks_msec())
	end_capture()
	if not preview["valid"] or float(preview["power"]) <= 0.0:
		return {"valid": false, "error": "no_signal"}
	if qualified < VoiceAnalysis.MIN_QUALIFIED_DURATION_SEC:
		return {"valid": false, "error": "too_short"}
	return {"valid": true, "token": token, "power": float(preview["power"])}


func _publish_status(error_code: String) -> void:
	var status := {
		"capture_id": _capture_token,
		"phase": Phase.keys()[_phase],
		"relative_live_level": _smoothed,
		"preview_power": float(_preview["power"]) if _preview["valid"] else 0.0,
		"signal_valid": bool(_preview["valid"]),
		"error_code": error_code,
	}
	if status != _last_status:
		_last_status = status
		status_updated.emit(status)


## --- Calibration recording (stages driven by the calibration UI, RB-021) ---
## Collects qualified window dBFS medians per stage using the same window
## pipeline. Only the resulting numbers are stored, never samples.

var _cal_stage := ""
var _cal_windows_db: Array[float] = []
var _cal_clip_frames := 0
var _cal_total_frames := 0
var _cal_qualified_sec := 0.0


func begin_calibration_stage(stage_name: String) -> bool:
	if stage_name not in ["room", "soft", "strong"]:
		return false
	if _phase != Phase.IDLE:
		end_capture()
	if not begin_capture():
		return false
	_cal_stage = stage_name
	_cal_windows_db.clear()
	_cal_clip_frames = 0
	_cal_total_frames = 0
	_cal_qualified_sec = 0.0
	return true


## Patch: while a calibration stage runs, record window levels too.
func _calibration_window_hook(analysis: VoiceAnalysis.WindowAnalysis, frame_count: int, qualified: bool) -> void:
	if _cal_stage.is_empty():
		return
	_cal_windows_db.append(analysis.dbfs)
	_cal_total_frames += frame_count
	if analysis.clip_count > 0:
		_cal_clip_frames += analysis.clip_count
	if qualified:
		_cal_qualified_sec += float(WINDOW_MS) / 1000.0


func finish_calibration_stage() -> Dictionary:
	var stage := _cal_stage
	end_capture()
	_cal_stage = ""
	var summary := {
		"stage": stage,
		"level_db": VoiceAnalysis.percentile(_cal_windows_db.duplicate(), 0.5) if not _cal_windows_db.is_empty() else -999.0,
		"noise_level_db": VoiceAnalysis.percentile(_cal_windows_db.duplicate(), 0.9) if not _cal_windows_db.is_empty() else -999.0,
		"clip_fraction": float(_cal_clip_frames) / float(maxi(_cal_total_frames, 1)),
		"qualified_sec": _cal_qualified_sec,
	}
	return summary


## Derive and store calibration from the three stage summaries. Returns the
## VoiceAnalysis.CalibrationProfile; on success the numbers go to
## SettingsStore (which persists only these numbers).
func apply_calibration(room: Dictionary, soft: Dictionary, strong: Dictionary) -> Dictionary:
	var profile := VoiceAnalysis.derive_calibration(
		float(room["noise_level_db"]),
		float(soft["level_db"]),
		float(strong["level_db"]),
		maxf(maxf(float(room["clip_fraction"]), float(soft["clip_fraction"])), float(strong["clip_fraction"])),
		float(soft["qualified_sec"]),
		float(strong["qualified_sec"])
	)
	if profile.valid:
		calibration = {
			"algorithm_version": "amplitude_v1",
			"gate_db": profile.gate_db,
			"lower_db": profile.lower_db,
			"upper_db": profile.upper_db,
			"route_category": PlatformAdapter.route_category(),
		}
	return {
		"valid": profile.valid,
		"error_code": profile.error_code,
		"calibration": calibration.duplicate() if profile.valid else {},
	}
