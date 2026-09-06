#!/usr/bin/env python3
"""Python reference-contract tests. These do not execute Godot/GDScript."""
import math
import unittest


def impulse(p: float) -> float:
    return 0.0 if not math.isfinite(p) or not 0 < p <= 1 else 1.5+8.5*p**1.6


def stars(completed: bool, strokes: int, par: int, maximum: int=12) -> int:
    if not completed or strokes<1 or par<1 or strokes>maximum:
        return 0
    return 3 if strokes<=par else 2 if strokes==par+1 else 1


def dbfs(frames: list[tuple[float,float]]) -> float:
    if not frames or any(not math.isfinite(x) for f in frames for x in f):
        return -120.0
    energy=sum((l*l+r*r)/2 for l,r in frames)/len(frames)
    return max(-120.0, min(0.0,20*math.log10(max(math.sqrt(energy),1e-6))))


def smooth(previous: float,target: float,dt: float) -> float:
    alpha=1-math.exp(-max(dt,0)/0.08)
    return max(0,min(1,previous+alpha*(target-previous)))


def quantile(values: list[float],q: float) -> float:
    if not values:
        return 0.0
    values=sorted(values); pos=(len(values)-1)*q; lo=math.floor(pos); hi=math.ceil(pos)
    return values[lo]+(values[hi]-values[lo])*(pos-lo)


def commit_preview(windows: list[tuple[float,float,bool]]) -> float:
    # Windows are (duration_seconds, smoothed_power, signal_qualified), oldest first.
    recent=[]; remaining=0.250
    for duration,power,qualified in reversed(windows):
        take=min(duration,remaining)
        if take<=0:
            break
        recent.append((take,power,qualified));remaining-=take
    if sum(t for t,p,q in recent if q)<0.150-1e-9:
        return 0.0
    return quantile([p for t,p,q in recent if q],0.75)


class ContractTests(unittest.TestCase):
    def test_zero_power_rejected(self): self.assertEqual(impulse(0),0)
    def test_negative_power_rejected(self): self.assertEqual(impulse(-1),0)
    def test_over_range_power_rejected(self): self.assertEqual(impulse(1.1),0)
    def test_nonfinite_rejected(self): self.assertEqual(impulse(float('nan')),0)
    def test_max_power(self): self.assertEqual(impulse(1),10)
    def test_monotonic_curve(self):
        values=[impulse(i/100) for i in range(1,101)]
        self.assertEqual(values,sorted(values))
    def test_par(self): self.assertEqual(stars(True,3,3),3)
    def test_under_par(self): self.assertEqual(stars(True,2,3),3)
    def test_par_plus_one(self): self.assertEqual(stars(True,4,3),2)
    def test_par_plus_two(self): self.assertEqual(stars(True,5,3),1)
    def test_twelfth_win(self): self.assertEqual(stars(True,12,3),1)
    def test_thirteenth_fails(self): self.assertEqual(stars(True,13,3),0)
    def test_incomplete_no_stars(self): self.assertEqual(stars(False,2,3),0)
    def test_invalid_strokes(self): self.assertEqual(stars(True,0,3),0)
    def test_silence(self): self.assertEqual(dbfs([(0,0)]*10),-120)
    def test_known_amplitude(self): self.assertAlmostEqual(dbfs([(0.1,0.1)]*10),-20)
    def test_opposite_phase(self): self.assertAlmostEqual(dbfs([(0.1,-0.1)]*10),-20)
    def test_empty_audio(self): self.assertEqual(dbfs([]),-120)
    def test_corrupt_audio(self): self.assertEqual(dbfs([(float('nan'),0)]),-120)
    def test_smoothing_time_invariance(self):
        self.assertAlmostEqual(smooth(smooth(0,1,0.04),1,0.04),smooth(0,1,0.08))
    def test_short_noise_cannot_commit(self):
        self.assertEqual(commit_preview([(0.02,1.0,True)]),0)
    def test_stable_window_can_commit(self):
        self.assertAlmostEqual(commit_preview([(0.02,0.5,True)]*10),0.5)
    def test_old_audio_expires(self):
        windows=[(0.02,1.0,True)]*10+[(0.02,0.0,False)]*13
        self.assertEqual(commit_preview(windows),0)
    def test_quantile(self): self.assertAlmostEqual(quantile([0,0.25,0.5,0.75,1],0.75),0.75)


if __name__=='__main__':
    unittest.main(verbosity=2)
