class_name BallController
extends RigidBody3D
## The single physics ball. Applies exactly one impulse per accepted
## ShotCommand (RB-010), models authored rolling resistance on supported
## tangential motion only, and owns rest detection + safe-teleport mechanics
## (RB-014). Never scaled non-uniformly; collider stays a 0.25 m sphere for
## every cosmetic.

signal settle_started()
signal settled(ball_transform: Transform3D, support_slope_ok: bool)
signal unsettled()
signal fall_detected(reason: String)
signal bounced(strength: float)  ## impact speed at contact start (presentation only)

const REST_LINEAR_SPEED := 0.06
const REST_ANGULAR_SPEED := 0.3
const SETTLE_DURATION_SEC := 0.4
const SAFE_SLOPE_DOT := 0.966  # ~15 degrees from up (safe-anchor eligibility)
const SUPPORT_DOT := 0.5  # surfaces steeper than 60 deg are not "support"
const SUPPORT_RAY_EXTRA := 0.06
const UP := Vector3(0.0, 1.0, 0.0)
const MAX_SPEED := 18.0  # bug containment after pad/portal interactions (docs/05 §2)

@export var turf_resistance := 0.55  # m/s^2 tangential deceleration while supported

var triggers_enabled := true  ## session disables during reset windows
var kill_plane_y := -100.0  ## authored per level via LevelConfig

var _resting := false
var _stable := false
var _settle_timer := 0.0
var _supported := false
var _support_normal := UP
var _support_is_static := false
var _teleport_pending := false
var _teleport_transform := Transform3D.IDENTITY
var _teleport_velocity := Vector3.ZERO
var _fall_emitted := false


func _ready() -> void:
	# 4.7 property name is continuous_cd (ccd for the fast-moving ball).
	continuous_cd = true
	# Explicit layers no matter how the body was created (scene vs code):
	# ball on layer 1; collides with Course(2) and MovingObstacle(4).
	collision_layer = 1
	collision_mask = 6
	# Contact reporting feeds only the bounce cue (GameRoot → Effects bus);
	# no gameplay branch reads contacts. Small cap: the ball is the only
	# dynamic body on the course.
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	mass = 1.0
	# Engine friction is NOT the rolling-resistance spec (docs/05 §2): Jolt's
	# default contact friction decelerates ~11 m/s² and drowns the authored
	# 0.55 m/s² term. Zero it here; BallController applies the authored
	# tangential resistance itself while supported.
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	material.bounce = 0.0
	physics_material_override = material
	# Damping stays tiny; rolling resistance is authored explicitly below so
	# we never double-count engine damping and the custom term.
	linear_damp = 0.0
	angular_damp = 0.05


func is_resting() -> bool:
	return _resting


func is_supported() -> bool:
	return _supported


func support_slope_ok() -> bool:
	return _supported and _support_normal.dot(UP) >= SAFE_SLOPE_DOT


func linear_speed() -> float:
	return linear_velocity.length()


## Cue strength = speed when the contact began (pre-resolution), so hard
## rail hits read louder than gentle nudges. Sub-threshold contacts stay
## silent — resting re-contacts must never tick.
func _on_body_entered(_body: Node) -> void:
	var strength := linear_velocity.length()
	if strength >= 0.8:
		bounced.emit(strength)


## Apply one accepted shot. Returns false (and does nothing) when the command
## is invalid or the ball is not at rest; the session must not count a stroke.
func apply_shot(command: ShotCommand) -> bool:
	if not command.is_valid() or not _resting:
		return false
	var direction := ShotMath.horizontal_direction(command.direction_world)
	if direction == Vector3.ZERO:
		return false
	var impulse_magnitude := ShotMath.impulse_for_power(command.normalized_power)
	if impulse_magnitude <= 0.0:
		return false
	_resting = false
	_settle_timer = 0.0
	unsettled.emit()
	apply_central_impulse(direction * impulse_magnitude)
	return true


## Engine-safe teleport: applied inside _integrate_forces, clearing all
## velocity so the move cannot produce a residual impulse (docs/05 §3).
func teleport_to(target: Transform3D) -> void:
	teleport_with_velocity(target, Vector3.ZERO)


