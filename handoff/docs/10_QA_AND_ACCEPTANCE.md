# QA, Acceptance, and Release Evidence

## 1. Evidence policy

A requirement is complete only with reproducible evidence on the relevant runtime. Written architecture is not a tested feature. A scene screenshot is not a successful physics run. A synthetic amplitude test is not an Android microphone test. All numbers below are proposed acceptance thresholds, not completed measurements.

For each failure record build hash, engine/export-template version, device/OS, renderer, input route, level ID, steps, expected/actual outcome, and non-sensitive logs. Do not record player audio to reproduce a voice-input bug; use synthetic fixtures or consented observations without retained PCM.

## 2. Proposed device matrix

Select actual inventory before G0 closes. Minimum set: one intended minimum-tier Android phone, one mid-tier target phone, and one newer phone with a different GPU/driver family. Include at least two OS generations where the support policy requires them, a notched/gesture-navigation device, and a tablet/aspect-ratio test. Device names remain unfilled until measured; no compatibility is asserted in this delivery.

Test built-in microphone, wired audio where available, and Bluetooth as a compatibility case. Bluetooth voice play may fall back to Touch if latency/route behavior is inadequate; communicate this instead of claiming every headset works. Desktop emulation is useful but does not replace the mobile gate.

## 3. Acceptance test catalog

| Test ID | Scenario | Expected result |
|---|---|---|
| QA-001 | Fresh install, choose Touch. | No mic prompt; complete CC01. |
| QA-002 | Fresh install, choose Voice and grant. | Calibration starts only after action/permission. |
| QA-003 | Deny or permanently deny mic. | Full Touch route; no prompt loop. |
| QA-004 | Revoke mic in OS settings. | Safe recovery; no stale Listening state. |
| QA-005 | Stay silent during shot hold. | No accepted shot/stroke. |
| QA-006 | Single short tap/clap noise. | Below duration gate; no accidental launch. |
| QA-007 | Sustained qualified soft/strong input. | Distinct reachable powers, capped at 1.0. |
| QA-008 | Opposite-phase stereo fixture. | Energy is not canceled by channel averaging. |
| QA-009 | All-zero/nonfinite/clipped/overrun input. | Bounded error handling; no NaN physics. |
| QA-010 | Irregular window/update durations. | Frame-time-aware smoothing behaves consistently. |
| QA-011 | Release twice / two fingers. | At most one impulse and one stroke. |
| QA-012 | Cancel gesture and >3 s hold. | No auto-fire; zero added strokes. |
| QA-013 | Background during capture/warmup/commit pending. | Pending shot canceled; capture closed. |
| QA-014 | Background while rolling. | Simulation pauses; no new impulse on resume. |
| QA-015 | Change audio route mid-hold. | Cancel and mark calibration stale. |
| QA-016 | Thirty capture/start/stop cycles. | No duplicate owner, buffer leak, or lingering mic indicator. |
| QA-017 | Game audio active during capture. | No voice monitoring; game does not power itself. |
| QA-018 | Same normalized Touch/Voice input. | Same command/impulse; outcome within same-build tolerance. |
| QA-019 | Positive/zero/out-of-range shot power. | Reject zero/invalid; clamp only valid range contract. |
| QA-020 | Shoot while rolling or settling. | Action rejected; no hidden stroke. |
| QA-021 | Flat roll distance sweep. | Stable stopping-distance bands at 25/50/75/100%. |
| QA-022 | Ramp and high-speed thin obstacle. | No unacceptable tunneling or invisible snag. |
| QA-023 | Slow ball on slope / midair apex. | No false safe rest. |
| QA-024 | Cup slow entry, fast pass, high flyover, underside. | Only eligible entry completes once. |
| QA-025 | Kill plane and kill volume fire together. | One penalty; one reset. |
| QA-026 | Last safe anchor blocked. | Valid fallback anchor/spawn; no reset loop. |
| QA-027 | Portal pair exit and re-entry. | Correct direction, clear exit, latch prevents loop. |
| QA-028 | Pad holds overlapping ball. | One impulse per eligible entry. |
| QA-029 | Moving gate pause/resume. | Phase preserved; no wall-clock teleport. |
| QA-030 | Ball stuck for watchdog period. | Explicit recovery option, not silent teleport. |
| QA-031 | Twelfth shot completes vs misses vs falls. | Win at <=12; failure otherwise; penalties correct. |
| QA-032 | Par, par+1, par+2 finishes. | 3/2/1 stars; failed result gives 0. |
| QA-033 | Replay worse result; duplicate completion. | Best data retained; no extra unlock mutation. |
| QA-034 | Complete CC06 with one star. | PP01 and Panda unlock. |
| QA-035 | Complete PP06. | Robot unlock; final result navigates correctly. |
| QA-036 | Truncated/invalid/future-version save. | Valid backup or clear recovery, no crash. |
| QA-037 | Kill process during each save step. | Prior durable progress remains recoverable. |
| QA-038 | Disk-write failure. | Save warning, retry, no false durable-success claim. |
| QA-039 | Invalid catalog/scene marker/portal pair. | Build validation or safe loading error. |
| QA-040 | All twelve holes independent playtest. | Successful reference routes and meaningful variation. |
| QA-041 | Narrow/tall/notched/tablet UI. | No clipped controls; course/cup readable. |
| QA-042 | Every screen pressed/disabled/error state. | Consistent feedback and no input fall-through. |
| QA-043 | Reduced Motion / Touch-only full run. | Equal completion/rewards; no mandatory sound cues. |
| QA-044 | Android Back through sheets and gameplay. | Correct stack; capture canceled safely. |
| QA-045 | Thirty level enter/exit/retry cycles. | One session, no runaway nodes/resources. |
| QA-046 | Fifteen-minute gameplay soak per quality tier. | Frame-time/memory/thermal targets met or documented blocker. |
| QA-047 | Storage/network/log inspection. | No retained/transmitted PCM; no hidden network SDK. |
| QA-048 | Signed release install and offline smoke. | Same core behavior as tested debug build. |

