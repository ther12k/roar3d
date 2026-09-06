class_name RoarballVoiceEnergy
extends RefCounted
## Illustrative energy helper only, not a complete capture/permission service.
## The implementation must also track clipping, freshness and qualified duration.

static func rms_dbfs(frames: PackedVector2Array) -> float:
    if frames.is_empty():
        return -120.0
    var energy: float = 0.0
    for frame: Vector2 in frames:
        if not is_finite(frame.x) or not is_finite(frame.y):
            return -120.0
        energy += (frame.x * frame.x + frame.y * frame.y) * 0.5
    var rms: float = sqrt(energy / float(frames.size()))
    return clampf(20.0 * log(maxf(rms, 0.000001)) / log(10.0), -120.0, 0.0)

static func smooth_power(previous: float, target: float, dt: float) -> float:
    if not is_finite(previous) or not is_finite(target) or not is_finite(dt):
        return 0.0
    var alpha: float = 1.0 - exp(-maxf(dt, 0.0) / 0.08)
    return clampf(previous + alpha * (target - previous), 0.0, 1.0)
