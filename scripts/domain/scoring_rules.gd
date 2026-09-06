class_name ScoringRules
extends RefCounted
## Stroke, star, and attempt-limit rules. Mirrors docs/01_PRD.md §7 exactly:
## a completion on stroke max_strokes wins; a shot that resolves without
## completion at max_strokes fails the attempt; a fall adds exactly one
## penalty stroke per shot.


## Stars for a resolved attempt. Failed attempts earn zero and never replace
## a stored best.
static func stars_for_result(completed: bool, strokes: int, par: int, max_strokes: int = 12) -> int:
	if not completed or strokes < 1 or par < 1 or strokes > max_strokes:
		return 0
	if strokes <= par:
		return 3
	if strokes == par + 1:
		return 2
	return 1


## A new shot may be taken only while the stroke count is still below the
## attempt limit.
static func can_take_shot(strokes_used: int, max_strokes: int) -> bool:
	return strokes_used < max_strokes


## After a shot resolves without cup completion, the attempt is finished once
## the stroke total reaches the limit. A fall on the final allowed shot adds
## its penalty first (e.g. 11 used -> shot -> fall -> 13 > 12 -> failed).
static func attempt_finished(strokes_used: int, max_strokes: int, completed: bool) -> bool:
	if completed:
		return false
	return strokes_used >= max_strokes


## Merge a completed result into stored bests. Returns
## {best_strokes, best_stars, improved_strokes, improved_stars}; never worsens
## an existing best.
static func merge_best(stored: Dictionary, strokes: int, stars: int) -> Dictionary:
	var best_strokes: int = strokes
	var best_stars: int = stars
	if stored.has("best_strokes") and int(stored["best_strokes"]) > 0:
		best_strokes = mini(int(stored["best_strokes"]), strokes)
	if stored.has("best_stars") and int(stored["best_stars"]) > 0:
		best_stars = maxi(int(stored["best_stars"]), stars)
	return {
		"best_strokes": best_strokes,
		"best_stars": best_stars,
		"improved_strokes": best_strokes < int(stored.get("best_strokes", 0)) or not stored.has("best_strokes"),
		"improved_stars": best_stars > int(stored.get("best_stars", 0)),
	}
