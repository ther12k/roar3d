#!/usr/bin/env python3
"""Synthesize the original short feedback cues for Roarball.

Regenerates a single named effect (default: bounce) as 16-bit stereo WAV at
22.05 kHz, matching the format of the existing putt/cup/fall/click cues.
All sounds are original, synthesized for this repo — see
docs/ASSET_INVENTORY.md. Usage:

    python3 tools/make_sfx.py [bounce]
"""

import sys
import wave

import numpy as np

SR = 22050


def envelope(n: int, attack: float, decay_tau: float) -> np.ndarray:
    t = np.arange(n) / SR
    env = np.exp(-t / decay_tau)
    attack_n = max(int(attack * SR), 1)
    env[:attack_n] *= np.linspace(0.0, 1.0, attack_n)
    return env


def render(stem: np.ndarray, path: str) -> None:
    stem = stem / (np.max(np.abs(stem)) + 1e-9) * 0.72
    data = (np.stack([stem, stem], axis=1) * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"wrote {path} ({len(stem) / SR:.2f}s)")


def make_bounce() -> np.ndarray:
    """Soft woody tock: damped low sine + filtered noise transient."""
    dur = 0.16
    n = int(SR * dur)
    t = np.arange(n) / SR
    env = envelope(n, attack=0.002, decay_tau=0.035)
    body = np.sin(2 * np.pi * 185 * t) * 0.8 + np.sin(2 * np.pi * 370 * t) * 0.25
    rng = np.random.default_rng(11)
    click = rng.standard_normal(n) * envelope(n, attack=0.0005, decay_tau=0.006) * 0.5
    return (body + click) * env


def make_stretch() -> np.ndarray:
    """Subtle rubber-band stretch / tension tick for slingshot charging."""
    dur = 0.08
    n = int(SR * dur)
    t = np.arange(n) / SR
    env = envelope(n, attack=0.003, decay_tau=0.025)
    f = 240 + 180 * (t / dur)
    body = np.sin(2 * np.pi * f * t) * 0.7
    return body * env


def make_launch() -> np.ndarray:
    """Airborne launch whoosh for roar-loft shots and jumps: filtered noise
    swell with a rising sine shimmer, gone in half a second."""
    dur = 0.5
    n = int(SR * dur)
    t = np.arange(n) / SR
    env = envelope(n, attack=0.06, decay_tau=0.16)
    rng = np.random.default_rng(7)
    noise = rng.standard_normal(n)
    # Cheap low-pass: moving average softens the hiss into a whoosh.
    kernel = np.ones(24) / 24.0
    whoosh = np.convolve(noise, kernel, mode="same") * 1.6
    shimmer = np.sin(2 * np.pi * (300 + 500 * t / dur) * t) * 0.22
    return (whoosh + shimmer) * env


def make_cheer() -> np.ndarray:
    """Celebration sting for sinking the cup: quick major arpeggio blip."""
    dur = 0.7
    n = int(SR * dur)
    t = np.arange(n) / SR
    out = np.zeros(n)
    # C5-E5-G5-C6 sparkle, one note per 90 ms.
    for i, freq in enumerate([523.25, 659.25, 783.99, 1046.5]):
        start = int(SR * 0.09 * i)
        seg = t[: n - start]
        note_env = envelope(n - start, attack=0.004, decay_tau=0.14)
        note = (np.sin(2 * np.pi * freq * seg) * 0.6
                + np.sin(2 * np.pi * freq * 2 * seg) * 0.18)
        out[start:] += note * note_env
    return out


def make_roll() -> np.ndarray:
    """Loopable rolling texture: low-passed rumble with a soft surface throb.
    The tail cross-feeds into the head so the loop point is click-free."""
    dur = 0.6
    n = int(SR * dur)
    t = np.arange(n) / SR
    rng = np.random.default_rng(3)
    rumble = np.convolve(rng.standard_normal(n), np.ones(48) / 48.0, mode="same") * 2.2
    fade = int(SR * 0.05)
    rumble[:fade] = (rumble[:fade] * np.linspace(0.0, 1.0, fade)
                     + rumble[n - fade:] * np.linspace(1.0, 0.0, fade))
    grain = np.sin(2 * np.pi * 9 * t) * 0.15
    return rumble + grain


MAKERS = {"bounce": make_bounce, "stretch": make_stretch,
          "launch": make_launch, "cheer": make_cheer, "roll": make_roll}


def main() -> None:
    name = sys.argv[1] if len(sys.argv) > 1 else "bounce"
    if name not in MAKERS:
        raise SystemExit(f"unknown effect '{name}' (have: {', '.join(sorted(MAKERS))})")
    render(MAKERS[name](), f"assets/audio/{name}.wav")


if __name__ == "__main__":
    main()
