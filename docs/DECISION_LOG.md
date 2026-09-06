# Decision Log

Bound decisions from implementation, with rationale and regression impact.
Format follows handoff/docs/12_DECISIONS_AND_RISKS.md conventions.

## D-001 · Ball collision mask set in code, not just the scene
**Decision.** `BallController._ready` forces `collision_layer=1`,
`collision_mask=6` (Course|MovingObstacle) regardless of how the body is created.
**Why.** Scene-authored values silently don't apply to code-created balls (tests),
and a default mask of 1 makes the ball fall through layer-2 turf.
**Impact.** Any new obstacle layer must update both `project.godot` layer names and
this constant; tests cover spawn settle so a mismatch fails loudly.

## D-002 · Engine friction zeroed on the ball; authored resistance only
**Decision.** The ball's `PhysicsMaterial` is friction 0 / bounce 0. Rolling
deceleration comes solely from the authored tangential-resistance term
(0.55 m/s² default, per-level via `LevelConfig.turf_resistance`).
**Why.** Measured on integrated Jolt 4.7.2 headless: with default contact friction
the ball decelerated ≈ **11 m/s²** (0.18 m/s per 60 Hz tick at ~5 m/s), i.e. a
maximum-power putt (10 N·s → 10 m/s) would stop in ≈ 4.5 m and the 10.5 m CC01
fairway would be unwinnable. docs/05 §2 anticipated exactly this (“friction alone
is not a reliable design specification… avoid double-counting”).
**Impact.** Analytic roll distance `v²/(2·resistance)` now matches sim closely;
CC01 completing band from 1 m before the cup is ≈ p ∈ (0, 0.07] and from spawn
≈ 0.38–0.42 (single-putt). Slopes will not self-arrest a frictionless ball —
future ramp holes must rely on geometry/anchors; revisit before CC04. Re-run the
flat-roll sweep (QA-021) after any change.

## D-003 · Godot 4.7.2 property names differ from later-version docs
**Decision.** Use `continuous_cd` (not `ccd_enabled`) and `PhysicsMaterial.bounce`
(not `restitution`) — both verified against this exact engine build via property
probes. Recorded because AI-written code frequently uses the newer names.
**Impact.** Any engine bump must re-grep these; a rename probe is cheap.

## D-004 · Assisted cup capture (no physical hole geometry yet)
**Decision.** The cup is an Area3D trigger + dark ring visual; completion freezes
the ball at the eligible position (distance ≤ 0.28 m, height band 0.15–0.40 m,
speed ≤ 1.2 m/s). Documented per docs/05 §4 (“intentionally use a visually
convincing assisted capture; document the chosen approach”).
**Impact.** QA-024 flyover/underside rejection is integration-tested. A future
real rim/hole model must re-run those tests.

## D-005 · Scene changes always deferred in AppRouter
**Decision.** `change_scene_to_file` is invoked through `call_deferred`.
**Why.** Routing from the boot scene's `_ready` triggered “Parent node is busy
adding/removing children” and dropped the transition (found in the first windowed
run, invisible to headless tests).
**Impact.** None expected; also defensively unpauses the tree on every route.

## D-006 · “Play” can only ever resolve to a playable scene
**Decision.** `ProgressStore.next_playable_level()` filters the catalog to entries
whose scene exists and status ≠ `design_only`; `AppRouter.goto_game` falls back to
it when a save references an unbuilt hole.
**Why.** Test progress once made the game resume at CC02 (no scene) → boot bounced
to Home → Play looped. Prevents “fake course or silent unlock” class of bugs
(docs/03 §8).
**Impact.** When new hole scenes land, catalog status must move off `design_only`
or they stay invisible to players.

## D-007 · Tests run with an isolated `user://`
**Decision.** `tools/run_tests.sh` points `XDG_DATA_HOME` at a temp dir per suite.
**Why.** Integration tests legitimately record completions; without isolation they
polluted the developer's real profile (which caused D-006's discovery).
**Impact.** Test runs leave no state behind; running suites manually without the
wrapper still writes real progress (acceptable locally, noted here).

## D-008 · Ball rest gate before impulse consume
**Decision.** `apply_shot` refuses when the ball is not at rest and the session
returns to READY with **no stroke** (commit consumed, shot void).
**Why.** Keeps the FR-06/FR-08 invariant one-sided and safe: a stroke can only be
spent together with a real impulse.
**Impact.** In normal flow unreachable (READY implies settled); protects against
direct teleports (tests, future tools). If it ever fires in play, it hides a
settle-detection bug — watch diagnostics.

## D-009 · Handoff folder ignored by the engine
**Decision.** `handoff/.gdignore` keeps the 20 MB reference PNGs/CSVs out of the
Godot import cache.
**Impact.** Handoff Python tools unaffected; gallery still opens from disk.
