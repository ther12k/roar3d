# Implementation Status

Last updated: 2026-09-07 (round 5: audio/quality/lifecycle/stability batch) ·
Engine: Godot **4.7.2.stable.official.ed1daf0bf** (pinned in `ENGINE_VERSION`;
`tools/run_tests.sh` refuses to run on any other version).

## Round 6 — all twelve holes + obstacles complete (RB-037/038/039/041/042/043)

- **Obstacles**:
  - \`BouncePad\` (\`scenes/obstacles/bounce_pad.tscn\`): one-shot impulse on eligible contact with latch preventing re-boosting while resting (QA-028 verified).
  - \`MovingGate\` (\`scenes/obstacles/moving_gate.tscn\`): sync-to-physics sliding gate across local X; pauses with session without wall-clock jump (QA-029 verified).
  - \`PortalPair\` (\`scenes/obstacles/portal_pair.tscn\`): mapped velocity direction and preserved speed on transit; cooldown and exit overlap latch prevent endless loops (QA-027 verified).
- **Course Kit Expansion & 12 Authored Holes**:
  - All 12 level scenes authored using modular kit components and tested end-to-end.
  - Cloud Cliffs CC01–CC06 and Portal Peaks PP01–PP06 all status \`graybox\` in packaged catalog.
  - Two dedicated route suites: \`run_level_route_tests.tscn\` (CC01–CC03) and \`run_hole_route_tests.tscn\` (CC04–CC06, PP01–PP06). Every hole completes within par+1.
- **Test Gate**:
  - 8 headless suites running in \`tools/run_tests.sh\`: **876 automated tests, 0 failures** on Godot 4.7.2.

## Round 5 — services, stability, and audit (RB-025/029/024/054/053)

- **Nonverbal feedback audio (RB-025)**: four original synthesized cues
  (`assets/audio/*.wav`: putt/cup/fall/click) played through a round-robin
  pool on the Effects bus (which sends only to Master — unit-tested, never
  the mic path). Wired: shot committed → putt, cup → cup chime, fall → fall,
  Shoot button → click. Capture ducking (−18 dB on Music+Effects) restores
  exactly; saved volumes now apply at boot and on change.
- **Quality tiers (RB-029)**: `QualityDirector` autoload applies
  low/medium/high to 3D resolution scale (0.7/1.0/1.0), MSAA (off/off/2x),
  and shadow filter quality + atlas sizes via the actual 4.7.2 API
  (`SHADOW_QUALITY_HARD/SOFT_HIGH` — there is no `shadow_quality_set` in this
  build; pinned by usage). Applies at boot and on settings change; unknown
  tiers fall back safely. Device performance *measurement* remains RB-052.
- **Background/focus lifecycle (RB-024)**: integration test drives the real
  `NOTIFICATION_APPLICATION_PAUSED` path mid-capture: tree paused, capture
  closed, zero strokes, resume to READY, mic stays off.
- **Stability suite** (`run_stability_tests.tscn`, 5th suite): QA-016 thirty
  capture start/stop cycles (no duplicate owner, all reach Listening, clean
  after), thirty pause-during-capture cycles (no stroke leak, mic stays off,
  level teardown), QA-045 thirty level enter/exit cycles (node/memory growth
  bounded ≤8 nodes / <8 MB). Desktop-sim stability; device interruptions
  remain RB-002 matrix runs.
- **Known cosmetic warning**: at headless-test exit the engine may report
  2–4 leaked `AudioStreamPlayback` objects — playbacks still registered in
  the audio server thread when the process quits mid-mix. `AudioDirector`
  stops players and releases streams in `_exit_tree` (halves the count);
  the rest is a shutdown race with no functional impact.
- **Privacy/dependency audit (RB-053)**: `docs/PRIVACY_AND_DEPENDENCY_AUDIT.md`
  — no network/telemetry surface (grep evidence), PCM structurally
  un-persistable, single engine dependency, honest device-audit limits.

## Round 4 — Cloud Cliffs holes 2–3 (RB-040, issue #46)

- **CC02 "Soft Landing"** and **CC03 "Bank Buddy"** authored as the first
  kit-composed levels (straight/plateau/corridor/green instances, not
  sculpted turf). A bare `plateau` kit module was added for CC02's open-edged
  risk area. Packaged catalog: CC01–CC03 now `graybox`; CC04+ remain
  `design_only` and refuse to load.
- **Route suite** `tests/integration/run_level_route_tests.tscn` (112 checks,
  4th suite): marker contracts, CC02 staged newcomer route (par), finishing
  power-band sweep (3 powers all complete), open-edge fall + exactly-one-
  penalty recovery, strong-shot rail stop; CC03 bank redirect band, bank
  route within par, deliberate two-turn alternate route, per-level full-stack
  smokes (game_root READY + touch shot + teardown).
- Level capture tool `tools/capture_level.tscn` (LEVEL_ID env) — CC02/CC03
  ready-state PNGs are release assets.
- Route tuning notes: finishing putts need overrun room behind the cup
  (impulse floor ≈1.5 m/s makes sub-0.6 m taps arrive >1.2 m/s), so CC02's
  cup sits 1.2 m off the back rail; bank lines must clear the tee rail end
  (shallow diagonals) — head-on bank shots stop dead at restitution 0 by
  design (Jolt bounce=0), which is the "hit the wall at an angle" lesson.

## Round 3 — modular course kit (RB-028, issue #17)

- **Six kit modules** under `scenes/course_kit/` (straight, corner, green,
  ramp, rail, cliff_edge) on a 5 m grid with shared materials and wrapper-owned
  collision — the M2 base for authoring CC02+ without sculpting each course.
  Contract + provenance: `docs/ASSET_INVENTORY.md`; decisions D-017/D-018.
- **Seam regression suite** `tests/integration/run_course_kit_tests.tscn`
  (167 checks, third suite in `tools/run_tests.sh`): ray-probe seam contract
  per module, low/high-speed seam crossing, roll-distance bands, corner
  traversal without traps, ramp climb/descent across both seams, cliff-edge
  openness, green containment — all through the real `ShotCommand` → impulse
  path with per-tick containment sampling. Suite build caught and fixed a real
  authoring bug (green far rail spanned the course lengthwise).
- **Tuning log (D-018)**: measured flat deceleration is ≈ 0.55 + 0.08·v m/s²
  (authored 0.55 + engine rolling losses), probe committed as
  `tools/roll_decel_probe.gd`.
- Kit showcase evidence capture is a release asset (see `docs/evidence/README.md`).

## Round 2 — review findings fixed

All three blockers and the high-priority items from the 2026-09-06 source review:

- **Mic adapter API (blocker)**: `AudioEffectCapture.get_buffer()` is used; the
  nonexistent `get_frames()` call is gone. A unit test pins the ClassDB surface
  (`get_buffer` exists, `get_frames` does not) so an engine bump or bad edit
  fails immediately. Real-microphone behavior remains device-untested.
- **Pause/overview (blocker)**: single authority — `GameRoot.set_gameplay_paused()`
  / `toggle_overview()` cancel capture, update the session FSM, pause the tree,
  and toggle overlays in one path. HUD is `PROCESS_MODE_ALWAYS`; resume reaches
  `session.resume_session()` (previously the world unpaused with the session
  still PAUSED). UI tests pause/resume mid-capture through real key events.
- **Aiming (blocker)**: `session.can_aim()` forwarding added (aim input
  previously errored on any mouse event); HUD root is `MOUSE_FILTER_IGNORE` so
  playfield drags reach the aiming handler while controls consume their own
  input. Tested via pushed input events: empty-drag rotates aim; slider drags
  never do.
- **Voice onboarding**: gameplay loads the saved calibration profile; an
  uncalibrated hold opens a 3-step calibration sheet (room/soft/strong with
  "Use Touch instead" always visible) instead of silently mapping to zero
  power; permission is requested in-context before calibration (best-effort
  `OS.request_permission`, device behavior unverified). Profile derivation
  persists through SettingsStore only after the strong stage validates.
- **Window qualification**: analysis windows are built from a residual
  accumulator (complete 20 ms windows only), timestamps derive from the audio
  sample clock, and the "recent 250 ms" preview window is measured on that
  clock — the same waveform now qualifies identically delivered as 1×400 ms or
  20×20 ms (integration test). Overrun detection uses a per-hold baseline
  (engine counter is cumulative; `clear_buffer()` does not reset it) — an
  overflow invalidates that hold and the next hold works (tested).
- **Power display (FR-04)**: three-state — selected slider value (Touch,
  pre-shot; previously showed 0% with the slider at 50%), qualified preview
  (Voice capture), committed power (rolling). Tested.
- **Saves**: shared `SaveFile` helper with checked copy/rename; rename failure
  now reports failure and leaves the old primary intact; backup-copy failure
  is a surfaced warning. Failure-injection unit tests at each step (QA-038).
  Both stores refactored onto it.
- **Header layout**: fixed 48 px pause slot inside the safe area, ellipsized
  hole label, second-line status — verified at 390 and 360 logical px.
- **Theme**: gameplay HUD uses the shared RoarTheme (was default-styled).

Visual slice (bounded): light-blue sky environment, stone island sides under
the turf, lion-face ball (mane ring/eyes/muzzle, still static on the rolling
body — billboard face is future work), warmer directional light. Evidence
screenshots are release assets, not repo files:
[release v0.1.0-graybox-slice](https://github.com/ther12k/roar3d/releases/tag/v0.1.0-graybox-slice)
(390 ready/paused, 360 ready; `docs/evidence/README.md` explains regeneration).
Note: this machine's window capture renders darker than nominal values
(round-1 evidence shows the same trait); on-screen appearance is brighter than
the PNGs suggest.

Round-2 suite growth: 153 unit (was 138) + 121 integration (was 75), including
HUD-driven interaction tests (pause/overview/power/aim through real input
events and visible controls), calibration gating, overrun recovery, chunk
equivalence, and save-failure injection.

## What is done and verified (round 1 summary retained below)

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
  Captures are release assets:
  [release v0.1.0-graybox-slice](https://github.com/ther12k/roar3d/releases/tag/v0.1.0-graybox-slice)
  (`*_first_run` found the missing ball mesh; `*_final` is round 1).
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
