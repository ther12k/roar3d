# Delivery Plan and GitHub Workflow

## 1. Milestones without invented dates

| Milestone | Outcome | Exit gate |
|---|---|---|
| M0 Foundation & feasibility | Toolchain, device inventory, renderer/physics/capture spikes. | Capture lifecycle and mobile rendering risks understood. |
| M1 Playable loop | One graybox hole, Touch and Voice, scoring/reset/results. | End-to-end physical-device run. |
| M2 Polished vertical slice | One production-quality course plus real menus/HUD. | Approved visual/interaction evidence. |
| M3 MVP content & progression | Twelve holes, two worlds, three cosmetics, robust local saves. | Independent level validation and progression run. |
| M4 Hardening & Android release | Performance, accessibility, privacy, stability, signing. | Signed release candidate passes gate. |
| Later / conditional | Kotlin adapter only if justified; iOS/new content afterward. | Separate approved scope. |

Do not set dates until actual team capacity and spike evidence exist. Task sizes are relative complexity (S/M/L), not time estimates or a commitment. P0 denotes a gate/critical-path item; P1 is needed for MVP but can follow the core path; P2 is deferred or conditional.

## 2. Critical path

Toolchain -> device/renderer/audio spike -> shot state and Touch physics -> microphone calibration and unified command -> complete graybox loop -> polished slice -> remaining content -> stability/privacy/performance -> signed release.

Art can explore mascot/module silhouettes during M0, but do not build twelve elaborate environments before the renderer and visual-slice gates pass. UI theme and save domain work can proceed in parallel after contracts are stable.

## 3. Task package

`tasks/backlog.json` is the canonical proposed backlog. `tasks/backlog.csv` is a convenience export, not a native GitHub import promise. Individual Markdown issues contain goals, implementation steps, acceptance checks, dependencies, evidence, and scope.

`tools/import_github_issues.py` uses GitHub CLI, which supports creating issues with titles and body files [S15]. It defaults to a local preview with no network/writes. `--apply --repo OWNER/REPO` is required to create actual issues. Default import includes only MVP tasks. Native/platform-later work requires `--include-conditional` or `--include-later` explicitly.

The importer uses stable issue IDs in titles/bodies and checks existing repository issue titles on apply to avoid ordinary duplicate reruns. It does not create a repository, set milestones, link GitHub Projects, or close existing issues. Milestone/priority/dependency metadata remains in each body. Dependencies use stable RB IDs; actual GitHub issue-number links can be added after import.

## 4. Working conventions

Small pull requests should reference RB IDs and explain the reproduced behavior, implementation, tests, visual/device evidence, and remaining risks. The included `.github` templates are optional repository setup material.

Keep a decision log for engine changes, voice thresholds, physical tuning, art budgets, and scope changes. Do not bury a Kotlin integration decision inside a feature branch. An AI agent must report its actual tests and failures; it must not describe untested screenshots as a finished game.

## 5. First implementation batch

Start RB-001 through RB-006 and the relevant shot-domain tasks. Produce a device report before expanding to expensive art. Then implement the full one-hole Touch loop, add Voice through the same command, and submit the first visual slice. Use the exact handoff prompt in the root file to keep the agent focused.
