class_name PortalPair
extends Node3D
## Authored portal pair (RB-038, docs/05 §5): entry/exit Area3D children with
## explicit transforms. Velocity direction maps through the entry→exit basis
## with speed preserved; the ball teleports through the engine-safe path.
## A per-ball latch (cooldown AND until the ball leaves the exit) prevents
## immediate re-entry loops (QA-027).

@export var cooldown_sec := 0.4
@export var exit_clearance := 0.55  ## spawn offset along the mapped forward
@export var exit_offset := Vector3(8.0, 0.0, 0.0)  ## exit placement in pair-local space
@export var exit_yaw_deg := 90.0  ## exit facing; 90 = local +X

@onready var entry: Area3D = $Entry
@onready var exit_area: Area3D = $Exit

# per-ball instance id -> armed at msec
var _armed_at: Dictionary = {}
var _inside_exit: Dictionary = {}


func _ready() -> void:
	# Structure contract: the pair scene owns exactly one valid counterpart.
	var entry_ok := entry != null and entry is Area3D
	var exit_ok := exit_area != null and exit_area is Area3D
	if not (entry_ok and exit_ok):
		push_error("PortalPair requires Entry and Exit Area3D children.")
		return
	exit_area.position = exit_offset
	exit_area.rotation_degrees = Vector3(0.0, exit_yaw_deg, 0.0)
	entry.body_entered.connect(_on_entry_entered)
	exit_area.body_entered.connect(_on_exit_entered)
	exit_area.body_exited.connect(_on_exit_exited)


func _on_exit_entered(body: Node3D) -> void:
	if body is BallController:
		_inside_exit[body.get_instance_id()] = true


func _on_exit_exited(body: Node3D) -> void:
	if body is BallController:
		_inside_exit.erase(body.get_instance_id())


func _on_entry_entered(body: Node3D) -> void:
	if body is BallController:
		_transfer(body)


func _transfer(ball: BallController) -> void:
	var id := ball.get_instance_id()
	var now := Time.get_ticks_msec()
	if _armed_at.has(id) and now < int(_armed_at[id]):
		return
	if bool(_inside_exit.get(id, false)):
		return  # already standing in this pair's exit
	_armed_at[id] = now + int(cooldown_sec * 1000.0)

	# Rotation-only mapping entry basis -> exit basis; speed preserved.
	var entry_basis := entry.global_transform.basis
	var exit_basis := exit_area.global_transform.basis
	var mapping := exit_basis.inverse() * entry_basis  # world->entry->exit? see below
	# Map a world direction d: express in entry frame, re-express in exit frame:
	# d_exit_world = exit_basis * entry_basis.inverse() * d_world
	var rotation_map := exit_basis * entry_basis.inverse()
	var velocity := ball.linear_velocity
	var mapped := rotation_map * velocity
	mapped.y = velocity.y  # keep the vertical (gravity) component honest
	if mapped.length() < 0.05:
		mapped = -exit_basis.z * 1.2  # gentle push so the ball clears the pad
	var forward := (-exit_basis.z).normalized()
	var origin := exit_area.global_position + forward * exit_clearance + Vector3(0.0, 0.25, 0.0)
	var face := Transform3D(Basis.looking_at(forward, Vector3.UP), origin)
	ball.teleport_with_velocity(face, mapped)
