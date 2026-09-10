# Store Listing & Policy Materials (RB-056 preparation)

Draft materials for the Google Play listing. The **name "Roarball" has no
trademark clearance yet** — that legal step and the final publishing account
remain the open parts of RB-056. Everything here is draft text ready for that
review.

## Store listing

**App name:** Roarball

**Short description (80 chars max):**
> Mini-golf where your voice is the power. Whisper to putt — roar to leap!

**Full description:**

> Roarball is a cozy 3D mini-golf puzzle game with a twist: your voice sets
> the shot power. Aim your cute lion ball with a swipe, then make a sound —
> a soft hum rolls the ball gently, a stronger sound launches it further.
> No shouting needed: a comfortable voice does everything.
>
> • 12 handcrafted floating-island holes across two worlds
> • Voice-powered shots — calibrated to YOUR comfortable range
> • Touch mode is a full, equal alternative (slider + button)
> • Sliding gates, bounce pads, and portal pairs to master
> • Unlock 7 balls: Lion, Classic, Gold, Tiger, Leaf, Panda, Robot
> • No ads, no purchases, no accounts, no internet required
>
> Your voice is processed instantly on your device and is never saved,
> uploaded, or used to recognize words. Roarball works fully offline.

**Feature graphic / screenshots:** capture set lives on release
`v0.1.0-graybox-slice` (home, gameplay HUD, calibration, sunset holes).
Regenerate via `tools/capture_home.tscn` + `tools/capture_level.tscn`.

## Content rating questionnaire (IARC) intended answers

- No objectionable content; cartoon competition only, no violence depicted
  against real people.
- No sharing of user-generated content; no communication features.
- No purchases, no ads, no gambling-adjacent mechanics.
- Expected rating: ESRB E / PEGI 3 (pending formal questionnaire).

## Data safety (Play Data safety form) — intended answers

- **Data collected:** None.
- **Data shared:** None.
- **Audio/microphone:** processed ephemerally on-device during explicit
  shot/calibration interactions; never stored, never transmitted, never used
  for speech recognition. Backed by `docs/PRIVACY_AND_DEPENDENCY_AUDIT.md`
  and the save-schema tests (PCM structurally cannot persist).
- **Account creation:** Not required. Everything is local.

## Privacy policy (draft — host at the final URL before submission)

> Roarball does not collect, store, or transmit personal data. The game
> works entirely offline. When you use Voice mode, microphone audio is
> analyzed in real time on your device to measure loudness — it is never
> recorded, saved, or uploaded, and no speech recognition is performed.
> The game stores only your progress and settings locally on your device
> (best scores, stars, unlocked cosmetics, sound preferences, and three
> calibration numbers). Deleting the app deletes all of it. Roarball
> contains no advertising, analytics, or third-party tracking of any kind.
> Contact: [publisher contact to be supplied at submission].

## Submission checklist (blocked items in **bold**)

- [x] Signed AAB/APK build pipeline (`tools/build_android.sh`)
- [x] Privacy audit (`docs/PRIVACY_AND_DEPENDENCY_AUDIT.md`)
- [x] Listing copy draft (this document)
- [ ] **Trademark/name clearance for "Roarball" (legal — external)**
- [ ] **Publisher account + privacy policy hosting (operations — external)**
- [ ] **On-device install + offline smoke (RB-002 hardware matrix)**
