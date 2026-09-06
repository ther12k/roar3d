# Voice Input, Calibration, and Privacy Specification

## 1. Scope

Detect relative sound level, not words, identity, emotion, or a literal whisper classification. No speech model, transcription service, cloud inference, audio upload, or persistent recording is necessary. The in-game labels Soft and Strong describe calibrated power bands.

Godot exposes microphone playback through AudioStreamMicrophone and raw stereo floating-point bus frames through AudioEffectCapture [S05, S06]. Input must be enabled in project settings and operating-system permission must be handled [S07, S08]. Hardware/device behavior must be verified rather than inferred from desktop success.

## 2. Bus and lifecycle design

Proposed routing: `MicPlayer -> MicCapture bus (AudioEffectCapture first) -> MicSilence bus -> Master`. Silence the monitoring path after the capture effect, never the Master bus. Confirm on devices that the capture effect still receives frames and the microphone is never played through the speakers. Do not apply gain/limiting before measurement unless explicitly modeled in calibration.

`MicPlayer.autoplay = false`. Capture starts only through VoiceInputService after the user explicitly selects Voice/calibration or starts a shot interaction. Allocate a fresh capture token, clear stale frames, duck game audio, start playback/capture, and wait for fresh frames. UI says “Starting mic” until frames arrive; only then says “Listening.”

On release/cancel/pause/background/route change, stop capture playback, stop processing, clear the ring buffer and rolling level history, invalidate the token, and restore output audio after shutdown. Never restart automatically on resume. Test the OS microphone indicator separately: stopping analysis or muting a bus is not equivalent to releasing the input device.

If the engine/driver leaves input active outside the expected capture period, fail the privacy gate. Investigate the selected engine's driver behavior first. A native Android audio adapter is permitted only after a documented need; it must acquire/release the actual recorder, and the built-in path must then be disabled to prevent two microphone owners. See document 09.

## 3. Capture and computation parameters

Starting values (all configurable): warmup discard 100 ms; frame analysis windows 20 ms; capture ring 250 ms; power smoothing time constant 80 ms; recent commit window 250 ms; minimum qualified duration 150 ms; maximum hold 3,000 ms; no-fresh-samples timeout 500 ms.

For AudioEffectCapture, determine the frame rate of its bus stream from the active mixer rather than hardcoding a device input rate. Compute window sample counts from that rate. The engine exposes rate-related APIs; input hardware and output mix rates may differ [S07]. The buffer API consumes frame counts and can report discarded frames [S06].

For stereo frame i, energy is `(left_i^2 + right_i^2) / 2`. Window RMS is `sqrt(mean(energy))`. This avoids cancellation from averaging out-of-phase channels before squaring. Convert to relative digital dBFS as `20 * log10(max(rms, 0.000001))`. Internally clamp to [-120, 0]. UI must not display this as measured real-world dB SPL.

Reject non-finite samples. Clamp only for numeric safety; count clipping separately when either channel magnitude >= 0.98. A capture overrun invalidates the current shot rather than making old audio appear current. Do not retain more than the small bounded window required for the algorithm.

## 4. Calibration procedure

Calibration is a skippable three-stage interaction plus a test shot. Soft/strong requests must say “Use a comfortable voice; no shouting needed.” Never reward longer or louder calibration.

Stage A: after permission, capture 1.5 seconds of room noise while the player stays quiet. Use the 90th percentile of valid window dBFS as `noise_db`. Stage B: capture a comfortable soft sound for up to 1.5 seconds and compute the median qualified window level as `soft_db`. Stage C: capture a comfortable stronger sound for up to 1.5 seconds and use its median as `strong_db`. Stop early only when enough qualified samples are stable.

Candidate quality checks: `soft_db >= noise_db + 6`, `strong_db >= soft_db + 8`, no excessive clipping (>5% of samples), and at least 0.3 seconds of qualified soft and strong data. These are proposed thresholds, not universal microphone truths. If failed, offer Recalibrate, Move closer/choose a quieter place, or Use Touch. Do not require repeated escalating vocal effort.

