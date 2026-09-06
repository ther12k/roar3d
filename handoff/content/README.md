# Content contracts

`level_catalog.json` contains 12 level-design briefs, not playable Godot scenes. Its `res://scenes/levels/...` paths are intended implementation paths and do not exist in this package.

`schemas/level_catalog.schema.json` validates metadata shape. `tools/validate_package.py` also checks IDs, world/order relationships, paths, and scope. A schema pass does not validate geometry, native resources, runtime loading, balance, or solvability.

`examples/` contains illustrative save/settings objects and an empty reference-solution evidence template. These are not a user's actual saved game. Replace the solution template's nulls only with real testing evidence.
