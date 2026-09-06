# Technical Architecture

## 1. Stack and boundaries

Use the standard Godot 4.7.2 editor/export templates and typed GDScript. Start with integrated Jolt, not an external Jolt addon [S01, S03]. Godot renders both world and UI; there is no Flutter dependency. Build authoring assets in Blender and export `.glb` for reproducible import [S11]. Kotlin is introduced only after a platform requirement passes the decision gate in document 09.

Pin engine version in `ENGINE_VERSION`, CI, export templates, and the contributor guide. A version bump is a tested change, not an automatic update. The exact Android SDK/Gradle requirements must be captured from the selected export template at implementation time [S09].

## 2. Proposed repository structure

```text
project.godot
ENGINE_VERSION
scenes/app/             # boot, loading, home, map, settings
scenes/game/            # gameplay root, ball, camera, cup, HUD
scenes/levels/          # CC01.tscn ... PP06.tscn
scenes/obstacles/       # reusable gate, pad, portal
scripts/domain/        # shot math, scoring, save migrations
scripts/game/          # session controller and scene adapters
scripts/audio/         # VoiceInputService and calibration
scripts/platform/      # GodotPlatformAdapter; native fallback
resources/             # themes, tuning .tres, catalog, cosmetics
assets/models/         # imported .glb; no baked UI text
assets/audio/          # original/licensed music and effects
assets/localization/   # keyed strings
addons/                # empty unless an approved dependency exists
android/plugins/       # absent until a Kotlin decision is approved
tests/unit/
tests/integration/
tests/fixtures/
tools/
```

Keep imported art separate from hand-authored wrapper scenes. A re-export must not erase collision, signals, or spawn markers. Use Git LFS for large art sources once the team chooses its repository policy; do not commit engine caches or signing secrets.

## 3. Runtime responsibilities

**AppRouter** owns top-level transitions and one active GameSession. **SettingsStore** owns user preferences and calibration. **ProgressStore** owns completed results and cosmetics. **AudioDirector** owns music/effects ducking, not microphone permission. These may be small autoload services; do not make every gameplay node global.

**GameSessionController** is the sole shot/stroke authority. **InputCoordinator** transforms touch/voice into intent. **VoiceInputService** owns capture buffers and explicit listening state. **BallController** applies accepted impulses and reports settlement. **LevelController** owns spawn anchors and win/fall routing. **CameraRig** consumes session state. **HUDPresenter** displays immutable view data and emits UI intent.

The UI never writes ball velocity, changes stroke totals, or saves best scores directly. A portal cannot increment score. The microphone service never launches the ball. This separation keeps repeated signals and platform callbacks from becoming duplicate shots.

## 4. Scene composition

```text
GameRoot (Node)
  GameSessionController (Node)
  InputCoordinator (Node)
  WorldRoot (Node3D)
    LevelInstance (Node3D)
      Visuals (Node3D)
      StaticCollision (Node3D)
      Spawn (Marker3D)
      Cup (Area3D + visual cup)
      SafeAnchors (Node3D)
      KillVolume (Area3D)
      Obstacles (Node3D)
    Ball (RigidBody3D)
      CollisionShape3D (sphere)
      VisualPivot (Node3D)
    CameraRig (Node3D)
      Camera3D
    Lighting (Node3D)
  GameUI (CanvasLayer)
    SafeAreaRoot (Control)
      HUD (Control)
      PauseLayer (Control)
      ResultLayer (Control)
```

Use `Control` containers and theme resources for UI rather than a single composited mockup PNG [S12]. Place scene art under Node3D and labels/buttons under CanvasLayer. Collision ownership belongs to wrapper scenes, not arbitrary mesh names.

## 5. State machine

Top-level states: Boot, Home, Loading, Playing, Results, RecoverableError. Inside Playing: Intro, Ready, CaptureWarmup, Capturing, CommitPending, Rolling, Settling, Resetting, Paused, Complete, Failed.

