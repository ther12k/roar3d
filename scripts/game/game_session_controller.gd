class_name GameSessionController
extends Node
## The sole shot/stroke authority (docs/03_TECHNICAL_ARCHITECTURE.md §3).
## Touch and Voice both arrive as ShotCommand values through guarded request
## methods; exactly one impulse and one stroke exist per accepted command.
## The UI never writes velocities or scores through here — it sends intents.

signal session_state_changed(state_name: String)
signal strokes_changed(strokes: int)
signal shot_committed(shot: ShotCommand)
signal shot_resolved(resolved: ShotResolved)
signal hole_completed(result: Dictionary)
signal attempt_finished()
signal stuck_recovery_changed(available: bool)
signal save_warning()

# Forgiveness tuning (D-020, from the first human playtest): finishing putts
# previously demanded ±0.02 power precision against a 0.28 m / 1.2 m/s capture
# band and lip-outs dominated. The wider band keeps fast flyovers (≈7 m/s in
# QA-024) rejected while letting honest approach speeds drop.
const CUP_HORIZONTAL_MAX := 0.34
const CUP_HEIGHT_MIN := 0.15
const CUP_HEIGHT_MAX := 0.40
const CUP_SPEED_MAX := 1.5
# Physical cavity (D-025): the turf collider is carved into a real hole with
# these dimensions; the visual cup in GameRoot must match. A ball whose center
# drops below the cup plane inside the hole is holed regardless of entry speed.
const CUP_HOLE_RADIUS := 0.30
const CUP_CAVITY_DEPTH := 0.30
const CUP_IN_HOLE_SPEED_MAX := 4.0
const STUCK_WATCHDOG_SEC := 20.0

@export var ball: BallController
@export var level: LevelController

var fsm := GameStateMachine.new()
var level_id := ""
var par := 3
var max_strokes := 12

var strokes := 0
var aim_direction := Vector3(0.0, 0.0, -1.0)
var last_committed_power := 0.0

var _session_id := 0
var _shot_seq := 0
var _pending_shot: ShotCommand = null
var _safe_anchor: Transform3D = Transform3D.IDENTITY
var _has_safe_anchor := false
var _reset_pending := false
var _stuck_timer := 0.0
var _stuck_available := false
var _active_shot_id := -1  # shot that owns the once-only fall penalty


func _ready() -> void:
	_session_id = randi() % 1000000
	fsm.state_changed.connect(_on_fsm_state_changed)
	if ball != null:
		ball.settle_started.connect(_on_settle_started)
		ball.settled.connect(_on_settled)
		ball.fall_detected.connect(_on_fall)
	if level != null:
		level.kill_zone_entered.connect(_on_fall)


func setup(p_ball: BallController, p_level: LevelController, p_level_id: String, p_par: int, p_max_strokes: int) -> void:
	ball = p_ball
	level = p_level
	level_id = p_level_id
	par = p_par
	max_strokes = p_max_strokes
	if ball != null:
		if not ball.settle_started.is_connected(_on_settle_started):
			ball.settle_started.connect(_on_settle_started)
		if not ball.settled.is_connected(_on_settled):
			ball.settled.connect(_on_settled)
		if not ball.fall_detected.is_connected(_on_fall):
			ball.fall_detected.connect(_on_fall)
	if level != null and not level.kill_zone_entered.is_connected(_on_fall):
		level.kill_zone_entered.connect(_on_fall)


## Begin one attempt. Ball spawns via engine-safe teleport and Ready begins
## after real settlement — never instantly.
func start_level() -> void:
	fsm.reset_for_new_session()
	strokes = 0
	strokes_changed.emit(strokes)
	_shot_seq = 0
	_pending_shot = null
	_active_shot_id = -1
	_safe_anchor = Transform3D.IDENTITY
	_has_safe_anchor = false
	_reset_pending = false
	_stuck_timer = 0.0
	_set_stuck_available(false)
	last_committed_power = 0.0
	ball.kill_plane_y = level.kill_plane_y()
	ball.turf_resistance = level.turf_resistance()
	aim_direction = level.initial_aim_direction()
	ball.teleport_to(level.spawn_transform())
	_safe_anchor = level.spawn_transform()
	_has_safe_anchor = true


