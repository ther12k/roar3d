# Implementation Status

Last updated: 2026-09-06 · Engine: Godot **4.7.2.stable.official.ed1daf0bf** (pinned in
`ENGINE_VERSION`, binary used for all evidence below)

## What is done and verified

### M0 — Foundation (partially; hardware spikes still open)

- **RB-001 Pin toolchain / repo**: Godot 4.7.2 stable downloaded from the official
  GitHub release; project scaffolded per `handoff/docs/03_TECHNICAL_ARCHITECTURE.md` §2.
  Clean-checkout import verified: `rm -rf .godot && godot --headless --path . --import`
  completes with **0 script/parse errors**. No Flutter, no Kotlin, `addons/` absent.
- **RB-004 Jolt spike (sim)**: integrated Jolt (`physics/3d/physics_engine=JoltPhysics3D`)
  runs the full ball loop headless: impulse, settling, fall, reset, cup capture. See
  *Untested* below for the physical-device part of the spike.
- **RB-046 catalog validation**: 12 design briefs validate (schema + semantic:
  two worlds × six holes, global `order` 1–12, per-world `world_index` 1–6,
  `max_strokes ≥ par+2`, scene-path/id match). CC01 is marked `graybox` in the
  packaged copy because its scene exists; the other 11 remain `design_only` and the
  game refuses to load them.

### M1 — Playable loop (Touch complete; Voice wired, mic hardware untested)

One complete graybox hole (CC01) end-to-end in **Touch**: boot → Home → game →
aim (drag or arrow keys) → slider power → Shoot → single impulse → rolling with
authored resistance → settling → cup capture (eligibility-gated) → results →
progress saved durably → retry/next. Pause cancels un-committed shots without
spending a stroke. Out-of-bounds adds exactly one penalty and resets to a verified
safe anchor. Attempt limit (12) fails with Retry/Map.

**Voice** runs the identical path through `ShotCommand`: hold → warmup → listening →
preview (p75 of qualified smoothed windows, last 250 ms) → release commits the same
command type; cancel/clap/timeout/interrupt/double-release all provably spend no
stroke. All verified **with a synthetic frame source**, not a real microphone.

### Automated evidence (this machine, engine build above)

- Unit: **138 passed, 0 failed** — shot math, scoring/stars/limits, sequential
  unlocks, cosmetics gating, voice math (dBFS incl. anti-phase stereo, smoothing,
  percentile, preview expiry, calibration derivation), save schema (progress +
  settings, incl. corrupt/future/PCM-injection fixtures), catalog validation,
  ShotCommand contracts, full state-machine transition table.
- Integration (real Jolt, 60 Hz, real CC01 scene): **75 passed, 0 failed** —
  spawn settle, one impulse/one stroke, zero/invalid power rejection, no shot
  while moving, cup completion + 3-star persistence, high-speed flyover rejection,
  OOB penalty + anchor reset, attempt-limit failure, pause-before-commit cancel,
  voice commit/cancel/interrupt/clap/double-release, full game_root scene smoke
  (HUD + camera + session), level teardown.
- Handoff package's own tools: `validate_package.py` PASS.
- Visual: windowed run on desktop (Vulkan, Forward Mobile renderer) with viewport
  capture — course, ball, flag, cup, aim guide, HUD all render and are readable.
  Captures: `docs/evidence/2026-09-06_cc01_ready_first_run.png` (first run —
  found the missing ball mesh) and `docs/evidence/2026-09-06_cc01_ready_final.png`.
  Reproduce: `ROAR3D_SCREENSHOT=/tmp/shot.png godot --path .`.

Reproduce everything: `tools/run_tests.sh /path/to/godot` (isolates `user://` per
run so tests never touch the real profile).

## Explicitly NOT tested / NOT done (do not claim otherwise)

- **No physical Android device work at all** (RB-002/003/005 open): microphone
  permission prompts, the OS mic privacy indicator after release, real capture
  latency, Bluetooth/wired route changes, sustained fps/thermal, signed APK. The
  mic-indicator gate in PRD §10 is unproven; do not ship “Mic off” copy.
- **Voice with a real microphone**: `AudioStreamMicrophone` + `AudioEffectCapture`
  path is implemented but never ran against hardware, even on desktop.
- **Renderer comparison** (RB-003): only Forward Mobile on one desktop GPU.
- **M2/M3/M4 not started**: no production art/assets, no Home hero/map/collection/
  calibration screens (graybox Home stand-in only), no moving gates/portals/bounce
  pads, holes CC02–PP06 have no scenes, no localization, no accessibility audit,
  no export templates/Android build.
- Tuning numbers are first-pass analytic values validated only against CC01
  (see `DECISION_LOG.md` D-003 for measured friction behavior and the completing
  power band); pars are the catalog's proposals, not playtested.
- CC01 is `graybox`, **not** `playtest_ready`/`validated`: no independent human
  solution run or usability evidence yet.

## Known gaps / next smallest tasks

1. RB-013 follow-up: follow-camera feel + overview on a real screen (logic exists,
   unreviewed visually beyond the static capture).
2. RB-021 calibration **UI** (the service-side stage recording works; no screen).
3. RB-037/038/039 obstacles, then RB-040+ hole authoring — catalog data ready.
4. Desktop manual play session for feel; record power bands per docs/02 §8.
