# Asset Inventory and Provenance

Covers every runtime asset in the repo. The handoff requires a budget and
provenance inventory per module (docs/07 §7); this file is that record. It is
updated whenever a runtime asset is added.

## Provenance summary

**Every asset below is original, authored in this repository as hand-written
Godot resources.** No third-party meshes, textures, fonts, or audio exist in
the project yet. The AI concept PNGs in `handoff/design/` are references only
and are not loaded by the game. No asset has trademark or commercial-use
clearance (includes the working name "Roarball" — PRD risk, unresolved).

## Course kit grid contract (RB-028)

Kit modules are **native Godot wrapper scenes** (`scenes/course_kit/*.tscn`).
Per docs/07 §3, the wrapper — not an imported mesh — owns collision, so a
future artist re-export cannot break tested interactions. There are no GLB
imports yet; when Blender-authored visuals arrive they slot under the same
wrappers (`Visuals` children), and the wrapper-owned `StaticCollision`
stays authoritative.

| Convention | Value |
|---|---|
| Unit | 1 Godot unit = 1 m |
| Grid pitch | 5 m × 5 m per module |
| Origin | Center of the walkable top surface, y = 0 |
| Forward | −Z (toward the cup), matching CC01 and `LevelController` |
| Turf | 5 × 0.5 × 5 box, top at y = 0 |
| Rails | 0.3 × 0.4 × 5 box at x = ±2.65 (inner faces at ±2.5 → 5 m corridor) |
| Collision | `StaticBody3D` on layer 2 (Course), mask 0, inside a `StaticCollision` node |
| Pivots | `Connect/In` and `Connect/Out` `Marker3D`s at seam-edge midpoints |
| Materials | Shared: `materials/kit_turf.tres`, `kit_rail_wood.tres`, `kit_stone.tres` |

Modules butt edge-to-edge with flush surfaces; seams are verified by
`tests/integration/run_course_kit_tests.tscn` (low/high-speed rolls, ramp
climb/descent, corner traversal, cliff openness, ray-probe seam contract).
Other turn directions/raised rows are made by rotating/offsetting instances;
the `Connect` pivots rotate with them.

## Inventory