# --- Shot intake (guarded intents, never direct physics writes) ---


## Touch path: slider power + Shoot press. Zero/invalid power never fires.
## Touch path: slider power + Shoot press or slingshot.
func request_touch_shot(power: float, loft: float = 0.0) -> bool:
	if not fsm.can_accept_touch_shot() or not ScoringRules.can_take_shot(strokes, max_strokes):
		return false
	if not ShotMath.is_valid_power(power):
		return false
	return _enqueue_command(ShotCommand.Source.TOUCH, power, loft)


## Voice path: called by InputCoordinator only after the service returned a
## valid preview from the same capture token that started the hold.
## Roaring (power >= 0.70) adds loft to the shot, launching the lion airborne!
func request_voice_shot(preview_power: float) -> bool:
	if not fsm.can_accept_voice_shot() or not ScoringRules.can_take_shot(strokes, max_strokes):
		return false
	if not ShotMath.is_valid_power(preview_power):
		return false
	var loft := 0.0
	if preview_power >= 0.70:
		loft = clampf((preview_power - 0.70) / 0.30, 0.0, 1.0) * 0.28
	return _enqueue_command(ShotCommand.Source.VOICE, preview_power, loft)


func can_begin_capture() -> bool:
	return fsm.state == GameStateMachine.State.READY and ScoringRules.can_take_shot(strokes, max_strokes)


func begin_capture_warmup() -> bool:
	if not can_begin_capture():
		return false
	return fsm.begin_capture_warmup()


func capture_became_active() -> bool:
	return fsm.capture_active()


func cancel_capture() -> bool:
	return fsm.cancel_capture()


func in_capture() -> bool:
	return fsm.is_capture_state()


## Mid-roll jump request. The session is the authority: it validates FSM state
## and ball support so no other layer needs to touch ball directly for jumps.
## ROLLING or SETTLING + ball grounded + jump token available → true.
## READY + ball resting → decorative hop only (no stroke, no state change).
## Returns true when the ball physically launched.
func request_jump() -> bool:
	if ball == null or not is_instance_valid(ball):
		return false
	if fsm.state in [GameStateMachine.State.ROLLING, GameStateMachine.State.SETTLING]:
		return ball.jump(3.8)
	# Allow a playful grounded hop at rest (visual only, session stays READY).
	if fsm.state == GameStateMachine.State.READY and ball.is_resting():
		return ball.jump(2.4)
	return false


func set_aim(direction: Vector3) -> void:
	if not can_aim():
		return
	var flat := ShotMath.horizontal_direction(direction)
	if flat != Vector3.ZERO:
		aim_direction = flat


## Aiming is gated to Ready (locked during capture/rolling). Input layers ask
## the session, never the raw FSM, so the authority stays in one place.
func can_aim() -> bool:
	return fsm.can_aim()


func _enqueue_command(source: ShotCommand.Source, power: float, loft: float = 0.0) -> bool:
	_shot_seq += 1
	var dir := aim_direction
	if loft > 0.001:
		dir = Vector3(aim_direction.x, loft, aim_direction.z).normalized()
	var command := ShotCommand.new(
		_session_id, _shot_seq, source, power, dir, level_id, ShotMath.TUNING_VERSION
	)
	if not command.is_valid():
		return false
	if not fsm.begin_commit():
		return false
	_pending_shot = command
	return true


# --- Physics tick: consume pending commands, poll cup, run watchdog ---


func _physics_process(_delta: float) -> void:
	if get_tree().paused:
		return
	_consume_pending_shot()
	_apply_cup_funnel()
	_poll_cup_capture()
	_update_stuck_watchdog(_delta)


