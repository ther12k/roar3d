class_name ShotMath
extends RefCounted
## Pure shot math shared by Voice and Touch. Every accepted shot goes through
## impulse_for_power exactly once; cosmetics never alter these numbers.
## Tuning lives in resources/tuning/shot_tuning.tres (versioned with content).

const TUNING_VERSION := "mvp-1"
const IMPULSE_MIN_N_S := 1.5
const IMPULSE_MAX_N_S := 10.0
const POWER_EXPONENT := 1.6
const MIN_IMPLUSIVE_POWER := 0.0  # powers <= 0 are rejected outright
const MAX_POWER := 1.0


## True when power is finite and in (0, 1]. Zero power must never fire.
static func is_valid_power(power: float) -> bool:
	return is_finite(power) and power > MIN_IMPLUSIVE_POWER and power <= MAX_POWER


## Impulse magnitude in N*s for an accepted normalized power.
## p^1.6 curve from docs/02_GAME_DESIGN.md §4. Returns 0.0 for invalid input.
static func impulse_for_power(power: float) -> float:
	if not is_valid_power(power):
		return 0.0
	return IMPULSE_MIN_N_S + (IMPULSE_MAX_N_S - IMPULSE_MIN_N_S) * pow(power, POWER_EXPONENT)


## Upward loft (the ShotCommand.direction_world.y contribution) for a
## Roar-tier shot. THE single copy of the loft rule (review round 4, input
## parity): slingshot, Touch slider, and Voice all reach the session, which
## applies this — no input layer keeps its own copy. 0.0 below the Roar
## threshold (0.70), rising linearly to 0.28 at full power.
const ROAR_POWER_THRESHOLD := 0.70
const ROAR_LOFT_MAX := 0.28


static func loft_for_power(power: float) -> float:
	if not is_valid_power(power) or power < ROAR_POWER_THRESHOLD:
		return 0.0
	var roar_fraction := (power - ROAR_POWER_THRESHOLD) / (MAX_POWER - ROAR_POWER_THRESHOLD)
	return clampf(roar_fraction, 0.0, 1.0) * ROAR_LOFT_MAX


## Horizontal shot direction on the world XZ plane. The standard shot adds no
## upward component; ramps and pads create vertical movement through geometry.
static func horizontal_direction(direction_world: Vector3) -> Vector3:
	var flat := Vector3(direction_world.x, 0.0, direction_world.z)
	if flat.length_squared() < 0.000001:
		return Vector3.ZERO
	return flat.normalized()


## Voice calibration power mapping: clamp (dbfs - lower) / (upper - lower)
## into [0, 1]. Invalid range (upper <= lower) means recalibration is required.
static func relative_power(dbfs: float, lower_db: float, upper_db: float) -> float:
	if not is_finite(dbfs) or not is_finite(lower_db) or not is_finite(upper_db):
		return 0.0
	if upper_db <= lower_db:
		return -1.0  # sentinel: invalid calibration, caller must not shoot
	return clampf((dbfs - lower_db) / (upper_db - lower_db), 0.0, 1.0)
