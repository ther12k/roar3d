# Art Direction and Asset Pipeline

## 1. Translation from concept to real-time

Keep the cheerful lion ball, rich green turf, pale stone cliffs, wood ramps, blue sky, and warm flags. Replace expensive cinematic detail with stylized shape, baked detail, readable silhouettes, and a small modular kit. The reference images are direction, not production assets or a performance promise.

Distant waterfalls use ribbons/planes and lightweight material animation. Distant islands may be low-detail meshes or background cards. Do not simulate water, render an entire kingdom, or use dozens of dynamic shadow lights to copy a concept image.

## 2. Asset roster

| Asset group | MVP contents | Initial budget |
|---|---|---|
| Ball | Lion, Panda, Robot; common sphere collider. | 2–4k triangles each; 1 material preferred. |
| Course kit | Straight, corner, wide green, cliff edge, ramp, rail. | 0.5–2k triangles/module; shared materials. |
| Cup kit | Rim, flagpole, flag, bottom/sink visual. | <2k triangles, simple collider. |
| Obstacles | Gate, portal entry/exit, pad. | 1–3k triangles each; collision simplified. |
| Environment | Rocks, trees, bushes, distant islands, waterfall ribbons. | Instanced repeats; no decorative collision. |
| UI | Panels, icons, stars, input badges, map thumbnails. | Reusable theme; no baked text. |
| Effects | Collision puff, pad pulse, portal flash, small confetti. | Bounded particle count; reduced-motion variant. |
| Audio | Putt, impact, fall, cup, pad, portal, result, ambient music. | Short licensed/original clips; no recorded player sound. |

These budgets are proposals. Final visible-scene budget is more important than the sum of every library asset. Record draw calls, material instances, texture memory, and transparency cost on the target device.

## 3. Blender and Godot workflow

Author using a consistent real-world scale and apply transforms before export. Use one meter per Godot unit. Export GLB/glTF with predictable names, origins, and material paths; this is a supported/recommended Godot import route [S11]. Keep `.blend` source under the team's art-source policy, with exported `.glb` as the runtime interchange artifact.

Store pivot conventions in an asset checklist: ball centered at origin; course module grid alignment; gate hinge/slide axis; portal local forward and exit marker; pad up-axis. Reimport one test asset before committing the whole kit.

Hand-authored Godot wrapper scenes own collision, interaction areas, scripts, sounds, and semantic markers. An artist's re-export must not replace a tested cup trigger or portal link. Use simplified box/convex collision for active objects; detailed background cliff meshes do not need colliders.

## 4. Material and lighting plan

Start with a shared turf/stone/wood palette atlas and no more than one or two material slots per common prop. Use 512–1024 textures for most props and at most 2048 where justified. Bake surface detail rather than using extra geometry everywhere. Avoid layered transparent foliage covering much of the phone screen.

One primary directional light and baked/static ambient treatment are the baseline. Establish the look on the chosen mobile renderer before producing final materials. Do not rely on unsupported or expensive effects simply because they appear in an editor screenshot [S02]. Low quality removes decorative effects, not gameplay cues.

## 5. Mascot and cosmetics

Make the ball's face readable at ordinary gameplay size. Use a compact mane integrated into the spherical silhouette; protruding horns and ears remain cosmetic. Panda and Robot change materials/face shells, not collider shape or mass.

Required expressions: idle, concentrating, rolling, surprised, success. Start with simple blend/material swaps or transform-based expressions instead of a complex rig. Optional face stabilization should not alter the physics transform.

## 6. UI construction

Rebuild panels and controls in a theme. Export only original icons and decorative textures as transparent assets with padding for nine-patch use where needed. Never crop a screenshot's button including text and use it as the final control. All text remains real UI text for localization and scaling.

`design/design_tokens.json` is a machine-readable starting point, not a generated Godot Theme. A task explicitly implements and verifies the theme. Fonts must be selected/licensed by the implementation team; no font binaries are included in this delivery.

## 7. Asset acceptance and provenance

For each asset, record author/source, license, modifications, source file, export file, triangle/material count, collider owner, and usage. The supplied AI concept images remain references; they are not proof of trademark clearance, exclusive rights, or a third-party asset license. The working name Roarball has not been cleared for commercial use.

Before approving a level, review it at actual phone size and in low quality. Collision boundaries, cup, gate timing, and portal pairing must remain readable without visual effects. Artifact files in this package contain no final `.glb` meshes or production audio.
