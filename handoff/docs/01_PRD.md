# Roarball — Product Requirements Document

Version 1.0 · September 5, 2026 · Proposed implementation baseline

## 1. Product decision

Roarball is a mobile-first, single-player 3D mini-golf puzzle game. Players aim a cute lion-faced ball with touch and set shot power using a short, comfortable sound. A soft sound produces a gentle putt; a stronger calibrated sound produces a stronger shot. Touch-only power is an equal, permanent alternative.

Build the entire game and interface in **Godot 4.7.2 stable with typed GDScript**. The official archive listed this stable version when checked on September 5, 2026 [S01]. Use the integrated Jolt 3D physics engine, subject to a physical-device spike [S03]. Kotlin is a conditional Android integration language, not a second gameplay language. No Flutter shell, Unity bridge, or external physics extension is required by the proposed MVP.

The product promise is **“Small shots. Big roars.”** It describes personality, not a requirement to scream. Roarball is about precision, timing, and playful physical consequences. Loudness is not a score multiplier.

## 2. Goals and non-goals

Primary goals are to make the first shot understandable without a text-heavy tutorial, make quiet and strong shots both useful, deliver repeatable physical behavior, and translate the reference art into readable real-time mobile scenes.

The first playable milestone must prove one complete hole on an Android phone: enter, aim, choose power, shoot, roll, finish, save, retry. The visual slice must then prove one polished hole before all remaining content is produced.

MVP non-goals: multiplayer, online leaderboards, user accounts, cloud saves, advertising, in-app purchases, energy/hearts, paid retries, daily challenges, generated courses, AI services, speech recognition, voice uploads, realistic water simulation, destructible terrain, and an in-game level editor. The extra worlds and economy elements in the earlier mockups are future concepts, not committed scope.

## 3. Audience and platform assumptions

The design targets casual puzzle players and families who enjoy short, expressive play sessions. This is a proposed audience, not a validated market claim. Do not infer a child-directed regulatory classification from cute art alone; the publisher must make and review that decision before release.

Android phones are the first release target. Desktop editor builds support development and QA. iOS is a later delivery track; keep platform boundaries clean but do not claim an iOS release is included. Portrait is primary. A landscape fallback and tablet layout must remain usable; the gameplay does not depend on a narrow device-specific screenshot.

Sessions are intended to contain a few holes; hole duration is a design target of roughly 30–120 seconds, not a hard timer. There is no mandatory microphone use and no need to pronounce English words. UI copy starts in English with localization keys; Indonesian is a planned translation task rather than hardcoded mixed-language text.

## 4. Core player journey

Boot to Home without an immediate microphone permission dialog. “Play” resumes the next unlocked hole. A first-session choice offers Voice or Touch. Choosing Voice explains local sound-level processing, requests permission, checks room noise, and calibrates comfortable soft and strong sounds. Denial goes directly to the full Touch experience.

The player enters a safe introductory hole, drags to aim, holds the microphone button, produces a short sound, sees the exact power that will be committed, and releases to shoot. A drag into Cancel aborts without a stroke. In Touch mode, the same place contains a power slider and Shoot button.

The ball rolls under physics. Shot controls are disabled while moving. The player can inspect the course or pause. If the ball goes out of bounds, one penalty stroke is added and the ball returns to its last safe resting position. Finishing produces a results screen with strokes, par, earned stars, and progress. Next Hole and Retry are always clear.

## 5. Scope at release

Two worlds contain twelve authored holes: Cloud Cliffs (CC01–CC06) and Portal Peaks (PP01–PP06). Every hole has a playable `.tscn` scene, validated metadata, an authored par, a twelve-stroke attempt limit, and an internal reference solution. Metadata in this package is a design brief; it is not evidence that geometry has been built or solved.

Cloud Cliffs introduces putting, strength control, rebounds, ramps, moving gates, and combinations. Portal Peaks introduces paired portals, bounce pads, and later recombinations. Wind fans, lava environments, multiple moving platforms, and full physics trajectory prediction are deferred.

