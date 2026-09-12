extends Node
## Deterministic hole replay + evidence harness (M5, hardened per review
## round 4).
##
## Replays a FIXED shot script on a hole through the real game scene, saving
## screenshots at defined beats and printing frame-time statistics. Required
## beats (reach READY, accepted shots, state transitions, captures) accumulate
## failures and the process exits NONZERO when any fail — the harness is a
## gate, not a narrator. Frame statistics sample one monotonic timestamp per
## RENDERED frame (a _process ticker), never per physics tick; headless runs
## report simulation statistics only and skip captures.
##
## Usage (display required for screenshots; headless runs print stats only):
##   LEVEL_ID=CC04 godot --path . --resolution 390x844 res://tools/replay_hole.tscn
##   ROAR3D_REPLAY_OUT=/tmp/dir  override screenshot output directory

const SETTLE_FRAMES_MAX := 600
const READY_FRAMES_MAX := 300

var _failures := 0
var _frame_ticker: _FrameTicker


func _ready() -> void:
	await _run()


func _run() -> void:
	var level_id := OS.get_environment("LEVEL_ID")
	if level_id.is_empty():
		level_id = "CC04"
	var out_dir := OS.get_environment("ROAR3D_REPLAY_OUT")
	if out_dir.is_empty():
		out_dir = "/tmp/roar3d_replay"
	DirAccess.make_dir_recursive_absolute(out_dir)
	# One monotonic sample per RENDERED frame. Physics awaits can run at a
	# different cadence than rendering, so frame stats must not be sampled
	# from physics loops (review round 4).
	_frame_ticker = _FrameTicker.new()
	add_child(_frame_ticker)

	AppRouter.current_level_id = level_id
	SettingsStore.set_input_mode("touch")
	var packed: PackedScene = load("res://scenes/game/game_root.tscn")
	if packed == null:
		printerr("game_root scene failed to load")
		get_tree().quit(1)
		return
	var root: GameRoot = packed.instantiate()
	add_child(root)
	# Deterministic voice source (the replay drives touch shots; the source
	# just keeps the pipeline identical to a real session).
	var source := VoiceFrameSource.SyntheticFrameSource.new()
	source.rate = 48000
	root.voice._source = source
	root.voice._is_real_mic = false
	if not OS.get_environment("ROAR3D_DEBUG_LIGHT").is_empty():
		await get_tree().process_frame
		for light in root.find_children("*", "DirectionalLight3D", true, false):
			(light as DirectionalLight3D).light_energy = 1.6

	var session := root.session

	# --- Beat 1: ready framing at spawn (REQUIRED) ---
	var ok := await _await_ready(session)
	_record("reach READY", ok)
	await _beat_capture(root, out_dir + "/1_ready.png")

	# --- Beat 2: approach putt toward the ramp ---
	_require_shot(session.request_touch_shot(0.45), "approach putt accepted")
	await _await_rolling(session)
	await _sim_frames(30)
	await _beat_capture(root, out_dir + "/2_midroll.png")
	await _await_resolved(session)

	# --- Beat 3: roar shot over the ramp (loft + launch feel) ---
	if session.fsm.state == GameStateMachine.State.READY:
		_require_shot(session.request_touch_shot(0.9), "roar shot accepted")
		await _await_rolling(session)
		await _sim_frames(20)
		await _beat_capture(root, out_dir + "/3_roar_airborne.png")
	await _await_resolved(session)

	# --- Beat 4: roll onto the green toward the cup ---
	if session.fsm.state == GameStateMachine.State.READY:
		_require_shot(session.request_touch_shot(0.3), "green roll accepted")
		await _await_rolling(session)
		await _sim_frames(25)
		await _beat_capture(root, out_dir + "/4_green.png")
	await _await_resolved(session)

	# --- Beat 5: settle state at end of script ---
	await _sim_frames(20)
	await _beat_capture(root, out_dir + "/5_end.png")

	_frame_ticker.report(level_id)
	print("REPLAY DONE strokes=%d state=%s failures=%d" % [session.strokes, session.fsm.state, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _record(what: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("REPLAY BEAT %s ok=%s" % [what, str(ok)])


func _require_shot(accepted: bool, what: String) -> void:
	if not accepted:
		_failures += 1
	print("REPLAY SHOT %s accepted=%s" % [what, str(accepted)])


func _await_ready(session: GameSessionController) -> bool:
	for i: int in READY_FRAMES_MAX:
		if session.fsm.state == GameStateMachine.State.READY:
			return true
		await get_tree().physics_frame
	return session.fsm.state == GameStateMachine.State.READY


func _await_rolling(session: GameSessionController) -> void:
	for i: int in 20:
		if session.fsm.state == GameStateMachine.State.ROLLING:
			return
		await get_tree().physics_frame


func _await_resolved(session: GameSessionController) -> void:
	for i: int in SETTLE_FRAMES_MAX:
		if session.fsm.state in [GameStateMachine.State.READY, GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED]:
			return
		await get_tree().physics_frame
	# Timed out without resolving: a required transition failed.
	_failures += 1
	print("REPLAY TIMEOUT waiting for shot resolution (state=%s)" % session.fsm.state)


func _sim_frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _beat_capture(root: GameRoot, path: String) -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		return  # no rendering target: stats-only run (CI)
	var image := get_viewport().get_texture().get_image()
	if image == null:
		_failures += 1
		print("REPLAY CAPTURE FAILED (null image): " + path)
		return
	var err := image.save_png(path)
	if err != Error.OK:
		_failures += 1
		print("REPLAY CAPTURE FAILED (%s): %s" % [error_string(err), path])
		return
	print("capture: " + path)


class _FrameTicker:
	extends Node
	## Samples one monotonic timestamp per main-loop iteration (this node's
	## _process). Report labels the clock honestly: on a display these are
	## rendered frames; headless has no renderer, so they are process ticks.
	## Physics awaits are NEVER sampled (review round 4: different cadence).
	## Caveat: an occluded/idle desktop throttles rendering — treat rendered
	## stats as reference only from an attended session.
	var _last_usec := -1
	var _intervals: PackedFloat64Array = []

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		if _last_usec > 0:
			_intervals.append(float(now - _last_usec) / 1000.0)
		_last_usec = now

	func report(level_id: String) -> void:
		if _intervals.is_empty():
			print("FRAMESTATS level=%s frames=0 (no samples)" % level_id)
			return
		var sorted := _intervals.duplicate()
		sorted.sort()
		var p95 := sorted[int(sorted.size() * 0.95)]
		var avg := 0.0
		for t in _intervals:
			avg += t
		avg /= _intervals.size()
		var clock := "rendered" if DisplayServer.get_name() != "headless" else "headless-process"
		print("FRAMESTATS level=%s clock=%s frames=%d avg_ms=%.2f p95_ms=%.2f max_ms=%.2f (monotonic per-%s-frame)" % [
			level_id, clock, _intervals.size(), avg, p95, sorted[sorted.size() - 1], clock])