Set `gate_db = noise_db + 4`, `lower_db = max(noise_db + 6, soft_db - 3)`, and `upper_db = strong_db`. Store only these numbers, calibration algorithm version, and a non-sensitive route category (built-in/wired/Bluetooth/unknown). Never store a hardware identifier. Recalibrate on route change and when signal/noise behavior changes significantly.

## 5. Runtime power mapping

For an eligible window above the gate, compute `raw = clamp((dbfs - lower_db) / (upper_db - lower_db), 0, 1)`. If the denominator is invalid or too small, require recalibration and do not shoot.

Smooth with frame-time-correct exponential interpolation: `alpha = 1 - exp(-dt / 0.08)`; `smooth += alpha * (raw - smooth)`. A longer frame must not make control radically slower. Clamp smooth to [0, 1]. This is relative power input, not yet the physical impulse curve.

The **Shot power preview** is the 75th percentile of qualified smoothed windows in the most recent 250 ms. Require at least 150 ms of qualified windows within that window and preview > 0. The same value is displayed and committed. A live amplitude bar may coexist but must have a different label. If the player stops making sound, preview expires as qualified samples age out; do not keep an old maximum forever.

On pointer release, use the last published preview from the same capture token. Stop/clear input and enqueue one ShotCommand. The UI does not pretend to account for unobserved device latency. Playback of the lion's sound occurs after capture closes.

## 6. Interaction edge cases

| Case | Required outcome |
|---|---|
| Permission is pending | Disable capture; offer Touch; no stroke. |
| Permission denied | Explain without nagging; persist Touch preference. |
| Permission permanently denied | Offer app settings plus Touch; no prompt loop. |
| All-zero samples | “No microphone signal”; do not interpret as a quiet shot. |
| Device too noisy | Cancel invalid shot and offer recalibration/Touch. |
| Phone tap / single clap | A transient shorter than qualified duration cannot shoot. |
| Sustained background sound | May resemble voice; disclose amplitude-only limitation and offer Touch. |
| Strong input clips | Saturate display safely; advise gentler input; never exceed maximum impulse. |
| Multitouch | Only initiating pointer controls capture; secondary release cannot fire. |
| Background or incoming interruption | Cancel uncommitted shot; close input; never auto-fire on return. |
| Bluetooth route changes | Cancel; invalidate calibration; no simultaneous input owners. |
| Release arrives twice | Token and shot-ID guard accept at most one command. |

Do not claim amplitude processing rejects speech from other people or knows which sound is the player's. This is a limitation to communicate and test, not hide with an “AI noise filter” label.

## 7. User-facing copy

Permission pre-prompt: “Use your sound to set shot power. Sound is processed on this device and is not saved or uploaded. You can play with touch instead.” This copy may ship only after implementation proves it.

Calibration prompt: “First, stay quiet. Then try a soft sound and a comfortable stronger sound.” Gameplay: “Hold, make a sound, release to shoot.” Cancel: “Slide here to cancel.” No signal: “We couldn't detect a usable sound. Try again or use touch.”

Do not say “Mic off” until the native release behavior has been validated. Accessibility copy should not imply that a speech impairment is a player failure. A soft hum or other comfortable sound can be used; no word matching is involved.

## 8. Synthetic and device validation

Synthetic fixtures must cover silence, fixed amplitudes, opposite-phase stereo, clipped values, short impulse noise, irregular frame times, too-small calibration ranges, stale frames, and duplicated release events. Calibration tests use digital values, not invented acoustic measurements.

Device validation must include room noise, phone speaker playback, headphones, permission revocation, repeated holds, a thirty-cycle input stress test, background/foreground, route changes, and microphone privacy indicator observation. Report measured capture/UI latency with the device/build/route. No physical microphone or Android audio path has been tested in this package.
