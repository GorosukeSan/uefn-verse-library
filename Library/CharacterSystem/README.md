# CharacterSystem

A System for "custom characters": entities driven from Verse without using the Fortnite character's movement. The body (`character_motor_component`) handles its own gravity, capsule sweep and grounding; walking, jumping, dashing, facing, input, reactions and conditions are added with components on the same entity or its descendants.

## Setup (placement)

| component | Where to place | What it does |
|---|---|---|
| `character_motor_component` | the custom character's entity (the parent of the visual mesh). To drive one per player, put that entity in a loadout prefab (LoadoutSystem's `loadout_component.Prefab`) | Every frame, adds gravity to the velocity (stronger while falling), sweeps the capsule and slides along surfaces hit (ceiling corners and low steps are corrected and passed), probes for ground and decides grounding (snaps to slopes and low steps). Knows nothing about input (`LockInput` locks the components' input) |
| `character_walk_component` (MoveKit) | the same entity as `character_motor_component` | Walks / runs by accelerating toward the input direction. Stops without input. Turnarounds accelerate harder |
| `character_jump_component` (MoveKit) | same | Jumps on input (coyote time, input buffering, air jumps, lower on release, a slight hang at the apex) |
| `character_dash_component` (MoveKit) | same | A short, sharp dash on input (fixed time / distance. Drops to walking speed when it ends. Cooldown, air dashes, energy) |
| `character_face_movement_component` (BodyKit) | same | Turns the entity's horizontal facing. Where it faces follows walk's side-input style (`Turn` = the movement direction, `Strafe` = the front of the walking direction, `TankTurn` = not turned (walk turns it)). `Turn` without walk |
| `character_owner_stasis_component` (BodyKit) | same | While running, pins the owner's Fortnite character in place with PutInStasis and hides it (the custom character moves independently. The Fortnite character is not moved) |
| `character_input_mapping_component` (BodyKit) | the custom character's entity or a descendant (where there is an owner) | Adds input mappings (`input_mapping`) to the owner and removes them when stopped |
| `character_action_trigger_component` (EventKit) | the custom character's entity or a descendant | Whenever the chosen action (landing, jump, ...) happens, sends an activation signal to `Targets` (this entity and its descendants if empty) |
| `character_motor_condition_component` (ConditionKit) | a descendant of the custom character's entity, directly under the entity of `ability_grant_condition_component` / `game_transition_component` / `condition_all` / `condition_any` | Satisfied while the body is in the chosen state (airborne, moving, ...) |
| `character_camera_component` (CameraExperimentalKit) | the same entity as `character_motor_component` | Makes the owner's view a camera following the custom character (experimental) |
| `character_surface_component` (SurfaceKit) | the entity of a platform, wall, gimmick or goal (the same entity as the mesh) | A box the custom character can "touch" or "step on" (derived from the entity's position, rotation and scale). Attaches `character_surface_tag` at start |
| `character_touch_component` (SurfaceKit) | the same entity as `character_motor_component` | Every frame, compares the body's box with nearby surface boxes and reports started touching / stopped touching / stepped on / stepped off |
| `character_ride_component` (SurfaceKit) | the same entity as `character_motor_component` | When the object the body stands on (the entity hit by the ground sweep) moves, moves the body by the same amount (riding MoverSystem's moving platforms). Inherits the platform's velocity when leaving. Neither `character_touch_component` nor the platform's `character_surface_component` is needed |
| `character_buff_component` (BuffKit) | wherever the activation signal arrives (a PickupSystem effect prefab, inside a loadout, a child of the body) | From the activation signal to the deactivation signal, stacks speed / jump / gravity multipliers onto the body (stacked ones multiply. Always removed when stopped) |
| `character_move_grant_component` (BuffKit) | same | From the activation signal to the deactivation signal, adds air jumps to the body and grants dash (dash's `RequiresGrant`) |
| `character_action_cell_component` (CellKit) | the same entity as `character_motor_component` | Action cells: the charge shared by air jump, boost (dash) and wall kick. Grants (`AddGrant`) add actions and cells; each use spends one. Single-use grants disappear when used up. While a timed grant (Refills) is attached, cells refill on landing |
| `character_action_cell_grant_component` (CellKit) | wherever the activation signal arrives (the root or a child of a PickupSystem effect prefab) | From the activation signal to the deactivation signal, adds a grant to the body's action cells (`Action`, `Cells`, `RefillOnLanding`). When used up, sends `activation_finished_event` (ActivationSystem) upward; in an effect prefab, the effect ends |

Every component other than `character_motor_component` finds the body with `FindCharacterMotorAbove` (the same entity or an ancestor).

Example: "give everyone a custom character that walks and jumps, and play a sound on landing" (to ride moving platforms, also add `character_ride_component` to the body. To know about touching / stepping on, also add `character_touch_component` to the body and `character_surface_component` to the platforms)
```
Loadout (loadout_component (LoadoutSystem), Prefab = the prefab below, ActiveOnBegin = true)

Prefab
└ Body (character_motor_component + character_walk_component + character_jump_component + character_owner_stasis_component)
  ├ Visuals (mesh)
  └ Landing (character_action_trigger_component, Action = Landed)
    └ Sound (device_audio_component (FNDeviceSystem))
```
The prefab is created under each player's slot, so that player becomes the body's owner. To use walking input (`MoveAction` or the 4 buttons), add a mapping holding those inputs to the owner with `character_input_mapping_component`. The default jump `Character.Jump` is part of Fortnite's `TraversalMapping`.

## Settings (@editable)
Body (`character_motor_component`)
- `RadiusCm : float = 40.0` — capsule radius (cm, 5..1000).
- `HeightCm : float = 180.0` — capsule height (cm, feet to head, 10..2000). The entity's position is the feet (bottom center).
- `GravityCmPerSecondSquared : float = 1960.0` — gravitational acceleration (cm/s^2, 0..20000).
- `MaxFallSpeedCmPerSecond : float = 4000.0` — maximum fall speed (cm/s).
- `MaxSlopeDegrees : float = 50.0` — maximum slope you can stand on (degrees, 0..89). Steeper surfaces slide as walls.
- `FallGravityMultiplier : float = 1.6` — multiplier on gravity while falling (vertical speed negative) (0.1..10). 1 is the same as rising (the previous behavior). Applies not only after a jump but also when walking off an edge or falling after a launch.
- `GroundProbeCm : float = 10.0` — distance to probe down from the feet for ground while falling from the air (cm, 0..200). Snaps if ground is within it.
- `GroundSnapCm : float = 20.0` — downward probe distance (cm, 0..200) for a body that was grounded and is moving along the ground (not leaving by a jump or launch). Snaps without floating when going down slopes or low steps. `GroundProbeCm` if smaller than it. 0 disables.
- `StepUpCm : float = 15.0` — maximum height (cm, 0..200) of a step corner the feet may hit and climb while grounded (not about to leave by a jump) and moving horizontally. For stairs. Not used in the air. 0 disables.
- `LedgeAssistCm : float = 0.0` — maximum height (cm, 0..200. Assist for a jump that fell slightly short) of a ledge corner the feet may hit and climb while falling in the air. 0 disables.
- `CornerCorrectionCm : float = 12.0` — maximum sideways shift (cm, 0..100) to keep rising when the head grazes the corner of a ceiling (downward-facing surface) while rising. Speed is not lost. Not used for walls. 0 disables.
- `MovingSpeedCmPerSecond : float = 10.0` — "moving" when the horizontal speed exceeds this.
- `AxisLock : character_axis_lock = None` — restricts movement to a plane. `Left` keeps the Left position where it was at start (or at `TeleportTo`) (side-scroller).
- `SpawnAtOwner : logic = true` — when on, moves to the owner's Fortnite character at start.

Walk (`character_walk_component`)
- `MoveAction : ?input_action(vector3) = false` — direction input. `ForwardAction` / `BackAction` / `LeftAction` / `RightAction : ?input_action(logic) = false` — 4 buttons. `SprintAction : ?input_action(logic) = false` — run while held. These three kinds of input and `SetMoveInput` from code are summed (length up to 1).
- `Space : character_walk_space = View` — what the walking direction is aligned to (View = the owner's view, World = the world, Facing = the character's facing, SideView = side-scroller. Side input moves along the world's forward / back).
- `MaxSpeedCmPerSecond : float = 600.0`, `AccelerationCmPerSecondSquared : float = 4000.0`, `BrakingCmPerSecondSquared : float = 5000.0`.
- `SprintMultiplier : float = 1.6` — multiplier while running (1..10).
- `TurnAroundMultiplier : float = 2.0` — multiplier on acceleration on a ground turnaround (input direction more than 90 degrees from the current horizontal motion) (1..10). 1 is the same as normal acceleration. In the air, `AirTurnAroundMultiplier`.
- Air control (while the body is not grounded):
  - `AirControlRatio : float = 0.6` — multiplier on `AccelerationCmPerSecondSquared` when accelerating toward the input direction in the air (0..1. 0 gives no air control). By default 2400 cm/s^2 (about 0.25 s from 0 to 600 cm/s. A jump stays airborne about 0.8 s by default).
  - `AirBrakingRatio : float = 0.2` — multiplier on `BrakingCmPerSecondSquared` without input in the air (0..1. 0 gives no braking). By default 1000 cm/s^2 (about 0.6 s from 600 cm/s to 0. A short jump keeps momentum, a long jump nearly stops at the end).
  - `AirTurnAroundMultiplier : float = 2.0` — upper bound of the multiplier on air acceleration on an air turnaround (1..10. Instead of the ground's `TurnAroundMultiplier`). The more the input opposes the current motion, the more applies (1x at a right angle, this multiplier when fully opposed. No abrupt change at 90 degrees). By default 4800 cm/s^2 when fully opposed (about 0.25 s from 600 cm/s to 600 cm/s the other way. 0.6x the ground turnaround of 8000 cm/s^2 = consistent with `AirControlRatio`).
  - `KeepAirMomentum : logic = true` — when on, speed above the cap (walk / run speed) in the air (gained from knockback or a launch) is only bent toward the input direction, never reduced (reduced only when the input opposes it). Input never exceeds the cap. When off, approaches the input speed in the air too (reduced to the cap). Dash speed does not remain, because dash cuts it to the cap when it ends.
  - The velocity inherited from moving ground (the body's `GetInheritedVelocity`. SurfaceKit's `character_ride_component`) is not braked even without input (jumping keeps moving with the floor). It shrinks when opposed by input or hitting a wall, and the lost part does not come back (input in the same direction later does not restore it as a non-braked part).
  - During a dash (the body's `IsMoveOverridden`, internal), walk leaves the velocity alone (only records the input direction).
- `SideStyle : character_side_style = Turn` — what to do with side input (base value). `Turn` = move sideways, the body turns toward the movement (as before). `Strafe` = move sideways, but the body keeps facing the front of the walking direction (the view direction when `Space = View`) (crab walk. Turns toward the front while standing still too). `TankTurn` = no sideways movement, turns in place; forward / back move along the body's facing (`Space` is not used). While a modifier on the body (`character_modifier.SideStyle`, BuffKit) decides it, that takes precedence.
- `TankTurnDegreesPerSecond : float = 180.0` — with `TankTurn`, degrees turned per second by side input (0..3600).
- `SideStyleToggleAction : ?input_action(logic) = false` — button that toggles the base between `SideStyle` and `ToggleSideStyle` on each press (empty if unused). `ToggleSideStyle : character_side_style = Strafe` — the style to toggle to.

Jump (`character_jump_component`)
- `JumpAction : input_action(logic) = Character.Jump`.
- `JumpSpeedCmPerSecond : float = 900.0` — upward speed at the moment of jumping. `AirJumps : int = 0` — number of jumps in the air (1 for a double jump).
- `CoyoteSeconds : float = 0.12` — seconds after walking off the ground during which a jump still counts as a ground jump (0 disables). Not available after leaving by your own jump. A coyote-time jump does not consume air jumps.
- `BufferSeconds : float = 0.12` — seconds to remember a jump pressed before landing and jump at the moment of landing (0 disables. Even at 0, presses since the previous frame are used). With air jumps remaining, the press becomes an air jump instead (not buffered).
- `ReleaseCutRatio : float = 0.5` — multiplier on the upward speed when released while rising after a jump (1 leaves it unchanged). Once per jump, not after starting to fall.
- `ApexSpeedThresholdCmPerSecond : float = 150.0` — apex hang: while held after a jump and the vertical speed (absolute) in the air is below this, gravity is weakened (cm/s, 0..5000). 0 disables.
- `ApexGravityMultiplier : float = 0.5` — gravity multiplier during the apex hang (0..1. Used instead of the body's `FallGravityMultiplier`). 1 does not weaken.

Dash (`character_dash_component`)
- `DashAction : ?input_action(logic) = false` — if empty, only `Dash` from code dashes.
- `DashSpeedCmPerSecond : float = 2200.0`, `DurationSeconds : float = 0.18` (distance = speed x time = 396 cm by default. Independent of frame length), `CooldownSeconds : float = 0.8` (counted from the moment of dashing), `AirDashes : int = 1` (dashes allowed in the air. Restored on landing).
- `DashEndSpeedRatio : float = 1.0` — when the dash ends, the speed along the dash direction is cut to "walk's `MaxSpeedCmPerSecond` x the modifiers' speed multiplier (excluding the run button) x this" (0..2. 0 stops on the spot). The sideways speed is removed. Without walk, 600 cm/s is taken as the walking speed.
- `DashGravityScale : float = 0.0` — multiplier on gravity during the dash (0..1. 0 keeps the height of an air dash). Applied with the body's `ScaleGravityThisFrame` (`SetGravityScale` is untouched).
- Sequence (default values): at 0 s pick the direction (walk's input direction -> current horizontal motion -> body facing. The `AxisLock` axis is removed), set the horizontal velocity to 2200 cm/s, zero the vertical speed in the air -> for 0.18 s the same speed every frame (gravity x0, walk leaves the velocity alone) -> at the end cut the speed along the dash direction to 600 cm/s (the walking speed cap) -> the next dash is available 0.8 s after dashing. Jumping (`Jumped` / `AirJumped`) or `LockInput` mid-dash ends it on the spot and cuts the speed the same way (no jumping at dash speed). At the moment of dashing, the velocity inherited from moving ground (`GetInheritedVelocity`) is cleared.
- `EnergyCost : float = 0.0` — energy spent per dash (0 spends none). Paid from the `energy_component` found by `FindEnergyAbove` (EnergySystem); cannot dash without enough.

BodyKit
- `character_face_movement_component.TurnSpeedDegreesPerSecond : float = 720.0` — degrees turned per second (0 faces instantly). Both `Turn` and `Strafe` turn at this speed (`TankTurn` uses walk's `TankTurnDegreesPerSecond`).
- `character_face_movement_component.AirFacesInput : logic = true` — when on, with `Turn`, in the air turns toward walk's input direction (`GetInputDirection`) instead of the movement direction (unchanged without input. Does not turn toward momentum inherited from a moving floor or a knockback direction). When off, toward the movement direction in the air too (the previous behavior). On the ground, the movement direction either way.
- `character_owner_stasis_component` — no settings (only pins and hides. There is no follow setting: the custom character has all its physics, collision and movement of its own).
- `character_input_mapping_component.Mapping : ?input_mapping = false` / `SecondMapping : ?input_mapping = false` — mappings to add (up to 2. Asset arrays cannot be written through MCP, so one field each. For 3 or more, put another of this component on a child entity). `RemoveOnEnd : logic = true` — removed when stopped (turn it off for Fortnite mappings such as `TraversalMapping`).

EventKit / ConditionKit
- `character_action_trigger_component.Action : character_action = Landed` — what to watch for. `Targets : []entity = array{}` — entities to send the activation signal to (this entity and its descendants if empty). `CooldownSeconds : float = 0.0` — seconds to ignore further occurrences.
- `character_motor_condition_component.State : character_motor_state = Airborne` — state to satisfy.

Dash (continued)
- `RequiresGrant : logic = false` — when on, dashing is possible only while a modifier "granting dash" (`character_modifier.GrantsDash`. BuffKit's `character_move_grant_component.GrantDash`) is stacked on the body (a pickup ability).

BuffKit (which body it affects: the body on this entity or an ancestor -> the owner's body -> the body of the agent in an activation signal that says who triggered it)
- `character_buff_component.SpeedMultiplier : float = 1.0` (on walk's top speed), `JumpMultiplier : float = 1.0` (on the jump speed. Height roughly squares), `GravityMultiplier : float = 1.0` (on gravity), `ActiveOnBegin : logic = false` (when on, from start). All 0..10.
- `character_buff_component.OverrideSideStyle : logic = false` — when on, sets walk's side-input style to `SideStyle : character_side_style = Strafe` while stacked (an effect that switches to crab walk or turning in place on pickup. No code needed inside a PickupSystem effect prefab). With several stacked, the last one wins; when all are removed, walk's base returns.
- `character_move_grant_component.ExtraAirJumps : int = 1` (added to the air jumps. Usable right away when gained in the air), `GrantDash : logic = false`, `ActiveOnBegin : logic = false`.

SurfaceKit
- `character_surface_component.SizeCm : vector3 = vector3{}` — box size (cm). Used if all components are above 0, ignoring the entity's scale. `MeshSizeCm : float = 100.0` — the edge length multiplied by the entity's scale (Scale) when `SizeCm` is not used (100 for a 100 cm cube mesh). `PivotAtBottom : logic = true` — the entity's position is the center of the box's bottom face (off: the center of the box).
- `character_touch_component.TouchMarginCm : float = 8.0` — margin added to the body's box (the body stops 2 cm short of surfaces, so make it larger than that). `StandToleranceCm : float = 15.0` — "standing on" when the feet are within this distance of the surface's top face. `SearchRadiusCm : float = 3000.0` — only surfaces within this distance of the feet are candidates. `RefreshSeconds : float = 0.5` — interval for refreshing the candidates.
- `character_ride_component.MaxCarryCm : float = 300.0` — does not follow a floor that moved more than this in one frame (so a warp / reset does not drag the body along). `FollowYaw : logic = true` — when the floor turns in yaw, the body's position is also rotated around the floor's position (the entity's origin) by the same amount (the body's facing is unchanged. E.g. a platform turned by MoverSystem's `mover_spline_route_component.FaceTravelDirection`). When off, only the floor's positional motion is added.
- `character_ride_component.GraceSeconds : float = 0.1` — if grounding drops for a moment while the same floor is still within 50 cm below the feet, keeps carrying as if riding for up to this many seconds (0..2. Not used when leaving upward (jump)). 0 disables.
- `character_ride_component.InheritVelocity : logic = true` — when on, when leaving a moving floor (jump, falling off the edge, `GraceSeconds` elapsed), adds the floor's velocity (excluding downward speed. For a rotating floor, the speed at the feet) to the body's velocity (walk does not brake this part in the air). When landing from the air, removes from the body's horizontal velocity the part along the floor's direction of motion, up to the floor's speed (no sliding when jumping and landing back on the same floor. Landing on a stopped floor has nothing to remove, so the body moves with the floor from the moment of landing). When off, nothing is added or removed.

CameraExperimentalKit (`character_camera_component`)
- `Projection : character_camera_projection = Perspective`, `OffsetCm : vector3 = vector3{Forward := -600.0, Up := 250.0}` (offset from the feet), `YawDegrees : float = 0.0`, `PitchDegrees : float = -15.0` (negative looks down), `FieldOfViewDegrees : float = 90.0` (horizontal field of view for Perspective), `OrthographicWidthCm : float = 3000.0` (length across the screen width for Orthographic), `Priority : int = 10`.

## Events
- `character_action_event` (scene_event, SendUp): `Trigger : character_action_trigger_component`, `Action : character_action`. From the `character_action_trigger_component` entity to the root. Not consumed.
- Activation signals: `character_action_trigger_component` sends `SendActivatedBy(owner)` (`activated_by_agent_event`) to `Targets` if there is an owner, otherwise `SendActivated`.
- `character_motor_component.PreMoveEvent : listenable(float)` — every frame before moving (seconds since the previous frame). Movement components call `AddVelocity` / `SetVelocity` here.
- `character_motor_component.PostMoveEvent : listenable(float)` — every frame after moving. Used by components that read the position and follow it (body_link, facing, conditions).
- `character_motor_component.ActionEvent : listenable(character_action)` — arrives whenever something happens. `Landed` / `LeftGround` / `StartedMoving` / `StoppedMoving` / `HitWall` are reported by the body, `Jumped` / `AirJumped` by jump, `Dashed` by dash (through `ReportAction`).
- `character_motor_component.LandedEvent : listenable(float)` — arrives whenever the body lands from the air, with the downward speed at that moment (cm/s, 0 or more). Right after `Landed` on `ActionEvent` (a handler of `Landed` can read the same value with `GetLastLandingSpeed`). For landing squash, dust, sound volume (the body has no visuals). Also arrives when step correction climbs onto a ledge.
- `character_walk_component.SideStyleChangedEvent : listenable(character_side_style)` — arrives with the new style whenever the current side-input style (`GetSideStyle`) changes. Immediately for `SetSideStyle`, `SwitchSideStyle` and the toggle button; before the next frame's move when a modifier on the body is added or removed (walk compares every frame). The style at start does not arrive (read it with `GetSideStyle`).
- `character_action_trigger_component.TriggeredEvent : listenable(character_action)` — whenever `Action` happens (except those ignored by `CooldownSeconds`).
- `character_motor_condition_component` sends `condition_changed_event` upward (ConditionSystem). Checks the state every frame after the body moves, and only when it changes.
- `character_surface_contact_event` (scene_event, SendUp): `Surface : character_surface_component`, `Motor : character_motor_component`, `Agent : ?agent` (the body's owner), `Contact : character_surface_contact` (`Touched` / `Untouched` / `SteppedOn` / `SteppedOff`). From the surface entity to the root. Sent by `character_touch_component`. Not consumed.
- `character_touch_component.ContactEvent : listenable(tuple(character_surface_component, character_surface_contact))` — on the body's side. (that surface, contact kind) whenever the contact changes. Order: stepped off -> stopped touching -> started touching -> stepped on.
- `character_surface_component.ContactEvent : listenable(tuple(character_motor_component, character_surface_contact))` — on the surface's side. The same notification arrives as (that body, contact kind). Gimmicks subscribe to this.

## Tags
- `character_modified_tag` (subclass of `player_state_tag`, abstract) and its subclasses `character_speed_modified_tag` / `character_jump_modified_tag` / `character_gravity_modified_tag` (a `character_buff_component` with a multiplier other than 1) / `character_air_jumps_added_tag` / `character_dash_granted_tag` (`character_move_grant_component`) / `character_side_style_modified_tag` (a `character_buff_component` with `OverrideSideStyle`) — on the body's owner while stacked (stacking attaches two or more of the same type).
- `custom_character_tag` (subclass of `player_state_tag`) — a `character_motor_component` with an owner attaches it to the owner (agent) while running and removes it when stopped.
- `character_surface_tag` (an entity role tag. Subclass of `tag`) — `character_surface_component` attaches it to its own entity at start and removes it when stopped. `character_touch_component` finds surfaces by this tag (`SetSearchRoot` narrows the search).

## Owner
A body placed under a player's slot (inside a loadout, etc.) gets an owner (`FindOwningPlayer`) and becomes that player's character. The owner is decided once, in `OnBeginSimulation`.
- `character_motor_component`: attaches `custom_character_tag` to the owner. With `SpawnAtOwner`, moves to the owner's Fortnite character. Does not collide with the owner's Fortnite character. Physics runs without an owner too (the tests use this form).
- walk / jump / dash: read the owner's input (`AwaitPlayerInput`). Without an owner no input is received, but `SetMoveInput` / `Jump` / `Dash` work from code. walk's `Space = View` is the owner's view direction.
- `character_owner_stasis_component`, `character_camera_component`, `character_input_mapping_component`: do nothing without an owner (camera and input_mapping log to the output log).
- `character_action_trigger_component`: with an owner, the activation signal says that player triggered it (readable with `FindActivatingAgent`).
- `Entity.FindCharacterMotorFor[Agent]`: finds that player's slot via the scope's `player_manager_component` and returns the body under it whose owner is that player.

## Public API
```verse
character_action<public> := enum:
    Jumped
    AirJumped
    Dashed
    Landed
    LeftGround
    StartedMoving
    StoppedMoving
    HitWall

character_motor_state<public> := enum:
    Grounded
    Airborne
    Rising
    Falling
    Moving
    Still

character_axis_lock<public> := enum:
    None
    Left
    Forward

character_side_style<public> := enum:                                  # what to do with side input (held by walk, read by face)
    Turn                                                               # move sideways, the body turns toward the movement (default)
    Strafe                                                             # move sideways, the body keeps facing the front of the walking direction (crab walk)
    TankTurn                                                           # side input turns in place, forward / back move along the body's facing

custom_character_tag<public> := class(player_state_tag):

character_motor_component<public> := class<final_super>(component):
    RadiusCm<public>:float
    HeightCm<public>:float
    GravityCmPerSecondSquared<public>:float
    MaxFallSpeedCmPerSecond<public>:float
    FallGravityMultiplier<public>:float                                     # gravity multiplier while falling
    MaxSlopeDegrees<public>:float
    GroundProbeCm<public>:float
    GroundSnapCm<public>:float                                              # downward probe distance while moving along the ground
    StepUpCm<public>:float                                                  # maximum step height to climb (only while grounded)
    LedgeAssistCm<public>:float                                             # maximum ledge height to climb while falling in the air (0 disables)
    CornerCorrectionCm<public>:float                                        # maximum sideways shift at a ceiling corner
    MovingSpeedCmPerSecond<public>:float
    AxisLock<public>:character_axis_lock
    SpawnAtOwner<public>:logic
    PreMoveEvent<public><final>:listenable(float)
    PostMoveEvent<public><final>:listenable(float)
    ActionEvent<public><final>:listenable(character_action)
    LandedEvent<public><final>:listenable(float)                            # downward speed at the moment of landing (cm/s)
    FindOwner<public>()<decides><transacts>:player                          # the owner. Fails where there is no owner
    GetVelocity<public>()<transacts>:vector3                               # cm/s, world space
    SetVelocity<public>(NewVelocity:vector3):void
    AddVelocity<public>(Delta:vector3):void
    IsGrounded<public>()<decides><transacts>:void
    IsInState<public>(State:character_motor_state)<decides><transacts>:void
    GetGroundNormal<public>()<transacts>:vector3                           # the last ground stood on when not grounded
    GetGroundEntity<public>()<decides><transacts>:entity                    # the object stood on (entity hit by the ground sweep). Fails when not grounded
    GetGroundVelocity<public>()<transacts>:vector3                         # velocity of the ground carrying the body (set by character_ride_component. 0 without it)
    GetInheritedVelocity<public>()<transacts>:vector3                      # horizontal velocity inherited when leaving moving ground (0 on landing)
    SetGravityScale<public>(Scale:float):void                              # 1.0 for the default, 0 for zero gravity
    GetGravityScale<public>()<transacts>:float
    ScaleGravityThisFrame<public>(Multiplier:float):void                   # multiplies this frame's gravity only (call inside PreMoveEvent. Resets to 1 every frame)
    GetLastLandingSpeed<public>()<transacts>:float                         # downward speed at the last landing (cm/s)
    LockInput<public>()<transacts>:cancelable                              # locks the components' input. Remove with Cancel on the returned cancelable (stackable)
    IsInputLocked<public>()<decides><transacts>:void                       # succeeds if at least one LockInput is active
    TeleportTo<public>(Position:vector3):void                              # moves the feet to Position without checking collisions. Velocity unchanged
    ReportAction<public>(Action:character_action):void                     # delivers to ActionEvent (from your own movement components)
    AddModifier<public>(Modifier:character_modifier)<transacts>:cancelable  # stacks a modifier onto the body. Remove with Cancel on the returned cancelable
    GetModifierCount<public>()<transacts>:int
    GetSpeedMultiplier<public>()<transacts>:float                          # product of the stacked modifiers (1 if none)
    GetJumpMultiplier<public>()<transacts>:float
    GetGravityMultiplier<public>()<transacts>:float                        # applied separately from SetGravityScale
    GetExtraAirJumps<public>()<transacts>:int                              # sum (0 if none)
    IsDashGranted<public>()<decides><transacts>:void                       # succeeds if at least one GrantsDash modifier
    GetSideStyleOverride<public>()<decides><transacts>:character_side_style  # the last added modifier with a SideStyle. Fails if none

character_modifier<public> := struct:
    SpeedMultiplier<public>:float = 1.0
    JumpMultiplier<public>:float = 1.0
    GravityMultiplier<public>:float = 1.0
    ExtraAirJumps<public>:int = 0
    GrantsDash<public>:logic = false
    SideStyle<public>:?character_side_style = false                       # walk's side-input style while stacked (the last one added wins)

(InEntity:entity).FindCharacterMotorFor<public>(Agent:agent)<decides><transacts>:character_motor_component
(InEntity:entity).FindCharacterMotorAbove<public>()<decides><transacts>:character_motor_component   # InEntity or an ancestor

# MoveKit
character_walk_space<public> := enum:
    View
    World
    Facing
    SideView

character_walk_component<public> := class<final_super>(component):
    MoveAction<public>:?input_action(vector3)
    ForwardAction<public>:?input_action(logic)
    BackAction<public>:?input_action(logic)
    LeftAction<public>:?input_action(logic)
    RightAction<public>:?input_action(logic)
    SprintAction<public>:?input_action(logic)
    Space<public>:character_walk_space
    MaxSpeedCmPerSecond<public>:float
    AccelerationCmPerSecondSquared<public>:float
    BrakingCmPerSecondSquared<public>:float
    AirControlRatio<public>:float                                          # multiplier on air acceleration
    AirBrakingRatio<public>:float                                          # multiplier on braking without input in the air
    AirTurnAroundMultiplier<public>:float                                  # multiplier on acceleration on an air turnaround
    KeepAirMomentum<public>:logic                                          # do not reduce speed above the cap in the air
    SprintMultiplier<public>:float
    TurnAroundMultiplier<public>:float                                     # multiplier on acceleration on a ground turnaround
    SideStyle<public>:character_side_style
    TankTurnDegreesPerSecond<public>:float
    SideStyleToggleAction<public>:?input_action(logic)
    ToggleSideStyle<public>:character_side_style
    SideStyleChangedEvent<public><final>:listenable(character_side_style)  # whenever the current style changes (the new style)
    SetMoveInput<public>(Input:vector3):void                               # Forward = forward, Left = left. Stays until the next call
    GetSideStyle<public>()<transacts>:character_side_style                 # current style (the modifier on the body if any, otherwise the base)
    GetBaseSideStyle<public>()<transacts>:character_side_style             # base (changed by SetSideStyle / toggle. SideStyle if unchanged)
    SetSideStyle<public>(Style:character_side_style):void                  # changes the base (while a modifier decides, takes effect once it is removed)
    SwitchSideStyle<public>():void                                         # toggles the base between SideStyle and ToggleSideStyle (same as the button)
    GetWalkBasis<public>()<transacts>:tuple(vector3, vector3)              # (forward, left) of the current walking direction. Body facing with TankTurn; forward is vector3{} in SideView
    GetWalkFront<public>()<transacts>:vector3                              # the forward of GetWalkBasis (where face turns with Strafe)
    GetRawMoveAxis<public>()<transacts>:vector3                            # diagnostics: the raw value of MoveAction
    GetInputDirection<public>()<transacts>:vector3                         # input direction of the last frame (world horizontal. Length 0..1. 0 while locked)

(Motor:character_motor_component).FindCharacterWalk<public>()<decides><transacts>:character_walk_component  # the body's walk (on the body entity, otherwise a descendant)

character_jump_component<public> := class<final_super>(component):
    JumpAction<public>:input_action(logic)
    JumpSpeedCmPerSecond<public>:float
    AirJumps<public>:int
    CoyoteSeconds<public>:float
    BufferSeconds<public>:float
    ReleaseCutRatio<public>:float
    ApexSpeedThresholdCmPerSecond<public>:float                            # speed range of the apex hang (0 disables)
    ApexGravityMultiplier<public>:float                                    # gravity multiplier during the apex hang
    Jump<public>():logic                                                   # jump without input. false if it cannot. Counted as held until ReleaseJump or landing
    ReleaseJump<public>():void                                             # release the jump from code (height control if still rising)

character_dash_component<public> := class<final_super>(component):
    DashAction<public>:?input_action(logic)
    DashSpeedCmPerSecond<public>:float
    DurationSeconds<public>:float
    DashEndSpeedRatio<public>:float                                        # fraction of the walking speed cap to cut to at the end
    DashGravityScale<public>:float                                         # gravity multiplier during the dash
    CooldownSeconds<public>:float
    AirDashes<public>:int
    EnergyCost<public>:float
    RequiresGrant<public>:logic
    IsDashing<public>()<decides><transacts>:void
    Dash<public>():logic                                                   # false if on cooldown, out of air dashes or energy

# BodyKit
character_face_movement_component<public> := class<final_super>(component):
    TurnSpeedDegreesPerSecond<public>:float
    AirFacesInput<public>:logic                                            # with Turn, face the input direction in the air

character_owner_stasis_component<public> := class<final_super>(component):
    FindParkedCharacter<public>()<decides><transacts>:fort_character   # the Fortnite character currently pinned

character_input_mapping_component<public> := class<final_super>(component):
    Mapping<public>:?input_mapping
    SecondMapping<public>:?input_mapping
    RemoveOnEnd<public>:logic

# EventKit
character_action_event<public> := class(scene_event):
    Trigger<public>:character_action_trigger_component
    Action<public>:character_action

character_action_trigger_component<public> := class<final_super>(component):
    Action<public>:character_action
    Targets<public>:[]entity
    CooldownSeconds<public>:float
    TriggeredEvent<public><final>:listenable(character_action)

# ConditionKit
character_motor_condition_component<public> := class<final_super>(condition_component):
    State<public>:character_motor_state

# SurfaceKit
character_surface_contact<public> := enum:
    Touched
    Untouched
    SteppedOn
    SteppedOff

character_surface_box<public> := struct<computes>:
    MinCm<public>:vector3
    MaxCm<public>:vector3

character_surface_contact_event<public> := class(scene_event):
    Surface<public>:character_surface_component
    Motor<public>:character_motor_component
    Agent<public>:?agent
    Contact<public>:character_surface_contact

character_surface_tag<public> := class(tag):

character_surface_component<public> := class<final_super>(component):
    SizeCm<public>:vector3
    MeshSizeCm<public>:float
    PivotAtBottom<public>:logic
    ContactEvent<public><final>:listenable(tuple(character_motor_component, character_surface_contact))
    GetBox<public>()<transacts>:character_surface_box                     # world-axis-aligned box (a rotated surface becomes its enclosing box)
    SetActive<public>(Value:logic):void                                    # not touchable while false (collision and visuals unchanged)
    IsActive<public>()<decides><transacts>:void

character_touch_component<public> := class<final_super>(component):
    TouchMarginCm<public>:float
    StandToleranceCm<public>:float
    SearchRadiusCm<public>:float
    RefreshSeconds<public>:float
    ContactEvent<public><final>:listenable(tuple(character_surface_component, character_surface_contact))
    SetSearchRoot<public>(Root:?entity):void                               # narrows the surface search to descendants of Root (false for the world)
    GetTouchingSurfaces<public>()<transacts>:[]character_surface_component
    IsTouching<public>(Surface:character_surface_component)<decides><transacts>:void
    FindStandingSurface<public>()<decides><transacts>:character_surface_component

character_ride_component<public> := class<final_super>(component):
    MaxCarryCm<public>:float
    FollowYaw<public>:logic
    GraceSeconds<public>:float                                             # seconds to keep carrying after grounding drops for a moment
    InheritVelocity<public>:logic                                          # inherit the floor's velocity on leaving, remove it on landing
    FindRidingEntity<public>()<decides><transacts>:entity                  # the object currently ridden
    GetRideVelocity<public>()<transacts>:vector3                           # its velocity (0 if not riding)

# BuffKit
character_modified_tag<public> := class<abstract>(player_state_tag):
character_speed_modified_tag<public> := class(character_modified_tag):
character_jump_modified_tag<public> := class(character_modified_tag):
character_gravity_modified_tag<public> := class(character_modified_tag):
character_air_jumps_added_tag<public> := class(character_modified_tag):
character_dash_granted_tag<public> := class(character_modified_tag):
character_side_style_modified_tag<public> := class(character_modified_tag):

character_buff_component<public> := class<final_super>(component):
    SpeedMultiplier<public>:float
    JumpMultiplier<public>:float
    GravityMultiplier<public>:float
    OverrideSideStyle<public>:logic
    SideStyle<public>:character_side_style
    ActiveOnBegin<public>:logic
    Apply<public>(Activator:?agent):void
    Remove<public>():void
    IsApplied<public>()<decides><transacts>:void

character_move_grant_component<public> := class<final_super>(component):
    ExtraAirJumps<public>:int
    GrantDash<public>:logic
    ActiveOnBegin<public>:logic
    Apply<public>(Activator:?agent):void
    Remove<public>():void
    IsApplied<public>()<decides><transacts>:void

# CameraExperimentalKit
character_camera_projection<public> := enum:
    Perspective
    Orthographic

character_camera_component<public> := class<final_super>(component):
    Projection<public>:character_camera_projection
    OffsetCm<public>:vector3
    YawDegrees<public>:float
    PitchDegrees<public>:float
    FieldOfViewDegrees<public>:float
    OrthographicWidthCm<public>:float
    Priority<public>:int

# A camera orbiting a chosen point (not a component. Overview map, looking over the stage, etc.)
MakePlayerOrbitCamera<public>(Player:player, ?FieldOfViewDegrees:float = 60.0, ?Priority:int = 100, ?MinPitchDegrees:float = -89.0, ?MaxPitchDegrees:float = 89.0):player_orbit_camera
player_orbit_camera<public> := class<internal>:
    Player<public>:player
    FieldOfViewDegrees<public>:float                     # horizontal field of view at 16:9 (degrees)
    Priority<public>:int
    MinPitchDegrees<public>:float
    MaxPitchDegrees<public>:float
    Attach<public>(Parent:entity)<suspends>:logic        # creates a camera as a child of Parent and adds it to Player's camera_director_component one frame later. true if added
    Detach<public>():void                                # removes and destroys it (back to the previous camera)
    IsAttached<public>()<decides><transacts>:void
    SetOrbit<public>(Pivot:vector3, YawDegrees:float, PitchDegrees:float, DistanceCm:float):void   # Yaw turns left seen from above (0 = Forward), Pitch negative looks down
    RotateBy<public>(DeltaYawDegrees:float, DeltaPitchDegrees:float):void
    SetDistance<public>(DistanceCm:float):void
    GetPivot / GetYawDegrees / GetPitchDegrees / GetDistanceCm / GetRotation / GetTransform   # feed GetTransform to WidgetSystem MarkerKit's widget_camera_pose to convert world positions to screen ratios
    FitDistanceCm<public>(Points:[]vector3, ?MarginRatio:float = 1.1, ?AspectRatio:float = 16:9, ?MinDistanceCm:float = 100.0)<transacts>:float   # the distance at which all Points are visible with the current rotation
```

## Requirements, caveats and limits
- The body is kinematic. Collision uses `FindSweepHits` (excluding its own entity and descendants, and the owner's Fortnite character). Order within one frame:
  1. Reset this frame's gravity factor to 1.
  2. `PreMoveEvent`: components on the same entity set the velocity (in subscription order. walk, jump, dash and ride do not depend on each other's results).
     - ride (`character_ride_component`): carries the body by how much the object stood on moved since the remembered position (the body's velocity is unchanged). Derives the floor's velocity.
     - jump: if grounded, restores the air jumps and coyote time -> on a press (presses since the previous frame plus buffered input up to `BufferSeconds` before), jumps from the ground (including coyote time), then as an air jump. If it cannot, the press stays buffered -> if released, multiplies a rising jump by `ReleaseCutRatio` -> if held near the apex, `ScaleGravityThisFrame(ApexGravityMultiplier)`.
     - walk: on the ground, accelerates toward the input direction (`TurnAroundMultiplier` on a turnaround) and brakes at `BrakingCmPerSecondSquared` without input. In the air, acceleration x `AirControlRatio` (further up to x `AirTurnAroundMultiplier` the more the input opposes), braking x `AirBrakingRatio` without input. With `KeepAirMomentum`, speed above the cap is only bent, not reduced. The part inherited from moving ground is not braked (what is lost is also removed from the body's inherited velocity). Vertical speed is unchanged. Leaves the velocity alone during a dash.
     - dash: during the dash, sets the horizontal velocity and weakens gravity with `ScaleGravityThisFrame(DashGravityScale)`. Cuts the speed before the move of the frame after it ends.
  3. Gravity: only in the air or when about to leave the ground (jump). `GravityCmPerSecondSquared` x `SetGravityScale` x the modifiers' `GravityMultiplier` x `ScaleGravityThisFrame` x `FallGravityMultiplier` while falling (up to `MaxFallSpeedCmPerSecond`). Always 0 with `SetGravityScale(0)`.
  4. Sweep and move (up to 4 times). On every hit:
     - A hit touching from the start of the sweep (distance 0, about to penetrate): push out without using the returned normal (trying the physics normal -> outward direction of the last wall touched -> reverse of the horizontal motion -> reverse of the horizontal velocity -> straight up -> straight down, at 2.5 cm and 8 cm) and sweep again. If pushing out fails, ignore that object for this frame.
     - Otherwise, stop 2 cm (`SkinCm`) from the surface along its normal, then corner correction (rising and the head grazed the corner of a ceiling (downward-facing surface) -> shift sideways by up to `CornerCorrectionCm` and continue) -> step correction (grounded and the feet hit the corner of a step of `StepUpCm` or less -> climb onto it. While falling in the air, `LedgeAssistCm` or less) -> if neither works, slide along the surface.
     - Sliding: floors, slopes and ceilings remove the motion and velocity into the surface. Walls (non-walkable surfaces whose normal's vertical component is above -0.3) keep vertical motion and speed and remove only the horizontal part into the wall. Removing velocity into a non-walkable surface reports `HitWall`.
  5. Grounding: a body that was grounded probes down by `GroundSnapCm` unless leaving the ground; an airborne body probes by `GroundProbeCm` while falling; snaps and aligns velocity with the ground (stays grounded up and down slopes). Hits touching from the start of the sweep (side walls) are not ground (push out, or probe again excluding that object). On change, `LeftGround` / `Landed` (and `LandedEvent`).
  6. `PostMoveEvent`: components that read the position (face, camera, conditions, touch). Here ride switches floors when the object stood on (`GetGroundEntity`) changes, and when leaving (after waiting up to `GraceSeconds` for a momentary drop) adds the floor's velocity to the body.
  7. After physics (`TickEvents.PostPhysics`): ride carries once more by the floor's motion that happened after the body moved (realigns onto the floor at the end of the frame).
- While grounded, upward velocity away from the ground of 200 cm/s (`GroundStickSpeedCmPerSecond`, private) or less is removed by aligning with the ground (so the body does not float on slopes). To launch the body off the ground, `SetVelocity` / `AddVelocity` faster than that.
- Vertical motion along walls: jumping or falling while pressed against a wall is not stopped by the wall (only the horizontal part into the wall is removed). The body stops 2 cm from the wall along its normal and pushes out when about to penetrate. Hitting a ceiling (normal below -0.3) stops upward motion.
- Steps up to `StepUpCm` can be climbed (make taller steps into slopes). Step correction works only while grounded (in the air, `LedgeAssistCm`. Default 0, unused). It advances to where the body will not slide off the corner, so it may move a few cm further than this frame's motion. The body alone does not move with a moving floor (add SurfaceKit's `character_ride_component` to be carried. The object stood on is the entity hit by the ground sweep = `GetGroundEntity`).
- Locking input (`LockInput`): walk treats input as 0 (only braking continues, no turning even with TankTurn, the toggle button is ignored), jump does not jump and discards presses (the apex hang stops too), dash does not dash and ends a dash in progress (cutting the speed to walking speed), face does not turn. Body physics (gravity, sweep, grounding) keep running, so to freeze the whole body also call `SetGravityScale(0)` and `SetVelocity(vector3{})` (dash does not change `SetGravityScale`, so the call order does not matter). Each caller keeps its returned cancelable and `Cancel`s it to unlock (input returns when all are removed). Your own movement components should check `IsInputLocked` too.
- Finding walk: face (and your own components) find walk with `FindCharacterWalk` (the body entity, otherwise any one of its descendants). If you place walk on a descendant, place only one.
- Modifiers (`AddModifier`, BuffKit): multipliers multiply, counts add. Removing all restores the `@editable` values of each component. Speed applies to walk's top speed (also when running), jump to jump's jump speed, gravity to the body's gravity (applied separately from the `SetGravityScale` factor. Even if dash or a freeze resets `SetGravityScale` to 1, the modifiers' share remains). The side-input style (`SideStyle`) is the last modifier added; when all are removed, walk's base (`GetBaseSideStyle`) returns. BuffKit components remove on both the deactivation signal and `OnEndSimulation`, so nothing lingers when an effect prefab (PickupSystem) disappears. Only custom character bodies are affected (not the Fortnite character).
- SurfaceKit: a custom character moves with its own capsule, so mesh overlap notifications (`EntityEnteredEvent`) never arrive. "Touched / stepped on" is decided by `character_touch_component` comparing the body's box with the `character_surface_component` boxes (world-axis-aligned cuboids) (if the entity the body stands on by the ground sweep carries a surface, the body counts as standing on it without comparing boxes). Moving so fast that a surface is passed within one frame does not touch it (make thin surfaces thicker). When "standing on" a rotated surface is decided by boxes, the box is the world-axis box enclosing the rotated one, so on a platform rotated about 45 degrees the body may count as standing on it outside the corners.
- Moving floors (`character_ride_component`): what carries the body is the entity it stands on by the ground sweep (a collidable mesh). Surfaces without collision (only a `character_surface_component` box) do not carry. Only the body's position is carried (the facing is unchanged). When the floor turns in yaw, `FollowYaw` (default on) rotates the body's position around the floor too. Pitch / roll of the floor are not followed. Vertical motion is applied as is (no sweeping while penetrating a floor that rose); horizontal motion stops short on hitting anything other than the floor (no penetrating walls while carried. Being pushed off the floor by a wall can happen). Not pushed back when squeezed against a ceiling above. Not carried along the axis locked by the body's `AxisLock`.
- Places to update when adding a side-input style (a value of `character_side_style`): `SideInputTurnsBody` in `CharacterMotorComponent.verse`, BodyKit's `character_face_movement_component.OnPostMove` (the `case` for where to face), MCPSystem's CharacterKit (the `case`s of `SideStyleName` / `SideStyleTitle` and the lookup-by-name list), TooltipKit's `WalkSideStyleToolTip`, this README. None of the `case`s writes `_`, so forgetting one fails to compile (only the lookup-by-name list is an array and compiles even if forgotten).
- When several modifiers on the body (`character_modifier.SideStyle`) are stacked, the last one added wins (by rule). When it is removed, the last of those added before it; when all are removed, walk's base returns.
- Side-input style: a single value (walk's `GetSideStyle`) is read by walk, face and MCP (changed through `SideStyle` (@editable), `SetSideStyle` / `SwitchSideStyle`, `SideStyleToggleAction`, `character_modifier.SideStyle` (BuffKit's `OverrideSideStyle`) and MCP's `character.set_side_style`). With `TankTurn`, walk turns the body (the motor entity) and face does nothing. The front for `Strafe` is `GetWalkFront` (with `Space = Facing` it is the body's own facing, so no turning; `SideView` has no front, so no turning). The yaw direction is matched with `YawSign` (directly under CharacterSystem. In UEFN v43.00, positive yaw turns right).
- During a dash, gravity is weakened every frame with `ScaleGravityThisFrame(DashGravityScale)` (`SetGravityScale` is untouched, so a factor set by other components remains). walk leaves the velocity alone during a dash, so the distance is the same regardless of component order (the order `PreMoveEvent` arrives in).
- `character_owner_stasis_component` does not move the Fortnite character. Point the view at the custom character with `character_camera_component` (CameraExperimentalKit) or similar (the standard camera stays on the pinned Fortnite character).
- Turn `character_input_mapping_component`'s `RemoveOnEnd` on only for mappings dedicated to the custom character (removing a Fortnite mapping disables other controls too).
- When building a level through MCP: Fortnite's standard `input_action` / `input_mapping` (`Character.Jump`, `TraversalMapping`, etc.) cannot be set as references with MCP's `SetComponentProperty`. Using them as code defaults (`JumpAction = Character.Jump`, etc.) is fine. To use something else, such as putting `TraversalMapping` in `Mapping`, pick it in the editor.
- Reactions inside a loadout (components under `character_action_trigger_component`, etc.) also receive the activation signal that arrives the frame after the loadout is attached, and the deactivation signal when it is removed (LoadoutSystem).
- `Character.Move` (Fortnite's movement direction input) is `@experimental` (v43.00 digest). Code using it for `MoveAction` lives in an `...ExperimentalKit` (`_Samples/Platformer2DSampleExperimentalKit` has this form).
- `CameraExperimentalKit` uses the `@experimental` camera API (`perspective_camera_component` / `orthographic_camera_component` added to `camera_director_component`). Using it prevents publishing the island. VerseShare distributes this folder only to projects with "include experimental" on.
- ⚠ Unverified (as noted in the code):
  - Whether `FindSweepHits` with a capsule returns hits, normals and distances as described (CharacterMotorComponent.verse). Corner / step correction rely on the height and sideways offset of `ContactPosition` (the contact point), so whether that value is as described (if not, the corrections simply do nothing and the body slides as usual).
  - Whether `FindSweepHits` returns a hit at distance 0 (`StartHitCm` = 0.01 cm or less) when touching from the start of the sweep (about to penetrate), and whether the normal is then the reverse of the sweep (inferred from UE physics conventions. The suspected cause of the wall-sticking issue). Whether the push-out clearance check (sweep 2 cm the other way and look for a distance-0 hit) can detect penetration.
  - The feel of the new defaults for motion along walls, dash and air control (`AirBrakingRatio = 0.2`, `AirTurnAroundMultiplier = 2.0`, dash 2200 cm/s x 0.18 s).
  - The feel of the defaults for fall gravity, apex hang, turnaround, coyote time and input buffering (values to be tuned in the editor).
  - The positive direction of Yaw in `character_face_movement_component`. If it faces backward, place the visual mesh rotated 180 degrees (BodyKit/CharacterBodyComponents.verse).
  - Whether the standard camera follows smoothly when the pinned Fortnite character's position is rewritten every frame during stasis (BodyKit/CharacterBodyComponents.verse).
  - The direction of `MoveAction`'s value (read as Forward = forward, Left = left) (MoveKit/CharacterWalkComponent.verse).
  - How `Strafe` / `TankTurn` look in the editor (the turn direction of `TankTurn`'s side input, the direction `Strafe` turns to follow the view) (MoveKit/CharacterWalkComponent.verse, BodyKit/CharacterBodyComponents.verse).
  - The positive direction of the camera's Yaw / Pitch (CameraExperimentalKit/CharacterCameraComponent.verse).
  - `player_orbit_camera`: whether a camera moved with `SetGlobalTransform` every frame renders smoothly. How the view returns to the previous camera after `Detach` (CameraExperimentalKit/PlayerOrbitCamera.verse). Rotations are built with `MakeRotationDegrees` (axis and angle. Right-handed), so they do not rely on the sign of `MakeRotationFromYawPitchRollDegrees`.
  - Whether `GetGlobalTransform` of a floor driven by keyframed_movement_component returns the moved position every frame on the server. Whether the carried body (which receives the server position) and the floor (played back on the client) stay aligned on the client's screen (SurfaceKit/CharacterSurfaceComponents.verse).
  - Whether moving the body in `TickEvents.PostPhysics` puts that position into the visuals and the replicated position within the same frame (ride's second carry).

## Verifying
- Test: `character_system_test_component` in `_Test/CharacterSystemTest/`. Place one entity with `player_manager_component` and one with this component, and start with one player standing on a flat floor. It creates an ownerless body (`AxisLock = Left`, `SpawnAtOwner = false`) 3 m in front of and 3 m above the player and checks that it has no owner, falls by gravity and lands (`IsGrounded`, `Landed` once), moves forward with `SetVelocity` while `AxisLock` keeps Left unchanged, and moves with `TeleportTo`. It also checks the landing speed (`GetLastLandingSpeed` above 100 cm/s) and that with two `LockInput`s stacked, removing one keeps it locked and removing both unlocks. Takes about 4 s. Results go to the output log as `[TEST] CharacterSystem`. Walking, jumping, input, the owned form, corner / step correction and slope snapping are not tested.
- Manual checks (play and watch):
  - Coyote time: you can jump right after walking off an edge. After leaving the edge by a jump, you cannot jump without air jumps.
  - Input buffering: pressing slightly before landing jumps at the moment of landing. With air jumps remaining, it jumps in the air when pressed.
  - Height control and apex hang: a short press jumps low, a long press high, with a slightly longer hang at the apex. Falling is faster than rising.
  - Corner correction: grazing a ceiling corner with the head does not stop you; the body shifts sideways a little and keeps rising. Step correction: low steps (up to 15 cm) can be walked up. Only with `LedgeAssistCm` set can you land on a ledge you slightly missed.
  - Slopes: `LeftGround` / `Landed` do not keep firing while going up and down (check with a sound on `Landed` of `character_action_trigger_component`).
  - `LockInput`: while locked, walking, jumping, dashing and facing do not change (also with TankTurn and Strafe). Unlocking restores them.
  - Air control: releasing input during a short jump keeps the momentum, and a long jump nearly stops at the end (`AirBrakingRatio`). Reversing input in the air changes direction faster the more opposed it is (`AirTurnAroundMultiplier`. Diagonal-back input does not change abruptly). With `Turn`, the body faces the input direction in the air (`AirFacesInput`).
  - Walls: jumping, falling or double-jumping while pressed against a wall does not stop halfway up the wall (vertical speed unchanged. `HitWall` does fire). You can jump while standing on the ground next to a wall.
  - Dash: travels the same distance every time (396 cm by default) and returns to walking speed when it ends (holding forward in the air does not keep drifting at dash speed). An air dash keeps its height. Jumping mid-dash gives a normal jump.
  - Moving floors (`character_ride_component` on the body): on a floor moved by MoverSystem's `mover_component` (both Keyframe and Physics), the body moves with floors going up, down, sideways and rotating (`FaceTravelDirection`), neither penetrating nor floating. Jumping on the floor keeps moving with it and lands back on the same floor. Jumping off or falling off the floor flies with the floor's velocity.
- Test: `character_surface_test_component` in `_Test/CharacterSystemTest/CharacterSurfaceTest.verse` (SurfaceKit). Same placement as the test above (needs a 5 m square floor 3 m in front of the player). It drops an ownerless body (motor + touch + ride) onto the floor, creates an invisible surface (a `SizeCm` box) at floor height and checks stepping on (`Touched`, `SteppedOn` once, `FindStandingSurface`), that ride rides the floor stood on (`GetGroundEntity`), that moving the non-collidable surface 150 cm forward does not carry the body (`GetGroundVelocity` is 0), that `SetActive(false)` gives stopped touching / stepped off, and that `GetBox` matches size, rotation and bottom origin (being carried by a moving floor is not tested since meshes cannot be created; see the manual checks above). About 5 s. Results go to the output log as `[TEST] CharacterSurface`.
- Test: `character_buff_test_component` in `_Test/CharacterSystemTest/CharacterBuffTest.verse` (modifiers and BuffKit). Just place one entity with this component (no player needed). It creates an ownerless body in the air and checks that `AddModifier` multiplies / adds and `Cancel` restores, and that `character_buff_component` / `character_move_grant_component` under the body stack on the activation signal and remove on the deactivation signal and when the entity is destroyed. About 1 s. Results go to the output log as `[TEST] CharacterBuff`.
- Sample: `platformer_2d_sample_component` in `_Samples/Platformer2DSampleExperimentalKit/` (experimental. Only for projects with "include experimental"). Attached to an empty entity on a floor, it creates a body for each joining player under their slot (motor `AxisLock = Left`, walk `SideView` (`Character.Move`), jump (double jump), body_link (not hidden), orthographic camera) for side-scrolling play. Entering the goal box returns you to the start. One `player_manager_component` is needed in the scope (or the world).

## Rounds
- `character_motor_component.ResetOnRoundStart` (default on): whenever a Fortnite round starts, clears velocity and moves to the owner's Fortnite character (respawned at the spawn point). Uses `round_watcher`.
- The 2D sample (`_Samples/Platformer2DSampleExperimentalKit`) turns this off on the body and returns everyone to the start at round start.

## Migration notes (2026-11-09, action cells)
Air jump, boost and wall kick can now be performed from a shared charge (action cells. CellKit).
- Added: CellKit (`character_action_cell_component` / `character_action_cell_grant_component` / `character_cell_action` / `character_cell_grant`), `character_action.WallKicked`, jump's `WallKickReachCm` / `WallKickAwaySpeedCmPerSecond` / `WallKickUpSpeedCmPerSecond`, ActivationSystem's `activation_finished_event` (PickupSystem effects end with it).
- Behavior changes:
  - jump: when jump is pressed in the air, if the body's action cells have WallKick and a wall is nearby, it kicks the wall before air-jumping. When `AirJumps` are used up, it jumps with the cells' AirJump. Without action cells, same as before.
  - dash: even without the `RequiresGrant` grant or remaining air dashes, dashes by spending one cell if the cells have Boost (no cell is spent when a grant / air dash allows it). Without action cells, same as before.
  - A value was added to `character_action`, so code that `case`s over all of them must add `WallKicked`.

## Migration notes (2026-11-09, wall / dash / air feel)
Fixes from playtesting (getting stuck when moving up / down while pressed against a wall, a dash that felt like a boost, odd air control). Default values that change behavior (and the values that restore the previous behavior):
- Body (the wall-sticking issue): two causes overlapped. (1) On a hit, the body stopped 2 cm back along the sweep direction, so on every shallow approach to a wall (jumping or falling while pressed against it) the gap shrank, reaching 0 within a few frames. (2) Sweeping with a 0 gap returns a hit touching from the start (distance 0) whose normal is the reverse of the sweep (straight up when falling), so the wall was mistaken for a floor / ceiling, vertical velocity was removed, and the ground probe "stood" halfway up the wall with gravity stopped (hypothesis. Listed under Unverified). In addition, a wall normal with a slight vertical component shaved vertical speed on every slide.
  - The stop distance is now 2 cm along the surface normal. Distance-0 hits are pushed out without using the normal (if that fails, the object is ignored for the frame). Grounding and ride's `GraceSeconds` probe no longer treat distance-0 hits as ground. Walls (non-walkable surfaces that are not ceilings) no longer change vertical motion or speed. There is no value to restore the previous behavior.
  - `StepUpCm` is used only while grounded (it used to apply while falling in the air too). The air ledge assist is the new `LedgeAssistCm` (default 0). For the previous behavior, `LedgeAssistCm = 15`.
  - `CornerCorrectionCm` is used only for ceilings (normal's vertical component below -0.3) (it used to apply to any slightly downward-facing surface).
- dash: it used to set the gravity scale 0 -> 1 with `SetGravityScale` and drop to 600 cm/s at the end (ignoring walk's speed. On frames where walk ran first, it shaved the dash speed, so the distance depended on component order).
  - Defaults changed to `DashSpeedCmPerSecond = 2000 -> 2200` and `DurationSeconds = 0.2 -> 0.18` (distance 400 -> 396 cm. Faster and shorter). For the previous behavior, 2000 / 0.2.
  - New `DashEndSpeedRatio = 1.0`: at the end, the speed along the dash direction is cut to walk's speed cap x (the modifiers' speed multiplier) x this, and the sideways speed is removed (it used to be a fixed 600 cm/s). New `DashGravityScale = 0`: gravity is weakened with `ScaleGravityThisFrame` (`SetGravityScale` is untouched. It used to be reset to 1 at the end).
  - The direction now prefers walk's input direction (it used to be current horizontal motion -> body facing). The `AxisLock` axis is removed.
  - Jumping or `LockInput` mid-dash ends it on the spot and cuts the speed (the dash used to continue at dash speed after a jump, and `LockInput` left the speed as is).
  - walk leaves the velocity alone during a dash (the body's `SetMoveOverride` / `IsMoveOverridden`, internal). The velocity inherited from moving ground is cleared at the moment of dashing.
  - Sequence: 0 s pick the direction and set 2200 cm/s (vertical 0 in the air) -> 0.18 s at the same speed (gravity x0. The last frame moves at dash speed only for the remaining seconds, so the distance is 396 cm regardless of frame length) -> before the next frame's move, cut to 600 cm/s (the walking speed cap) -> the next dash is available 0.8 s after dashing.
- walk (air control): `AirBrakingRatio = 0.1 -> 0.2` (releasing input, 600 cm/s stops in 0.6 s instead of 1.2 s. It kept drifting like on ice). `AirTurnAroundMultiplier = 2.5 -> 2.0`, applied smoothly by the degree of opposition (it used to jump from 2400 to 6000 cm/s^2 at the 90-degree boundary, turning abruptly only for diagonal-back input). `AirControlRatio = 0.6` is unchanged. For the previous behavior, `AirBrakingRatio = 0.1` and `AirTurnAroundMultiplier = 2.5` (the smooth application cannot be reverted).
  - When the velocity inherited from moving ground shrinks from opposing input or a wall, the body's inherited velocity shrinks too (after hitting a wall, input in the same direction used to restore the non-braked inherited speed, which kept drifting after release).
- Additions only (no migration needed): the body's `LedgeAssistCm`, dash's `DashEndSpeedRatio` / `DashGravityScale`. Internal `SetInheritedVelocity` / `SetMoveOverride` / `IsMoveOverridden`.

## Migration notes (2026-11-09, air control and moving floors)
Air control was split up and riding moving floors was rebuilt. Default values that change behavior (and the values that approximate the previous behavior):
- walk: `AirControlRatio` now applies only to air acceleration (it used to apply to both acceleration and braking). The default was raised from 0.35 to 0.6. Braking without input in the air is the new `AirBrakingRatio = 0.1` (it used to be 0.35, same as `AirControlRatio`), and air turnarounds use the new `AirTurnAroundMultiplier = 2.5` (it used to be `TurnAroundMultiplier` x `AirControlRatio`). For the previous behavior, `AirControlRatio = 0.35`, `AirBrakingRatio = 0.35`, `AirTurnAroundMultiplier = 2`, `KeepAirMomentum = false`.
- walk: `KeepAirMomentum = true` (speed above the cap in the air is not reduced unless the input opposes it). It used to approach the input speed in the air too (dash and knockback momentum was lost to input). `false` for the previous behavior.
- face: `AirFacesInput = true` (with `Turn`, turns toward the input direction in the air. No turning without input). `false` for the previous behavior (the movement direction in the air too).
- ride: the object ridden is now decided by the entity hit by the body's ground sweep (`GetGroundEntity`) instead of `character_touch_component`'s `FindStandingSurface` (surface boxes). `character_touch_component` and the platform's `character_surface_component` are no longer needed (leaving them is fine). Surfaces without collision (box only) no longer carry when moved (they used to).
- ride: carrying switched from `TeleportTo` to the body's `CarryBy` (internal). Horizontal motion stops short on hitting anything other than the floor (it used to penetrate walls). Not carried along the axis locked by the body's `AxisLock` (the locked position used to move with the floor). Carrying no longer cancels the `SpawnAtOwner` move one frame later (it used to, being treated as a TeleportTo).
- ride: `InheritVelocity = true` (inherit the floor's velocity on leaving, remove it on landing). `false` for the previous behavior (the floor's motion vanished the moment you left). `GraceSeconds = 0.1` (0 for the previous behavior). Now also carries after physics (`TickEvents.PostPhysics`).
- touch: if the entity the body stands on carries a `character_surface_component`, the body counts as standing on that surface without comparing boxes (even if the box size / origin settings are off).
- Additions only (no migration needed): the body's `GetGroundEntity` / `GetGroundVelocity` / `GetInheritedVelocity`, walk's `GetInputDirection`, ride's `FindRidingEntity` / `GetRideVelocity`.

## Migration notes (2026-11-09, feel)
Movement feel was added. Default values that change behavior (and the values that restore the previous behavior):
- Body: `FallGravityMultiplier = 1.6` (falls faster. 1 for the previous behavior), `GroundSnapCm = 20` (snaps when going down slopes and steps up to 20 cm. 0 for the previous behavior), `StepUpCm = 15` (climbs steps up to 15 cm and onto ledges. 0 for the previous behavior), `CornerCorrectionCm = 12` (shifts sideways at ceiling corners. 0 for the previous behavior).
- Body: while grounded, upward velocity of 200 cm/s or less is now removed by aligning with the ground (any upward velocity used to lift the body briefly). The body stays grounded while going up slopes (it used to alternate between airborne and grounded, firing `LeftGround` / `Landed` repeatedly). On grounding, the velocity is aligned with the ground (only the downward speed used to be zeroed).
- walk: `TurnAroundMultiplier = 2` (faster turnarounds. 1 for the previous behavior).
- jump: `ApexSpeedThresholdCmPerSecond = 150` / `ApexGravityMultiplier = 0.5` (hangs at the apex while held. 0 / 1 for the previous behavior). `Jump` from code (including MCP's `jump`) used to get height control applied immediately, giving a low jump; it is now counted as held until `ReleaseJump` is called or the body lands (a high jump). For a low jump, call `ReleaseJump` after jumping.
- jump: at most one jump per frame. Even with `BufferSeconds = 0`, presses since the previous frame can jump (at 0 it used to hardly jump at all). Height control no longer applies to a jump that started falling or to a launch.
- face: finds walk on the body's descendants as well as the body entity (`FindCharacterWalk`).
- Additions only (no migration needed): `LandedEvent`, `GetLastLandingSpeed`, `ScaleGravityThisFrame`, `LockInput` / `IsInputLocked`, `ReleaseJump`, `FindCharacterWalk`.
- MCPSystem's CharacterKit still finds walk only on the body entity (`Motor.Entity.GetComponent[character_walk_component]`). To use a walk on a descendant too, change that to `Motor.FindCharacterWalk[]`.

## Migration notes (2026-11-09)
- Additions only (no migration needed): the side-input style `character_side_style` (walk's `SideStyle` (default `Turn`, as before), `TankTurnDegreesPerSecond`, `SideStyleToggleAction`, `ToggleSideStyle`, `GetSideStyle` / `GetBaseSideStyle` / `SetSideStyle` / `SwitchSideStyle` / `GetWalkFront` / `SideStyleChangedEvent`, `character_modifier.SideStyle`, `character_motor_component.GetSideStyleOverride`, `character_buff_component.OverrideSideStyle` / `SideStyle`, `character_side_style_modified_tag`). `YawSign` moved from BodyKit to directly under CharacterSystem (internal. No effect unless used from outside).

## Migration notes (2026-11-08)
- Added `character_ride_component.FollowYaw` (default on): when the surface ridden turns in yaw, the body's position is now rotated around the surface too. Surfaces that do not rotate behave as before. Turn it off for the previous behavior (positional motion only).
- Additions only (no migration needed): `character_modifier` and `character_motor_component.AddModifier` etc., `character_dash_component.RequiresGrant` (default off, as before), BuffKit.
- `character_body_link_component` (OffsetCm / HideBody) -> `character_owner_stasis_component` (no settings). The behavior of making the Fortnite character follow the custom character was dropped (the custom character is meant to move entirely on its own). Needs re-placing

## Migration notes (2026-11-09, clinging to walls and ceilings)
The slime ability (clinging to and crawling on walls and ceilings) was added. See `ClingKit/README.md` for details. Mostly additions, but enumerators were added, so the following needs fixing:
- `ClingStart` / `ClingEnd` were added to `character_action` and `Clinging` to `character_motor_state` (both appended at the end). Code that `case`s over them without `_` no longer compiles, so add the two / the one (MCPSystem's CharacterKit is already fixed).
- The body's `IsMoveOverridden` (internal) now also succeeds while clinging (tracked separately from dash's `SetMoveOverride`). Without the cling component, same as before.
- Additions only (no migration needed): `character_cling_surface`, `character_modifier.GrantsCling`, the body's `CanCling` / `IsClinging` / `GetClingSurface` / `GetClingNormal` (and the internals for ClingKit), walk's `GetMoveInput`, BuffKit's `character_move_grant_component.GrantCling` and `character_cling_granted_tag`, ClingKit's `character_cling_component`.
- Behavior that changes only with the cling component present: walk leaves the velocity alone while clinging and does not turn the body on a wall even with TankTurn. jump jumps off the cling first (air jumps are restored while clinging). dash does not dash while clinging and ends a dash in progress on attaching. face faces the wall on a wall. The body does not probe for ground while clinging and rising.

## Migration notes (2026-11-09, overview camera)
- Additions only (no migration needed): CameraExperimentalKit's `player_orbit_camera` / `MakePlayerOrbitCamera` (a camera orbiting a chosen point. Rotation and distance are changed from code).
