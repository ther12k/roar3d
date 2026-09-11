# Roarball

Mobile-first 3D mini-golf puzzle game. Aim with touch, set shot power with a
comfortable sound (or an equal Touch slider), release to shoot. Godot 4.7.2
stable, typed GDScript, integrated Jolt physics. Android first, iOS later.

This repository is implementation work driven by the planning package in
[`handoff/`](handoff/START_HERE.md). The handoff documents are the product and
technical source of truth; where code and handoff disagree, fix one of them
deliberately and record it in `docs/DECISION_LOG.md`.

## Current state

Feature-complete prototype: 12 authored holes (CC01–CC06, PP01–PP06) with
obstacles (banks, cliffs, ramps, bounce pads, moving gates, portals), Touch
slingshot + Voice input, roar-loft shots, mid-roll jump, physically recessed
cup, progression/unlocks, and a production GLB lion mascot. All 8 headless
test suites pass on every push (see `.github/workflows/tests.yml`); run them
locally with `tools/run_tests.sh`.

Still **device-unverified** (tracked in GitHub issues): physical-Android
microphone lifecycle, renderer benchmark on the device matrix, sustained
mobile performance/thermal, and all-hole human playtesting. Android build
tooling exists (`tools/build_android.sh`) but devices have not validated it.
See [docs/IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md) for the
detailed verified/unverified split.

## Requirements

- Godot **4.7.2 stable** (exact version pinned in `ENGINE_VERSION`).
  Download the official Linux/editor build and matching export templates.
- Python 3.10+ only for the handoff package tools (not needed to run the game).

## Commands

```bash
# Import resources (fresh checkout / CI)
godot --headless --path . --import

# Run domain + state machine + save + voice-math unit tests
godot --headless --path . res://tests/unit/run_tests.tscn

# Run gameplay integration tests (physics loop, cup, out-of-bounds, limits)
godot --headless --path . res://tests/integration/run_integration_tests.tscn

# Both suites
tools/run_tests.sh

# Play (desktop, mouse emulates touch)
godot --path .
```

`godot` on PATH must be 4.7.2-stable; `godot --version` is printed by
`tools/run_tests.sh` as evidence.

## Layout

Follows `handoff/docs/03_TECHNICAL_ARCHITECTURE.md` §2:

- `scenes/app/` boot + home; `scenes/game/` gameplay root, ball, HUD;
  `scenes/levels/` authored holes; `scenes/course_kit/` shared course modules;
  `scenes/obstacles/` gates, pads, portals.
- `assets/models/` production mascot GLB + provenance; `assets/audio/`,
  `assets/locale/` packaged audio and translations.
- `scripts/domain/` pure, engine-independent logic (shot math, scoring,
  progression, calibration math, save schema, catalog validation).
- `scripts/game/` session controller, state machine, ball, level, input,
  camera, HUD. `scripts/audio/` voice capture service and frame sources.
- `scripts/app/` autoload services (router, progress, settings, audio buses).
- `resources/catalog/level_catalog.json` packaged copy of the level metadata
  (game copy; the handoff original stays untouched).
- `tests/unit/`, `tests/integration/` headless suites; no editor addons.
- `tools/` asset generators (mascot GLB, music, SFX), capture harnesses,
  Android build script, and the CI test runner.

## Non-negotiables (from the handoff)

No screaming required; no voice storage/upload; only the OS mic indicator
proves release; no mockup screenshots as UI; no coins/hearts/shop/daily
challenges; Touch and Voice share one `ShotCommand` and scoring path.
