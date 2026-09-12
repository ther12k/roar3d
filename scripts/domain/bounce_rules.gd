class_name BounceRules
extends RefCounted
## Pure Roar Bounce math (experiment branch, review round 6 design). No engine
## dependencies: eligibility, rebound speed, surface classes, and Perfect
## Bounce timing all live here so the rules are unit-testable and the
## physics layer only applies what these functions accept.
##
## Design invariants (review round 6):
## - Gentle putting is untouched: below MIN_IMPACT_SPEED nothing happens.
## - Rebounds decay (restitution < 1) and are capped per shot.
## - Perfect Bounce is a bounded timing reward on a landing, never a mash
##   exploit: one press per descent, a short acceptance window, and a hard
##   outgoing-speed cap.
## - The mechanic is opt-in per level (bounce_enabled); default courses keep
##   restitution 0 physics exactly as shipped in rc2.

const MIN_IMPACT_SPEED := 1.2  ## m/s normal impact for any rebound
const TURF_RESTITUTION := 0.35
const SPRING_RESTITUTION := 0.60
const MAX_REBOUNDS_PER_SHOT := 2
const PERFECT_WINDOW_MS := 120  ## press-to-landing acceptance window
const PERFECT_BOOST := 1.6  ## m/s added along the surface normal
const MAX_OUTGOING_SPEED := 4.0  ## m/s along the surface normal

const CLASS_TURF := "turf"
const CLASS_SPRING := "spring"
const CLASS_DEAD := "dead"  ## authored non-bouncing surface (finishing green)


## Restitution for an authored surface class. Unknown classes are ordinary
## turf — never invent bounce from unrecognized geometry.
static func restitution_for(bounce_class: String) -> float:
	match bounce_class:
		CLASS_SPRING:
			return SPRING_RESTITUTION
		CLASS_DEAD:
			return 0.0
		_:
			return TURF_RESTITUTION


## A landing needs a mostly-upward surface normal (floors and gentle slopes).
## Walls, rails, and ceilings are not landings.
static func is_landing_normal(surface_normal: Vector3) -> bool:
	return surface_normal.dot(Vector3.UP) >= 0.5


## Incoming speed along the surface normal (how hard the ball is closing on
## the surface). Positive when approaching, 0 otherwise.
static func incoming_normal_speed(velocity: Vector3, surface_normal: Vector3) -> float:
	return maxf(0.0, -velocity.dot(surface_normal))


## Whether this landing may produce a rule-driven rebound at all.
static func is_eligible(incoming_speed: float, rebounds_so_far: int) -> bool:
	return incoming_speed >= MIN_IMPACT_SPEED and rebounds_so_far < MAX_REBOUNDS_PER_SHOT


## Outgoing normal speed for one accepted rebound: restitution loss plus an
## optional Perfect Bounce boost, hard-capped. Never negative.
static func outgoing_speed(incoming_speed: float, restitution: float, boost: float) -> float:
	var raw := incoming_speed * restitution + maxf(boost, 0.0)
	return clampf(raw, 0.0, MAX_OUTGOING_SPEED)


## Perfect Bounce acceptance: the buffered press must be within the window of
## the landing. An early press expires; nothing extends it.
static func perfect_accepts(elapsed_ms: int) -> bool:
	return elapsed_ms >= 0 and elapsed_ms <= PERFECT_WINDOW_MS
