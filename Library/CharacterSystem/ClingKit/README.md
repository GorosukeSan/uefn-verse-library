# ClingKit

The "slime ability": a custom character (CharacterSystem's `character_motor_component`) clings to walls and ceilings and crawls on them. It is built to be granted temporarily by an item (a PickupSystem effect prefab) and can be set up without writing code.

## Setup (placement)

| component | Where to place | What it does |
|---|---|---|
| `character_cling_component` (ClingKit) | the same entity as `character_motor_component` (walk is required too. With jump, you can jump off) | While clinging is allowed (with `RequiresGrant`, while a `GrantsCling` modifier is on the body), attaches when pushing into a wall or hitting a ceiling, crawls by input, and lets go on jump, ledge, edge or lost grant |
| `character_move_grant_component` (BuffKit) | a PickupSystem effect prefab (root or child), inside a loadout, or wherever the activation signal arrives | With `GrantCling = true`, stacks the cling grant (`character_modifier.GrantsCling`) onto the body from the activation signal to the deactivation signal |

Example: "pick it up and become a slime that can cling to walls and ceilings for 10 seconds"
```
Loadout prefab
└ Body (character_motor_component + character_walk_component + character_jump_component + character_face_movement_component
      + character_cling_component (RequiresGrant = true))
  └ Visuals (mesh)

Effect prefab (PickupSystem. Effect duration 10 s)
└ Root (pickup_effect_component + character_move_grant_component (GrantCling = true, ExtraAirJumps = 0))
```
`character_move_grant_component.ExtraAirJumps` defaults to 1, so set it to 0 when granting cling only. When the effect ends (deactivation signal, or the effect prefab disappears) the grant is removed, and a clinging body lets go on the spot and falls.
For a character that can always cling, set `character_cling_component.RequiresGrant = false` (no effect needed).

## How it moves

Every frame (the body's `TickEvents.PrePhysics`):

1. The body's `PreMoveEvent` (the order of walk / jump / dash / cling is unspecified)
   - If clinging: if jump asked to release, release (`TakeClingRelease`). If the grant is gone or `LockInput` is on, release. Otherwise set gravity to 0 (`ScaleGravityThisFrame(0)`), derive a velocity along the surface from the input and set it on the body (`SetVelocity`). Also give the body the velocity jump would use (`SetClingState`)
   - walk checks the body's `IsMoveOverridden` (succeeds while clinging) and leaves the velocity alone (the input direction `GetInputDirection` and input `GetMoveInput` are still recorded = read by cling. They may be one frame old)
   - When jump is pressed, jump checks the cling first (`GetClingSurface`): on a wall it jumps with the `GetClingJumpVelocity` velocity (`Jumped`), on a ceiling it lets go and falls. Either way it asks cling to release with `RequestClingRelease`
2. The body: gravity (x0) -> capsule sweep (the velocity runs along the surface, so the surface clung to is not hit) -> grounding (not probed while clinging and rising)
3. The body's `PostMoveEvent`
   - If clinging: checks inner corner -> stick to surface -> top ledge -> outer corner -> no surface, in that order (below)
   - If not clinging: decides whether to attach, ceiling first (`HitWall` this frame with a ceiling straight above), then wall (a wall in walk's input direction)

### Attaching
- Wall: walk's input direction points within 60 degrees at a non-walkable surface (steeper than the body's `MaxSlopeDegrees`) whose normal's vertical component is above -0.7 (walls, overhanging walls), and there is a wall within about 10 cm in that direction. Immediately in the air; on the ground, with `AttachFromGround`, after pushing for `GroundAttachDelaySeconds`.
- Ceiling: on the frame the body hits a ceiling (normal's vertical component at most -0.7) in the air, with a ceiling within about 10 cm straight above (no input needed).
- At the moment of attaching: the body is pulled to SkinCm (2 cm) from the surface and only the velocity along the surface is kept (cut to the crawl speed). `ClingStart` is reported, and a dash in progress ends.
- No attaching during `ReattachCooldownSeconds` (after jumping, letting go, hopping onto a ledge or `Release`).

### Crawling (mapping the input)
- Wall (`ClimbSpeedCmPerSecond` x the modifiers' speed multiplier):
  - `Turn` / `Strafe`: walk's input direction (world horizontal. With `Space = View`, relative to the view) is mapped onto the wall. Toward the wall = up, away from the wall = down, along the wall = sideways (left / right as seen facing the wall). Looking at the wall gives "forward = up, back = down, left / right = left / right"; looking parallel to the wall, "tilting toward the wall = up".
  - `TankTurn`: walk's raw input (forward = up, back = down, left / right = left / right as seen facing the wall). The body is not turned on a wall.
  - `SideView` (side-scroller): pushing into the wall goes up, away goes down (no sideways motion).
  - Without input, slides down at `WallSlideSpeedCmPerSecond` (0 stops). On a tilted wall, up means up along the surface.
- Ceiling (`CeilingSpeedCmPerSecond`): crawls horizontally (along the surface) in walk's input direction. Stops without input.
- The current velocity approaches the target at `ClimbAccelerationCmPerSecondSquared` (0 reaches it at once).

### Following the surface (after the move)
- Stick to the surface: probes about 14 cm toward the surface; if it is the same kind, pulls to 2 cm from it and refreshes the normal (follows gently curved walls).
- Inner (concave) corners: if another clingable surface lies in the direction moved on the wall, switches to it (wall -> adjacent wall, climbing a wall onto the ceiling). Never ceiling -> wall (after moving from wall to ceiling the same input still points at the wall, so it would switch back and forth. Heading into a wall on a ceiling just stops).
- Outer corners: with `FollowOuterCorners`, when crawling sideways on a wall past where the surface ends, moves around to the side the wall was on and switches to the adjacent wall (3 sweeps). If it cannot wrap around, see "no surface" below.
- Top ledge: when climbing a wall (moving more up than sideways) and the surface ends (or the ledge corner = a walkable surface is touched), a small hop onto the ledge and release (toward the wall x `LedgeHopForwardSpeedCmPerSecond` + up x `LedgeHopUpSpeedCmPerSecond`).
- No surface: after `ContactGraceSeconds`, lets go and falls (bottom edge of a wall, edge of a ceiling, a window).

### Releasing (each one reports `ClingEnd`)
| Trigger | Velocity | No re-attach for |
|---|---|---|
| Jump (wall) | away from the wall x `WallJumpAwaySpeedCmPerSecond` + up x `WallJumpUpSpeedCmPerSecond` (x the modifiers' jump multiplier) + the current sideways speed. jump also reports `Jumped`; height control on release and the apex hang while held apply | `ReattachCooldownSeconds` |
| Jump (ceiling) | the current velocity along the ceiling + down x `CeilingDropSpeedCmPerSecond` (no `Jumped`) | same |
| Held input away from the wall for `AwayDetachSeconds` | unchanged (walk moves it away) | same |
| Top ledge | see "Top ledge" above | same |
| `Release` | unchanged | same |
| No surface (`ContactGraceSeconds`) | unchanged (gravity returns and it falls) | none |
| Grant removed (effect ended), `LockInput` | unchanged | none |
| Landed on the ground on a wall with no climb input, touched the ground on a ceiling | unchanged | none |

While clinging, jump's air jumps are restored (you can air-jump again after jumping off a wall). Coyote time is not used.

### Interplay with other components
- walk: leaves the velocity alone while clinging (the body's `IsMoveOverridden`). Does not turn the body on a wall even with `TankTurn`.
- jump: jumps off the cling before anything else (above).
- dash: no dash while clinging. A dash in progress ends on attaching (`ClingStart`).
- face (BodyKit's `character_face_movement_component`): faces the wall on a wall regardless of style. On a ceiling, its usual rule (airborne, so `Turn` faces the input direction).
- body: does not probe for ground while clinging and rising (starting to climb slowly from the foot of a wall does not snap to the floor). `IsInState(Clinging)` succeeds, and so does `Airborne`.
- ride (SurfaceKit): not carried while clinging, since the body is not grounded (does not follow moving walls).
- visuals (LookKit, etc.): watch `ClingStart` / `ClingEnd` on the body's `ActionEvent`, and `IsClinging` / `GetClingSurface` / `GetClingNormal`.

## Settings (@editable)
`character_cling_component` (category "Clinging to walls and ceilings")
- `RequiresGrant : logic = true` — when on, clings only while a `GrantsCling` modifier is on the body.
- `WallCling : logic = true`, `CeilingCling : logic = true` — whether to cling to walls / ceilings.
- `AttachFromGround : logic = true`, `GroundAttachDelaySeconds : float = 0.15` — whether pushing into a wall from the ground attaches, and how long to push (0 for at once).
- `ClimbSpeedCmPerSecond : float = 400`, `CeilingSpeedCmPerSecond : float = 350`, `ClimbAccelerationCmPerSecondSquared : float = 4000` (0 for at once).
- `WallSlideSpeedCmPerSecond : float = 50` — slide-down speed on a wall without input (0 stops).
- `WallJumpAwaySpeedCmPerSecond : float = 600`, `WallJumpUpSpeedCmPerSecond : float = 850`, `CeilingDropSpeedCmPerSecond : float = 0`.
- `LedgeHopUpSpeedCmPerSecond : float = 500`, `LedgeHopForwardSpeedCmPerSecond : float = 300` — the small hop onto a top ledge (by default rises about 64 cm to the apex and moves about 75 cm forward by then).
- `ContactGraceSeconds : float = 0.15`, `AwayDetachSeconds : float = 0.4` (0 never lets go by input), `ReattachCooldownSeconds : float = 0.25`.
- `FollowOuterCorners : logic = true` — whether to wrap around outer corners (off: lets go at the corner).

`character_move_grant_component` (BuffKit)
- `GrantCling : logic = false` — when on, stacks the cling grant onto the body. While attached, the owner carries `character_cling_granted_tag`.

## Public API
```verse
# CharacterSystem (the body)
character_action<public> := enum: ... ClingStart, ClingEnd
character_motor_state<public> := enum: ... Clinging
character_cling_surface<public> := enum: Wall, Ceiling
character_modifier<public> := struct: ... GrantsCling<public>:logic = false

character_motor_component:
    CanCling<public>()<decides><transacts>:void                              # at least one GrantsCling modifier
    IsClinging<public>()<decides><transacts>:void
    GetClingSurface<public>()<decides><transacts>:character_cling_surface
    GetClingNormal<public>()<transacts>:vector3                              # outward normal of the surface (the last surface after letting go)
    # internal (used by ClingKit and MoveKit): SetClingState / GetClingJumpVelocity / RequestClingRelease / TakeClingRelease /
    #   ProbeSurfaceFrom / IsSweepClear / SnapToHit / MoveBodyBy / IsWalkableNormal / GetSkinCm. IsMoveOverridden also succeeds while clinging

# MoveKit
character_walk_component:
    GetMoveInput<public>()<transacts>:vector3                                # input before converting to the walking direction (forward = Forward, left = Left. Length 0..1)

# ClingKit
character_cling_component<public> := class<final_super>(component):
    RequiresGrant<public>:logic
    WallCling<public>:logic
    CeilingCling<public>:logic
    AttachFromGround<public>:logic
    GroundAttachDelaySeconds<public>:float
    ClimbSpeedCmPerSecond<public>:float
    CeilingSpeedCmPerSecond<public>:float
    ClimbAccelerationCmPerSecondSquared<public>:float
    WallSlideSpeedCmPerSecond<public>:float
    WallJumpAwaySpeedCmPerSecond<public>:float
    WallJumpUpSpeedCmPerSecond<public>:float
    CeilingDropSpeedCmPerSecond<public>:float
    LedgeHopUpSpeedCmPerSecond<public>:float
    LedgeHopForwardSpeedCmPerSecond<public>:float
    ContactGraceSeconds<public>:float
    AwayDetachSeconds<public>:float
    ReattachCooldownSeconds<public>:float
    FollowOuterCorners<public>:logic
    IsClinging<public>()<decides><transacts>:void
    GetClingSurface<public>()<decides><transacts>:character_cling_surface
    GetClingNormal<public>()<transacts>:vector3
    IsAllowed<public>()<decides><transacts>:void                             # RequiresGrant is off, or a grant is present
    Release<public>():void                                                   # release from code (no re-attach during ReattachCooldownSeconds)

# BuffKit
character_cling_granted_tag<public> := class(character_modified_tag):
character_move_grant_component:
    GrantCling<public>:logic
```

## Requirements, caveats and limits
- While clinging, velocity added by other components (knockback, launch) is overwritten by the crawl velocity on the next frame. Call `Release` first to knock the body away.
- Input away from the wall serves both "crawl down" and "let go". A short push crawls down; holding for `AwayDetachSeconds` lets go. To crawl all the way down a tall wall, set `AwayDetachSeconds = 0` (then only jumping, edges and a lost grant release).
- Walking into a wall on the ground starts climbing after `GroundAttachDelaySeconds` (a low fence puts you onto its ledge). Set `AttachFromGround = false` if unwanted.
- Never ceiling -> wall (above). To come down from a ceiling, jump (fall) or crawl to the edge.
- Does not follow moving walls or ceilings (ride works on ground only).
- With the body's `AxisLock` (side-scroller), there is no motion along the locked axis (no left / right on a wall, only up / down).
- ⚠ Unverified: the sweep hits when wrapping around corners, hopping onto ledges and switching to the ceiling, and whether moving along the surface clung to grazes it (UEFN 43.00 in the editor).

## Verifying (MCP, character toolset)
Positions `pos` are `[left, up, forward]` (cm).
1. No grant: `character.state` shows `can_cling = false` and `clinging = false`. `teleport` in front of a wall and `move` (input toward the wall) for 1 s -> no attaching (with `RequiresGrant = true`).
2. Pick up the effect (an effect prefab with `GrantCling = true`) or set `ActiveOnBegin = true` on a `character_move_grant_component` under the body -> `can_cling = true`.
3. Wall: `teleport` into the air 50 cm in front of a wall, `move` toward the wall -> `state` shows `clinging = true`, `cling_surface = "wall"`, `cling_normal` pointing out of the wall, and `"clinging"` in `states`. With `record_start`, `cling_start` appears.
4. Climb: keep the input toward the wall for a few seconds -> the up value of `pos` grows. At the top ledge `cling_end` appears and the body lands on the ledge (`grounded = true`).
5. Slide down: stop the input (`stop`) -> the up value drops at 50 cm/s. `cling_end` on reaching the floor.
6. Wall jump: `jump` while clinging -> `jumped` and `cling_end`, velocity 600 away from the wall and 850 up. No re-attaching for 0.25 s.
7. Ceiling: `jump` under a low ceiling -> `cling_start`, `cling_surface = "ceiling"`, the up value of `velocity` stays 0. `move` crawls horizontally along the ceiling. `jump` drops (no `jumped`).
8. Lost grant: end the effect while clinging -> `cling_end` and the body falls.
