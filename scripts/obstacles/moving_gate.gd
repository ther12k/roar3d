class_name MovingGate
extends AnimatableBody3D
## Sliding gate (RB-037, docs/05 §6): fixed physics-time motion with an
## authored period/phase. The clock accumulates physics deltas only, so the
## gate pauses with the session and never wall-clock teleports through the
## ball after returning from background (QA-029). Kinematic collider and the
## visible mesh are the same body, so they can never disagree.

@export var period_sec := 3.0
@export var travel_distance := 6.5  ## slide along local X (its width) until the lane is fully clear
@export var phase := 0.0  ## 0..1 offset into the cycle

var _clock := 0.0
var _origin := Transform3D.IDENTITY


func _ready() -> void:
	collision_layer = 4  # MovingObstacle
	collision_mask = 0
	sync_to_physics = true
	_origin = transform


func _physics_process(delta: float) -> void:
	_clock += delta
	var cycle := sin(TAU * (_clock / maxf(period_sec, 0.01) + phase))
	var t := cycle * 0.5 + 0.5  # 0 (closed) .. 1 (open)
	transform = _origin.translated_local(Vector3(travel_distance * t, 0.0, 0.0))


## Phase position 0..1 (0 = sealed lane, 1 = fully open) for level pacing/tests.
func openness() -> float:
	var cycle := sin(TAU * (_clock / maxf(period_sec, 0.01) + phase))
	return cycle * 0.5 + 0.5