MVP collection has three cosmetics: Lion (default), Panda (unlock after CC06), and Robot (unlock after PP06). All share identical collider, mass, friction, and shot curve. No stat boosts, rarity economy, currencies, purchases, or random unlocks.

## 6. Functional requirements

| ID | Requirement | Acceptance evidence |
|---|---|---|
| FR-01 | Home, level selection, collection, settings, pause, and results are usable without a mic. | End-to-end Touch run through all holes. |
| FR-02 | Permissions are requested in context after Voice is selected. | Fresh-install grant, deny, and permanently-denied recordings. |
| FR-03 | Calibration distinguishes room noise, soft input, and comfortable strong input. | Synthetic tests plus device session records. |
| FR-04 | The power shown on release equals the power used by physics. | Logged shot command and UI value differ by at most 0.01. |
| FR-05 | Invalid/no-signal capture, cancel, and interruption never spend a stroke. | State-transition tests. |
| FR-06 | One accepted release produces one impulse and one stroke. | Double-event and multi-touch regression tests. |
| FR-07 | Touch and Voice use the same normalized power-to-impulse curve. | Same-power trajectory comparison on one device/build. |
| FR-08 | A settled, supported ball can be aimed; a moving ball cannot be shot again. | Flat, ramp, and bumper tests. |
| FR-09 | Out-of-bounds recovery uses a verified safe anchor with one penalty. | Repeat fall and blocked-anchor tests. |
| FR-10 | Cup completion requires eligible proximity, height, and low speed. | Near-miss, flyover, and high-speed pass tests. |
| FR-11 | Stars and best strokes persist without duplicate rewards. | Replay and interrupted-save tests. |
| FR-12 | Sequential hole unlocks depend on completion, not three-star mastery. | Low-score progression test. |
| FR-13 | All twelve holes have meaningful layout/mechanic differences. | Content review with solution evidence. |
| FR-14 | Cosmetic choices never change physics. | Collider and tuning equality tests. |
| FR-15 | Pause, app background, focus loss, route change, and input-mode change safely cancel capture. | Physical-device lifecycle matrix. |
| FR-16 | No raw microphone audio is written to disk, transmitted, or included in telemetry. | Storage/network inspection and code review. |
| FR-17 | Settings expose input mode, recalibration, music, effects, haptics, reduced motion, and quality. | Screen and persistence tests. |
| FR-18 | Invalid content or save data fails safely with recovery UI. | Corrupt-file fixtures. |
| FR-19 | Scene loading and back navigation cannot leave two active sessions or microphones. | Thirty enter/exit cycles. |
| FR-20 | Shipped interface components replace, rather than screenshot, the reference art. | Visual review and node inspection. |

## 7. Scoring and progression rules

A committed shot adds one stroke. An out-of-bounds event adds one additional penalty stroke, exactly once for that shot. Scores are evaluated after the ball resolves: a ball can finish on the twelfth stroke; exceeding the limit cannot earn stars. At twelve strokes without completion, show Attempt Finished with Retry and Map. At eleven strokes, a shot followed by a fall resolves as thirteen and fails.

A completion within the limit earns three stars at or below par; two stars at par + 1; one star above par + 1. Store the best star result and the fewest completed strokes independently. A failed attempt does not replace a prior best. No timer-based score, voice-quality score, “best whisper,” accuracy percentage, gem reward, or loudness bonus is included.

Unlock CC01 initially and each next hole on completing the previous hole. PP01 unlocks after CC06; do not gate it on a star total. Show 0–18 stars per world. Finishing PP06 unlocks free replay and the Robot cosmetic. There is no consumable attempt counter.

## 8. UX and accessibility requirements

The course and landing area have priority over decorative UI. In gameplay, use a compact header and a thumb-reachable bottom control tray; do not repeat the oversized logo from the concept images. The first playfield should not hide the flag behind the power panel.

