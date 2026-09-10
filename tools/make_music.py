#!/usr/bin/env python3
"""Synthesize the Roarball background music loops (original, license-clean).

Generates two seamless WAV loops into assets/audio/:
  music_sunny.wav  — C-major-pentatonic kalimba arpeggio, 96 BPM, 8 bars (20.0 s)
  music_sunset.wav — A-minor-pentatonic warm plucks + pad, 72 BPM, 8 bars (~26.7 s)

Run from the repo root:  python3 tools/make_music.py
Loop seams are perfect: every note tail is folded around the loop length
(modulo add), so the last bar decays into the first.
"""
import wave
import numpy as np

SR = 22050


def pluck(freq: float, dur: float, amp: float) -> np.ndarray:
    """Kalimba-ish pluck: decaying sine + soft harmonics, 5 ms attack."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    env = np.exp(-t / 0.38) * np.minimum(t / 0.005, 1.0)
    tone = (
        np.sin(2 * np.pi * freq * t)
        + 0.35 * np.sin(2 * np.pi * 2 * freq * t)
        + 0.12 * np.sin(2 * np.pi * 3 * freq * t)
    )
    return amp * env * tone


def pad(freqs: list, dur: float, amp: float) -> np.ndarray:
    """Soft slow-attack chord pad with gentle detune."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    env = np.minimum(t / (dur * 0.35), 1.0) * np.minimum((dur - t) / (dur * 0.35), 1.0)
    out = np.zeros(n)
    for f in freqs:
        out += np.sin(2 * np.pi * f * 0.999 * t) + np.sin(2 * np.pi * f * 1.001 * t)
    return amp * env * out / (2 * len(freqs))


def render(bars: int, beats_per_bar: int, bpm: float, events: list, pads: list) -> np.ndarray:
    dur = bars * beats_per_bar * 60.0 / bpm
    total = int(round(dur * SR))
    mix = np.zeros(total)
    for start_beat, note in events:
        start = int(round(start_beat * 60.0 / bpm * SR)) % total
        samples = note
        end = start + len(samples)
        if end <= total:
            mix[start:end] += samples
        else:  # fold the tail around the loop point
            cut = total - start
            mix[start:] += samples[:cut]
            mix[: end - total] += samples[cut:]
    for start_beat, chord in pads:
        start = int(round(start_beat * 60.0 / bpm * SR)) % total
        samples = chord
        end = start + len(samples)
        if end <= total:
            mix[start:end] += samples
        else:
            cut = total - start
            mix[start:] += samples[:cut]
            mix[: end - total] += samples[cut:]
    # gentle low-pass to sit behind gameplay, then normalize to a quiet bed
    kernel = np.ones(9) / 9.0
    mix = np.convolve(mix, kernel, mode="same")
    peak = np.abs(mix).max()
    return (mix / peak * 0.30)


def write_wav(path: str, stereo: np.ndarray) -> None:
    data = (np.clip(stereo.T, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", path, f"{stereo.shape[1]/SR:.2f}s")


def sunny() -> None:
    bpm, bars, bpb = 96.0, 8, 4
    C3, D3, E3, G3, A3, C4, D4, E4, G4 = 130.81, 146.83, 164.81, 196.0, 220.0, 261.63, 293.66, 329.63, 392.0
    beat = 60.0 / bpm
    events = []
    # Bass roots: C - G - Am - F(analog G/E shape kept pentatonic-safe) x 2
    roots = [C3, G3, A3, E3, C3, G3, A3, G3]
    for bar, root in enumerate(roots):
        events.append((bar * 4, pluck(root / 2, 1.6, 0.5)))
    # Arpeggio: two 8ths per beat from a per-chord pentatonic pool
    pools = [
        [C4, E4, G4, D4], [G3, D4, G4, E4], [A3, C4, E4, G4], [E3, G3, C4, D4],
        [C4, E4, G4, D4], [G3, D4, G4, E4], [A3, C4, E4, D4], [G3, C4, D4, E4],
    ]
    for bar in range(bars):
        pool = pools[bar]
        for step in range(8):
            t = bar * 4 + step * 0.5
            amp = 0.42 if step % 4 == 0 else 0.3
            pan_note = pool[(step + bar) % 4]
            events.append((t, pluck(pan_note, 0.9, amp)))
    pads = []
    for bar, root in enumerate(roots):
        pads.append((bar * 4, pad([root, root * 1.5, root * 2], 4 * beat, 0.16)))
    mono = render(bars, bpb, bpm, events, pads)
    # light stereo widening: right channel delayed 12 ms
    d = int(0.012 * SR)
    right = np.concatenate([np.zeros(d), mono[:-d]])
    write_wav("assets/audio/music_sunny.wav", np.array([mono, 0.92 * mono + 0.08 * right]))


def sunset() -> None:
    bpm, bars, bpb = 72.0, 8, 4
    A2, C3, D3, E3, G3, A3, C4, D4, E4 = 110.0, 130.81, 146.83, 164.81, 196.0, 220.0, 261.63, 293.66, 329.63
    beat = 60.0 / bpm
    events = []
    roots = [A2, G3 - 49.0, C3, E3, A2, G3 - 49.0, C3, D3]  # A - G - C - E walk
    for bar, root in enumerate(roots):
        events.append((bar * 4, pluck(root, 2.2, 0.5)))
    pools = [
        [A3, C4, E4, D4], [G3, C4, D4, E4], [C4, E4, D4, A3], [E3, A3, C4, D4],
        [A3, C4, E4, D4], [G3, C4, D4, A3], [C4, D4, E4, A3], [D4, C4, A3, E4],
    ]
    for bar in range(bars):
        pool = pools[bar]
        for step in range(6):  # sparser, lazier pattern
            t = bar * 4 + step * (4.0 / 6.0)
            events.append((t, pluck(pool[(step + bar) % 4], 1.3, 0.3)))
    pads = []
    for bar, root in enumerate(roots):
        pads.append((bar * 4, pad([root * 2, root * 3, root * 2.4], 4 * beat, 0.2)))
    mono = render(bars, bpb, bpm, events, pads)
    d = int(0.018 * SR)
    right = np.concatenate([np.zeros(d), mono[:-d]])
    write_wav("assets/audio/music_sunset.wav", np.array([mono, 0.88 * mono + 0.12 * right]))


if __name__ == "__main__":
    sunny()
    sunset()