## Mild cup assist (D-025): with the turf physically carved into a real hole,
## gravity does the capture — this only steadies honest slow approaches and
## lip-unders, never yanks a rolling ball off its line from a distance.
func _apply_cup_funnel() -> void:
	if level == null or ball == null or not is_instance_valid(ball):
		return
	if fsm.state != GameStateMachine.State.ROLLING and fsm.state != GameStateMachine.State.SETTLING:
		return
	var cup := level.cup_position()
	var ball_pos := ball.global_position
	var flat_delta := Vector3(cup.x - ball_pos.x, 0.0, cup.z - ball_pos.z)
	var flat_dist := flat_delta.length()
	if flat_dist < 0.35 and flat_dist > 0.01:
		var height := ball_pos.y - level.cup_plane_y()
		if height >= 0.05 and height <= 0.45:
			var pull_factor := (0.35 - flat_dist) / 0.35
			var inward := flat_delta.normalized()
			ball.apply_central_force(inward * (pull_factor * 2.5) + Vector3.DOWN * (pull_factor * 2.0))


func _consume_pending_shot() -> void:
	if _pending_shot == null or fsm.state != GameStateMachine.State.COMMIT_PENDING:
		return
	var shot := _pending_shot
	_pending_shot = null
	if ball.apply_shot(shot):
		strokes += 1
		_active_shot_id = shot.shot_id
		last_committed_power = shot.normalized_power
		fsm.begin_rolling()
		strokes_changed.emit(strokes)
		shot_committed.emit(shot)
	else:
		# Physically unshootable (not at rest): no stroke, back to Ready.
		fsm.enter_ready()


# --- Resolution: settle, fall, cup ---


func _on_settle_started() -> void:
	if fsm.state == GameStateMachine.State.ROLLING:
		fsm.begin_settling()


func _on_settled(ball_transform: Transform3D, slope_ok: bool) -> void:
	match fsm.state:
		GameStateMachine.State.INTRO:
			fsm.enter_ready()
		GameStateMachine.State.RESETTING:
			_reset_pending = false
			if ScoringRules.attempt_finished(strokes, max_strokes, false):
				fsm.mark_failed()
				attempt_finished.emit()
			else:
				fsm.finish_reset()
		GameStateMachine.State.SETTLING, GameStateMachine.State.ROLLING:
			_maybe_store_safe_anchor(ball_transform, slope_ok)
			_emit_resolved(ShotResolved.OUTCOME_REST, ball_transform)
			if ScoringRules.attempt_finished(strokes, max_strokes, false):
				fsm.mark_failed()
				attempt_finished.emit()
			else:
				fsm.enter_ready()


func _maybe_store_safe_anchor(ball_transform: Transform3D, slope_ok: bool) -> void:
	if not slope_ok:
		return
	if level.anchor_near_cup(ball_transform.origin):
		return
	if not level.anchor_blocked(Transform3D(Basis.IDENTITY, ball_transform.origin)):
		_safe_anchor = ball_transform
		_has_safe_anchor = true


## Kill volume and kill plane coalesce here: one penalty per fall event, the
## reset itself defers to verified settlement (QA-025, QA-026).
func _on_fall(reason: String = "kill_volume") -> void:
	if not fsm.is_playing() or _reset_pending:
		return
	if fsm.state == GameStateMachine.State.COMPLETE or fsm.state == GameStateMachine.State.FAILED:
		return
	_reset_pending = true
	_active_shot_id = -1
	# A fall before the first Ready (misauthored spawn) recovers without
	# spending a penalty stroke; every fall after that costs exactly one.
	if fsm.state != GameStateMachine.State.INTRO:
		strokes += 1
		strokes_changed.emit(strokes)
	var anchor := _choose_reset_anchor()
	ball.teleport_to(anchor)
	if not fsm.begin_resetting():
		_reset_pending = false


func _choose_reset_anchor() -> Transform3D:
	if _has_safe_anchor and not level.anchor_blocked(_safe_anchor):
		return _safe_anchor
	var fallback := level.fallback_anchor()
	if not level.anchor_blocked(fallback):
		return fallback
	return level.spawn_transform()


## Player-confirmed stuck recovery: same +1 penalty rule, same reset path,
## never a silent teleport (QA-030).
func request_stuck_recovery() -> bool:
	if not _stuck_available:
		return false
	_set_stuck_available(false)
	_on_fall("stuck_recovery")
	return true


