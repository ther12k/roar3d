# Privacy, Permissions, and Dependency Audit (RB-053)

Audit date: 2026-09-07 · Engine: Godot 4.7.2.stable (pinned in `ENGINE_VERSION`).
Evidence is greppable from the repo; commands are listed per claim.

## 1. Network / telemetry inventory

**Claim: the game makes no network connections and contains no analytics,
ads, crash-reporting, or tracking SDKs.**

- `grep -rn "HTTPRequest\|WebSocket\|StreamPeerTCP\|ENetMultiplayer\|XMLHttpRequest\|JavaScriptBridge" scripts/ scenes/` → no matches in game code.
- `addons/` directory does not exist (no third-party plugins).
- The only runtime downloads are none: assets are packaged (see
  `docs/ASSET_INVENTORY.md` — every asset is original and hand-authored).
- The MVP has no server, account, leaderboard, or analytics event collection
  by design (docs/08 §7).

## 2. Microphone and privacy-sensitive behavior

- **Only sensitive permission used:** microphone, requested exclusively
  through Godot's `OS.request_permission("RECORD_AUDIO")` path
  (`scripts/platform/platform_adapter.gd`), and only after the player
  explicitly chooses Voice (never at boot — `main_boot.gd` performs no mic
  work).
- **No PCM retention:** `AudioEffectCapture` buffers live only inside
  `VoiceInputService` for the duration of a hold; `end_capture()` clears the
  buffer, history, and residual windows. Nothing from the microphone is ever
  written to disk or to a log: `save_schema.gd` validates every persisted
  payload and rejects unknown keys, so a calibration/settings/progress file
  structurally cannot contain audio data (unit-tested, incl. a PCM-injection
  fixture).
- **Stored calibration content:** three numbers (`gate_db`, `lower_db`,
  `upper_db`) plus a non-sensitive algorithm version. No device identifiers
  are read or stored anywhere.
- **Mic-off copy policy:** the game never claims "Mic off" in UI copy; the
  OS-level indicator behavior after release is unverified until the device
  spike (RB-005 / docs/04 §2) — deliberately untested claims are not shipped.
- **Monitoring path:** the mic capture bus routes to a muted sink; game
  effects live on the Effects bus sending only to Master (unit-tested), so
  the game cannot feed itself power through speakers (QA-017 design stance),
  and game audio ducks −18 dB while a hold is open (RB-025, unit-tested).

## 3. On-disk footprint (`user://`)

| File | Content | Validation |
|---|---|---|
| `progress.json` (+ `.bak`) | schema-versioned best results/completions | strict v1 schema, checked replace |
| `settings.json` (+ `.bak`) | input mode, volumes, flags, quality, calibration numbers | strict schema, checked replace |

No other files are written. No caches, no logs shipped in production builds,
no crash attachments. Write/recovery algorithm and failure-injection tests:
`tests/unit/test_save_file.gd` (QA-036/037/038 coverage).

## 4. Dependency and provenance inventory

- **Engine:** Godot 4.7.2.stable.official.ed1daf0bf — the only dependency.
  Pinned via `ENGINE_VERSION`; `tools/run_tests.sh` refuses other versions.
- **Third-party assets:** none. All meshes/materials are Godot primitives;
  the four sound effects are synthesized tones generated for this repo
  (`assets/audio/*.wav`, original, documented in `docs/ASSET_INVENTORY.md`).
- **Fonts:** engine default only (no font binaries committed).
- **Name clearance:** the working name "Roarball" is NOT cleared for
  commercial use (PRD risk; RB-056 tracks the store/legal work).

## 5. Remaining limits (do not over-claim)

- This audit covers the repository and desktop/headless runs. A device
  audit — OS mic indicator observation, permission-revocation recovery, and
  network-traffic capture on a real phone — is part of the RB-002 device
  matrix and RB-005 lifecycle spike, which remain open by design until
  hardware is available.
- QA-047 (storage/network/log inspection on device) cannot be evidenced
  from this environment.
