Captures are excluded from the tree on purpose.
Evidence PNGs live as release assets:
https://github.com/ther12k/roar3d/releases/tag/v0.1.0-graybox-slice
Regenerate locally with:
ROAR3D_SCREENSHOT=/tmp/s.png godot --path .

Course-kit showcase:
godot --path . --resolution 900x1600 -s tools/capture_course_kit.gd
(writes /tmp/roar3d_course_kit_showcase.png; see docs/ASSET_INVENTORY.md)

Per-level ready-state captures (real game_root + HUD):
LEVEL_ID=CC02 godot --path . --resolution 390x844 res://tools/capture_level.tscn
(writes /tmp/roar3d_<level>_ready.png)
