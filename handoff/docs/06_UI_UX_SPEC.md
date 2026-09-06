# UI/UX Implementation Specification

## 1. Source of truth

The seven supplied Roarball PNGs are the existing AI-generated concept references from this conversation. They establish the lion-ball identity, floating islands, saturated warm/cool palette, and rounded game UI. They are not layered assets, real-time screenshots, final text, validated navigation, or measured performance targets.

Use this specification and PRD when a concept image conflicts with the MVP. Do not ship a full-screen mockup PNG with invisible buttons on top. World, camera, lighting, UI, icons, and interactions must be separate implementation elements.

## 2. Reference reconciliation

| Reference | Keep | Change for MVP |
|---|---|---|
| 01_original_gameplay.png | Mascot, floating turf, clear flag, playful obstacles. | Smaller header; no coins; real shot/cancel states. |
| 02_home.png | Hero scene, dominant Play, friendly brand. | Remove daily challenge, player level, coins; use Play, Map, Balls, Settings. |
| 03_world_map.png | Islands, connected hole nodes, star results. | Only two worlds/six nodes each; remove hearts/shop/lava world. |
| 04_calibration.png | Large mic, simple scale, practice setting. | Real noise/soft/strong steps, Touch skip, cancel/error states. |
| 05_advanced_gameplay.png | Ramps, gates, portals, readable depth. | No wind fan in MVP; never introduce every hazard in one early hole. |
| 06_collection.png | Selected ball pedestal and Equip action. | Lion/Panda/Robot only; no currency/rarity/Trails/Emotes shop. |
| 07_results.png | Celebration, stars, clear Next Hole. | Strokes/par/stars only; no whisper %, accuracy %, gems, or Share requirement. |

## 3. Design tokens and layout

Reference canvas: 390 × 844 logical units. Base spacing: 4; regular gaps: 8/12/16/24. Page margin: 16 plus mapped safe inset. Panel radius: 20; button radius: 16. Small controls have minimum 48 × 48 touch boxes even when visible icons are smaller. Primary buttons are 56–64 high. Mic control is 80 × 80 with an outer cancel-safe gesture area.

Typography target: title 28/34, screen heading 24/30, body 16/22, compact label 14/18. Use a separately licensed rounded typeface or Godot's default during development. No font files are bundled here. Never bake localization text into textures. Avoid all-caps paragraphs and long slogans across scenery.

Palette: dark navy panels #132B3A, panel variant #1D4258, light text #F5F9FC, secondary text #B9CDDA, voice cyan #2DCEFF, primary green #63DC65, warm accent #FFBE42, danger #EF6A6A. Verify final contrast in rendered states; these are proposed tokens, not a completed accessibility audit. Disabled controls need shape/label distinction, not only lower opacity.

Use a reusable Theme resource, StyleBoxFlat/texture-backed nine-patch panels, Buttons, Sliders, Labels, and Container nodes. Godot's stretch and multi-resolution behavior must be configured deliberately [S12]. Do not interpret 390 logical units as 390 physical pixels on every device.

## 4. Screen inventory and acceptance

### UI-01 Boot and loading

Show compact logo, meaningful progress if available, and no mic dialog. Loading failure offers Retry and Home with a diagnostic code. Animated background is optional; never block input with an endless spinner. Do not fabricate percentage progress from an unrelated timer.

### UI-02 Home

Hero lion on one simplified tee with distant islands. Top bar: Roarball and Settings, not a faux player account. Primary Play; secondary World Map and Balls. Small input-mode chip says Voice or Touch and opens settings. After first completion, Play opens next unlocked hole; after full completion, Play opens last played level.

### UI-03 Mode choice and permission pre-prompt

Two equally visible options: Use Voice and Use Touch. Explain local temporary processing. Continue requests the platform permission only for Voice. Back returns home. Denial does not launch calibration repeatedly. A desktop keyboard testing shortcut is a developer tool, not a mobile onboarding option.

### UI-04 Calibration

Header Back and “Find your shot power.” Step display: Room / Soft / Strong. Each step includes one sentence, visible duration/progress, a Start action, current signal validity, and Use Touch. A test shot follows valid calibration. No automatic recording begins just because this screen was navigated to.

Display comfortable input range, not a red demand to scream. Invalid signal shows a reason and Retry Step. Keep previous valid calibration until a replacement succeeds. A route change marks old calibration stale without deleting player progress.

### UI-05 World map

