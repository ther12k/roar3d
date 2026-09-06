# Game Design and Rules

## 1. Design pillars

**Precision before loudness.** Every course must reward at least one deliberately restrained action. A stronger voice does not grant a better score; it supplies a different physical tool.

**Readable physical play.** Give the player a clear launch point, a visible or discoverable landing area, and an understandable obstacle. No foreground foliage on collision edges. Interactive hazards use consistent silhouettes and feedback.

**Playful recovery.** Falls are short, comprehensible setbacks, not punishment screens. Retry is immediate, free, and does not reset world progress. Celebrate smart short shots as much as long jumps.

**Small authored spaces.** Build compact islands from a modular kit. Distant islands are scenery, not mandatory simulated geometry. A complete course should be understood through one camera overview.

## 2. Shot interaction

1. In Ready, drag on the playfield to change horizontal aim; the bottom tray remains stationary.
2. Hold the mic button to enter CaptureWarmup, then Capturing after samples are valid. Lock aim for the hold. The pointer that started the interaction owns it.
3. Speak softly or comfortably strongly. Show a live level plus a labeled “Shot power” preview. Only the preview becomes the shot.
4. Release within the active hit region to commit. Drag into the explicit cancel region and release to abort. A hold above three seconds cancels with “Try a short sound.” It never fires automatically.
5. Consume the immutable ShotCommand on the next physics tick, then disable shooting until supported and settled.

No signal, a canceled gesture, losing focus, or an audio-route change returns to Ready with zero additional strokes. During Capturing, camera gestures and other shot controls are disabled; Pause and Cancel remain available.

Touch mode uses drag-to-aim plus a 0–100% slider and Shoot. Zero power cannot fire. An accessibility alternative to hold is a tap-to-start, tap-to-confirm voice interaction with a clear Cancel button; introduce only after the default loop passes tests. Both paths use the same ShotCommand and stroke rules.

## 3. Course mechanics

| Mechanic | MVP behavior | Feedback |
|---|---|---|
| Turf | Predictable rolling surface with authored resistance. | Soft roll sound; grass color. |
| Rail/wall | Solid bank surface; no hidden collision protrusions. | Brief collision sound and squash accent. |
| Ramp | Transfers horizontal momentum into a jump through geometry. | Clear chevrons and visible landing platform. |
| Moving gate | Fixed-period kinematic bumper; timing affects route. | Visible travel range; no lethal spikes in early holes. |
| Portal pair | Moves ball to paired exit once, transforms direction, preserves allowed speed. | Matching color, arrows, short pulse. |
| Bounce pad | Adds a configured one-shot impulse on entering. | Compression then bounce cue. |
| Cup | Low-speed entry captures ball and ends attempt. | Distinct ring, flag, completion animation. |
| Void | One penalty; reset to last safe rest anchor. | Short fall/fade; “+1 penalty” once. |

Avoid moving platforms as resting surfaces in MVP. Avoid physics-driven chains or destructible meshes. Curved art ramps may use simplified segmented collision surfaces with no seams large enough to trap a ball.

## 4. Rules and numerical tuning

The first tuning pass uses one world unit as one meter, a 0.25 m sphere radius, 1.0 kg mass, gravity 9.8 m/s², and a 1.5–10.0 N·s impulse range. These are starting values, not realistic golf simulation or tested balance.

Normalized power p is in [0, 1]. Reject p <= 0. For accepted p, impulse magnitude is `1.5 + (10.0 - 1.5) * p^1.6`. Apply once along a normalized horizontal direction tangent to the world XZ plane. Ramps and pads create vertical movement; the standard shot adds no arbitrary upward boost.

Power curve tuning must be versioned with content. Re-run authored solutions after changing ball radius, collision, mass, resistance, physics engine, impulse curve, or physics tick rate. Cosmetics cannot override these parameters.

Par is authored from playtests. Initial pars in the content catalog are proposals. The reference solution need not be the only solution. Do not promise exact cross-platform physics determinism or replay by input alone.

## 5. Rest, failure, and completion

Ready requires translational speed below 0.06 m/s, angular speed below 0.3 rad/s, stable support on allowed static terrain, and 0.4 seconds of continuous settlement. The system must not freeze a ball that is still descending or on an ineligible slope. Minor cosmetic animation can continue after physical rest.

A terminal fall occurs in the kill volume or below the authored kill plane. A watchdog also offers recovery if the ball remains moving with no useful progress for 20 seconds; it does not silently teleport a possibly valid long roll. Player-confirmed stuck recovery uses the same +1 penalty rule. Timeout during background is not a fall.

For cup capture, require horizontal center distance <= 0.28 m, ball center within the authored cup height band, and speed <= 1.2 m/s. Test these candidate thresholds with actual cup geometry. Do not let a ball passing high above the cup win. Completion owns its own idempotence key and suppresses any subsequent fall signal from the celebration animation.

## 6. Level progression

Cloud Cliffs: CC01 First Putt; CC02 Soft Landing; CC03 Bank Buddy; CC04 Little Leap; CC05 Gate Timing; CC06 Cliff Combo.

Portal Peaks: PP01 Through the Ring; PP02 Exit Angle; PP03 Spring Step; PP04 Portal and Pad; PP05 Gate Escape; PP06 Royal Route.

Each level card in `content/level_catalog.json` records the teaching goal, layout brief, route alternatives, common failure, and validation checklist. Three internal graybox diagnostic scenes are also required: straight roll distance, ramp/CCD collision, and cup capture. These are engineering tools, not additional advertised holes.

## 7. Camera and emotional feedback

Use a consistent three-quarter perspective with the ball in the lower-middle playable zone and the target in the upper area. Ready camera moves slowly and stops before capture begins. Follow mode tracks rolling without hiding the next relevant surface. Overview is a deliberate inspection action, not a mandatory free-camera skill.

A face mesh or decal may be presented toward the camera independently from the sphere's rolling transform for readability. This is a cosmetic convention; the collision body still behaves as a sphere. Avoid rotating a large protruding mane collider with every bounce.

Provide quiet, short sonic feedback. Suppress shot-button clicks, voice playback, and music during capture so the game does not power itself. The lion's roar sound plays only after input has been closed. No screen shake is necessary for ordinary putting.

## 8. Balancing review

A hole fails design review if a newcomer cannot distinguish the route from background scenery, if perfect loudness is required to cross an unavoidable gap, if the cup is hidden by HUD, if one missed shot causes an inescapable position, or if touch users cannot earn the same reward.

Record minimum/recommended/maximum successful power bands for major shots, not only a single ideal value. For introductory holes aim for forgiving bands around at least ±10 percentage points in the primary route, subject to playtesting. Later holes can ask for more accuracy but must offer understandable feedback.
