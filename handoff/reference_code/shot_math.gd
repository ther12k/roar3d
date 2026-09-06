class_name RoarballShotMath
extends RefCounted
## Illustrative Godot 4.x reference. Not parsed/run in Godot in this delivery.
## Call once per accepted shot, not once per rendered frame.

static func impulse_for_power(power: float) -> float:
    if not is_finite(power) or power <= 0.0 or power > 1.0:
        return 0.0
    return 1.5 + 8.5 * pow(power, 1.6)

static func stars_for_result(
    completed: bool, strokes: int, par: int, max_strokes: int = 12
) -> int:
    if not completed or strokes < 1 or par < 1 or strokes > max_strokes:
        return 0
    if strokes <= par:
        return 3
    if strokes == par + 1:
        return 2
    return 1

static func relative_power(dbfs: float, lower_db: float, upper_db: float) -> float:
    if not is_finite(dbfs) or not is_finite(lower_db) or not is_finite(upper_db):
        return 0.0
    if upper_db <= lower_db:
        return 0.0
    return clampf((dbfs - lower_db) / (upper_db - lower_db), 0.0, 1.0)
