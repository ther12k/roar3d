class_name ProgressionRules
extends RefCounted
## Sequential unlock derivation. Unlocks are always derived from the set of
## completed level IDs plus catalog order — never from trusted booleans in a
## save file (docs/08_CONTENT_AND_SAVE_DATA.md §3).

const COSMETIC_LION := "lion"
const COSMETIC_PANDA := "panda"
const COSMETIC_ROBOT := "robot"
const PANDA_UNLOCK_LEVEL := "CC06"
const ROBOT_UNLOCK_LEVEL := "PP06"


## A level is unlocked when it is first in order, or when the immediately
## preceding catalog level is completed. The catalog must be pre-validated
## (unique, contiguous order) before calling this.
static func is_level_unlocked(level_id: String, ordered_ids: Array, completed: Dictionary) -> bool:
	var index := ordered_ids.find(level_id)
	if index < 0:
		return false
	if index == 0:
		return true
	var previous: String = ordered_ids[index - 1]
	return completed.has(previous)


## The next hole "Play" should open: the first unlocked, uncompleted level in
## order; after full completion, the last played/last in order.
static func next_playable(ordered_ids: Array, completed: Dictionary, last_played: String) -> String:
	for id: String in ordered_ids:
		if not completed.has(id):
			return id
	if ordered_ids.has(last_played):
		return last_played
	return String(ordered_ids[ordered_ids.size() - 1]) if not ordered_ids.is_empty() else ""


## Cosmetic unlocks derived from completion (PRD §7): Panda after CC06,
## Robot after PP06, Lion always. No currency, no random unlocks.
static func is_cosmetic_unlocked(cosmetic_id: String, completed: Dictionary) -> bool:
	match cosmetic_id:
		COSMETIC_LION:
			return true
		COSMETIC_PANDA:
			return completed.has(PANDA_UNLOCK_LEVEL)
		COSMETIC_ROBOT:
			return completed.has(ROBOT_UNLOCK_LEVEL)
		_:
			return false


## Total earned stars in a world (0..18 for six holes).
static func world_stars(best_results: Dictionary, world_level_ids: Array) -> int:
	var total := 0
	for id: String in world_level_ids:
		if best_results.has(id):
			total += int(best_results[id].get("best_stars", 0))
	return total
