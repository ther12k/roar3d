class_name LevelConfig
extends Node3D
## Authored per-level metadata attached to every level scene root child named
## "LevelConfig" (marker contract in docs/08 §1). Part of the scene, not the
## catalog: geometry authors own these values and they are validated by
## LevelController on load.

@export var kill_plane_y := -6.0
@export var turf_resistance := 0.55
## Horizontal world AABB used by the camera rig (excludes decorative islands).
@export var course_bounds := AABB(Vector3(-5.0, -1.0, -9.0), Vector3(10.0, 4.0, 18.0))
## Height of the cup opening plane (eligibility band is relative to this).
@export var cup_plane_y := 0.0
## Anchors closer than this to the cup never become safe rest anchors.
@export var cup_anchor_exclusion_radius := 0.6
## Roar Bounce experiment (review round 6): opt-in per level. When true the
## ball gains bounded landing rebounds and the Perfect Bounce timing action;
## default courses keep rc2 physics exactly.
@export var bounce_enabled := false
