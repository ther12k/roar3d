# AI-agent implementation handoff prompt

Copy the block below into the coding agent after adding this extracted handoff package to the repository or accessible workspace. This prompt requests implementation; the package itself is not a completed game.

---

You are implementing **Roarball**, a mobile-first 3D mini-golf puzzle game. Use **Godot 4.7.2 stable with typed GDScript** and matching export templates. Use integrated Jolt after validating the physics spike. Build menus and gameplay in Godot. Do not use Flutter. Kotlin is optional only for a demonstrated Android capability gap, using Godot's v2 Android plugin architecture. Do not add a native module preemptively.

Read START_HERE.md, docs/01_PRD.md, docs/02_GAME_DESIGN.md, docs/03_TECHNICAL_ARCHITECTURE.md, docs/04_VOICE_INPUT_SPEC.md, docs/05_PHYSICS_AND_CAMERA.md, docs/06_UI_UX_SPEC.md, docs/09_ANDROID_KOTLIN_AND_BUILD.md, and docs/10_QA_AND_ACCEPTANCE.md before changing code. Inspect all seven PNG references and the keep/change table. Treat the written specs as authoritative over the images.

Inspect the actual repository first. Preserve existing useful work and identify conflicts. Do not claim there is already a playable project based on the planning files: the handoff contains no project.godot or final GLB assets. Establish a proper Godot project with versioned scenes/scripts/resources/tests.

MVP: two worlds and twelve authored holes; Lion/Panda/Robot cosmetics with identical physics; sequential completion unlocks; local durable progress; Android first; full equal Touch and Voice controls. No backend, accounts, ads, purchases, currency, hearts, daily challenges, multiplayer, AI service, speech recognition, or player-audio storage/upload.

Implement in evidence-gated stages:

1. M0: pin tools, identify real Android devices, run renderer/Jolt/microphone-lifecycle spikes. Observe native microphone privacy indicators on stop/pause/background. If built-in capture does not release the device correctly, document a minimal reproduction and evaluate the conditional adapter. Never label a processing stop as proof the microphone is off.
2. M1: complete one graybox hole end-to-end with aiming, Touch power, single physics impulse, settling, cup, fall reset, score, save, retry, and results. Then integrate Voice through the identical ShotCommand. Confirm denied microphone still permits full play.
3. M2: create one polished real mobile slice using optimized models and real Godot Controls, not composited mockup screenshots. Match mascot, hierarchy, color, course readability, and feedback while keeping scope small. Review performance and visual evidence before scaling art.
4. M3: implement reusable gate/portal/pad systems and author all twelve holes. Validate actual scene markers and independently solve each hole. The supplied catalog is design-only; do not mark it validated until evidence exists. Implement three cosmetics, map, settings, and robust saves.
5. M4: run automated and device QA, interrupted-save tests, privacy audit, accessibility/Touch parity, sustained performance, and signed Android smoke tests.

The core voice gesture is aim -> hold -> comfortable sound -> preview -> release to shoot. Cancel/no signal/timeout/background cannot consume a stroke. Displayed Shot power must match committed power. One shot ID produces at most one impulse and one stroke. Pause before physics commit cancels pending commands; pause after commit preserves the spent stroke. Never send microphone playback to the speakers.

Voice analysis is calibrated digital amplitude, not literal whisper recognition or real-world dB SPL. Use energy across stereo channels, bounded fresh windows, duration qualification, frame-time-aware smoothing, and the documented recent preview selection. Keep raw samples temporary and local. No per-frame audio/physics bridge to Kotlin. All cosmetics and input modes share physics and scoring.

Use tasks/backlog.json and individual issue files. Work in dependency order; RB IDs are not necessarily topological. Default scope is the 56 MVP tasks. RB-048 is conditional; RB-058–RB-060 are later. Update the decision log when a genuine constraint changes the plan, with rationale and regression impact. Do not silently change the stack or expand the feature list.

For each batch report: files changed, functional behavior achieved, actual commands/tests run and outcomes, actual engine/device/build versions, visual evidence for UI/art work, failures/untested areas, and the next smallest unblocked task. Do not claim device validation from synthetic tests, playable geometry from catalog metadata, or production UI from a concept screenshot. Keep the final repository reproducible and do not commit keys, credentials, fonts without approved licensing, recordings, or engine cache.

Start by reviewing the repository and implementing M0 plus the smallest complete Touch-based graybox loop. Request human intervention only for genuinely unavailable hardware/accounts/signing decisions; otherwise make bounded decisions consistent with the docs and record them.

---
