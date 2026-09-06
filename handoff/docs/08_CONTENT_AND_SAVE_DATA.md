# Content, Local Saves, and Data Validation

## 1. Content approach

Author geometry as Godot scenes with modular reusable objects. Use a small JSON catalog for ordered metadata and build-time validation. This package includes twelve metadata briefs and a JSON Schema. It does not include the twelve playable scenes; the scene paths are the target contract for implementation.

The application maps a validated catalog ID to a packaged scene allowlist. Saves reference IDs only, not arbitrary scene paths or scripts. JSON metadata cannot invoke methods, choose classes, or load network content. IDs are permanent once released.

Required level scene markers: Spawn, Cup, KillVolume or kill plane config, CourseBounds, and at least one safe fallback anchor. Optional obstacles expose stable IDs so validation can check portal pairs and references. Each hole has at most one portal pair in MVP.

## 2. Catalog fields

Each level entry has `id`, `world_id`, `order`, `title`, `scene_path`, `par`, `max_strokes`, `mechanics`, `teaching_goal`, `layout_brief`, `solution_brief`, `validation_checks`, and `status`. Status is `design_only` in this delivery. A built level may become `graybox`, `playtest_ready`, then `validated` with evidence stored separately.

Schema validation enforces types/ranges. Semantic validation additionally enforces uniqueness, contiguous order, exactly six levels per world for this release, twelve total levels, known mechanics, matching path/ID, and `max_strokes >= par + 2`. A schema passing does not prove a course is fun or solvable.

Reference solutions record an engine version, tuning version, level scene/content hash, device/build, aim/power bands, stroke count, and notes. Do not store only an ideal float sequence and call it deterministic playback. A human tester must independently reproduce a successful route.

## 3. Local save format

Store local progress separately from settings. Use schema version 1 initially. Proposed progress envelope:

```json
{
  "schema_version": 1,
  "content_version": "mvp-1",
  "best_results": {
    "CC01": {"best_strokes": 2, "best_stars": 3}
  },
  "completed_levels": ["CC01"],
  "equipped_cosmetic": "lion",
  "last_played_level": "CC02",
  "applied_completion_ids": ["local-session-id:CC01:1"]
}
```

Unlocks are derived from completed IDs and current catalog order, not trusted free-form booleans. Validate positive integer strokes, star range 1–3, allowed cosmetics, and known IDs. Do not allow malformed data to equip an unearned cosmetic or crash the game. Preserve unknown future fields only through an explicit migration policy, not blind dictionary merging.

Settings store input mode, volume, haptics, reduced motion, quality, and calibration constants/version. Do not store PCM, a waveform history, audio recordings, transcripts, user names, or hardware device identifiers.

## 4. Write and recovery algorithm

Godot's FileAccess and JSON APIs are appropriate primitives for local persistence [S13]. The game still needs explicit validation and recovery.

1. Build an immutable new save snapshot in memory and validate it.
2. Write a temporary file in the same `user://` directory. Flush and close; re-read and validate the bytes/JSON.
3. Keep the previous validated primary as the last-good backup. Replace the primary through a checked rename/replacement operation appropriate to the platform. Do not delete the only valid copy first.
4. On any write/rename error, retain the in-memory snapshot and previous durable version; show Save Warning with Retry Save.
5. On boot, validate primary; if invalid, validate backup. Recover the last valid one and inform the player. If neither is valid, offer a fresh local profile without pretending the old data was recovered.

Test failure at every step. “Atomic” must not be claimed universally from a desktop test; mobile process-kill and filesystem behavior require validation. Temporary files must never be trusted automatically without schema validation.

## 5. Completion idempotency

Generate one completion ID per completed attempt. Apply the result once even if cup trigger, animation callback, and result screen all fire. Better stars and lower strokes update only on a valid completed result. Limit stored completion IDs to a bounded recent set sufficient for local duplicate prevention; better-result merging makes older replayed duplicates harmless because MVP has no currency.

Completed-level membership never shrinks because of a worse replay. Cosmetic unlocks are derived from CC06 and PP06 completion. At max-stroke failure, no completion entry is written. Save settings independently to avoid reverting progress when input preferences change.

## 6. Versioning and migration

Every engine/physics/tuning change records a version. Existing best strokes may remain as historical personal results, but content designers must decide how materially changed holes affect comparison. Never silently reset all player progress because an obstacle was moved.

A future schema migration must back up old data, transform to a new object, validate, then commit. Unit fixtures cover missing optional settings, unknown level IDs, invalid numeric values, duplicate completions, future schema version, and truncated JSON. Future schema version should produce a safe unsupported-save state instead of guessing.

## 7. Diagnostics

Use developer-only logs with level IDs, state transitions, normalized shot power, and non-sensitive errors. Normalized power can be logged in controlled QA builds without any PCM; disable histories in production. Never include capture buffers or full device identifiers in crash attachments.

The MVP has no server schema, authentication, leaderboard, or analytics event collection. A future online layer must have its own security, consent, data-retention, and abuse design; it is not a hidden prerequisite of the local game.
