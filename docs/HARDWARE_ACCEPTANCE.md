# Hardware Acceptance Package — Android Voice & Performance (RB-002/003/005)

Narrow, scripted acceptance run for a physical Android device session. This is
the package a device tester executes; everything automatable without hardware
is already gated by CI (`tools/run_tests.sh`, 985 checks). Results attach to
issues #2, #4, #6, and #53 — do not close those from this document alone.

## Preparation

- Build: `tools/build_android.sh` (signed debug build is sufficient).
- Reference desktop baseline: run
  `LEVEL_ID=CC04 ROAR3D_REPLAY_OUT=/tmp/ref godot --path . --resolution 390x844 res://tools/replay_hole.tscn`
  and keep the five PNGs plus the `FRAMESTATS` line — the device run compares
  against these.
- Device setup: battery ≥ 80 %, no charger, background apps cleared, screen
  brightness fixed at 50 %, record device model / Android version / RAM.

## Script (run in order, record at each step)

| # | Step | What to record |
|---|---|---|
| 1 | Fresh install → first launch | Permission prompt timing/wording; no mic indicator before any capture |
| 2 | Choose Voice → Room / Soft / Strong calibration | Each stage completes; OS mic indicator ON only while recording; power meter reacts to voice only |
| 3 | CC04 Touch run (3 strokes, use the replay script above as the shot plan) | Playable end-to-end; HUD readable; touch never triggers the OS mic indicator |
| 4 | CC04 Voice run | Whisper rolls, ROAR lofts; meter previews match effort; audio cues duck during capture |
| 5 | Background mid-hold (home button during a capture) | Capture closes; no mic indicator after backgrounding; resume returns to READY with no stroke |
| 6 | Bluetooth earbuds: connect → calibrate → one shot | Route change invalidates calibration (stale prompt); indicator behavior correct |
| 7 | 10–15 min sustained play (replay CC01→CC04 loop) | FPS overlay (`ROAR3D_PERF=1`) sampled every 2 min; note frame spikes, thermal warnings, mic failures |
| 8 | Permission revoke while backgrounded → return | App handles denial gracefully (no capture, status surfaced, no crash) |

## Pass gates

- Mic indicator ON **only** during an active capture hold, on every route
  (speaker / wired / Bluetooth), at every step above.
- No audible microphone feedback through the speakers at any point.
- Sustained play: p95 frame time within 2× of the desktop `FRAMESTATS` p95,
  no unbounded growth across repeated holes, no thermal throttling cliff
  before minute 10.
- Every failure blocks voice release rather than being relabeled (RB-005).

## Evidence to attach

Screen recording of steps 2/4/6, the FPS overlay samples from step 7,
device matrix row (model/OS/RAM), and any mic-indicator screenshots. File
results on the respective issue; a red gate stays red until re-run passes.
