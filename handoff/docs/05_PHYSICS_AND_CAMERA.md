# Physics, Obstacles, and Camera Specification

## 1. Physics setup

Use one RigidBody3D ball with a SphereShape3D collider, integrated Jolt, fixed 60 Hz physics, and continuous collision detection enabled for the fast-moving ball. Godot documents impulse-based rigid-body control and CCD behavior [S03, S04]. CCD reduces missed collisions; it is not a guarantee against every tunneling case.

Start with radius 0.25 m, mass 1.0 kg, and gravity 9.8 m/s². Keep visual scale independent of collision scale. Avoid nonuniformly scaling the physics body. A decorative lion mane cannot protrude into a larger gameplay collider than other cosmetics.

Use static collision for course surfaces, kinematic/AnimatableBody3D wrappers for moving obstacles, and Area3D triggers for cup, pads, portals, and kill volumes. Complex scenery must not accidentally become collidable. A fixed collision-layer convention is part of the project setup: Ball, Course, MovingObstacle, GameplayTrigger, and CameraBlocker.

## 2. Impulse and movement

An accepted shot becomes `direction.normalized() * impulse_magnitude`. Apply once via the rigid body's impulse API on a physics tick. Do not apply the same impulse every rendered frame or multiply an impulse by delta. Do not directly overwrite position each frame to imitate a rolling simulation [S04].

At Ready, remove only measured numerical drift; do not reset a still-moving body's angular motion to force readiness. The initial impulse curve is the shared domain function in document 02. The candidate upper speed cap is 18 m/s for bug containment after pad/portal interactions. If cap use becomes frequent, fix tuning rather than silently flattening every strong shot.

Use modest physical friction and explicitly tune rolling resistance. Friction alone is not a reliable design specification for how far a golf ball should roll. Proposed turf resistance decelerates tangential speed at 0.55 m/s² while supported; wood uses 0.35 m/s². Compute only the tangential component relative to contact/support normal. Preserve gravity and vertical momentum; do not apply ground resistance in flight.

Avoid double-counting resistance through both heavy engine damping and a custom term. An initial small global damping of 0.05 can be evaluated; keep a tuning log. Reduce tangential speed toward zero, never reverse it. The implementation belongs in the safe physics integration path, with tests on flat terrain and slopes.

## 3. Support and resting anchors

A rest detector checks speed, angular speed, support, and duration. The authored thresholds are 0.06 m/s, 0.3 rad/s, and 0.4 seconds. Require a valid static support with a normal close enough to up for a safe reset position. Proposed maximum safe-anchor slope: 15 degrees. Being almost motionless in midair is not rest.

Store the last safe resting transform, not the ball's last position before a fall. Exclude portals, pads, moving gates, cup capture zones, and positions too close to a cliff. A sphere overlap/sweep verifies free space before reset. If the saved anchor is blocked or no longer valid, use the last authored checkpoint or Spawn marker.

Reset must clear linear/angular velocity and active forces, move through the engine's safe physics-state mechanism, and restore motion without producing a residual impulse. Disable relevant trigger reactions during the reset window, then re-enable after the ball is safely supported. A one-shot penalty token prevents double counting.

## 4. Cup capture

Keep the cup collision and cup trigger distinct. Model a real opening/rim or intentionally use a visually convincing assisted capture; document the chosen approach. Do not cover a visual hole with invisible flat floor and expect a convincing drop.

The trigger verifies horizontal distance, a center-height band relative to cup surface, and low speed. Candidate thresholds: <=0.28 m horizontal, ball center from 0.15 to 0.40 m above cup plane, speed <=1.2 m/s. Adjust these against the actual 0.25 m radius and rim geometry. High-speed flyovers and underside entries must not complete.

Once accepted, GameSessionController enters Complete exactly once. Turn off shot input and fall resolution, then use a short cosmetic sink animation. Persist the result before presenting Next Hole. A celebratory visual copy of the ball may bounce; the scoring body is no longer active.

## 5. Portals

Portals are authored pairs with entry/exit transforms and explicit local forward axes. Construct a mapping basis from the entry frame to the exit frame; define the art's facing convention once. Transform velocity direction through that mapping and preserve allowed speed, rather than blindly reversing X or Z.

Place the ball at the exit clearance marker plus a safe radius offset. Check for collision-free space. A paired-portal cooldown is per ball and pair: candidate 0.4 seconds and until the ball has left the exit trigger. Do not rely on time alone while the ball remains inside. Mark teleport as a controlled transform update and ignore stale triggers for the transfer tick.

The exit must be visible in Overview and share the pair's symbol/color. Level validation ensures each portal has exactly one valid counterpart, an unobstructed exit, and no unavoidable immediate re-entry loop. Allow at most one pair per MVP hole to control complexity.

## 6. Bounce pads and moving gates

A pad applies its authored impulse only on a new eligible contact/entry. A contact latch clears after leaving. Holding a ball inside an Area3D must not add energy every frame. Use shared tuning with an allowed-speed cap and tests for side entry and repeated bounces.

Move gates using fixed physics-time motion and a clear period/phase. Candidate initial period is 3.0 seconds. Motion pauses with the session, not with wall-clock time; returning from background must not suddenly sweep through the ball. Kinematic collider movement must match the visible obstacle.

No gate should seal the only possible resting location. Gate collision feedback is harmless and readable; it may knock the ball away but must not trap it indefinitely. Avoid elaborate chained rigid bodies for the first release.

## 7. Camera modes

Ready camera: proposed 45-degree field of view, elevation 45–55 degrees, distance fit to ball and next relevant target. These are starting settings, not mandatory fixed coordinates. Keep the player ball above the bottom tray. Orient world-forward consistently within each hole; camera rotation is not part of the puzzle.

Follow camera: smoothed positional tracking with bounded speed; small look-ahead in travel direction; no automatic spin as the ball rolls. If the ball drops, keep its last useful course view then transition to reset; do not dive into the void after it.

Overview camera: fit authored course bounds excluding remote decorative islands. Freeze aim changes, but do not let overview pause moving hazards only when it benefits scoring; either overview is available only in Ready or explicitly pause the whole session consistently. MVP chooses Overview only in Ready, with simulation paused during inspection.

During Capturing, lock camera and aim so a thumb motion does not accidentally redirect the shot. On narrow screens adjust camera framing, not collision geometry. Reduced Motion uses direct or gentle transitions and no shakes.

## 8. Aiming visualization

MVP uses a direction ray and short dotted guide projected onto nearby terrain, plus explicit shot power. It is not an exact trajectory simulator. Clip it at the first obstruction and avoid promising a landing point past an unseen collision.

A later predictive preview must run the same physics/tuning model or clearly indicate uncertainty. Do not build a fake parabola that ignores rolling resistance, ramps, gates, or portals. That feature is outside the MVP and is not required to match the reference image.

## 9. Regression evidence

Each tuning change runs flat roll distances at 25/50/75/100% power, oblique wall rebounds, ramp launch, high-speed thin barrier, pad latch, portal exit/loop protection, cup flyover, slope settlement, safe reset, and duplicate fall events. Save a tolerance band per engine/content version, not an assertion of bit-identical outcomes across all devices.
