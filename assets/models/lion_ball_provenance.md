# Lion Mascot Asset — Provenance (RB-027)

## Asset

- **File**: `assets/models/lion_ball.glb` (glTF 2.0 binary)
- **Source**: authored for this project by
  `tools/generate_lion_asset.py` (Python stdlib, deterministic — regenerating
  produces a byte-identical file).
- **License**: CC0-1.0. No third-party meshes, textures, or code. The palette
  matches the previously shipped procedural mascot so visual tuning carries
  over.

## Contents

| Part | Meshes | Triangles (per instance) |
|---|---|---|
| BallBody | 1 | 884 |
| Mane tufts (2 rings: 20 outer + 14 inner) | 34 | 8 |
| EarOuter / EarInner | 2 + 2 | 192 / 120 |
| EyeWhite | 2 | 192 |
| Pupil | 2 | 192 |
| Muzzle | 1 | 252 |
| Nose | 1 | 120 |

- **Distinct meshes**: 8 · **Materials**: 8 (untextured PBR base-color)
- **Rendered triangle budget**: ≈ 2 080 tris — a fraction of one frame's
  budget on low-tier mobile; no LODs are required at gameplay size.
- **File size**: ≈ 55 KB.

## Runtime contract

`game_root.gd` loads the GLB under the ball's `VisualRoot` and reparents the
expression subtrees (`Mane`, ears, `FaceRoot`) onto the camera-billboarding
`FaceRig`. Expressions (blink, brow arch, smile/O-mouth, mane puff, ear pin)
drive these nodes at runtime; the GLB carries no baked animations by design —
all motion is code-driven and reduced-motion aware.

The legacy scene primitives remain as an automatic fallback if the asset is
missing, so the game never renders an invisible ball.

## Physics isolation

The collider stays the authored 0.25 m sphere; the asset replaces visuals
only. `tests/integration/run_integration_tests.gd`
(`asset.mascot_contract`) asserts:

- node contract (`LionBall`, `BallBody`, `Mane`, ears, `FaceRoot`, pupils,
  muzzle, nose) present after import;
- instance and triangle budgets hold;
- the full game reports the asset active, `FaceRoot`/`Mane` billboard on the
  face rig;
- cosmetic tints land on the asset body, legacy mesh hidden;
- collider radius (0.25 m) and mass (1.0) are unchanged.

## Regenerating

```sh
python3 tools/generate_lion_asset.py
```

Then re-open the Godot editor once (or run any headless `--editor --quit`)
so the imported scene is refreshed.