func _update_stuck_watchdog(delta: float) -> void:
	var rolling := fsm.state == GameStateMachine.State.ROLLING or fsm.state == GameStateMachine.State.SETTLING
	if not rolling:
		_stuck_timer = 0.0
		_set_stuck_available(false)
		return
	_stuck_timer += delta
	_set_stuck_available(_stuck_timer >= STUCK_WATCHDOG_SEC)


func _set_stuck_available(available: bool) -> void:
	if _stuck_available != available:
		_stuck_available = available
		stuck_recovery_changed.emit(available)


## Cup eligibility: horizontal proximity, height band above the cup plane,
## low speed — OR physically inside the carved cavity at any fall speed.
## High flyovers and underside passes cannot complete (QA-024): the rim-height
## band requires low speed, and the in-hole branch only fires below the plane.
func _poll_cup_capture() -> void:
	if not level.ball_in_cup_zone:
		return
	if fsm.state != GameStateMachine.State.ROLLING and fsm.state != GameStateMachine.State.SETTLING:
		return
	var cup := level.cup_position()
	var ball_pos := ball.global_position
	var flat_delta := Vector3(ball_pos.x - cup.x, 0.0, ball_pos.z - cup.z)
	var flat_dist := flat_delta.length()
	if flat_dist > CUP_HORIZONTAL_MAX:
		return
	var height := ball_pos.y - level.cup_plane_y()
	if height >= CUP_HEIGHT_MIN and height <= CUP_HEIGHT_MAX:
		if ball.linear_velocity.length() <= CUP_SPEED_MAX:
			_complete_hole(ball.global_transform)
			return
	# Ball center below the cup plane while inside the hole footprint: it has
	# physically dropped into the carved cavity — holed (QA-024 safe: only a
	# ball already below the rim qualifies, never a flyover above the plane).
	if flat_dist <= CUP_HOLE_RADIUS and height < CUP_HEIGHT_MIN \
			and height > -CUP_CAVITY_DEPTH - 0.1 \
			and ball.linear_velocity.length() <= CUP_IN_HOLE_SPEED_MAX:
		_complete_hole(ball.global_transform)


func _complete_hole(ball_transform: Transform3D) -> void:
	if not fsm.mark_complete():
		return
	_active_shot_id = -1
	ball.triggers_enabled = false
	ball.freeze = true
	_emit_resolved(ShotResolved.OUTCOME_CUP, ball_transform)
	var stars := ScoringRules.stars_for_result(true, strokes, par, max_strokes)
	var completion_id := "%d:%s:1" % [_session_id, level_id]
	var recorded: Dictionary = ProgressStore.record_completion(level_id, strokes, stars, completion_id)
	if not ProgressStore.save():
		save_warning.emit()
	var result := {
		"level_id": level_id,
		"strokes": strokes,
		"par": par,
		"stars": stars,
		"best_strokes": int(recorded.get("best_strokes", strokes)),
		"best_stars": int(recorded.get("best_stars", stars)),
		"is_new_best": bool(recorded.get("improved_strokes", false)),
		"completion_id": completion_id,
	}
	hole_completed.emit(result)


func _emit_resolved(outcome: int, resting: Transform3D) -> void:
	var resolved := ShotResolved.new()
	resolved.shot_id = _shot_seq
	resolved.outcome = outcome
	resolved.resting_transform = resting
	resolved.strokes_total = strokes
	shot_resolved.emit(resolved)


# --- Pause / lifecycle ---


## Pause cancels any un-committed shot (no stroke spent) and closes capture.
## Rolling state is preserved by the paused tree, not by re-impulse.
func pause_session() -> void:
	if not fsm.is_playing():
		return
	if fsm.state == GameStateMachine.State.COMMIT_PENDING:
		_pending_shot = null  # canceled before the physics tick: no stroke
	fsm.pause()


func resume_session() -> void:
	fsm.resume()


func _on_fsm_state_changed(_from: int, to: int) -> void:
	session_state_changed.emit(GameStateMachine.state_name(to))
