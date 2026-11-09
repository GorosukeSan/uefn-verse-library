using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { CharacterSystem.TooltipKit }

# Something that happened to the character (arrives on character_motor_component.ActionEvent. EventKit's character_action_trigger_component watches it)
character_action<public> := enum:
    # Jumped from the ground (reported by the jump component)
    Jumped
    # Jumped in the air (2nd jump onward. Reported by the jump component)
    AirJumped
    # Kicked off a wall in the air (reported by the jump component through the WallKick of CellKit's action cell)
    WallKicked
    # Dashed (reported by the dash component)
    Dashed
    # Came down from the air onto the ground
    Landed
    # Left the ground (jump or fall)
    LeftGround
    # Started moving horizontally (exceeded MovingSpeedCmPerSecond)
    StartedMoving
    # Stopped horizontally (dropped below MovingSpeedCmPerSecond)
    StoppedMoving
    # Hit a wall or ceiling (hard enough to change the direction of motion)
    HitWall
    # Clung to a wall or ceiling (reported by ClingKit's character_cling_component. Not sent when moving from wall to ceiling while still clinging)
    ClingStart
    # Left a wall or ceiling (jumped, released, surface gone, grant expired, input stopped, or landed. Reported by the ClingKit component)
    ClingEnd

# Kind of surface being clung to (decided by ClingKit's character_cling_component, remembered by the body)
character_cling_surface<public> := enum:
    # Wall (a non-walkable surface that does not face steeply downward). Crawl up / down and sideways
    Wall
    # Ceiling (a downward-facing surface). Crawl horizontally
    Ceiling

# Continuous state of the character (watched by ConditionKit's character_motor_condition_component)
character_motor_state<public> := enum:
    # On the ground
    Grounded
    # In the air
    Airborne
    # In the air and rising
    Rising
    # In the air and falling
    Falling
    # Moving horizontally
    Moving
    # Horizontally still
    Still
    # Clinging to a wall or ceiling (ClingKit. While clinging the body is not grounded, so it is also Airborne)
    Clinging

# Restrict movement to a plane (side-scrolling 2D, etc.)
character_axis_lock<public> := enum:
    # No restriction (3D)
    None
    # Lock Left. Move only along Forward and up / down (side-scroller)
    Left
    # Lock Forward. Move only along Left and up / down
    Forward

# What to do with side input (held by MoveKit's character_walk_component. Read by BodyKit's character_face_movement_component)
#   Places to update when adding a value (none of the cases uses _, so forgetting one fails to compile):
#     SideInputTurnsBody below (used by walk), BodyKit's character_face_movement_component.OnPostMove (where to face the body),
#     MCPSystem's CharacterKit (SideStyleName / SideStyleTitle and the lookup-by-name list), TooltipKit's WalkSideStyleToolTip, README
#   When several modifiers on the body (character_modifier.SideStyle) are stacked, the last one added wins (by rule. character_motor_component.GetSideStyleOverride)
character_side_style<public> := enum:
    # Move sideways; the body turns toward the movement direction (default)
    Turn
    # Move sideways, but the body keeps facing the walk's forward (the view direction when Space = View) (crab walk)
    Strafe
    # Do not move sideways; turn the body in place. Forward / back move along the body's facing (walk's Space is not used)
    TankTurn

# True if, for Style, side input only turns the body (no sideways movement; forward / back move along the body's facing) (used by walk)
SideInputTurnsBody<internal>(Style:character_side_style)<computes>:logic =
    case (Style):
        character_side_style.Turn => false
        character_side_style.Strafe => false
        character_side_style.TankTurn => true

# Tag attached to the player (agent) while they are driving a custom character. character_motor_component adds and removes it
custom_character_tag<public> := class(player_state_tag):

# A modifier stacked onto the body's movement (buff / ability grant). Add with character_motor_component.AddModifier, remove with Cancel on the returned cancelable
#   Any number can be stacked. Multipliers multiply, counts add, dash / cling permission is granted if at least one grants it, the side-input style (SideStyle) is the last one added. Removing all of them restores the originals (the @editable values of each component)
#   BuffKit's character_buff_component / character_move_grant_component use this (your own components can use it too)
character_modifier<public> := struct:
    # Multiplier on the walk / run speed cap (walk's MaxSpeedCmPerSecond). Default 1
    SpeedMultiplier<public>:float = 1.0
    # Multiplier on the upward speed at the moment of jumping (jump's JumpSpeedCmPerSecond. Height changes roughly with the square). Default 1
    JumpMultiplier<public>:float = 1.0
    # Multiplier on gravity (0.5 for a floaty fall). Applied separately from SetGravityScale. Default 1
    GravityMultiplier<public>:float = 1.0
    # Number added to the air jump count (jump's AirJumps). Default 0
    ExtraAirJumps<public>:int = 0
    # If true, dashing is allowed even when dash's RequiresGrant is on. Default false
    GrantsDash<public>:logic = false
    # If true, ClingKit's character_cling_component (with RequiresGrant on) can cling to walls and ceilings. Default false
    GrantsCling<public>:logic = false
    # While stacked, sets walk's side-input style to this (takes precedence over walk's base SideStyle. With several, the last one added). false leaves it unchanged. Default false
    SideStyle<public>:?character_side_style = false

