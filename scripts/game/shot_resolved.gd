class_name ShotResolved
extends RefCounted
## Resolution report for one shot (docs/03 §6). Each shot_id resolves once;
## kill-volume and kill-plane events coalesce into one OUT_OF_BOUNDS.

const OUTCOME_REST := 0
const OUTCOME_CUP := 1
const OUTCOME_OUT_OF_BOUNDS := 2

var shot_id := -1
var outcome := OUTCOME_REST
var resting_transform := Transform3D.IDENTITY
var strokes_total := 0


static func outcome_name(value: int) -> String:
	match value:
		OUTCOME_REST:
			return "rest"
		OUTCOME_CUP:
			return "cup"
		OUTCOME_OUT_OF_BOUNDS:
			return "out_of_bounds"
		_:
			return "unknown"
