extends Node
## Deterministic hole replay + evidence harness (M5).
##
## Replays a FIXED shot script on a hole through the real game scene, saving
## screenshots at defined beats and printing frame-time statistics. The script
## drives the same guarded session APIs a player's inputs produce, so the
## sequence is reproducible on any machine with the same engine build — a
## device tester can compare their capture against desktop reference frames.
##
## Usage (display required for screenshots; headless runs print stats only):
##   LEVEL_ID=CC04 godot --path . --resolution 390x844 res://tools/replay_hole.tscn
##   ROAR3D_REPLAY_OUT=/tmp/dir  override screenshot output directory
## Headless-safe: without a rendering target the PNG saves are skipped.

const SETTLE_FRAMES_MAX := 600
const READY_FRAMES_MAX := 300


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

	var frames := _FrameStats.new()
	var session := root.session

	# --- Beat 1: ready framing at spawn ---
	var ok := false
	for i: int in READY_FRAMES_MAX:
		frames.tick(get_process_delta_time())
		await get_tree().physics_frame
		if session.fsm.state == GameStateMachine.State.READY:
			ok = true
			break
	_record("reach READY", ok, frames)
	await _beat_capture(root, out_dir + "/1_ready.png")

	# --- Beat 2: approach putt toward the ramp ---
	session.request_touch_shot(0.45)
	await _await_rolling(session, frames)
	await _frames(root, frames, 30)
	await _beat_capture(root, out_dir + "/2_midroll.png")
	await _await_resolved(session, frames)

	# --- Beat 3: roar shot over the ramp (loft + launch feel) ---
	if session.fsm.state == GameStateMachine.State.READY:
		session.request_touch_shot(0.9, 0.28)
		await _await_rolling(session, frames)
		await _frames(root, frames, 20)
		await _beat_capture(root, out_dir + "/3_roar_airborne.png")
	await _await_resolved(session, frames)

	# --- Beat 4: roll onto the green toward the cup ---
	if session.fsm.state == GameStateMachine.State.READY:
		session.request_touch_shot(0.3)
		await _await_rolling(session, frames)
		await _frames(root, frames, 25)
		await _beat_capture(root, out_dir + "/4_green.png")
	await _await_resolved(session, frames)

	# --- Beat 5: settle state at end of script ---
	await _frames(root, frames, 20)
	await _beat_capture(root, out_dir + "/5_end.png")

	frames.report(level_id)
	print("REPLAY DONE strokes=%d state=%s" % [session.strokes, session.fsm.state])
	get_tree().quit(0)


func _await_rolling(session: GameSessionController, frames: _FrameStats) -> void:
	for i: int in 20:
		frames.tick(get_process_delta_time())
		await get_tree().physics_frame
		if session.fsm.state == GameStateMachine.State.ROLLING:
			return


func _await_resolved(session: GameSessionController, frames: _FrameStats) -> void:
	for i: int in SETTLE_FRAMES_MAX:
		frames.tick(get_process_delta_time())
		await get_tree().physics_frame
		if session.fsm.state in [GameStateMachine.State.READY, GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED]:
			return


func _frames(root: GameRoot, frames: _FrameStats, count: int) -> void:
	for i: int in count:
		frames.tick(get_process_delta_time())
		await get_tree().physics_frame


func _beat_capture(root: GameRoot, path: String) -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		return  # no rendering target: stats-only run (CI)
	var image := get_viewport().get_texture().get_image()
	if image != null:
		image.save_png(path)
		print("capture: " + path)


func _record(what: String, ok: bool, frames: _FrameStats) -> void:
	print("REPLAY BEAT %s ok=%s after %.2fs sim" % [what, str(ok), frames.sim_seconds()])


class _FrameStats:
	## Frame-time statistics over the whole replay: p95/max expose spikes
	## that an FPS average hides — the same metric the device gate uses.
	var _times: PackedFloat64Array = []

	func tick(delta: float) -> void:
		_times.append(delta * 1000.0)

	func sim_seconds() -> float:
		var total := 0.0
		for t in _times:
			total += t
		return total / 1000.0

	func report(level_id: String) -> void:
		if _times.is_empty():
			return
		var sorted := _times.duplicate()
		sorted.sort()
		var p95 := sorted[int(sorted.size() * 0.95)]
		var avg := 0.0
		for t in _times:
			avg += t
		avg /= _times.size()
		print("FRAMESTATS level=%s frames=%d avg_ms=%.2f p95_ms=%.2f max_ms=%.2f" % [
			level_id, _times.size(), avg, p95, sorted[sorted.size() - 1]])
