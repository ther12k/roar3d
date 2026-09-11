# Store Listing Draft (RB-056 prep — NOT approved store copy)

Working materials for the eventual Play submission. Everything here describes
**implemented behavior only**; claims match the shipped build (v0.1.0-rc1,
`fa94f27`). Items marked **[PUBLISHER DECISION]** or **[UNRESOLVED]** require
a human/publisher and cannot be closed from this document.

## Screenshots (real engine builds, 390×844, reproducible)

All in `assets/marketing/screenshots/`, generated via
`tools/capture_level.tscn` / `tools/replay_hole.tscn` against a real game
scene — no concept art, no mockups:

| File | Shown |
|---|---|
| `01_cc01_first_putt.png` | First hole, Touch HUD, aim guide, lion mascot |
| `02_cc03_bank_buddy.png` | Bank-shot hole layout |
| `03_cc04_little_leap.png` | Ramp-leap hole (signature jump) |
| `04_results_3stars.png` | Hole-complete flow, 3-star scoring (display payload synthetic; no save writes — capture tool) |
| `05_pp01_portal_dusk.png` | Portal Peaks world, dusk atmosphere |
| `06_roar_loft_airborne.png` | Roar shot mid-air, jump prompt live |
| `07_pause_settings.png` | Pause sheet: input switch, volumes, quality, reduced motion |

Regenerate after any accepted visual change; a screenshot set must always
postdate the build it advertises.

## Listing text (draft)

**Title:** Roarball — **[UNRESOLVED: name clearance]** (working name; no
trademark search performed yet).

**Short description (≤80 chars):**
`Mini-golf on floating islands: putt with your voice — whisper rolls, ROAR jumps.`

**Full description:**
Roarball is a mobile-first 3D mini-golf puzzle game. Twelve floating-island
holes across two worlds — Cloud Cliffs and Portal Peaks — with banks, ramps,
bounce pads, moving gates, and portals.

- **Two ways to play.** Drag to aim and pull back like a slingshot, or set
  your shot power with your voice: whisper to roll, speak harder to charge,
  and ROAR to launch over gaps.
- **One jump per landing.** Tap while the ball rolls for a mid-roll hop —
  spend it wisely.
- **Real holes.** The cup is a genuine recessed cavity: lip-outs, rim
  rattles, and honest drops.
- **Offline by design.** Progress saves on your device. No accounts, no ads,
  no in-app purchases, no coins or hearts.
- **Your voice stays yours.** Microphone audio is processed live on-device
  and is never recorded, stored, or uploaded.

## Data safety / privacy copy (grounded in implementation)

Source of truth: `docs/04_VOICE_INPUT_SPEC.md`, `docs/08_CONTENT_AND_SAVE_DATA.md`,
`docs/ASSET_INVENTORY.md`.

- **Data collected:** none. No analytics, no identifiers, no network play
  services. Save progress is local (`user://progress.json`) and never synced
  or uploaded.
- **Microphone:** accessed only during an explicit capture hold (calibration
  or a shot). Frames are processed in memory for live loudness analysis and
  discarded; PCM is never persisted, and the capture bus routes to a muted
  sink so mic audio can never reach the speakers. The OS microphone indicator
  is expected to show **only** while a hold is open — verified behaviors and
  the on-device checklist live in `docs/HARDWARE_ACCEPTANCE.md`.
- **Permissions:** `RECORD_AUDIO` only, requested at first Voice-mode use;
  the game is fully playable in Touch mode after denial.
- **Third-party code/assets:** engine (Godot 4.7.2, MIT) plus first-party
  assets only — every runtime asset is original to this repo or CC0 (see
  `docs/ASSET_INVENTORY.md`, `assets/models/lion_ball_provenance.md`).

## Policy findings (before submission — blockers recorded)

1. **Target API gap [BLOCKER for Play submission]:** the Android export
   preset has `gradle_build/target_sdk=""` (unset — defers to the Godot
   Gradle template default, not verified in a built artifact). Google Play
   requires **target API 36 (Android 16) for all new apps and updates since
   2026-08-31**. Before any submission: set/verify target SDK 36 in the build,
   produce a signed build, and record `aapt dump badging` output showing
   `targetSdkVersion: 36` as evidence.
2. **Name clearance [UNRESOLVED]:** "Roarball" has had no trademark/usage
   search. PRD risk, still open.
3. **Device validation [UNRESOLVED]:** mic lifecycle, renderer benchmark,
   and sustained performance remain unverified on physical hardware
   (issues #2, #4, #6, #53; procedure: `docs/HARDWARE_ACCEPTANCE.md`).
4. **No compliance guarantee:** passing this checklist asserts nothing about
   store approval; policy review by a human remains required.

## Publisher decisions to record (gates #47 closure)

- [ ] Final app name (clearance result).
- [ ] Audience classification / content rating questionnaire answers.
- [ ] Support contact (email/site).
- [ ] Store asset finals from the screenshot set above (any resize/crop).
