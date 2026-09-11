extends Node
## Automated 12-hole balance matrix (RB-047 evidence, partial).
##
## Drives a naive scripted bot through every catalog hole through the REAL
## game scene: at each READY it aims straight at the cup and shoots with
## distance-scaled power; mid-roll it jumps only when a gap sits ahead
## (never — kept naive). Records strokes to completion, outcome, and per-hole
## frame stats. This is independent completion evidence + a difficulty
## signal; it does NOT replace human playtesting (novice fairness, fun) which
## stays in RB-047's acceptance criteria.
##
## Run: godot --headless --path . res://tools/balance_matrix.tscn

const STROKE_TIMEOUT_FRAMES := 60 * 20  # 20 s per stroke at 60 Hz
const HOLE_TIMEOUT_SEC := 120.0

const RESULTS := []


func _ready() -> void:
	await _run()


func _run() -> void:
	var catalog := LevelCatalog.load_packaged()
	var line := "\n| Hole | Par | Outcome | Strokes | Notes |"
	line += "\n|---|---|---|---|---|"
	for level_id: String in catalog.ordered_ids:
		var row := await _play_hole(level_id, catalog)
		line += "\n| %s | %d | %s | %d | %s |" % [
			level_id, row["par"], row["outcome"], row["strokes"], row["notes"]]
	print("BALANCE_MATRIX" + line)
	get_tree().quit(0)


func _play_hole(level_id: String, catalog: LevelCatalog.CatalogData) -> Dictionary:
	AppRouter.current_level_id = level_id
	var packed: PackedScene = load("res://scenes/game/game_root.tscn")
	var root: GameRoot = packed.instantiate()
	add_child(root)
	var source := VoiceFrameSource.SyntheticFrameSource.new()
	source.rate = 48000
	root.voice._source = source
	root.voice._is_real_mic = false
	var session := root.session
	var level := root.level
	var errors := level.load_level(catalog.level_by_id(level_id))
	var note := "load_errors=" + str(errors) if not errors.is_empty() else ""
	session.max_strokes = 12
	session.start_level()
	var frames := 0
	var waited := 0.0
	while session.fsm.state != GameStateMachine.State.READY and waited < 10.0:
		await get_tree().physics_frame
		frames += 1
		waited += 1.0 / 60.0
	# Naive strategy: aim straight at the cup, power from remaining distance.
	while not session.fsm.state in [GameStateMachine.State.COMPLETE, GameStateMachine.State.FAILED] \
			and waited < float(HOLE_TIMEOUT_SEC):
		if session.fsm.state == GameStateMachine.State.READY:
			var ball_pos: Vector3 = root.ball.global_position
			var to_cup := level.cup_position() - ball_pos
			var dist := Vector3(to_cup.x, 0.0, to_cup.z).length()
			session.set_aim(Vector3(to_cup.x, 0.0, to_cup.z).normalized() if to_cup.length() > 0.01 else Vector3(0, 0, -1))
			# Graduated flat power only: distance-scaled, never lofted. The
			# bot cannot see gaps or portals, so this measures how far a
			# straight-line strategy gets; a loft drive reliably clears far
			# rails on lane holes (honest penalty, first version looped OOB).
			var power := clampf(0.10 + dist * 0.048, 0.06, 0.68)
			session.request_touch_shot(power, 0.0)
		await get_tree().physics_frame
		frames += 1
		waited += 1.0 / 60.0
	var outcome := "TIMEOUT"
	if session.fsm.state == GameStateMachine.State.COMPLETE:
		outcome = "COMPLETE"
	elif session.fsm.state == GameStateMachine.State.FAILED:
		outcome = "FAILED(attempt-limit)"
	if note.is_empty():
		note = "naive straight-shot bot" if outcome == "COMPLETE" else "bot stuck/limited"
	var result := {
		"hole": level_id,
		"par": session.par,
		"outcome": outcome,
		"strokes": session.strokes,
		"notes": note,
	}
	root.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return result