## 4. Unit and integration suites

Domain tests cover calibration math, quantile selection, smoothing, clamp/rejection, shot curve, star thresholds, attempt limits, sequential unlocks, and save merge/idempotency. Use injected clocks and synthetic level windows. Avoid game-state changes depending on wall clock.

Scene tests exercise the ball/controller boundary, start-stop capture tokens using a fake provider, cup eligibility, fall coalescing, portal transforms, pad latching, gate motion, safe reset, and loading cleanup. Assertions must distinguish simulation ticks from rendered frames.

Content validation checks schema and authored scene invariants. A metadata file saying “solvable” is not proof. Attach QA evidence to each final hole, including route screenshots and achieved strokes in the pinned build.

## 5. Performance protocol

Measure release-like builds after a warmup run. Use at least 15 minutes of repeated play per device/quality tier; track frame-time distribution, memory trend, loading hitches, and thermal slowdown. Proposed targets: 60 fps target tier and stable 30 fps low tier, with 60 Hz physics on both. If p95 frame time exceeds the chosen tier budget, identify CPU/GPU/UI/audio cost before cutting mechanics.

Initial budgets in PRD are adjustable only through an explicit decision with evidence. Test the most demanding actual level and worst-case particles. No performance result in this ZIP has been measured on a phone.

## 6. Usability protocol

Ask testers to select an input mode, take a gentle shot, take a strong shot, cancel, recover after a fall, use Overview, and switch to Touch. Observe without coaching until they get stuck. Record confusion around release-to-shoot versus power slider, whether the target is hidden by UI, and whether they feel pressured to be loud.

Afterward ask which moments felt intentional, which failures felt unfair, and whether voice adds enjoyment over Touch. Do not interpret “funny once” as durable retention. If voice control is frustrating, prioritize calibration/feedback rather than more rewards.

## 7. Definition of done

An implementation task needs code/assets, review, relevant automated tests, reproducible manual evidence where necessary, no new errors/warnings accepted without explanation, and updated documentation if contracts change. Visual tasks require device-scale captures, not only editor screenshots. Native tasks require physical-device evidence and fallback tests.

A release requires all P0 gates, no unresolved critical/major defects, content validation for twelve holes, first-run/offline/save recovery evidence, signed-build smoke, asset/license inventory, privacy-copy audit, and current store submission review. Store approval is not guaranteed by a technical checklist.
