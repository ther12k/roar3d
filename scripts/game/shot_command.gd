class_name ShotCommand
extends RefCounted
## Immutable shot intent (docs/03_TECHNICAL_ARCHITECTURE.md §6). Created on
## the main thread after validation; consumed exactly once on a physics tick.
## Touch and Voice produce the same type and share every downstream rule.
## Never carries PCM or microphone identity.

enum Source { TOUCH, VOICE }

var session_id: int
var shot_id: int
var source: Source
var normalized_power: float
var direction_world: Vector3
var level_id: String
var tuning_version: String


func _init(
	p_session_id: int,
	p_shot_id: int,
	p_source: Source,
	p_normalized_power: float,
	p_direction_world: Vector3,
	p_level_id: String,
	p_tuning_version: String
) -> void:
	session_id = p_session_id
	shot_id = p_shot_id
	source = p_source
	normalized_power = p_normalized_power
	direction_world = p_direction_world
	level_id = p_level_id
	tuning_version = p_tuning_version


func is_valid() -> bool:
	return ShotMath.is_valid_power(normalized_power) and ShotMath.horizontal_direction(direction_world) != Vector3.ZERO


func describe() -> String:
	return "%s shot %d power=%.3f level=%s tuning=%s" % [
		Source.keys()[source], shot_id, normalized_power, level_id, tuning_version
	]
