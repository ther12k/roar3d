# Android Delivery, Optional Kotlin, and Build Runbook

## 1. Default: no Kotlin module

Implement gameplay, HUD, calibration logic, input state, saves, and scene flow in typed GDScript. The normal Godot Android export workflow does not require the team to build a separate Kotlin app [S09]. Do not create a Flutter host or Android Activity wrapper just to keep a familiar language in the stack.

Kotlin becomes eligible only for a demonstrated Android capability gap: microphone acquisition/release control that the built-in path cannot satisfy, a required native settings/deep-link action unavailable through a supported API, or a later explicitly approved Android SDK integration. Ads, billing, notifications, and Play services are not MVP requirements.

## 2. Native-integration decision gate

First create a minimal reproduction on the pinned Godot version and two physical Android devices. Record expected behavior, observed driver/permission/lifecycle behavior, and why the supported GDScript/engine path cannot meet it. Check if the problem is misuse of audio buses or permission timing rather than a missing API.

Approve a native adapter only if it fixes the documented gap with bounded scope, adds no required network service, and preserves a complete Touch fallback. An Android-specific solution does not automatically solve iOS. Add the platform boundary now; add native implementation only when evidence justifies it.

## 3. Optional Kotlin contract

Use Godot's v2 Android plugin architecture and the version-matched Godot Android library [S10]. Extend GodotPlugin, annotate exposed methods with `@UsedByGodot`, declare plugin metadata, and package through the v2 export-plugin workflow. Method names are exact; do not assume camelCase/snake_case conversion [S10].

Proposed singleton name: `RoarballAndroid`. GDScript accesses it behind a PlatformAdapter after `Engine.has_singleton(...)`. Missing plugin means supported fallback, not a crash. If the plugin owns mic capture, expose permission/capture/error state and bounded RMS summaries; it should not move the ball or mutate UI nodes.

Suggested contract (design only; signatures must be finalized against the selected plugin template):

```text
getCapabilities() -> Dictionary
requestMicrophonePermission(requestId: String) -> void
startLevelCapture(captureId: String) -> void
stopLevelCapture(captureId: String) -> void
openAppSettings() -> void
signals:
  permissionResult(requestId, granted, canAskAgain)
  captureStarted(captureId)
  levelWindow(captureId, rms, clipRatio, windowSeconds)
  captureStopped(captureId)
  platformError(requestId, code)
```

The Android adapter releases its recorder on stop, pause, destruction, and errors. Never hold both Godot and native microphone capture simultaneously. Bound buffering and make stop idempotent. Marshal callback data to the appropriate engine thread; do not pass raw PCM through a UI bridge at 60 fps. Do not claim native noise cancellation without device evidence.

No compiled Kotlin library, Gradle module, or native capture implementation is included in this planning package. Conditional task RB-048 covers it and is excluded from the default import set.

## 4. Permission behavior

Declare the microphone permission in the Android export configuration. Request it only after the player's pre-prompt choice and handle the asynchronous result. Godot's OS permission API documents that a true return can mean already granted, not a completed new dialog [S08]. Test the selected version; do not use obsolete short permission-name examples blindly.

Fresh denial, permanent denial, revocation in Settings, and revocation while paused have explicit UX. Touch must remain available. Avoid permission requests at boot. Verify the merged manifest contains only permissions required by the actual shipped features.

## 5. Toolchain and export

Pin Godot 4.7.2 and matching export templates [S01]. Use the selected version's Android export guide for Java/SDK/tooling; the stable guide checked for this document recommends OpenJDK 17 [S09]. Capture the exact SDK packages, build tools, NDK, Gradle and Android plugin versions in the repository once the release template is installed. Do not guess a dependency matrix from old snippets.

The engine's build requirements and the store's target-API policy are separate. Check the current store policy before each submission; this document does not assert that a particular API level is sufficient for September 2026 publishing. Choose final minimum device/API support after the physical-device gate.

Create a debug APK for device testing and a signed release artifact using the store-appropriate format. Use the final publisher-owned package identifier, not an assumed ShieldTech domain. Keep keystores/passwords in secure release storage and CI secrets, never this ZIP or Git.

## 6. Build sequence

1. Install the pinned editor and matching templates; record `godot --version`.
2. Import the project headlessly once, then run pure GDScript and integration tests.
3. Validate catalog/schema/scene markers and check missing assets.
4. Export debug Android build with the selected renderer and microphone permission.
5. Run the device gate: frame timing, microphone lifecycle, no-feedback audio, pause/resume, and repeated scene entry.
6. Freeze toolchain and content version; produce signed release build only after QA approval.
7. Install the release build, not only the debug build, and repeat smoke/permission/save tests.

Signing details are intentionally absent. Use a clean CI workspace with no production credentials on pull requests. Engine caches, generated build folders, export credentials, and local saves must not be committed.

## 7. Suggested CI jobs

Static/content validation: JSON schema, dependency graph, localization keys, missing file references, script parse checks. Domain tests: shot power, scoring, unlocks, save migrations. Integration tests: small headless scenes where applicable. Device performance/audio tests are separate; headless success cannot certify GPU/audio behavior.

Use a documented headless import/check/test command suited to the implemented project. The reference `.gd` files in this package are illustrative and have not been parsed by a Godot executable here. Do not copy a green Python validation badge into a claim that the Android game compiles.

## 8. Optional iOS track

Godot documents a standalone iOS export workflow through macOS and Xcode [S14]. Kotlin does not provide iOS integration. If native iOS capture is required, it needs its own Swift/Objective-C boundary and tests. iOS build/signing/permission work is post-MVP and not a reason to embed Godot in Flutter.