Two chapter cards or a lightweight vertically scrolling island map. Each has six numbered nodes, earned stars, lock explanation, and a current-level indicator. Each node offers title, par, best strokes, and Play in a small detail sheet. Buttons remain two-dimensional Controls even when the map art looks 3D.

Avoid a heavy active 3D scene per visible node. Use one background/map scene or rendered thumbnails. Navigation: Home / Map / Balls. Locked PP01 explains “Finish Cloud Cliffs” rather than showing a price.

### UI-06 Gameplay Ready

Top safe row: Hole name/number, Par, Strokes, Pause. A small objective chip can appear below for the first introduction, then dismiss. Center: course, ball, target. Bottom tray: input-mode chip, power preview, mic or touch slider/Shoot, and Overview. Omit collection shopping and currencies during play.

Aim gestures operate only outside UI hit regions. In Voice mode initial copy says “Aim, then hold to power.” Power is visibly zero/unset until usable input. In Touch mode slider preserves its last selected value between shots but requires a new Shoot press.

### UI-07 Gameplay Capturing

Same composition, with camera locked. Label Starting mic then Listening; live level and clearly labeled Shot power. Mic ring animates gently. A Cancel region appears above/aside the thumb; release rules are discoverable in tutorial. Other game navigation is disabled, but Pause and Cancel always work. Invalid signal never creates a hidden shot.

### UI-08 Rolling, falling, and reset

Power controls are dimmed and labeled “Ball moving.” Do not leave a mic glow that suggests listening. On fall show “Out of bounds · +1 stroke,” then a brief reset without a modal penalty screen. Disable repeated taps during reset. At attempt limit, show Retry and Map.

### UI-09 Pause and settings

Pause sheet offers Resume, Restart Hole, Input & Sound, and Map. Restart/exit while an attempt is underway asks for confirmation; completed progress remains safe. Resume never restarts capture. In settings expose Touch/Voice, Recalibrate, volume, haptics, reduced motion, and quality. Input switching mid-hold cancels that hold.

### UI-10 Results

Lion celebration above a panel: Hole Complete, earned stars, strokes and par, world completion progress. Primary Next Hole, secondary Retry and Map. Best-result improvement can be labeled New Best. No fabricated accuracy or voice-performance metric. On final hole, replace Next with World Map and show all-holes completion.

The first result write must complete or yield a recoverable Save Warning before navigation. If saving fails, keep the result in memory, show Retry Save, and avoid pretending progress is durable.

### UI-11 Collection

One selected 3D preview; three cards with names and unlock criteria. Locked cards are informative, not purchase funnels. Equip changes visuals only. Selected and equipped are separate states: previewing a locked Robot does not equip it. Use a static thumbnail grid, not multiple animated viewports.

### UI-12 Recoverable errors

Include designed states for no microphone, denied permission, too-noisy calibration, stale route, save failure, missing level data, and graphics incompatibility. Each state has one clear recovery action and a safe exit. Do not silently fall back to a different input mode while the user's finger is committing a shot.

## 5. Responsive behavior

At 360-wide phone reference size, collapse secondary labels and keep controls at least the target size; do not scale the entire UI down to fit. On taller phones add course space above the tray. On tablets cap menu content width and use a two-column settings/collection layout. In landscape, move the control tray to the right with course framing adjusted; portrait remains the preferred orientation.

Read the device safe region and convert it into the chosen canvas coordinates before applying margins. Test notches, gesture/navigation bars, and display cutouts on real devices. The UI's minimum hit sizes apply in logical canvas coordinates after the stretch policy, not in untransformed native screen pixels.

## 6. Interaction and motion

Button press: 80–120 ms subtle scale/color change; screen navigation: 180–250 ms; results: <1.5 seconds before Next is usable. Reduced Motion can remove transforms and shorten celebrations. Do not use long entry animations that lock every tap. These are proposed feel targets.

Back stack is explicit. Android Back dismisses the top sheet first, pauses gameplay second, and never exits mid-capture without cancellation. Home does not request a microphone. A settings toggle must not accidentally pass through to the 3D world.

## 7. Visual handoff checklist

For every screen, submit portrait and narrow-device captures, default/pressed/disabled/error states where relevant, safe-area overlay, and a short interaction recording. Compare hierarchy, silhouette, color, and affordance to the references; do not demand pixel identity with impossible concept geometry.

A vertical slice is approved only after real buttons, real camera framing, the real ball, real input feedback, and at least one real course are shown together. UI-only reskins of a graybox do not satisfy this visual gate.
