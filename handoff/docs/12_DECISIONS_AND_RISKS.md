# Decisions, Risks, and Open Questions

## Architecture decisions

ADR-001: One Godot runtime owns both UI and world. Rationale: avoid a second rendering/input/lifecycle boundary for a standalone game. Revisit only if this game becomes part of a larger existing application.

ADR-002: Typed GDScript is the default gameplay language. Kotlin is a conditional Android adapter, never a parallel gameplay layer. No mandatory native addon is selected.

ADR-003: Integrated Jolt is the initial physics choice, pinned with the engine [S03]. Validate actual ball/ramp/portal behavior before content scaling; engine choice is not proof of appropriate golf tuning.

ADR-004: Offline local progression and cosmetic-only rewards. No account, economy, advertising, purchases, or analytics SDK in MVP. Reference art containing these elements is explicitly superseded.

ADR-005: Voice uses local calibrated amplitude; Touch is equivalent. No speech model or actual scream threshold. Hardware capture lifetime must be measured independently of UI state.

ADR-006: Twelve authored holes across two worlds; one polished vertical slice precedes full content. Par and power bands remain provisional until playtested.

ADR-007: Menus use Godot Controls and theme resources. Reference PNGs are review material only; they are not production UI layers or 3D assets.

## Risk register

| Risk | Impact | Mitigation / owner |
|---|---|---|
| Microphone remains active outside interaction. | Privacy failure; possible native work. | G0 physical indicator/lifecycle test; audio/platform owner. |
| Ambient noise or automatic gain makes power unpredictable. | Frustration; false shots. | Per-route calibration, valid-duration gate, clear Touch fallback; audio owner. |
| Game music powers the next shot. | Broken control. | Silent monitoring path and ducked output during capture; audio owner. |
| Concept art drives excessive geometry/effects. | Low frame rate or scope explosion. | One measured mobile slice and modest modular kit; art/tech lead. |
| Ball never settles or tunnels through edges. | Unplayable holes. | Rolling-resistance tuning, CCD tests, simplified collision; gameplay owner. |
| Portal/pad triggers repeat. | Infinite acceleration or loops. | Per-shot IDs, pair/contact latches, regression scenes; gameplay owner. |
| Physics changes invalidate authored pars. | Unfair progression. | Versioned tuning and solution revalidation; design/QA. |
| Save write interruption loses progress. | Trust loss. | Validate/backup/recover and kill-step tests; systems owner. |
| AI implementation delivers a UI facade. | False completion. | Real-device video, node/code inspection, strict task evidence; lead. |
| Child/family positioning adds compliance work. | Release risk. | Publisher decision and current policy review before submission. |
| Working name conflicts with existing product. | Branding/release risk. | Commercial name/trademark review; publisher. |

## Open decisions with defaults

Final Android minimum device/API: default is unresolved until M0 measurement; do not advertise compatibility early. Default input choice: show Voice and Touch equally on first run; do not default into a permission dialog. Renderer: evaluate Mobile first, Compatibility fallback as an explicit tested target [S02].

Monetization: none in MVP. iOS: later. Kotlin: absent unless RB-048 is approved with reproduction evidence. Final art tools/font/license selection: team-owned approval; no font binaries or third-party art packs are bundled.

## Change policy

Changes affecting controls, privacy copy, physics, stars, unlocks, or engine version require an updated decision entry, impacted-task list, and targeted regression plan. Adding new mockups does not automatically expand scope. Any business request for analytics, recording, accounts, or purchases is a separate privacy/security review.
