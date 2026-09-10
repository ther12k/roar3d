class_name CameraRig
extends Node3D
## Graybox camera (RB-013). Ready framing fits ball + cup from behind the
## ball at a ~50° elevation; follow tracks the rolling ball with bounded
## smoothing; overview (Ready only) pauses the session while inspecting.
## Reduced Motion (settings) removes the soft pull entirely.

const FOV := 45.0
const ELEVATION := 0.68  # ~38 deg — keeps the ball clear of the bottom tray
const FOLLOW_LERP := 4.0
const OVERVIEW_EXTRA_HEIGHT := 7.0
const OVERVIEW_EXTRA_BACK := 6.0

@export var camera: Camera3D
@export var session: GameSessionController
@export var level: LevelController

var overview_active := false
var _follow_target := Vector3.ZERO
var _ready_basis_pos := Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # usable while paused (overview/pause)
	if camera == null:
		camera = get_node_or_null("Camera3D") as Camera3D
	camera.fov = FOV


func _process(delta: float) -> void:
	if session == null or level == null or not level.has_level():
		return
	if overview_active:
		_frame_overview(delta)
		return
	if session.fsm.state in [GameStateMachine.State.READY, GameStateMachine.State.INTRO, GameStateMachine.State.CAPTURE_WARMUP, GameStateMachine.State.CAPTURING]:
		_frame_ready(delta)
	elif session.fsm.state in [GameStateMachine.State.ROLLING, GameStateMachine.State.SETTLING, GameStateMachine.State.RESETTING, GameStateMachine.State.COMMIT_PENDING]:
		_frame_follow(delta)


func _ready_position() -> Vector3:
	var ball_pos := session.ball.global_position
	var cup_pos := level.cup_position()
	var back := (ball_pos - cup_pos)
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else Vector3(0.0, 0.0, 1.0)
	var span := ball_pos.distance_to(cup_pos)
	var distance := clampf(span * 0.75 + 3.0, 5.0, 14.0)
	var height := distance * ELEVATION
	return ball_pos + back * distance * 0.9 + Vector3(0.0, height, 0.0)


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