Use a 390 × 844 logical portrait design reference, flexible containers, explicit safe-area margins, and minimum 48-logical-unit interaction targets as our internal design standard. These are design choices, not claims that Godot uses Android dp automatically. Map device safe areas into the actual viewport transform. Test narrow phones, tall phones, and tablet proportions.

Voice states must be indicated by text/icon as well as color. A visible Listening indicator accompanies capture; a mic icon alone is insufficient. Calibrated power is relative to the device; never label it as real-world sound pressure in decibels. The strongest shot must be reachable at a comfortable voice level.

All holes and rewards must be reachable in Touch mode. Reduced Motion suppresses screen shake, camera overshoot, and excessive celebrations. Do not rely on audio-only instructions or vibration-only feedback. Prefer large icons and concise copy; UI text is editable and localized.

## 9. Nonfunctional targets

These are proposed budgets to validate, not measured results. Aim for sustained 60 fps on the selected mid-tier Android target and a stable 30 fps quality tier on the minimum supported target. Physics stays at 60 ticks per second across quality tiers. Record p50/p95/p99 frame times and long-run temperature behavior; average FPS alone is insufficient.

Initial budgets: at most 150,000 visible triangles, 100 visible draw calls, 32 MB compressed content per world, one shadow-casting directional light, and no dynamic global illumination. Start with a 150 MB installed-content budget and 450 MB peak process-memory target, then revise based on measured device data. Do not treat arbitrary budget numbers as engine limits.

Voice target: a visible power response within 120 ms p95 of usable incoming samples and a committed shot on the next physics tick after an accepted release. Hardware capture latency must be measured separately. Level-to-level transitions should avoid blocking hitches and release unused resources. Final minimum Android/API/device support remains a release gate until the device matrix is selected and measured.

## 10. Privacy and resilience

The game must work offline after installation. Voice analysis is local, temporary, and limited to explicit interactions. Store only calibration numbers and user settings, not recordings. Do not put PCM, transcripts, amplitude timelines, hardware identifiers, or permission decisions into production analytics. The MVP has no network analytics SDK.

Stopping GDScript analysis is not proof that the operating system released the microphone. A specific device gate must verify the hardware privacy indicator and audio-driver behavior after release, pause, and background. If Godot's built-in capture cannot meet this requirement, document the reproduction and evaluate a narrowly scoped native input adapter. Do not hide this issue by relabeling the UI “Mic off.”

Save at completed holes, collection changes, and settings changes. A killed application resumes at the last completed progress state; mid-shot resume is not required. The player may lose the current attempt, never previously completed holes. Corrupted primary saves should recover from the last validated backup where possible.

## 11. Success and validation plan

Run a formative usability session with at least eight representative testers; this is a discovery sample, not statistical proof. Proposed acceptance targets: seven can take an intentional first shot without spoken coaching, six can intentionally distinguish gentle and strong power, and everyone can find Touch fallback after denial. Capture observations, not user voice recordings.

Compare replay enjoyment and frustration qualitatively between Touch and Voice. If voice feels less predictable, fix calibration and feedback before adding content. A visually impressive screenshot does not compensate for unreliable input.

## 12. Release gates and ownership

Gate G0: pin tools, identify device tiers, validate capture lifecycle and renderer/physics behavior. Gate G1: one complete graybox hole playable in Touch and Voice. Gate G2: one polished vertical slice approved against the reference direction. Gate G3: all twelve holes, three cosmetics, and local progression complete. Gate G4: device, content, save, accessibility, and release checks pass.

Product/design owns mechanics and scope; gameplay owns the shot/physics loop; audio/platform owns capture and permissions; art owns reusable assets; QA owns reproducible evidence. A small team may combine roles but must not omit their acceptance work.

No delivery dates or market outcomes are implied. `tasks/` contains the proposed work breakdown, dependencies, and completion criteria. Any later addition of accounts, ads, purchases, children's targeting, or audio sharing requires a new product and privacy review.
