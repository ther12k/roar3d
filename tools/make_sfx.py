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


MAKERS = {"bounce": make_bounce, "stretch": make_stretch}


def main() -> None:
    name = sys.argv[1] if len(sys.argv) > 1 else "bounce"
    if name not in MAKERS:
        raise SystemExit(f"unknown effect '{name}' (have: {', '.join(sorted(MAKERS))})")
    render(MAKERS[name](), f"assets/audio/{name}.wav")


if __name__ == "__main__":
    main()