| Current | Event / guard | Next / effect |
|---|---|---|
| Ready | valid mic press, consent/calibration ready | CaptureWarmup; allocate session token, lock aim |
| CaptureWarmup | first fresh frames, still held | Capturing; show Listening |
| Capturing | valid release and stable signal | CommitPending; close capture; queue one ShotCommand |
| Capturing | cancel, timeout, focus loss, route change | Ready or Paused; close capture; no stroke |
| Ready | positive touch power + Shoot | CommitPending; queue same command type |
| CommitPending | valid session token at physics tick | Rolling; +1 stroke, apply one impulse |
| Rolling | below thresholds with support | Settling |
| Settling | stable duration reached | Ready; update safe anchor |
| Rolling / Settling | fall | Resetting; +1 penalty once |
| Rolling / Settling | eligible cup entry | Complete; persist completion once |
| Resetting | verified reset finished, limit not exceeded | Ready |
| Any playing state | pause/background | Paused; preserve simulation snapshot, cancel uncommitted shot |
| Paused | resume | prior non-capture state, never auto-restart mic |

An accepted but not yet applied command is canceled if background/pause happens before the physics tick. Once applied, the stroke remains spent. Resume a Rolling ball with its paused state, not a fresh impulse. Intro/Ready/Capturing cannot win from stale cup signals.

## 6. Data contracts

`ShotCommand`: session_id, shot_id, source (voice/touch), normalized_power, direction_world, level_id, tuning_version. The main thread creates it after validation. No PCM or microphone identity is attached.

`ShotResolved`: shot_id, outcome (rest/cup/out_of_bounds), resting_transform, strokes_total. Resolution accepts each shot_id only once. Compound signals from kill volume and kill plane coalesce.

`LevelResult`: completion_id, level_id, content_version, completed, strokes, par, stars, elapsed_active_seconds. Time is informational, not a rank. ProgressStore rejects duplicate completion IDs and does not overwrite a better result.

`VoiceStatus`: capture_id, phase, relative_live_level, preview_power, signal_valid, error_code. Errors include permission_denied, no_input, too_noisy, route_changed, interrupted, timeout, and buffer_overrun. UI maps error codes to localized copy.

## 7. Dependency and event policy

Use typed signals for one-way events and explicit methods for commands. Pass dependencies through constructors/setup methods or exported node references where practical. Avoid stringly typed global event buses. Never connect the same handler on each scene re-entry without disconnecting it.

Main-thread code owns the scene tree. DSP over short buffers should remain bounded; introduce a worker only after profiling. Native callbacks must marshal safely to Godot's expected thread rather than mutate scenes from an Android audio callback. No per-frame Kotlin bridge messages are needed for default capture.

## 8. Loading, saves, and failure recovery

Validate catalog data before displaying locked levels. Map validated level IDs to a packaged allowlist of `.tscn` resources. Do not instantiate arbitrary paths from a save file. Clear the previous LevelInstance, capture, pending commands, and listeners before loading a new session.

Read local settings/progress using a versioned schema, strict type/range validation, and a last-good backup. FileAccess and JSON are supported building blocks, not an automatic transactional database [S13]. See document 08 for replacement/recovery rules.

If loading fails, show Retry and Home. Do not show a fake course or silently unlock the next hole. Errors should include a non-sensitive diagnostic code usable by QA.

## 9. Rendering approach

Choose the Mobile renderer as the initial 3D candidate, then compare with Compatibility on target devices [S02]. Keep visual requirements within a shared, deliberately modest feature set: static lighting where possible, simple PBR/stylized materials, one main shadow light, modest particles, and cheap waterfall ribbons.

Quality tiers may change resolution scale, particles, foliage, and shadows. They must not change collision, input timing, physics tick rate, or scoring. Changing renderer is a tested configuration change; do not assume that a live low/high quality toggle can replace the rendering backend safely.

## 10. Testing seams

Pure domain functions cover voice normalization, power curve, scoring, unlocks, and save validation. Integration scenes cover impulse, settlement, cup, portal, and reset behavior. UI tests cover safe area, focus, selected/disabled states, and screen navigation. Device tests cover rendering, latency, native privacy indicators, and interruptions.

This handoff is a specification and reference-code package. It does not include a complete Godot project, imported game assets, or a tested Android binary. Do not mark a task Done solely because a design document or interface stub exists.
