# Measured Power Bands per Hole (RB-047 / docs/02 §8)

Bands below come from the automated route suites on the pinned engine
(`run_level_route_tests.tscn` + `run_hole_route_tests.tscn`, headless Jolt
4.7.2). Power p is the normalized 0–1 value; shot speed ≈ 1.5 + 8.5·p^1.6 m/s.
Effective flat deceleration is velocity-dependent (≈ 0.55 + 0.08·v m/s², see
D-018), so distances shrink on longer rolls. These are **engine-measured
reference bands**, not human-playtested tuning — the qualitative playtest
itself (feel, frustration, fun) remains the open part of RB-047.

| Hole | Shot | Min | Recommended | Max | Notes |
|---|---|---|---|---|---|
| CC01 | Tee putt | 0.30 | 0.40 | 0.55 | 4 m corridor; overshoot hits back rail safely |
| CC02 | Tee → approach | 0.30 | 0.40 | 0.45 | plateau edges punish sideways power ≥ ~0.5 |
| CC02 | Green-front finish | 0.05 | 0.065 | 0.08 | cup has 1.2 m overrun room behind it |
| CC02 | Strong tee bank | 0.70 | 0.75 | 0.85 | outer rail stops the ball in putt range |
| CC03 | Corner entry | 0.45 | 0.60 | 0.60 | shallow diagonals only; head-on banks stop dead |
| CC04 | Ramp jump | 0.60 | 0.75 | 0.80 | below 0.6 stalls on the slope |
| CC05 | Pre-gate staging | 0.35 | 0.40 | 0.45 | then poll the gate and pass at 0.55 |
| CC06 | Gate pass + jump | 0.15 | 0.20 (gate) / 1.0 (jump) | — | stage between; jump needs near-max from the ramp foot |
| PP01 | Portal entry | 0.35 | 0.45 | 0.55 | exit nudge carries onto the approach |
| PP02 | Portal entry | 0.35 | 0.45 | 0.55 | same family as PP01 |
| PP03 | Pad runway | 0.50 | 0.56 | 0.62 | pad gives vertical launch; roll supplies approach |
| PP04 | Portal + pad run | 0.40 | 0.45 (portal) / 0.55 (pad) | 0.60 | two-stage staging is forgiving |
| PP05 | Portal + gate | 0.40 | 0.45 / 0.65 | 0.70 | generous staging both sides of the gate |
| PP06 | Portal + pad | 0.40 | 0.45 / 0.55 | 0.60 | finishing putts under par are common |

## Observations for the human playtest (RB-047)

- Finishing putts have narrow bands (±0.02 p) because the 1.5 N·s impulse
  floor dominates short taps. First human playtest confirmed the frustration
  (D-020): the cup capture band widened to 0.34 m / 1.5 m/s, and the touch
  slingshot now eases drag->power (p = (drag/170 px)^1.35) so the 0.05–0.08
  finishing band sits at the dead-zone edge. The impulse model itself is
  unchanged — all bands above remain authoritative for route tests.
- Gate holes reward waiting — confirm the wait is communicated (gate
  travel is visible from the staging plateau).
- Corner/bank holes need the "shallow angle" lesson taught (CC03 is the
  teaching hole); watch newcomers attempt head-on banks.
- Max-power tee shots never leave the course at CC01/CC02 (rails contain);
  plateau holes (CC02, PP03+) are where falls happen — intended.
