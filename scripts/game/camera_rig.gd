class_name CameraRig
extends Node3D
## Gameplay camera (RB-013 + M5 game-feel pass). Ready framing fits ball +
## cup from behind the ball at ~38° elevation; follow tracks the rolling ball
## with bounded smoothing; overview (Ready only) pauses the session while
## inspecting. Feel layer: charge anticipation (slight dolly-out while the
## slingshot stretches) and trauma-based impact shake. Both are disabled by
## Reduced Motion.

const FOV := 45.0
const ELEVATION := 0.68  # ~38 deg — keeps the ball clear of the bottom tray
const FOLLOW_LERP := 4.0
const OVERVIEW_EXTRA_HEIGHT := 7.0
const OVERVIEW_EXTRA_BACK := 6.0
const CHARGE_DOLLY_MAX := 1.1  # meters pulled back at full slingshot power
const SHAKE_DECAY := 2.6  # trauma units per second
const SHAKE_MAX_OFFSET := 0.22  # meters at full trauma

@export var camera: Camera3D
@export var session: GameSessionController
@export var level: LevelController

var overview_active := false
var _follow_target := Vector3.ZERO
var _ready_basis_pos := Vector3.ZERO
var _trauma := 0.0  # 0..1; offset = trauma^2 * SHAKE_MAX_OFFSET
var _charge := 0.0  # 0..1 slingshot stretch, drives anticipation dolly
var _charge_pullback := 0.0  # smoothed meters of anticipation dolly


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # usable while paused (overview/pause)
	if camera == null:
		camera = get_node_or_null("Camera3D") as Camera3D
	camera.fov = FOV


## Impact events call this: hard bounce = 0.3, cup drop = 0.45, fall = 0.6.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Slingshot stretch 0..1 (GameRoot feeds it every frame while aiming).
func set_charge(amount: float) -> void:
	_charge = clampf(amount, 0.0, 1.0)


func _process(delta: float) -> void:
	if session == null or level == null or not level.has_level():
		return
	_trauma = maxf(_trauma - delta * SHAKE_DECAY, 0.0)
	if not overview_active:
		_apply_feel(delta)
	if session.fsm.state in [GameStateMachine.State.READY, GameStateMachine.State.INTRO, GameStateMachine.State.CAPTURE_WARMUP, GameStateMachine.State.CAPTURING]:
		_frame_ready(delta)
	elif session.fsm.state in [GameStateMachine.State.ROLLING, GameStateMachine.State.SETTLING, GameStateMachine.State.RESETTING, GameStateMachine.State.COMMIT_PENDING]:
		_frame_follow(delta)
	else:
		return
	_apply_shake()


## Feel offsets are applied to the camera (never the rig) right after framing.
func _apply_shake() -> void:
	if SettingsStore.settings.get("reduced_motion", false) or _trauma <= 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		return
	var amount := _trauma * _trauma * SHAKE_MAX_OFFSET
	var t := Time.get_ticks_msec() / 1000.0
	camera.h_offset = sin(t * 47.0) * amount
	camera.v_offset = cos(t * 39.0) * amount * 0.7


## Anticipation: while the slingshot stretches, ease the camera back a touch
## so releasing reads as a snap forward (follow lerp provides the snap).
func _apply_feel(_delta: float) -> void:
	if SettingsStore.settings.get("reduced_motion", false):
		_charge_pullback = 0.0
		return
	var target := _charge * CHARGE_DOLLY_MAX
	_charge_pullback = lerpf(_charge_pullback, target, minf(_delta * 8.0, 1.0))


func _ready_position() -> Vector3:
	var ball_pos := session.ball.global_position
	var cup_pos := level.cup_position()
	var back := (ball_pos - cup_pos)
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else Vector3(0.0, 0.0, 1.0)
	var span := ball_pos.distance_to(cup_pos)
	var distance := clampf(span * 0.75 + 3.0, 5.0, 14.0)
	var height := distance * ELEVATION
	return ball_pos + back * (distance * 0.9 + _charge_pullback) + Vector3(0.0, height, 0.0)


func _frame_ready(delta: float) -> void:
	var target := _ready_position()
	if SettingsStore.settings.get("reduced_motion", false):
		global_position = target
	else:
		global_position = global_position.lerp(target, minf(delta * FOLLOW_LERP, 1.0))
	# On long holes the fit distance clamps and the ball would sit behind the
	# bottom console; bias the look target toward the ball as the hole grows.
	var span := session.ball.global_position.distance_to(level.cup_position())
	var fit := clampf(span * 0.75 + 3.0, 5.0, 14.0)
	var bias := remap(fit, 5.0, 14.0, 0.45, 0.26)
	_look_between(session.ball.global_position, level.cup_position(), bias)


func _frame_follow(delta: float) -> void:
	var ball_pos := session.ball.global_position
	var cup_pos := level.cup_position()
	var back := (ball_pos - cup_pos)
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else Vector3(0.0, 0.0, 1.0)
	var distance := 7.0
	var target := ball_pos + back * distance * 0.75 + Vector3(0.0, distance * ELEVATION, 0.0)
	if SettingsStore.settings.get("reduced_motion", false):
		global_position = target
	else:
		global_position = global_position.lerp(target, minf(delta * FOLLOW_LERP, 1.0))
	_look_between(ball_pos, ball_pos.lerp(cup_pos, 0.25))


func _frame_overview(_delta: float) -> void:
	var bounds := level.course_bounds()
	var center := bounds.get_center()
	var size := bounds.size
	var dist := maxf(size.x, size.z) * 0.9 + 4.0
	var target := center + Vector3(0.0, dist * 0.8 + OVERVIEW_EXTRA_HEIGHT, dist * 0.55 + OVERVIEW_EXTRA_BACK)
	global_position = target
	camera.look_at(center, Vector3.UP)


func _look_between(a: Vector3, b: Vector3, t: float = 0.45) -> void:
	camera.look_at(a.lerp(b, t), Vector3.UP)


## Overview framing only; pausing during inspection is owned by GameRoot so
## there is exactly one pause authority (review finding: split pause paths).
func set_overview_active(active: bool) -> void:
	overview_active = active


func is_overview() -> bool:
	return overview_active
