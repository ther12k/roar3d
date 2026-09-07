class_name BouncePad
extends Area3D
## One-shot bounce pad (RB-039, docs/05 §6): applies its authored impulse on
## a NEW eligible contact only. A contact latch clears after the ball leaves,
## so holding a ball inside never adds energy every frame (QA-028). The ball
## keeps its speed cap; the pad just adds one impulse.

@export var launch_speed := 5.0  ## m/s along the pad's local up
@export var rearm_delay_sec := 0.15  ## debounce against exit/enter jitter

var _latched_ids: Dictionary = {}
var _rearm_at_msec: Dictionary = {}


func _ready() -> void:
	collision_layer = 8  # GameplayTrigger
	collision_mask = 1   # Ball
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body is BallController:
		_launch(body)


func _physics_process(_delta: float) -> void:
	# Safety net for spawn-inside overlap: Area3D fires body_entered on entry;
	# a ball that comes to rest overlapping stays latched (no energy pump).
	pass


func _launch(ball: BallController) -> void:
	var id := ball.get_instance_id()
	var now := Time.get_ticks_msec()
	if _latched_ids.has(id):
		return
	if _rearm_at_msec.has(id) and now < int(_rearm_at_msec[id]):
		return
	_latched_ids[id] = true
	var launch := (global_transform.basis.y).normalized() * launch_speed
	ball.apply_central_impulse(launch * ball.mass)


func _on_body_exited(body: Node3D) -> void:
	if body is BallController:
		var id := body.get_instance_id()
		_latched_ids.erase(id)
		_rearm_at_msec[id] = Time.get_ticks_msec() + int(rearm_delay_sec * 1000.0)