# Role: the body and physics of a custom character. Does not use the Fortnite character's movement; moves this entity from Verse (kinematic: integrates velocity itself and sweeps a capsule to resolve collisions)
#   Every frame (TickEvents.PrePhysics): PreMoveEvent (movement components on the same entity set the velocity) -> gravity -> sweep and slide along surfaces hit (up to 4 times) -> probe downward for ground and decide grounding -> PostMoveEvent
#   Gravity: GravityCmPerSecondSquared x the SetGravityScale factor x GravityMultiplier of stacked modifiers x this frame's factor (ScaleGravityThisFrame) x FallGravityMultiplier while falling. SetGravityScale(0) always gives 0 (can hold the body still)
#   On hit: stop SkinCm away from the surface along its normal (not SkinCm back along the sweep direction), then slide the rest along the surface
#     Floors / slopes (walkable surfaces) and ceilings: slide along the surface (landing or bumping the head stops vertical motion)
#     Walls (non-walkable surfaces that are not ceilings): vertical motion is kept; only the horizontal part heading into the wall is removed (a wall does not stop falling or jumping along it)
#     Hits touching from the start of the sweep (distance 0, about to penetrate): do not trust the returned normal (it is the reverse of the sweep, which looks like a floor when falling); push out and sweep again. If pushing out fails, ignore that object for this frame
#   Corrections on hit (tried on every sweep hit, before sliding along the surface):
#     Corner correction: if the head only grazed the corner of a ceiling (downward-facing surface) while rising, shift sideways by up to CornerCorrectionCm and keep rising (velocity unchanged)
#     Step correction: if, grounded and moving horizontally, the feet only hit the corner of a step (StepUpCm or less), climb onto the step (stairs). While falling in the air, only ledges of LedgeAssistCm or less (default 0, unused)
#   Grounding: a body that was grounded, while it moves along the ground (not leaving by jump or launch), probes down by GroundSnapCm, snaps to the ground and aligns velocity with it (no floating when walking up or down slopes)
#   The body shape is a vertical capsule whose feet (bottom center) are at this entity's position (diameter RadiusCm x 2, height HeightCm). Collision uses FindSweepHits (ignores its own entity and descendants, and the owner's Fortnite character)
#   Ways of moving (walk, jump, dash, facing, syncing the Fortnite character) are added with MoveKit / BodyKit components on the same entity (this component knows nothing about input). To write your own component, subscribe to PreMoveEvent and call AddVelocity / SetVelocity
# Placement: in the editor, attach to the custom character's entity (the parent of the visual mesh). To drive one per player, make this entity a prefab and put it in the Prefab of LoadoutSystem's loadout_component (which assigns the owner)
# Same entity: MoveKit components (character_walk_component, character_jump_component, ...), BodyKit components (character_owner_stasis_component, character_face_movement_component)
# When: runs from the start of simulation. With SpawnAtOwner, moves to the owner's Fortnite character one frame after start (so the visual children follow). With ResetOnRoundStart, clears velocity and moves to the owner whenever a Fortnite round starts (fort_round_manager)
# Notifications: ActionEvent (character_action), PreMoveEvent / PostMoveEvent (seconds since the previous frame), LandedEvent (downward speed at the moment of landing)
# Tags: attaches custom_character_tag to the owner (while driving)
# From outside: Entity.FindCharacterMotorFor[Agent] finds the body a player is driving. GetVelocity / SetVelocity / AddVelocity / IsGrounded / IsInState / GetGroundNormal / GetGroundEntity / GetGroundVelocity / GetInheritedVelocity / SetGravityScale / ScaleGravityThisFrame / GetLastLandingSpeed / TeleportTo / ReportAction / FindOwner
#   Modifiers (buffs / ability grants): AddModifier (stack a character_modifier, remove with the returned cancelable), GetSpeedMultiplier / GetJumpMultiplier / GetGravityMultiplier / GetExtraAirJumps / IsDashGranted / CanCling / GetSideStyleOverride (read by walk / jump / dash / cling)
#   Cling (decided by ClingKit's character_cling_component): IsClinging / GetClingSurface / GetClingNormal. While clinging IsMoveOverridden succeeds (walk leaves the velocity alone) and no ground probe is done while rising (starting to climb from the foot of a wall does not snap to the floor)
#     jump checks cling first (on a wall it jumps with GetClingJumpVelocity; on a ceiling it only lets go. RequestClingRelease asks cling to release)
# Requirements / notes: steps up to StepUpCm can be climbed (make taller steps into slopes). The body alone does not move with a moving floor (add SurfaceKit's character_ride_component to be carried. The object stood on is the entity hit by the ground sweep = GetGroundEntity)
#   While grounded, upward velocity away from the ground of GroundStickSpeedCmPerSecond (200 cm/s) or less is removed by aligning with the ground (faster jumps / launches do leave)
# ⚠ Unverified: whether FindSweepHits with a capsule returns hits, normals, distances and ContactPosition (used by corner / step correction) as described (UEFN 43.00 in the editor)
character_motor_component<public> := class<final_super>(component):

    # Capsule radius (cm). Default 40
    @editable_number(float):
        ToolTip := MotorRadiusToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{5.0}
        MaxValue := option{1000.0}
    RadiusCm<public>:float = 40.0
    # Capsule height (cm, feet to head). Default 180
    @editable_number(float):
        ToolTip := MotorHeightToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{10.0}
        MaxValue := option{2000.0}
    HeightCm<public>:float = 180.0
    # Gravitational acceleration (cm/s^2). Default 1960
    @editable_number(float):
        ToolTip := MotorGravityToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.0}
        MaxValue := option{20000.0}
    GravityCmPerSecondSquared<public>:float = 1960.0
    # Maximum fall speed (cm/s). Default 4000
    @editable_number(float):
        ToolTip := MotorMaxFallToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.0}
        MaxValue := option{50000.0}
    MaxFallSpeedCmPerSecond<public>:float = 4000.0
    # Multiplier on gravity while falling (vertical speed negative). Falls faster than it rises, less floaty. 1 means the same as rising. Default 1.6
    #   Applies not only after a jump but also when walking off an edge or falling after a launch (stays 0 with SetGravityScale(0))
    @editable_number(float):
        ToolTip := MotorFallGravityToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.1}
        MaxValue := option{10.0}
    FallGravityMultiplier<public>:float = 1.6
    # Maximum slope angle you can stand on (degrees). Steeper surfaces slide as walls. Default 50
    @editable_number(float):
        ToolTip := MotorMaxSlopeToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.0}
        MaxValue := option{89.0}
    MaxSlopeDegrees<public>:float = 50.0
    # Ground probe distance (cm). Snaps if ground is within this distance below the feet. Default 10
    @editable_number(float):
        ToolTip := MotorGroundProbeToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.0}
        MaxValue := option{200.0}
    GroundProbeCm<public>:float = 10.0
    # Downward probe distance (cm) for a body that was grounded and is moving along the ground (not leaving by a jump). Snaps without floating when going down slopes or low steps. GroundProbeCm if smaller than it. 0 disables. Default 20
    @editable_number(float):
        ToolTip := MotorGroundSnapToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.0}
        MaxValue := option{200.0}
    GroundSnapCm<public>:float = 20.0
    # Maximum height (cm) of a step corner the feet may hit and climb while grounded and moving horizontally. For stairs. 0 disables. Default 15
    #   Not used in the air (no climbing onto walls while falling or jumping along them). The air ledge assist is LedgeAssistCm
    @editable_number(float):
        ToolTip := MotorStepUpToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.0}
        MaxValue := option{200.0}
    StepUpCm<public>:float = 15.0
    # Maximum height (cm) of a ledge corner the feet may hit and climb while falling in the air (assist for a jump that fell slightly short). 0 disables. Default 0
    @editable_number(float):
        ToolTip := MotorLedgeAssistToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.0}
        MaxValue := option{200.0}
    LedgeAssistCm<public>:float = 0.0
    # Maximum sideways shift (cm) to keep rising when the head grazes a ceiling corner. 0 disables. Default 12
    @editable_number(float):
        ToolTip := MotorCornerCorrectionToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.0}
        MaxValue := option{100.0}
    CornerCorrectionCm<public>:float = 12.0
    # "Moving" (StartedMoving / Moving) when the horizontal speed exceeds this. Default 10
    @editable_number(float):
        ToolTip := MotorMovingSpeedToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.0}
        MaxValue := option{1000.0}
    MovingSpeedCmPerSecond<public>:float = 10.0
    # Restrict movement to a plane. Left keeps the Left position where it was at start (or at TeleportTo) (side-scroller). Default None
    @editable:
        ToolTip := MotorAxisLockToolTip
        Categories := array{CharacterMotorCategory}
    AxisLock<public>:character_axis_lock = character_axis_lock.None
    # When on, moves to the owner's Fortnite character at start. Default on
    @editable:
        ToolTip := MotorSpawnAtOwnerToolTip
        Categories := array{CharacterMotorCategory}
    SpawnAtOwner<public>:logic = true
    # When on, clears velocity and moves to the owner's Fortnite character whenever a Fortnite round starts (restart from the start each round). Default on
    @editable:
        ToolTip := MotorResetOnRoundToolTip
        Categories := array{CharacterMotorCategory}
    ResetOnRoundStart<public>:logic = true

    # Distance kept from surfaces (cm). Stops slightly short so the body never penetrates the surface hit
    SkinCm<private>:float = 2.0
    MaxSlideIterations<private>:int = 4
    # While grounded, if the speed away from the ground is at most this (cm/s), the body counts as moving along the ground. Absorbs the wobble of slopes and acceleration; jumps and launches (faster) do leave
    GroundStickSpeedCmPerSecond<private>:float = 200.0
    # Number of steps tried by corner correction when the shift direction is unknown (hit a flat ceiling) (CornerCorrectionCm divided equally, nearest first)
    CornerCorrectionSteps<private>:int = 3
    # A hit at this distance (cm) or less counts as "touching from the start of the sweep (about to penetrate)". Its normal cannot be trusted
    StartHitCm<private>:float = 0.01
    # A surface whose normal's vertical component is below this (facing down) is a ceiling. Other non-walkable surfaces are walls (do not reduce vertical motion)
    CeilingNormalUp<private>:float = -0.3
    # Number of frames to remember the direction of the last wall touched, for pushing out of penetration
    WallMemoryFrames<private>:int = 30

    PreMoveEventInternal<private><final>:event(float) = event(float){}
    PostMoveEventInternal<private><final>:event(float) = event(float){}
    ActionEventInternal<private><final>:event(character_action) = event(character_action){}
    LandedEventInternal<private><final>:event(float) = event(float){}

    # Arrives every frame before moving, with the seconds since the previous frame. Movement components call AddVelocity / SetVelocity here
    PreMoveEvent<public><final>:listenable(float) = MakeProxyListenable(PreMoveEventInternal)

    # Arrives every frame after moving, with the seconds since the previous frame. Components that read the position and follow it (Fortnite character, camera) move here
    PostMoveEvent<public><final>:listenable(float) = MakeProxyListenable(PostMoveEventInternal)

    # Arrives whenever something happens (landed, jumped, dashed, started moving, ...)
    ActionEvent<public><final>:listenable(character_action) = MakeProxyListenable(ActionEventInternal)

    # Arrives whenever the body lands from the air, with the downward speed at that moment (cm/s, 0 or more). Right after Landed on ActionEvent. For landing squash, dust, sound volume, etc.
    LandedEvent<public><final>:listenable(float) = MakeProxyListenable(LandedEventInternal)

    var<private> Velocity:vector3 = vector3{}
    # Gravity multiplier for this frame only (ScaleGravityThisFrame. Reset to 1 before PreMoveEvent every frame)
    var<private> FrameGravityMultiplier:float = 1.0
    # Downward speed at the last landing (cm/s)
    var<private> LastLandingSpeed:float = 0.0
    var<private> Grounded:logic = false
    var<private> Moving:logic = false
    var<private> GroundNormal:vector3 = vector3{Up := 1.0}
    # The object stood on (the entity of the component hit by the ground sweep). false when not grounded
    var<private> GroundEntity:?entity = false
    # Velocity of the object stood on (cm/s. character_ride_component sets it every frame. 0 when not being carried)
    var<private> GroundVelocity:vector3 = vector3{}
    # Horizontal velocity inherited when leaving moving ground (cm/s. 0 on landing. The part walk does not decelerate in the air)
    var<private> InheritedVelocity:vector3 = vector3{}
    # true while another component (dash) is setting the velocity (walk leaves the velocity alone)
    var<private> MoveOverridden:logic = false
    # Counter incremented every OnTick, the counter value when a wall was last touched, and that wall's outward direction (horizontal unit vector)
    var<private> FrameIndex:int = 0
    var<private> LastWallFrame:int = -1000
    var<private> LastWallNormal:vector3 = vector3{}
    var<private> GravityScale:float = 1.0
    var<private> Owner:?player = false
    # Whether TeleportTo was called since start (if so, the SpawnAtOwner move one frame later is skipped. Does not overwrite a position another component set first)
    var<private> TeleportedSinceBegin:logic = false
    # Position kept by AxisLock (cm)
    var<private> LockedValue:float = 0.0
    var<private> TickSubscription:?cancelable = false
    # Stacked modifiers (id, modifier) and their totals
    var<private> Modifiers:[]tuple(int, character_modifier) = array{}
    var<private> NextModifierId:int = 0
    var<private> SpeedMultiplier:float = 1.0
    var<private> JumpMultiplier:float = 1.0
    var<private> GravityMultiplier:float = 1.0
    var<private> ExtraAirJumps:int = 0
    var<private> DashGrants:int = 0
    var<private> ClingGrants:int = 0
    var<private> SideStyleOverride:?character_side_style = false
    # Cling (set by ClingKit's character_cling_component through SetClingState): kind of surface clung to (false when not clinging), surface normal (outward unit vector), velocity jump uses when jumping off
    var<private> ClingSurface:?character_cling_surface = false
    var<private> ClingNormal:vector3 = vector3{}
    var<private> ClingJumpVelocity:vector3 = vector3{}
    # jump asked to release the cling (cling releases the next time it looks and resets this to false)
    var<private> ClingReleaseRequested:logic = false
    # Ids of active LockInput locks
    var<private> InputLocks:[]int = array{}
    var<private> NextInputLockId:int = 0
    OwnerTags<private>:player_tag_holder = player_tag_holder{}
    Rounds<private>:round_watcher = round_watcher{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (OwningPlayer := Entity.FindOwningPlayer[]):
            set Owner = option{OwningPlayer}
            OwnerTags.Add(OwningPlayer, custom_character_tag{})
        set LockedValue = LockedComponent(Entity.GetGlobalTransform().Translation)
        set TickSubscription = option{TickEvents.PrePhysics.Subscribe(OnTick)}
        if (ResetOnRoundStart?):
            Rounds.Start(Entity, OnRoundStarted, OnRoundEnded)

    # The SpawnAtOwner move is done one frame later. Moving inside OnBeginSimulation left children not yet in the scene (the visual mesh) behind,
    # so body and visuals stayed apart (UEFN v43.00: moving a body created from a prefab at start left the child mesh where it was created)
    OnSimulate<override>()<suspends>:void =
        Sleep(0.0)
        if (SpawnAtOwner?, not TeleportedSinceBegin?, OwningPlayer := Owner?, Body := OwningPlayer.FindPlayerEntity[]):
            TeleportTo(Body.GetGlobalTransform().Translation)

    OnEndSimulation<override>():void =
        TickSubscription.CancelIfSet()
        set TickSubscription = false
        Rounds.Stop()
        OwnerTags.RemoveAll()
        (super:)OnEndSimulation()

    # Owner (the player driving this character). Fails when placed somewhere without an owner
    FindOwner<public>()<decides><transacts>:player =
        Owner?

    # Current velocity (cm/s, world space)
    GetVelocity<public>()<transacts>:vector3 =
        Velocity

    # Set the velocity (cm/s, world space)
    SetVelocity<public>(NewVelocity:vector3):void =
        set Velocity = NewVelocity

    # Add to the velocity (cm/s. launches, knockback, etc.)
    AddVelocity<public>(Delta:vector3):void =
        set Velocity = Velocity + Delta

    # Succeeds while grounded
    IsGrounded<public>()<decides><transacts>:void =
        Grounded?

    # Succeeds if currently in State
    IsInState<public>(State:character_motor_state)<decides><transacts>:void =
        case (State):
            character_motor_state.Grounded => Grounded?
            character_motor_state.Airborne => not Grounded?
            character_motor_state.Rising => (not Grounded?, Velocity.Up > 0.0)
            character_motor_state.Falling => (not Grounded?, Velocity.Up <= 0.0)
            character_motor_state.Moving => Moving?
            character_motor_state.Still => not Moving?
            character_motor_state.Clinging => ClingSurface?

    # Normal of the ground stood on (upward unit vector). When not grounded, the last ground stood on
    GetGroundNormal<public>()<transacts>:vector3 =
        GroundNormal

    # The object currently stood on (entity of the mesh hit by the ground sweep. For a moving floor, that entity or a child). Fails when not grounded (result of the previous frame's move)
    GetGroundEntity<public>()<decides><transacts>:entity =
        GroundEntity?

    # Velocity of the ground currently carrying the body (cm/s, world space. For a rotating floor, the speed at the feet). Set by SurfaceKit's character_ride_component (0 without it or when not being carried)
    GetGroundVelocity<public>()<transacts>:vector3 =
        GroundVelocity

    # Horizontal velocity inherited when leaving moving ground (jump or walked off the edge) (cm/s. Set by character_ride_component). 0 on landing. walk does not decelerate this part in the air (jumping off a moving floor keeps moving with it)
    GetInheritedVelocity<public>()<transacts>:vector3 =
        InheritedVelocity

    # Called from character_ride_component: sets the velocity of the ground being ridden
    SetGroundVelocity<internal>(Value:vector3)<transacts>:void =
        set GroundVelocity = Value

    # Called from character_ride_component: the body left moving ground, so add its velocity Value to the body's velocity and remember the horizontal part as inherited velocity (until landing)
    InheritVelocity<internal>(Value:vector3)<transacts>:void =
        set Velocity = Velocity + Value
        set InheritedVelocity = vector3{Forward := Value.Forward, Left := Value.Left}
        set GroundVelocity = vector3{}

    # Called from MoveKit: sets the inherited velocity to Value (horizontal part only). walk shrinks it in the air by what input / walls removed (the removed part does not come back). dash clears it (a dash replaces momentum)
    SetInheritedVelocity<internal>(Value:vector3)<transacts>:void =
        set InheritedVelocity = vector3{Forward := Value.Forward, Left := Value.Left}

    # Called from MoveKit's dash: while Value is true, another component (dash) sets the velocity (walk leaves it alone. Dash speed and distance do not depend on the order PreMoveEvent arrives)
    SetMoveOverride<internal>(Value:logic)<transacts>:void =
        set MoveOverridden = Value

    # Succeeds during SetMoveOverride(true) or while clinging to a wall / ceiling (ClingKit sets the velocity) (walk checks every frame)
    #   Cling is tracked separately from dash's SetMoveOverride (when dash ends and sets false, walk still does not overwrite the cling velocity)
    IsMoveOverridden<internal>()<decides><transacts>:void =
        MoveOverridden? or ClingSurface?

    # Succeeds while clinging to a wall or ceiling (decided by ClingKit's character_cling_component. Checked by jump / dash / face / walk)
    IsClinging<public>()<decides><transacts>:void =
        ClingSurface?

    # Kind of surface clung to (Wall / Ceiling). Fails when not clinging
    GetClingSurface<public>()<decides><transacts>:character_cling_surface =
        ClingSurface?

    # Normal of the surface clung to (outward unit vector. For a wall, toward the body; for a ceiling, downward). When not clinging, the last surface clung to (vector3{} if never)
    GetClingNormal<public>()<transacts>:vector3 =
        ClingNormal

    # Called from ClingKit: sets the cling state. Surface false means released (the normal keeps its last value). JumpVelocity is the velocity jump uses at that time (away from the wall; for a ceiling, the falling velocity)
    SetClingState<internal>(Surface:?character_cling_surface, Normal:vector3, JumpVelocity:vector3)<transacts>:void =
        set ClingSurface = Surface
        if (Surface?):
            set ClingNormal = Normal
            set ClingJumpVelocity = JumpVelocity
        else:
            set ClingReleaseRequested = false

    # Called from MoveKit's jump: the velocity to jump with while clinging (ClingKit sets it every frame)
    GetClingJumpVelocity<internal>()<transacts>:vector3 =
        ClingJumpVelocity

    # Called from MoveKit's jump: asks to release the cling (jumped, or dropped from a ceiling). cling releases before or after the next frame's move
    RequestClingRelease<internal>()<transacts>:void =
        if (ClingSurface?):
            set ClingReleaseRequested = true

    # Called from ClingKit: returns true if a release was requested, and clears the request
    TakeClingRelease<internal>()<transacts>:logic =
        Requested := ClingReleaseRequested
        set ClingReleaseRequested = false
        Requested

    # Called from ClingKit: sweeps this capsule by Displacement as if its feet were at Feet (world position) and returns the first hit (excluding self and owner). Fails on a hit touching from the start of the sweep (normal not trustworthy). Does not move the body
    ProbeSurfaceFrom<internal>(Feet:vector3, Displacement:vector3)<decides><transacts>:sweep_hit =
        Hit := FindFirstHitFrom[Feet, Displacement]
        not IsStartHit[Hit]
        Hit

    # Called from ClingKit: sweeps this capsule by Displacement as if its feet were at Feet and succeeds if nothing is hit (including hits touching from the start). Does not move the body
    IsSweepClear<internal>(Feet:vector3, Displacement:vector3)<decides><transacts>:void =
        not FindFirstHitFrom[Feet, Displacement]

    # Called from ClingKit: assuming a sweep from the current position along Direction (unit vector) hit Hit, moves the body to SkinCm away from the surface along its normal (does not move along the AxisLock axis)
    SnapToHit<internal>(Hit:sweep_hit, Direction:vector3)<transacts>:void =
        MoveBy(ApplyLock(Direction * StopDistance(Hit, Direction), 0.0))

    # Called from ClingKit: moves the body by Delta (world, cm) without checking collisions (does not move along the AxisLock axis. Velocity unchanged. Unlike TeleportTo, does not change the locked position or the start-move handling)
    MoveBodyBy<internal>(Delta:vector3)<transacts>:void =
        MoveBy(ApplyLock(Delta, 0.0))

    # Succeeds if Normal is a standable slope (MaxSlopeDegrees or less) (ClingKit uses it to tell cling surfaces from floors)
    IsWalkableNormal<internal>(Normal:vector3)<decides><transacts>:void =
        IsWalkable[Normal]

    # Distance kept from surfaces (cm. ClingKit adds it to its probe distance)
    GetSkinCm<internal>()<transacts>:float =
        SkinCm

    # Called from character_ride_component: carries the body by Delta (world, cm), the amount the ground Ground moved. Velocity unchanged
    #   Vertical: moved as is (undo the floor's rise first so we do not sweep while penetrating the floor). Horizontal: on hitting anything other than Ground, stop short (SkinCm from the surface) and slide the rest along it once (no penetrating walls while carried)
    #   If touching something other than Ground from the start of the sweep (about to penetrate), do not carry horizontally
    #   Does not move along the AxisLock axis
    CarryBy<internal>(Delta:vector3, Ground:entity)<transacts>:void =
        Move := ApplyLock(Delta, 0.0)
        if (Move.Up <> 0.0):
            MoveBy(vector3{Up := Move.Up})
        var Horizontal:vector3 = vector3{Forward := Move.Forward, Left := Move.Left}
        var Iteration:int = 0
        loop:
            HorizontalCm := Horizontal.Length()
            if (Iteration >= 2 or HorizontalCm < 0.01):
                break
            set Iteration += 1
            Feet := Entity.GetGlobalTransform().Translation
            if (Hit := FindFirstHitFromExcept[Feet, Horizontal, option{Ground}]):
                if (IsStartHit[Hit]):
                    break
                Allowed := StopDistance(Hit, Horizontal / HorizontalCm)
                MoveBy(Horizontal * (Allowed / HorizontalCm))
                Rest := Horizontal * (1.0 - Allowed / HorizontalCm)
                set Horizontal = SlideAlong(Rest, Hit.ContactNormal)
                set Horizontal = vector3{Forward := Horizontal.Forward, Left := Horizontal.Left}
            else:
                MoveBy(Horizontal)
                break

    # Called from character_ride_component: probes down from the feet by DistanceCm and returns the entity of a walkable surface if any (does not move the body). Fails if none
    #   Hits touching from the start of the sweep (about to penetrate a side wall; the normal can look straight up) are not ground (do not mistake a wall for the same floor and keep carrying)
    FindGroundEntityBelow<internal>(DistanceCm:float)<decides><transacts>:entity =
        Hit := FindFirstHit[vector3{Up := -(DistanceCm + SkinCm)}]
        not IsStartHit[Hit]
        IsWalkable[Hit.ContactNormal]
        Hit.TargetComponent.Entity

    # Gravity scale (1.0 for GravityCmPerSecondSquared as is. 0 for zero gravity)
    SetGravityScale<public>(Scale:float):void =
        set GravityScale = Scale

    # Current gravity scale
    GetGravityScale<public>()<transacts>:float =
        GravityScale

    # Multiplies this frame's gravity only by Multiplier (0 or more). Call inside PreMoveEvent (reset to 1 before PreMoveEvent every frame, so call every frame to keep it). Repeated calls multiply
    #   Also multiplies with SetGravityScale, stacked GravityMultiplier and FallGravityMultiplier while falling (stays 0 with SetGravityScale(0)). jump's apex hang (ApexGravityMultiplier) uses this
    ScaleGravityThisFrame<public>(Multiplier:float):void =
        set FrameGravityMultiplier *= Max(Multiplier, 0.0)

    # Downward speed at the last landing from the air (cm/s. 0 or more. 0 if never landed). Same value as LandedEvent
    GetLastLandingSpeed<public>()<transacts>:float =
        LastLandingSpeed

    # Moves to Position (feet, world position, cm) without checking collisions. Velocity unchanged
    TeleportTo<public>(Position:vector3):void =
        Current := Entity.GetGlobalTransform()
        Entity.SetGlobalTransform(Current.WithTranslation(Position))
        set LockedValue = LockedComponent(Position)
        set TeleportedSinceBegin = true

    # A component reports something that happened (Jumped, Dashed, ...) (arrives on ActionEvent). Your own movement components can call it too
    ReportAction<public>(Action:character_action):void =
        ActionEventInternal.Signal(Action)

    # Stacks Modifier onto the body's movement. Remove with Cancel on the returned cancelable (does nothing from the second call). To avoid leaks, always Cancel when the component that added it stops
    AddModifier<public>(Modifier:character_modifier)<transacts>:cancelable =
        set NextModifierId += 1
        Id := NextModifierId
        set Modifiers += array{(Id, Modifier)}
        RecomputeModifiers()
        character_modifier_handle{Motor := Self, Id := Id}

    # Number of modifiers currently stacked
    GetModifierCount<public>()<transacts>:int =
        Modifiers.Length

    # Locks input (lobby, result screen, etc.). Remove with Cancel on the returned cancelable (does nothing from the second call). Any number can be stacked; input returns when all are removed (each caller locks and unlocks independently)
    #   While locked: walk treats input (buttons, direction, SetMoveInput) as 0 (velocity brakes with BrakingCmPerSecondSquared) and does not turn even with TankTurn. The side-style toggle button is ignored too
    #   jump does not jump (neither button nor Jump. Presses are discarded, not buffered. Not counted as held, so the apex hang stops too). dash does not dash (a dash in progress ends). face (character_face_movement_component) does not turn the body
    #   Body physics (gravity, sweep, grounding) keep running. To freeze the whole body, also call SetGravityScale(0) and SetVelocity(vector3{})
    LockInput<public>()<transacts>:cancelable =
        set NextInputLockId += 1
        Id := NextInputLockId
        set InputLocks += array{Id}
        character_input_lock_handle{Motor := Self, Id := Id}

    # Succeeds while input is locked by LockInput (walk / jump / dash / face check it every frame. Your own movement components should check it too)
    IsInputLocked<public>()<decides><transacts>:void =
        InputLocks.Length > 0

    # Called from character_input_lock_handle's Cancel: removes the lock with id Id
    UnlockInput<internal>(Id:int)<transacts>:void =
        set InputLocks = for (Each : InputLocks, Each <> Id):
            Each

    # Speed multiplier of the stacked modifiers (product. 1 if none)
    GetSpeedMultiplier<public>()<transacts>:float =
        SpeedMultiplier

    # Jump multiplier of the stacked modifiers (product. 1 if none)
    GetJumpMultiplier<public>()<transacts>:float =
        JumpMultiplier

    # Gravity multiplier of the stacked modifiers (product. 1 if none). Separate from the SetGravityScale factor
    GetGravityMultiplier<public>()<transacts>:float =
        GravityMultiplier

    # Air jumps added by the stacked modifiers (sum. 0 if none)
    GetExtraAirJumps<public>()<transacts>:int =
        ExtraAirJumps

    # Succeeds if at least one stacked modifier grants dash (GrantsDash)
    IsDashGranted<public>()<decides><transacts>:void =
        DashGrants > 0

    # Succeeds if at least one stacked modifier grants cling (GrantsCling) (if ClingKit's character_cling_component has RequiresGrant on, clinging is possible only while this holds)
    CanCling<public>()<decides><transacts>:void =
        ClingGrants > 0

    # Side-input style decided by the stacked modifiers (the last one added that has a SideStyle). Fails if none (walk uses its own base value)
    GetSideStyleOverride<public>()<decides><transacts>:character_side_style =
        SideStyleOverride?

    # Called from character_modifier_handle's Cancel: removes the modifier with id Id
    RemoveModifier<internal>(Id:int)<transacts>:void =
        set Modifiers = for (Entry : Modifiers, Entry(0) <> Id):
            Entry
        RecomputeModifiers()

    RecomputeModifiers<private>()<transacts>:void =
        var Speed:float = 1.0
        var Jump:float = 1.0
        var Gravity:float = 1.0
        var AirJumps:int = 0
        var Dash:int = 0
        var Cling:int = 0
        var Side:?character_side_style = false
        # Modifiers are in insertion order, so a later SideStyle overwrites (the last one added wins)
        for (Entry : Modifiers):
            Modifier := Entry(1)
            set Speed *= Modifier.SpeedMultiplier
            set Jump *= Modifier.JumpMultiplier
            set Gravity *= Modifier.GravityMultiplier
            set AirJumps += Modifier.ExtraAirJumps
            if (Modifier.GrantsDash?):
                set Dash += 1
            if (Modifier.GrantsCling?):
                set Cling += 1
            if (Style := Modifier.SideStyle?):
                set Side = option{Style}
        set SpeedMultiplier = Speed
        set JumpMultiplier = Jump
        set GravityMultiplier = Gravity
        set ExtraAirJumps = AirJumps
        set DashGrants = Dash
        set ClingGrants = Cling
        set SideStyleOverride = Side

    # Round start: clear velocity and move to the owner's character (respawned at the spawn point)
    OnRoundStarted<private>()<suspends>:void =
        set Velocity = vector3{}
        set InheritedVelocity = vector3{}
        if (Player := Owner?, Body := Player.FindPlayerEntity[]):
            TeleportTo(Body.GetGlobalTransform().Translation)

    OnRoundEnded<private>():void =
        set Velocity = vector3{}

    OnTick<private>(DeltaTime:float):void =
        if (DeltaTime <= 0.0):
            return
        set FrameIndex += 1
        # This frame's gravity factor is decided inside the following PreMoveEvent (leftovers from the previous frame are not used)
        set FrameGravityMultiplier = 1.0
        PreMoveEventInternal.Signal(DeltaTime)
        set Velocity = ApplyLock(Velocity, 0.0)
        ApplyGravity(DeltaTime)
        MoveWithCollision(Velocity * DeltaTime)
        if (AxisLock <> character_axis_lock.None):
            Current := Entity.GetGlobalTransform()
            Entity.SetGlobalTransform(Current.WithTranslation(ApplyLock(Current.Translation, LockedValue)))
        UpdateGround()
        UpdateMoving()
        PostMoveEventInternal.Signal(DeltaTime)

    # Adds gravity only in the air or when leaving the ground (jump, launch). Not while moving along the ground (up or down a slope)
    ApplyGravity<private>(DeltaTime:float):void =
        if (not Grounded? or IsLeavingGround[]):
            # Multiply by FallGravityMultiplier while falling (fall faster). Everything is 0 with SetGravityScale(0)
            Shape := if (Velocity.Up < 0.0) then FallGravityMultiplier else 1.0
            Acceleration := GravityCmPerSecondSquared * GravityScale * GravityMultiplier * FrameGravityMultiplier * Shape
            Fall := Max(Velocity.Up - Acceleration * DeltaTime, -MaxFallSpeedCmPerSecond)
            set Velocity = vector3{Forward := Velocity.Forward, Left := Velocity.Left, Up := Fall}

    # Succeeds if grounded and the speed away from the ground exceeds GroundStickSpeedCmPerSecond (about to leave the ground by a jump or launch)
    IsLeavingGround<private>()<decides><transacts>:void =
        Grounded?
        DotProduct(Velocity, GroundNormal) > GroundStickSpeedCmPerSecond

    # Moves by Displacement. On hit, stops SkinCm from the surface, slides the rest along it and tries again (up to MaxSlideIterations). Velocity into the surface is removed (for a wall, only the horizontal part)
    #   Before sliding, tries corner correction (head grazed a ceiling corner) and step correction (feet hit a step corner). If a correction works, velocity is unchanged
    #   Rules against sticking to walls (UEFN v43.00: jumping or falling while pressed against a wall stopped halfway up the wall and got stuck):
    #     1. The stop distance is SkinCm along the surface normal (StopDistance). Backing off SkinCm along the sweep direction let the gap shrink to 0 on every shallow approach to a wall
    #     2. Hits touching from the start of the sweep (distance 0) return a normal that is the reverse of the sweep (straight up when falling); mistaken for floor / ceiling, they removed vertical motion and velocity.
    #        Push out without using the normal and sweep again (TryDepenetrate); if pushing out fails, ignore that object for this frame
    #     3. Walls (non-walkable surfaces that are not ceilings) do not change vertical motion (SlideAlong, ClipVelocity). Removing along the normal used to shave vertical speed on slightly tilted walls and ledge corners
    #     4. Step correction only while grounded (in the air, LedgeAssistCm). Corner correction only for ceilings (downward-facing surfaces)
    MoveWithCollision<private>(Displacement:vector3):void =
        var Remaining:vector3 = Displacement
        # Object ignored in this frame's sweeps (could not be pushed out of, or only grazed)
        var Skip:?entity = false
        var Iteration:int = 0
        loop:
            if (Iteration >= MaxSlideIterations or Remaining.LengthSquared() < 0.0001):
                break
            set Iteration += 1
            Feet := Entity.GetGlobalTransform().Translation
            if (Hit := FindFirstHitFromExcept[Feet, Remaining, Skip]):
                if (IsStartHit[Hit]):
                    # About to penetrate: if pushed out, sweep the same move again from there. If not, ignore the object and keep moving (do not stop)
                    Pushed := TryDepenetrate(Hit, Remaining)
                    if (not Pushed?):
                        set Skip = option{Hit.TargetComponent.Entity}
                else:
                    Direction := Remaining / Remaining.Length()
                    Normal := Hit.ContactNormal
                    Allowed := StopDistance(Hit, Direction)
                    MoveBy(Direction * Allowed)
                    Rest := Remaining - Direction * Allowed
                    if (DotProduct(Direction, Normal) > -0.001):
                        # Only grazed a surface not facing the motion: do not stop, move the rest as is (ignore the object for this frame)
                        set Remaining = Rest
                        set Skip = option{Hit.TargetComponent.Entity}
                    else if (TryCornerCorrection(Hit, Rest)?):
                        # Shifted sideways, so continue the remaining motion as is
                        set Remaining = Rest
                    else if (TryStepUp(Hit, Rest)?):
                        # Climbed onto the step (the remaining horizontal motion is used up)
                        break
                    else:
                        set Remaining = SlideAlong(Rest, Normal)
                        ClipVelocity(Normal)
            else:
                MoveBy(Remaining)
                break

    # Succeeds if Hit's distance is StartHitCm or less (touching from the start of the sweep, about to penetrate)
    IsStartHit<private>(Hit:sweep_hit)<decides><transacts>:void =
        Hit.SourceHitDistance <= StartHitCm

    # Succeeds if Normal is a wall (non-walkable surface that is not a ceiling). Walls do not change vertical motion
    IsWallNormal<private>(Normal:vector3)<decides><transacts>:void =
        not IsWalkable[Normal]
        Normal.Up > CeilingNormalUp

    # Distance (cm) allowed when moving along Direction (unit vector) and hitting Hit. Up to where the gap measured along the surface normal becomes SkinCm (0 to the hit distance)
    #   Only backing off SkinCm along the sweep direction lets the gap shrink to SkinCm x angle on every shallow approach (falling or jumping along a wall), reaching 0 within a few frames
    StopDistance<private>(Hit:sweep_hit, Direction:vector3)<transacts>:float =
        HitCm := Hit.SourceHitDistance
        Approach := -DotProduct(Direction, Hit.ContactNormal)
        if (Approach > 0.001) then Clamp(HitCm - SkinCm / Approach, 0.0, HitCm) else Max(HitCm - SkinCm, 0.0)

    # Slides the remaining motion Rest along the surface hit (normal Normal). Removes only the part heading into the surface (motion away from it is kept)
    #   Floors / slopes (walkable) and ceilings: remove the component along the normal (landing or bumping the head stops vertical motion)
    #   Walls: vertical motion is kept; only the horizontal part is shifted outward to follow the surface (a wall does not stop falling or jumping along it. Vertical motion is not shaved on slightly tilted walls or ledge corners either)
    SlideAlong<private>(Rest:vector3, Normal:vector3)<transacts>:vector3 =
        Into := DotProduct(Rest, Normal)
        if (Into >= 0.0):
            return Rest
        if (IsWallNormal[Normal]):
            Flat := vector3{Forward := Normal.Forward, Left := Normal.Left}
            FlatSquared := Flat.LengthSquared()
            if (FlatSquared > 0.000001):
                # Zero the normal component of Rest + Flat x k (k = -Into / |Flat|^2). The vertical component is unchanged
                return Rest + Flat * (-Into / FlatSquared)
        Rest - Normal * Into

    # Removes velocity into the surface hit (normal Normal). For a wall, only the horizontal part into it (vertical speed unchanged) and remembers the wall's outward direction (used to push out of penetration)
    #   Reports HitWall when velocity into a non-walkable surface (wall or ceiling) was removed
    ClipVelocity<private>(Normal:vector3):void =
        if (IsWallNormal[Normal]):
            Flat := vector3{Forward := Normal.Forward, Left := Normal.Left}
            FlatCm := Flat.Length()
            if (FlatCm > 0.001):
                Away := Flat / FlatCm
                set LastWallNormal = Away
                set LastWallFrame = FrameIndex
                Into := DotProduct(Velocity, Away)
                if (Into < 0.0):
                    set Velocity = Velocity - Away * Into
                    ReportAction(character_action.HitWall)
        else:
            Into := DotProduct(Velocity, Normal)
            if (Into < 0.0):
                set Velocity = Velocity - Normal * Into
                if (not IsWalkable[Normal]):
                    ReportAction(character_action.HitWall)

    # When touching Hit from the start of the sweep (about to penetrate), tries push-out directions in order and succeeds (true) if the body can move to a free spot (touching nothing). If not, the body is not moved
    #   Directions tried: the normal physics returned (unless it is exactly the reverse of the sweep = untrustworthy) -> outward direction of the last wall touched -> reverse of the horizontal motion Motion -> reverse of the horizontal velocity -> straight up (floor) -> straight down (ceiling). Each at two distances, SkinCm + 0.5 and SkinCm x 4
    TryDepenetrate<private>(Hit:sweep_hit, Motion:vector3)<transacts>:logic =
        Feet := Entity.GetGlobalTransform().Translation
        MotionCm := Motion.Length()
        Direction := if (MotionCm > 0.0001) then Motion / MotionCm else vector3{}
        Normal := Hit.ContactNormal
        var Candidates:[]vector3 = array{}
        if (DotProduct(Normal, Direction) > -0.99):
            set Candidates += array{Normal}
        if (FrameIndex - LastWallFrame <= WallMemoryFrames):
            set Candidates += array{LastWallNormal}
        set Candidates += array{vector3{Forward := -Motion.Forward, Left := -Motion.Left}, vector3{Forward := -Velocity.Forward, Left := -Velocity.Left}, vector3{Up := 1.0}, vector3{Up := -1.0}}
        var Pushed:logic = false
        for (Candidate : Candidates, Step : array{SkinCm + 0.5, SkinCm * 4.0}, not Pushed?):
            Free := ApplyLock(Candidate, 0.0)
            FreeCm := Free.Length()
            if (FreeCm > 0.001):
                Away := Free / FreeCm
                if (IsFreeAt(Feet + Away * Step, Away)?):
                    MoveBy(Away * Step)
                    set Pushed = true
        Pushed

    # true if nothing is touched with the feet at Feet (sweeps SkinCm opposite to Away and checks for a hit touching from the start)
    IsFreeAt<private>(Feet:vector3, Away:vector3)<transacts>:logic =
        if (Hit := FindFirstHitFrom[Feet, Away * (-SkinCm)], IsStartHit[Hit]) then false else true

    # Corner correction: if, while rising, the head (upper hemisphere) only grazed the corner of a ceiling (a surface whose normal is below CeilingNormalUp), shifts sideways by up to CornerCorrectionCm and succeeds (true)
    #   Not used for walls (near-vertical surfaces): SlideAlong follows walls without changing vertical motion, so no shift is needed (it used to shift sideways on grazing a wall)
    #   If the corner position (ContactPosition) is offset sideways from the head center, shift the opposite way by just enough to clear it
    #   When a flat ceiling surface was hit (no offset), try the horizontal motion direction (with AxisLock, both directions of the free axis), nearest first
    TryCornerCorrection<private>(Hit:sweep_hit, Rest:vector3)<transacts>:logic =
        if (CornerCorrectionCm <= 0.0 or Rest.Up <= 0.0 or Hit.ContactNormal.Up > CeilingNormalUp):
            return false
        Feet := Entity.GetGlobalTransform().Translation
        HeadCenter := Feet + vector3{Up := Max(HeightCm - RadiusCm, RadiusCm)}
        Contact := Hit.ContactPosition
        if (Contact.Up < HeadCenter.Up):
            return false
        Rise := vector3{Up := Max(Rest.Up, SkinCm)}
        Away := ApplyLock(vector3{Forward := HeadCenter.Forward - Contact.Forward, Left := HeadCenter.Left - Contact.Left}, 0.0)
        AwayCm := Away.Length()
        if (AwayCm >= 0.5):
            # The corner is to the side: shift until it is cleared (horizontal distance between head center and corner becomes radius + SkinCm)
            Need := RadiusCm + SkinCm - AwayCm + 0.5
            if (Need > 0.0, Need <= CornerCorrectionCm):
                return TryNudge(Feet, Away * (Need / AwayCm), Rise)
            return false
        var Nudged:logic = false
        for (Side : GetCornerSides(), Index := 1..CornerCorrectionSteps, not Nudged?):
            if (TryNudge(Feet, Side * (CornerCorrectionCm * (Index * 1.0) / (CornerCorrectionSteps * 1.0)), Rise)?):
                set Nudged = true
        Nudged

    # Directions (horizontal unit vectors) to try shifting when a flat ceiling was hit. With AxisLock, both directions of the free axis; otherwise the horizontal motion direction and its reverse (nothing if not moving sideways)
    GetCornerSides<private>()<transacts>:[]vector3 =
        Horizontal := vector3{Forward := Velocity.Forward, Left := Velocity.Left}
        HorizontalCm := Horizontal.Length()
        Moving2D := if (HorizontalCm > 1.0) then array{Horizontal / HorizontalCm, Horizontal * (-1.0 / HorizontalCm)} else array{}
        case (AxisLock):
            character_axis_lock.Left => array{vector3{Forward := 1.0}, vector3{Forward := -1.0}}
            character_axis_lock.Forward => array{vector3{Left := 1.0}, vector3{Left := -1.0}}
            character_axis_lock.None => Moving2D

    # If the body can shift sideways from Feet by Nudge and the space above there is clear by Rise, shifts and succeeds (true)
    TryNudge<private>(Feet:vector3, Nudge:vector3, Rise:vector3)<transacts>:logic =
        if (FindFirstHitFrom[Feet, Nudge]):
            return false
        if (FindFirstHitFrom[Feet + Nudge, Rise]):
            return false
        MoveBy(Nudge)
        true

    # Step correction: if grounded (not about to leave by a jump), moving horizontally, and the feet hit the corner of a step of StepUpCm or less, climbs onto the step and succeeds (true)
    #   In the air, only ledges of LedgeAssistCm or less while falling (default 0, unused). No climbing onto walls while falling or jumping along them
    #   Checks three things before moving: the space above is clear -> the space ahead from the lifted position is clear -> there is a walkable surface below (if any fails, do nothing = slide as usual)
    #   To avoid sliding off the corner, advances to where the corner touches at a walkable angle (horizontal distance between body axis and corner below radius x sin(MaxSlopeDegrees)) (so it may move further than this frame's motion)
    TryStepUp<private>(Hit:sweep_hit, Rest:vector3)<transacts>:logic =
        OnGround := if (Grounded?, not IsLeavingGround[]) then true else false
        Limit := if (OnGround?) then StepUpCm else if (Velocity.Up <= 0.0) then LedgeAssistCm else 0.0
        if (Limit <= 0.0):
            return false
        Normal := Hit.ContactNormal
        if (IsWalkable[Normal] or Normal.Up < -0.1):
            return false
        Horizontal := vector3{Forward := Rest.Forward, Left := Rest.Left}
        HorizontalCm := Horizontal.Length()
        if (HorizontalCm < 0.01):
            return false
        # No correction unless the horizontal motion heads into the corner (just moving up / down along a wall)
        if (DotProduct(Horizontal, vector3{Forward := Normal.Forward, Left := Normal.Left}) >= 0.0):
            return false
        Feet := Entity.GetGlobalTransform().Translation
        Contact := Hit.ContactPosition
        StepCm := Contact.Up - Feet.Up
        if (StepCm <= 0.0 or StepCm > Limit):
            return false
        Ahead := Horizontal / HorizontalCm
        ToContact := DotProduct(vector3{Forward := Contact.Forward - Feet.Forward, Left := Contact.Left - Feet.Left}, Ahead)
        if (ToContact <= 0.0):
            return false
        SlopeCos := Cos(MaxSlopeDegrees * PiFloat / 180.0)
        Reach := RadiusCm * Sqrt(Max(1.0 - SlopeCos * SlopeCos, 0.0)) - 1.0
        AdvanceCm := Max(HorizontalCm, ToContact - Reach)
        if (AdvanceCm > RadiusCm + SkinCm):
            return false
        Lift := vector3{Up := StepCm + SkinCm}
        Push := Ahead * AdvanceCm
        if (FindFirstHitFrom[Feet, Lift]):
            return false
        if (FindFirstHitFrom[Feet + Lift, Push]):
            return false
        if (Down := FindFirstHitFrom[Feet + Lift + Push, vector3{Up := -(Lift.Up + SkinCm)}], IsWalkable[Down.ContactNormal]):
            MoveBy(Lift + Push + vector3{Up := -Max(Down.SourceHitDistance - SkinCm, 0.0)})
            return true
        false

    # Probes down from the feet and, if a walkable surface is found, snaps to it and becomes grounded
    #   A grounded body: while moving along the ground (not IsLeavingGround), probes by GroundSnapCm (GroundProbeCm if smaller). No floating when going down slopes or low steps
    #   An airborne body: probes by GroundProbeCm only while falling (vertical speed 0 or less)
    #   On grounding, aligns velocity with the ground (horizontal speed kept, vertical speed matched to the slope. 0 vertical speed on flat ground). The entity hit becomes the object stood on (GetGroundEntity)
    #   On grounding from the air, clears the velocity inherited from moving ground (GetInheritedVelocity)
    #   Hits touching from the start of the sweep (about to penetrate a side wall) are not ground (FindGroundHit. Do not mistake a wall for a floor and stand halfway up it without gravity)
    #   No probing while clinging to a wall / ceiling and rising (ClingKit) (starting to climb from the foot of a wall slower than GroundStickSpeedCmPerSecond must not snap to the floor and lose vertical speed)
    UpdateGround<private>():void =
        WasGrounded := Grounded
        var NowGrounded:logic = false
        var NowGround:?entity = false
        Climbing := if (ClingSurface?, Velocity.Up > 0.0) then true else false
        Probing := if (Climbing?) then false else if (WasGrounded?) then (if (IsLeavingGround[]) then false else true) else (if (Velocity.Up <= 0.0) then true else false)
        ProbeCm := if (WasGrounded?) then Max(GroundProbeCm, GroundSnapCm) else GroundProbeCm
        MaybeHit:?sweep_hit = if (Probing?) then FindGroundHit(ProbeCm) else false
        if (Hit := MaybeHit?, IsWalkable[Hit.ContactNormal]):
            set NowGrounded = true
            set NowGround = option{Hit.TargetComponent.Entity}
            set GroundNormal = Hit.ContactNormal
            MoveBy(vector3{Up := -Max(Hit.SourceHitDistance - SkinCm, 0.0)})
            if (not WasGrounded?):
                set LastLandingSpeed = Max(-Velocity.Up, 0.0)
                set InheritedVelocity = vector3{}
            set Velocity = AlongGround(Velocity, Hit.ContactNormal)
        set Grounded = NowGrounded
        set GroundEntity = NowGround
        if (WasGrounded? and not NowGrounded?):
            ReportAction(character_action.LeftGround)
        else if (not WasGrounded? and NowGrounded?):
            ReportAction(character_action.Landed)
            LandedEventInternal.Signal(LastLandingSpeed)

    # Probes down from the feet by DistanceCm (+ SkinCm) and returns the first hit. false if none
    #   Hits touching from the start of the sweep are not used: if pushed out, probe again from there; if not, probe again excluding that object (finds the real floor below it, if any)
    FindGroundHit<private>(DistanceCm:float)<transacts>:?sweep_hit =
        Down := vector3{Up := -(DistanceCm + SkinCm)}
        if (First := FindFirstHit[Down]):
            if (not IsStartHit[First]):
                return option{First}
            Pushed := TryDepenetrate(First, Down)
            Except:?entity = if (Pushed?) then false else option{First.TargetComponent.Entity}
            if (Again := FindFirstHitFromExcept[Entity.GetGlobalTransform().Translation, Down, Except], not IsStartHit[Again]):
                return option{Again}
        false

    UpdateMoving<private>():void =
        Horizontal := vector3{Forward := Velocity.Forward, Left := Velocity.Left}
        NowMoving := if (Horizontal.Length() > MovingSpeedCmPerSecond) then true else false
        if (NowMoving <> Moving):
            set Moving = NowMoving
            ReportAction(if (NowMoving?) then character_action.StartedMoving else character_action.StoppedMoving)

    # Succeeds if Normal is a standable slope (MaxSlopeDegrees or less)
    IsWalkable<private>(Normal:vector3)<decides><transacts>:void =
        Normal.Up >= Cos(MaxSlopeDegrees * PiFloat / 180.0)

    # Sweeps this capsule from the current position by Displacement and returns the first hit (excluding self and the owner's Fortnite character). Fails if nothing is hit
    FindFirstHit<private>(Displacement:vector3)<decides><transacts>:sweep_hit =
        FindFirstHitFrom[Entity.GetGlobalTransform().Translation, Displacement]

    # Sweeps this capsule by Displacement as if its feet were at Feet (world position) and returns the first hit. Fails if nothing is hit (does not move the body. Used to look ahead for corner / step correction)
    FindFirstHitFrom<private>(Feet:vector3, Displacement:vector3)<decides><transacts>:sweep_hit =
        FindFirstHitFromExcept[Feet, Displacement, false]

    # Same as FindFirstHitFrom, also excluding hits on the Except entity (when carried by a moving floor, that floor is not hit)
    FindFirstHitFromExcept<private>(Feet:vector3, Displacement:vector3, Except:?entity)<decides><transacts>:sweep_hit =
        Capsule := collision_capsule{}
        set Capsule.Radius = RadiusCm
        set Capsule.Length = Max(HeightCm - RadiusCm * 2.0, 0.0)
        Center := Feet + vector3{Up := HeightCm / 2.0}
        var Found:?sweep_hit = false
        for (Hit : Entity.FindSweepHits(Displacement, MakeTranslationTransform(Center), Capsule), not Found?, not IsIgnored[Hit.TargetComponent.Entity], not IsOptionEntity[Hit.TargetComponent.Entity, Except]):
            set Found = option{Hit}
        Found?

    # Succeeds if Other is self (this entity or a descendant) or the owner's Fortnite character
    IsIgnored<private>(Other:entity)<decides><transacts>:void =
        var Current:?entity = option{Other}
        var Ignored:logic = false
        if (Player := Owner?, Body := Player.FindPlayerEntity[], Body = Other):
            set Ignored = true
        loop:
            if (Ignored?):
                break
            if (Candidate := Current?):
                if (Candidate = Entity):
                    set Ignored = true
                else:
                    set Current = if (Parent := Candidate.GetParent[]) then option{Parent} else false
            else:
                break
        Ignored?

    # Value of the axis locked by AxisLock
    LockedComponent<private>(V:vector3)<transacts>:float =
        case (AxisLock):
            character_axis_lock.Left => V.Left
            character_axis_lock.Forward => V.Forward
            character_axis_lock.None => 0.0

    # Sets the locked axis of V to Value (V as is if not locked)
    ApplyLock<private>(V:vector3, Value:float)<transacts>:vector3 =
        case (AxisLock):
            character_axis_lock.Left => vector3{Forward := V.Forward, Left := Value, Up := V.Up}
            character_axis_lock.Forward => vector3{Forward := Value, Left := V.Left, Up := V.Up}
            character_axis_lock.None => V

    MoveBy<private>(Delta:vector3)<transacts>:void =
        Current := Entity.GetGlobalTransform()
        Entity.SetGlobalTransform(Current.WithTranslation(Current.Translation + Delta))

# Role: the cancelable returned by character_motor_component.AddModifier, for removing the modifier (runtime only)
character_modifier_handle<internal> := class<internal>(cancelable):
    Motor<internal>:character_motor_component
    Id<internal>:int
    var<private> Canceled:logic = false

    Cancel<override>()<transacts>:void =
        if (not Canceled?):
            set Canceled = true
            Motor.RemoveModifier(Id)

# Role: the cancelable returned by character_motor_component.LockInput, for removing the input lock (runtime only)
character_input_lock_handle<internal> := class<internal>(cancelable):
    Motor<internal>:character_motor_component
    Id<internal>:int
    var<private> Canceled:logic = false

    Cancel<override>()<transacts>:void =
        if (not Canceled?):
            set Canceled = true
            Motor.UnlockInput(Id)

# Succeeds if Candidate is the same entity as the content of Maybe (fails if Maybe is false)
IsOptionEntity<internal>(Candidate:entity, Maybe:?entity)<decides><transacts>:void =
    Other := Maybe?
    Other = Candidate

# Removes the component of V along Normal (follow the surface)
RemoveComponent<internal>(V:vector3, Normal:vector3)<reads>:vector3 =
    V - Normal * DotProduct(V, Normal)

# Aligns V with the ground (direction Normal, upward): horizontal speed kept, vertical speed matched to the slope (dot product of V and Normal becomes 0). If Normal is nearly horizontal, vertical speed becomes 0
AlongGround<internal>(V:vector3, Normal:vector3)<reads>:vector3 =
    UpValue := if (Normal.Up > 0.01) then -(V.Forward * Normal.Forward + V.Left * Normal.Left) / Normal.Up else 0.0
    vector3{Forward := V.Forward, Left := V.Left, Up := UpValue}

# 1.0 if the yaw of MakeRotationFromYawPitchRollDegrees turns left, -1.0 if it turns right (checked by the Left of the forward axis rotated 90 degrees)
#   ArcTan(Left, Forward) is "positive when turning left", so multiply by this when passing an angle as yaw (UEFN v43.00: positive yaw turns right)
#   Used by both BodyKit (facing) and MoveKit (walk's TankTurn), so it lives directly under CharacterSystem
YawSign<internal>()<reads>:float =
    if (MakeRotationFromYawPitchRollDegrees(90.0, 0.0, 0.0).GetForwardAxis().Left >= 0.0) then 1.0 else -1.0