| Asset | Path | Author | Source | License | Tris (approx) | Materials | Collider owner | Notes |
|---|---|---|---|---|---|---|---|---|
| Straight module | `scenes/course_kit/straight.tscn` | ther12k | Hand-written .tscn (Godot primitives) | Original (this repo) | 36 (3 boxes) | 2 shared | Wrapper (`StaticCollision`) | 5×5 turf + 2 rails |
| Corner module | `scenes/course_kit/corner.tscn` | ther12k | Hand-written .tscn | Original | 36 | 2 shared | Wrapper | 5×5 square, left+far rails, 90° turn −Z→+X |
| Green module | `scenes/course_kit/green.tscn` | ther12k | Hand-written .tscn | Original | 36 | 2 shared | Wrapper | 10×5 turf, side+far rails, open entry |
| Ramp module | `scenes/course_kit/ramp.tscn` | ther12k | Hand-written .tscn | Original | 48 | 3 shared | Wrapper | 5 m run, 1 m rise (11.3°), sloped rails, stone skirt (visual only) |
| Rail module | `scenes/course_kit/rail.tscn` | ther12k | Hand-written .tscn | Original | 12 | 1 shared | Wrapper | 5 m barrier for custom edges |
| Plateau module | `scenes/course_kit/plateau.tscn` | ther12k | Hand-written .tscn | Original | 12 | 1 shared | Wrapper | Bare 5×5 turf, no rails — open-edge risk areas (added round 4 for CC02) |
| Cliff edge module | `scenes/course_kit/cliff_edge.tscn` | ther12k | Hand-written .tscn | Original | 60 | 3 shared | Wrapper | Far edge open (fall hazard); stone faces are visual-only, no collision |
| Kit showcase | `scenes/course_kit/kit_showcase.tscn` | ther12k | Hand-written .tscn | Original | — | — | n/a | All modules laid out; evidence capture via `tools/capture_course_kit.gd` |
| Sound effects | `assets/audio/{putt,cup,fall,click}.wav` | ther12k | Synthesized tones (python, generated for this repo) | Original | — | — | n/a | Nonverbal feedback cues on the Effects bus (RB-025); no recordings |
| Kit materials | `scenes/course_kit/materials/*.tres` | ther12k | Hand-written .tres | Original | — | 3 files | n/a | Shared across modules (budget: ≤3 material slots) |
| CC01 level | `scenes/levels/CC01.tscn` | ther12k | Hand-written .tscn | Original | ~150 | 6 inline (pre-kit) | Wrapper | Graybox hole; predates the kit, refactor optional |
| CC02 level | `scenes/levels/CC02.tscn` | ther12k | Kit composition (.tscn) | Original | ~60 + kit | 1 inline + shared | Kit wrappers | First kit-composed hole: straight tee → 2 plateaus → green |
| CC03 level | `scenes/levels/CC03.tscn` | ther12k | Kit composition (.tscn) | Original | ~60 + kit | 1 inline + shared | Kit wrappers | Kit-composed L: tee → corner → corridor → rotated green |
| CC04 level | `scenes/levels/CC04.tscn` | ther12k | Kit composition (.tscn) | Original | ~60 + kit | 1 inline + shared | Kit wrappers | Ramp jump over void to landing plateau & green |
| CC05 level | `scenes/levels/CC05.tscn` | ther12k | Kit composition (.tscn) | Original | ~60 + kit | 1 inline + shared | Kit wrappers | Sliding gate obstacle timing passage |
| CC06 level | `scenes/levels/CC06.tscn` | ther12k | Kit composition (.tscn) | Original | ~80 + kit | 1 inline + shared | Kit wrappers | Gate timing + ramp jump combo finale |
| PP01 level | `scenes/levels/PP01.tscn` | ther12k | Kit composition (.tscn) | Original | ~60 + kit | 1 inline + shared | Kit wrappers | Portal pair introduction: tee to approach |
| PP02 level | `scenes/levels/PP02.tscn` | ther12k | Kit composition (.tscn) | Original | ~60 + kit | 1 inline + shared | Kit wrappers | Portal exit angle onto green |
| PP03 level | `scenes/levels/PP03.tscn` | ther12k | Kit composition (.tscn) | Original | ~60 + kit | 1 inline + shared | Kit wrappers | Bounce pad launch over void to raised green |
| PP04 level | `scenes/levels/PP04.tscn` | ther12k | Kit composition (.tscn) | Original | ~80 + kit | 1 inline + shared | Kit wrappers | Portal transit to staging, bounce pad to raised green |
| PP05 level | `scenes/levels/PP05.tscn` | ther12k | Kit composition (.tscn) | Original | ~80 + kit | 1 inline + shared | Kit wrappers | Portal transit to sliding gate corridor |
| PP06 level | `scenes/levels/PP06.tscn` | ther12k | Kit composition (.tscn) | Original | ~80 + kit | 1 inline + shared | Kit wrappers | Portal Peaks finale: portal to staging, pad to green |
| Moving Gate | `scenes/obstacles/moving_gate.tscn` | ther12k | Hand-written .tscn | Original | 24 | 2 shared | Wrapper | Sliding obstacle with physics delta sync |
| Bounce Pad | `scenes/obstacles/bounce_pad.tscn` | ther12k | Hand-written .tscn | Original | 32 | 1 shared | Wrapper | Trigger pad with entry latch |
| Portal Pair | `scenes/obstacles/portal_pair.tscn` | ther12k | Hand-written .tscn | Original | 48 | 3 shared | Wrapper | Linked entry and exit with velocity mapping |
| Scenery islands | `scripts/course_kit/scenery.gd` | ther12k | Runtime primitives | Original | ~40/cluster | inline | None (decor) | Pine/leafy/rock/bush variants; placed outside CourseBounds |
| Hole sign | runtime in `game_root.gd` | ther12k | Runtime primitives | Original | 2 boxes + Label3D | inline | None (decor) | Wooden 'HOLE ID · Par N' board at each tee |
| Game scene | `scenes/game/game_root.tscn` | ther12k | Hand-written .tscn | Original | ~2k (lion ball) | ~8 inline | Wrapper | Sky, lighting, lion ball (mane/eyes/muzzle), HUD |
| Ball visuals | `game_root.tscn` sub-resources | ther12k | Godot primitives | Original | ~2k | inline | n/a | Sphere collider 0.25 m owned by `BallController`; cosmetics never change it |

Budget check (docs/07 §2 proposal "0.5–2k triangles/module, shared
materials"): every module is ≤ 60 triangles with ≤ 3 shared material slots —
well inside budget. Final visible-scene draw-call budgets are still
unmeasured on a phone (RB-003 open).

## Reimport policy

The kit has no imported (GLB/texture) assets, so an engine reimport cannot
replace wrapper content structurally. `tools/run_tests.sh` performs a clean
`--import` (deleting `.godot/`) before every run and the kit suite then
instantiates every module and re-verifies collision ownership, layer, pivots,
and seam geometry — the "reimports preserve wrapper interactions" gate is
that full run staying green. When GLB visuals are added under these wrappers,
add a one-asset reimport check before committing the batch (docs/07 §3).
