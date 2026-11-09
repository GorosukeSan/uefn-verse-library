# CharacterSystem / LookKit

The "visual motion" Kit for custom characters. Following the body's (`character_motor_component`) motion and events, it squashes and stretches the visual shell with a spring (squash and stretch) and keeps the core inside the shell at the center of the deformed shell. Collision (the body's capsule) is unchanged. Only the local transforms of the visual entities are written.

## Setup (placement)

| component | Where to place | What it does |
|---|---|---|
| `character_squash_stretch_component` | the custom character's body (the `character_motor_component` entity or a descendant) | Every frame (the body's `PostMoveEvent`), moves toward the shape of the current state (still, running, airborne) with a per-axis spring; on events (jump, air jump, landing, dash, wall) snaps to that shape and springs back. Writes the `Shell`'s scale and lean and the `Core`'s position (center of the shell) |

Example: "a character with a small glowing core floating inside a transparent box shell"
```
Prefab
└ Body (character_motor_component + MoveKit / BodyKit components + character_squash_stretch_component (Shell = shell, Core = core))
  └ Visuals (entity that groups facing and position)
    ├ Shell (100 cm box mesh. Origin at the bottom center. Scale 1.1 -> 110 cm. Placed at the feet)
    └ Core (same box mesh. Scale 0.28. 41 cm up = its center at the center of the shell)
```
- Put the shell mesh's origin at the feet (bottom center). Scale factors and lean apply around the origin, so the feet stay on the ground through squash and stretch.
- Place the core as a child of the same parent as the shell (with different parents, a message goes to the output log at start and the core drifts from the center). If the core mesh's origin is its center, turn `MeshPivotAtBottom` off.
- The position, rotation and scale of the shell and core as placed in the editor are the base shape. They are read one frame after start (inside `OnBeginSimulation` the prefab's children may not be in the scene yet and may not follow when moved). The base shape is restored when stopping.
- If `Shell` is empty, nothing happens (logged once to the output log). If `Core` is empty, only the shell moves.

## Motion

Target shape every frame (forward, left, up factors. 1 keeps the base):
- Still on the ground: breathing (vertically +/-`IdleBreathAmount`, one cycle per `IdleBreathSeconds`).
- Running on the ground: vertical bob (+/-`RunBobAmount`, one cycle per `RunBobStrideCm` traveled) and a lean toward the travel direction around the feet (up to `RunLeanDegrees`). Both peak at a horizontal speed of `RunFullSpeedCmPerSecond` and blend with breathing while slower.
- In the air: vertical stretch with the vertical speed (`AirStretchPer1000CmPerSecond` per 1000 cm/s, up to `AirStretchMax`). The lean returns to zero.

Events (the body's `ActionEvent` / `LandedEvent`): the shape snaps, holds for `PulseHoldSeconds` (`DashHoldSeconds` for a dash), then springs back to the target (overshooting a little).
- `Jumped` -> `JumpScale`, `AirJumped` -> `AirJumpScale`
- Landing -> nothing if the downward speed is below `LandMinSpeedCmPerSecond`, `LandSquashScale` at `LandFullSpeedCmPerSecond` (blended in between)
- `Dashed` -> `1 + DashStretch` toward the current horizontal velocity
- `HitWall` -> `1 - HitWallSquash` along the horizontal velocity before the hit (only when the horizontal speed then was at least `HitWallMinSpeedCmPerSecond`. It arrives every frame while pressed against a wall, so at most once per 0.3 s)

With `PreserveVolume`, the three axis factors are normalized so their product is 1 before applying to the shell (stretching vertically gets thinner, squashing gets fatter). `JumpScale (0.8, 0.8, 1.3)` becomes `(0.85, 0.85, 1.38)`.

### Rule for stretching toward the travel direction (dash, wall)
Scale factors can only be applied along the shell's axes (forward, left, up), never along a skewed direction. So the travel direction is split into the shell's axes and each axis is stretched by the square of its share.
- If the body faces the travel direction (`Turn` of BodyKit's `character_face_movement_component`), only the shell's forward axis stretches (the intended shape).
- When moving diagonally (`Strafe` at an angle, etc.), forward and left stretch by their shares (no rhombus).
- The velocity is read in the orientation of the shell's parent entity (the body's yaw belongs to the body entity).

### Core
The core's center in the base shape is measured from the shell's origin along the shell's axes, moved by the same factors as the shell and leaned the same way (so it ends up at the center of the deformed shell). The core's scale follows the shell's deformation by `CoreDeformRatio` (0 unchanged, 1 same as the shell).

## Settings (@editable)
- `Shell : ?entity = false` — the shell entity to squash and stretch.
- `Core : ?entity = false` — the core entity kept at the center of the shell.
- `MeshHeightCm : float = 100.0` — height of the core mesh at scale 1 (cm). Used to find the core's center.
- `MeshPivotAtBottom : logic = true` — on: the core mesh's origin is at the bottom center; off: at the center.
- `CoreDeformRatio : float = 0.0` — fraction by which the core follows the shell's deformation (0..1).
- `SpringStiffness : float = 260.0` — spring stiffness (1..5000. Higher returns faster).
- `SpringDamping : float = 14.0` — spring damping (0..200. Lower keeps oscillating; around 2 x sqrt(stiffness) returns without oscillating). The spring is advanced in 0.008 s slices, so it stays stable on long frames.
- `PreserveVolume : logic = true` — roughly preserve volume.
- `PulseHoldSeconds : float = 0.05` — seconds to hold the jump / landing / wall shape.
- `JumpScale : vector3 = (0.8, 0.8, 1.3)`, `AirJumpScale : vector3 = (0.75, 0.75, 1.35)`, `LandSquashScale : vector3 = (1.3, 1.3, 0.65)` — shapes (forward, left, up factors).
- `LandMinSpeedCmPerSecond : float = 250.0`, `LandFullSpeedCmPerSecond : float = 1800.0` — downward landing speed at which squashing starts / is strongest.
- `DashStretch : float = 0.45`, `DashHoldSeconds : float = 0.15` — amount of dash stretch and how long to hold it (about MoveKit dash's `DurationSeconds`).
- `HitWallSquash : float = 0.25`, `HitWallMinSpeedCmPerSecond : float = 350.0` — amount of wall squash (0 disables) and the minimum speed for it.
- `AirStretchPer1000CmPerSecond : float = 0.15`, `AirStretchMax : float = 0.25` — vertical stretch in the air.
- `RunBobAmount : float = 0.04`, `RunBobStrideCm : float = 160.0`, `RunFullSpeedCmPerSecond : float = 600.0`, `RunLeanDegrees : float = 5.0` — run bob and lean (0 disables).
- `IdleBreathAmount : float = 0.025`, `IdleBreathSeconds : float = 2.4` — breathing (0 disables).

## Public API
```verse
character_look_pulse<public> := enum:
    Jump
    AirJump
    Land          # same as landing at the speed halfway between LandMinSpeedCmPerSecond and LandFullSpeedCmPerSecond
    Dash          # toward the current horizontal velocity
    HitWall       # along the previous frame's horizontal velocity

character_squash_stretch_component<public> := class<final_super>(component):
    Shell<public>:?entity
    Core<public>:?entity
    # (the other @editable values are under "Settings" above)
    Pulse<public>(Kind:character_look_pulse):void                  # add a preset deformation (amounts from the @editable values)
    PulseLanding<public>(SpeedCmPerSecond:float):void              # squash as if landing at this downward speed
    Squash<public>(Amount:float):void                              # squash vertically (0..0.8). Negative stretches vertically
    PulseShape<public>(Shape:vector3, HoldSeconds:float):void      # snap to Shape (forward, left, up factors along the shell's axes), hold for HoldSeconds, then spring back
    GetDeformation<public>()<reads>:vector3                        # the factors currently applied to the base scale (after normalizing with PreserveVolume)
```
From game code, find it with `GetComponent[character_squash_stretch_component]` on the body entity (e.g. via `Entity.FindCharacterMotorFor[Agent]`) and call it (landed on a bouncy floor, took damage, etc.). Successive `Pulse`-style calls replace the previous one.

## Requirements, caveats and limits
- Writes the local transforms of the shell and core every frame. Do not move the shell or core from other components (move the parent entity instead).
- The body's motion (collision, capsule) is unchanged. Visuals only.
- The direction of the lean rotation is chosen by rotating the up axis and picking the way that tips toward the travel direction (independent of the sign convention of rotations).
- ⚠ Unverified (UEFN v43.00): whether writing the local scale and rotation of the shell and core every frame looks smooth to other players.
