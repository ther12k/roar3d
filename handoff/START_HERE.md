# Roarball — Godot implementation handoff

**September 5, 2026 · Version 1.0 · Planning and design package**

A voice-powered 3D mini-golf puzzle game: aim with touch, set shot power with a comfortable sound, release to shoot. Touch-only controls are equal and permanent. Build the entire game in Godot with typed GDScript; use Kotlin only for a demonstrated Android platform gap.

## Read in this order

1. `docs/01_PRD.md` — scope, requirements, scoring, platform decisions, release gates.
2. `design/gallery.html` — seven existing concept mockups and explicit MVP changes.
3. `docs/03_TECHNICAL_ARCHITECTURE.md` and `docs/04_VOICE_INPUT_SPEC.md` — boundaries and input behavior.
4. `tasks/README.md` and `tasks/backlog.json` — 60 scoped tasks with dependencies and acceptance criteria.
5. `AI_AGENT_HANDOFF.md` — copy/paste implementation prompt and evidence standards.

`Roarball_Handbook.pdf` is the readable product/technical handbook. `handbook.html` is the searchable offline browser version. Markdown files remain the editable source of truth. Extract the entire ZIP before opening the gallery/HTML so relative images work.

## What is included

PRD; game rules; Godot architecture; voice/calibration, physics/camera, UI, asset pipeline, save/content, Android/Kotlin, QA, delivery, decisions/risks, and sources documentation. Seven existing Roarball concept PNGs. Design tokens. Twelve validated metadata briefs plus schema/examples. Sixty issue bodies with JSON/CSV exports and requirements traceability. An optional GitHub CLI importer that previews by default. Two illustrative GDScript math helpers, Python contract tests, and package validation tools.

## What is not included

This is **not a complete or runnable game/MVP**. There is no `project.godot`, playable course scenes, final GLB models, final audio, compiled Kotlin plugin, signed Android artifact, or tested iOS build. Existing mockups are concept references, not real engine screenshots. No fonts are bundled. No GitHub issues were created.

The implementation baseline is Godot 4.7.2 stable based on the official archive checked on this date [S01 in `docs/13_SOURCES.md`]. Engine/runtime/mobile tests must be performed by the implementation team. Package-level checks do not prove that the game builds or plays well.

## MVP scope

Two worlds, twelve authored holes, three purely cosmetic balls, local progress, full Voice/Touch modes, no ads/accounts/currency/shop/daily challenge. Android first; iOS later. The older mockups contain extra features; follow the written scope where they conflict.

## Local validation and optional issue creation

```bash
python3 tools/validate_package.py
python3 tools/test_contracts.py
python3 tools/import_github_issues.py
```

These commands require Python 3.10+ and do not create remote issues. The optional JSON Schema engine is listed in `tools/requirements.txt`; semantic validation works without it. No Godot runtime is bundled or invoked by these commands.

To explicitly create the 56 MVP issues in a repository you control after reviewing the preview:

```bash
python3 tools/import_github_issues.py --apply --repo OWNER/REPO
```

GitHub CLI must be installed/authenticated. Conditional Kotlin and later tasks are excluded unless explicitly requested. The importer does not create repositories, labels, milestones, project boards, or releases. See the tool's help and `tasks/README.md`.

## Non-negotiable implementation boundaries

Do not require screaming; do not store/upload voice; verify the OS mic indicator rather than only stopping analysis. Do not replace the world with screenshot artwork. Do not copy coins/hearts/gems from old mockups into the MVP. Do not introduce Flutter or Kotlin without a documented need. First prove one complete graybox hole, then one polished mobile slice, then scale to twelve holes.
