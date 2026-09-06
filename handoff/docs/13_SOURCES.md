# Sources and Verification Boundaries

All sources were checked September 5, 2026. Primary official engine/API documentation and the GitHub CLI manual are used for factual platform capabilities. Stable documentation can move; implementation must compare it with the pinned engine version.

References such as [S06] resolve below. Gameplay thresholds, budgets, scope, UI dimensions, level designs, and milestones are proposed product decisions, not externally measured facts. No page is reproduced in full.

## S01 — Godot official download archive

https://godotengine.org/download/archive/

Supports: Stable baseline: 4.7.2 listed with release date August 18, 2026. Version selection, not local binary verification.

## S02 — Godot overview of renderers

https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html

Supports: Mobile and Compatibility roles, features, and hardware tradeoffs.

## S03 — Godot using Jolt Physics

https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html

Supports: Integrated physics engine and relevant behavioral differences.

## S04 — Godot RigidBody3D API

https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html

Supports: Impulse control, CCD, rigid-body properties; not application-specific tuning.

## S05 — Godot AudioStreamMicrophone API

https://docs.godotengine.org/en/stable/classes/class_audiostreammicrophone.html

Supports: Microphone stream and enabled-input requirement.

## S06 — Godot AudioEffectCapture API

https://docs.godotengine.org/en/stable/classes/class_audioeffectcapture.html

Supports: Stereo floating-point capture frames, ring buffer, availability/discard APIs.

## S07 — Godot ProjectSettings API

https://docs.godotengine.org/en/stable/classes/class_projectsettings.html

Supports: Audio input permission caveats and mix/input rate distinctions.

## S08 — Godot OS API

https://docs.godotengine.org/en/stable/classes/class_os.html

Supports: Permission request semantics and platform limits.

## S09 — Godot exporting for Android

https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html

Supports: Export setup and Java/SDK guide; not current store-policy certification.

## S10 — Godot Android plugins

https://docs.godotengine.org/en/stable/tutorials/platform/android/android_plugin.html

Supports: v2 plugin architecture, Kotlin/Java methods, metadata and export packaging.

## S11 — Godot available 3D formats

https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html

Supports: Blender/glTF import workflow.

## S12 — Godot multiple resolutions

https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html

Supports: Viewport/stretch design; our pixel sizes and layout are proposals.

## S13 — Godot saving games

https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html

Supports: FileAccess/JSON persistence primitives; transactional protocol is our design.

## S14 — Godot exporting for iOS

https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html

Supports: Separate macOS/Xcode export track, outside default MVP.

## S15 — GitHub CLI issue create manual

https://cli.github.com/manual/gh_issue_create

Supports: Issue creation flags used by the optional local import helper.

## Supplied visual provenance

Seven existing Roarball concept PNGs were recovered from the active conversation files. They are copied without new generation or editing into design/references. No new images were generated for this documentation task. They are not layered art, GLB models, production textures, or tested gameplay screenshots.

## Not verified in this delivery

No Godot runtime, Android/iOS build, GPU benchmark, physical microphone capture, name clearance, store-policy compliance, Kotlin compilation, or level solvability has been verified. Package-level checks are reported separately and must not be confused with runtime QA.