## Teleport that preserves an authored exit velocity (portal transit, docs/05
## §5: transform the direction through the pair mapping, keep the speed).
func teleport_with_velocity(target: Transform3D, exit_velocity: Vector3) -> void:
	_teleport_pending = true
	_teleport_transform = target
	_teleport_velocity = exit_velocity
	_fall_emitted = false
	_resting = false
	_settle_timer = 0.0
	linear_velocity = exit_velocity
	angular_velocity = Vector3.ZERO


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _teleport_pending:
		_teleport_pending = false
		state.transform = _teleport_transform
		state.linear_velocity = _teleport_velocity
		state.angular_velocity = Vector3.ZERO
		_teleport_velocity = Vector3.ZERO
		_supported = true  # re-verified on the next step
		_support_normal = UP
		return

	_update_support(state)
	_apply_rolling_resistance(state)
	_clamp_speed(state)
	_update_rest(state)
	_check_kill_plane(state)


func _clamp_speed(state: PhysicsDirectBodyState3D) -> void:
	var speed := state.linear_velocity.length()
	if speed > MAX_SPEED:
		state.linear_velocity = state.linear_velocity * (MAX_SPEED / speed)


func _update_support(state: PhysicsDirectBodyState3D) -> void:
	var origin: Vector3 = state.transform.origin
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + Vector3(0.0, -1.0, 0.0) * (0.25 + SUPPORT_RAY_EXTRA)
	)
	var exclude: Array[RID] = [get_rid()]
	query.exclude = exclude
	query.collision_mask = 0b0000_0000_0110  # Course | MovingObstacle
	var hit: Dictionary = state.get_space_state().intersect_ray(query)
	if hit.is_empty():
		_supported = false
		_support_is_static = false
		_support_normal = UP
		return
	var normal: Vector3 = hit["normal"]
	var is_static := true
	var collider: Object = hit.get("collider")
	if collider is AnimatableBody3D:
		is_static = false
	_support_normal = normal
	_supported = normal.dot(UP) >= SUPPORT_DOT
	_support_is_static = is_static


## Authored rolling resistance: reduce only the tangential component of
## velocity while supported, never in flight, never below zero (docs/05 §2).
func _apply_rolling_resistance(state: PhysicsDirectBodyState3D) -> void:
	if not _supported or _resting:
		return
	var velocity: Vector3 = state.linear_velocity
	var normal := _support_normal
	var tangent := velocity - normal * velocity.dot(normal)
	var tangent_speed := tangent.length()
	if tangent_speed < 0.001:
		return
	var deceleration := turf_resistance * state.step
	var new_speed := maxf(tangent_speed - deceleration, 0.0)
	tangent = tangent * (new_speed / tangent_speed)
	state.linear_velocity = normal * velocity.dot(normal) + tangent


## Rest requires low speeds, real support, and 0.4 s of continuous
## settlement; a descending or unsupported ball is never frozen (docs/02 §5).
func _update_rest(state: PhysicsDirectBodyState3D) -> void:
	var lin := state.linear_velocity.length()
	var ang := state.angular_velocity.length()
	var stable := _supported and _support_is_static and lin < REST_LINEAR_SPEED and ang < REST_ANGULAR_SPEED
	if stable:
		_settle_timer += state.step
		if not _stable:
			_stable = true
			settle_started.emit()
	else:
		_settle_timer = 0.0
		if _stable:
			_stable = false
	if not _resting and _settle_timer >= SETTLE_DURATION_SEC:
		_resting = true
		# Remove measured numerical drift only; never touch a moving body.
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		settled.emit(state.transform, _support_normal.dot(UP) >= SAFE_SLOPE_DOT)
	elif _resting and not stable:
		_resting = false
		_stable = false
		_settle_timer = 0.0
		unsettled.emit()


## Authored kill plane; the level's kill volume is the other half of fall
## detection and both coalesce in the session (QA-025).
func _check_kill_plane(state: PhysicsDirectBodyState3D) -> void:
	if not triggers_enabled or _fall_emitted:
		return
	if state.transform.origin.y < kill_plane_y:
		_fall_emitted = true
		fall_detected.emit("kill_plane")
