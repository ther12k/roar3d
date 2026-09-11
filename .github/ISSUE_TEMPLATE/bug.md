---
name: Bug report
about: Reproducible gameplay, UI, audio, or platform failure
---

## Environment — every field required

- RC tag tested: <!-- e.g. v0.1.0-rc1 — report against the frozen RC, never "latest" -->
- Device model:
- Android version:
- Renderer: <!-- Mobile / Compatibility -->
- Input mode: <!-- Touch / Voice -->
- Audio route: <!-- speaker / wired / Bluetooth -->
- Hole: <!-- e.g. CC04, or "menu" -->

## Steps

1. ...

## Expected vs actual

Describe the observable difference. Quote numbers (frame ms, strokes, seconds) wherever possible — "feels weird" is a starting point, not a report.

## Evidence

Attach non-sensitive logs, screenshots, or video of the reproduction; include FPS/frame-time overlay samples (`ROAR3D_PERF=1`) when performance is involved. Do not attach player voice recordings, PCM buffers, or credentials.

## Severity and recovery

Does it crash, lose progress, retain microphone access (OS indicator), or block completion? How did you recover?
