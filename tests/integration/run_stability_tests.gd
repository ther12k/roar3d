extends Node
## Stability stress suite (RB-054): automated QA-016 (thirty capture
## start/stop cycles), QA-013-style pause-interrupt cycles, and QA-045
## (thirty level enter/exit cycles). Proves no duplicate capture owner, no
## lingering listening state, no node/memory leak drift, and no stroke leaks
## across repeated cycles. Run:
## godot --headless --path . res://tests/integration/run_stability_tests.tscn
## Desktop-sim stability only — real-device interruptions are the RB-002
## matrix runs.

const CYCLES := 30

var harness := TestHarness.new()


func _ready() -> void:
	await _run_all()
	var exit_code := harness.report("STABILITY TESTS")
	get_tree().quit(exit_code)


func _run_all() -> void:
	await _test_thirty_capture_cycles()
	await _test_thirty_pause_interrupt_cycles()
	await _test_thirty_level_enter_exit_cycles()


# --- QA-016: thirty capture start/stop cycles on one service ---


func _test_thirty_capture_cycles() -> void:
	harness.suite = "stability.capture_cycles"
	var source := VoiceFrameSource.SyntheticFrameSource.new()
	source.rate = 48000
	var voice := VoiceInputService.new(source, false)
	add_child(voice)
	voice.calibration = {"gate_db": -50.0, "lower_db": -40.0, "upper_db": -20.0}
	var opened := 0
	var heard := 0
	for i: int in CYCLES:
		if voice.begin_capture():
			opened += 1
		source.push_constant_ms(300, 0.05)
		await get_tree().process_frame
		await get_tree().process_frame
		if voice.is_listening():
			heard += 1
		if i == 0:
			harness.check(voice.is_listening(), "capture listens on the first cycle")
			harness.check(bool(voice.published_preview()["valid"]), "preview valid on the first cycle")
		voice.end_capture()
		if i == 0:
			harness.check(not voice.is_listening(), "capture closes on the first cycle")
	harness.check_eq(opened, CYCLES, "every cycle opened capture (no duplicate-owner refusal)")
	harness.check_eq(heard, CYCLES, "every cycle reached Listening (no stale buffer blocking)")
	harness.check(not voice.is_listening(), "no lingering capture owner after 30 cycles")
	# The service must still work normally afterwards.
	harness.check(voice.begin_capture(), "capture opens normally after the stress run")
	source.push_constant_ms(300, 0.05)
	await get_tree().process_frame
	await get_tree().process_frame
	harness.check(bool(voice.published_preview()["valid"]), "preview still valid after the stress run")
	voice.end_capture()
	voice.queue_free()
	await get_tree().physics_frame


# --- QA-013: repeated pause-during-capture cycles on the full game ---


func _test_thirty_pause_interrupt_cycles() -> void:
	harness.suite = "stability.pause_cycles"
	AppRouter.current_level_id = "CC01"
	var packed: PackedScene = load("res://scenes/game/game_root.tscn")
	var root: GameRoot = packed.instantiate()
	add_child(root)
	await get_tree().physics_frame
	var source := VoiceFrameSource.SyntheticFrameSource.new()
	source.rate = 48000
	root.voice._source = source
	root.voice._is_real_mic = false
	for i: int in 300:
		if root.session.fsm.state == GameStateMachine.State.READY:
			break
		await get_tree().physics_frame
	root.voice.calibration = {"gate_db": -50.0, "lower_db": -40.0, "upper_db": -20.0}
	var coordinator := root.coordinator
	var strokes := 0
	var recovered := 0
	for i: int in CYCLES:
		if not coordinator.voice_hold_started():
			continue
		source.push_constant_ms(150, 0.05)
		await get_tree().process_frame
		await get_tree().process_frame
		root.notification(GameRoot.NOTIFICATION_APPLICATION_PAUSED)
		await get_tree().process_frame
		if root.session.strokes == strokes:  # no stroke leaked this cycle
			recovered += 1
		strokes = root.session.strokes
		# Resume through the HUD path; the mic must never restart by itself.
		root.hud.resume_requested.emit()
		await get_tree().process_frame
		if i == 0:
			harness.check(not get_tree().paused, "first cycle: resumed to an unpaused tree")
			harness.check(not root.voice.is_listening(), "first cycle: mic stays off after resume")
		var ready_again := false
		for j: int in 60:
			if root.session.fsm.state == GameStateMachine.State.READY:
				ready_again = true
				break
			await get_tree().physics_frame
		harness.check(ready_again, "cycle %d returned to READY" % (i + 1))
	harness.check_eq(recovered, CYCLES, "no stroke leaked across 30 pause-during-capture cycles")
	harness.check(not root.voice.is_listening(), "mic never left open across the cycles")
	# Tear down through the exit path and confirm a clean unload.
	var level_ref := root.level
	root.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	harness.check(not is_instance_valid(level_ref) or level_ref.instance == null, "level torn down after stress cycles")


# --- QA-045: thirty level enter/exit cycles with leak accounting ---


func _test_thirty_level_enter_exit_cycles() -> void:
	harness.suite = "stability.level_cycles"
	var nodes_before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var mem_before := int(OS.get_static_memory_usage())
	var completed_cycles := 0
	for i: int in CYCLES:
		AppRouter.current_level_id = "CC01"
		var packed: PackedScene = load("res://scenes/game/game_root.tscn")
		var root: GameRoot = packed.instantiate()
		add_child(root)
		await get_tree().physics_frame
		var ok := false
		for j: int in 300:
			if root.session.fsm.state == GameStateMachine.State.READY:
				ok = true
				break
			await get_tree().physics_frame
		harness.check(ok, "cycle %d reached READY" % (i + 1))
		if ok:
			completed_cycles += 1
		root.session.request_touch_shot(0.2)
		await get_tree().physics_frame
		root.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame
	harness.check_eq(completed_cycles, CYCLES, "all 30 enter/exit cycles completed a full session boot")
	var node_growth := Performance.get_monitor(Performance.OBJECT_NODE_COUNT) - nodes_before
	harness.check(node_growth <= 8, "node count grew by only %d across 30 cycles (no leak)" % node_growth)
	var mem_growth_mb := float(OS.get_static_memory_usage() - mem_before) / (1024.0 * 1024.0)
	harness.check(mem_growth_mb < 8.0, "static memory grew by only %.1f MB across 30 cycles" % mem_growth_mb)
