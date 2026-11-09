using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Fortnite.com/Input }
using { InputSystem }
using { CharacterSystem }
using { CharacterSystem.CellKit }
using { CharacterSystem.TooltipKit }

# Role: jump on input. Pressing JumpAction sets the upward speed to JumpSpeedCmPerSecond
#   Coyote time: for CoyoteSeconds after walking off the ground, you can still jump as if grounded (not after leaving by your own jump)
#   Input buffering: a jump pressed up to BufferSeconds before landing jumps at the moment of landing (even at 0, presses since the previous frame are used)
#   Air jumps: up to AirJumps jumps in the air (restored on landing). ExtraAirJumps of the modifiers on the body is added (gained in the air, the extra jumps are usable right away)
#     Order on press: ground (including coyote time) -> remaining air jumps -> otherwise remembered as a buffered input. At most one jump per frame (the same press is never used twice)
#   Height control: releasing while rising after a jump multiplies the upward speed by ReleaseCutRatio (a short press jumps lower. 1 leaves it unchanged. Once per jump, not after starting to fall)
#   Apex hang: while held after a jump and the vertical speed is below ApexSpeedThresholdCmPerSecond, gravity is scaled by ApexGravityMultiplier (the body's ScaleGravityThisFrame. Takes precedence over the body's FallGravityMultiplier)
#   The jump speed is multiplied by JumpMultiplier of the modifiers on the body (BuffKit)
#   No jump while input is locked by the body's LockInput (presses are discarded. Not counted as held)
#   Action cells (CellKit's character_action_cell_component on the same entity): once AirJumps are used up, air-jumps with the cells' AirJump (one cell per jump)
#     Wall kick: in the air, if the cells' WallKick is usable and a wall (non-walkable, nearly vertical surface) is within WallKickReachCm, kicks the wall before air-jumping (away from the wall x WallKickAwaySpeedCmPerSecond, up x WallKickUpSpeedCmPerSecond. Reports WallKicked. One cell per kick)
#   While clinging to a wall / ceiling (ClingKit's character_cling_component. The body's IsClinging), jumps off the cling before anything else: on a wall, jumps away from the wall (Jumped. Speed from cling's WallJumpAwaySpeedCmPerSecond / WallJumpUpSpeedCmPerSecond); on a ceiling, lets go and falls (no Jumped)
#     Air jumps are restored while clinging (you can still air-jump after jumping off a wall). Coyote time is not used
# Placement: in the editor, attach to the same entity as character_motor_component
# Notifications: Jumped (AirJumped in the air) on character_motor_component's ActionEvent when jumping
# From outside: Jump (jump without input. true if it jumped. Counted as held until ReleaseJump is called or the body lands), ReleaseJump (release the jump from code)
# Requirements / notes: when a buffered input jumps at the moment of landing and the button is already released, height control applies immediately (short press = low jump)
character_jump_component<public> := class<final_super>(component):

    # Jump button. Default Character.Jump (part of Fortnite's TraversalMapping)
    @editable:
        ToolTip := JumpActionToolTip
        Categories := array{CharacterJumpCategory}
    JumpAction<public>:input_action(logic) = Character.Jump
    # Upward speed at the moment of jumping (cm/s). Default 900
    @editable_number(float):
        ToolTip := JumpSpeedToolTip
        Categories := array{CharacterJumpCategory}
        MinValue := option{0.0}
        MaxValue := option{20000.0}
    JumpSpeedCmPerSecond<public>:float = 900.0
    # Number of jumps in the air (1 for a double jump). Default 0
    @editable_number(int):
        ToolTip := JumpAirJumpsToolTip
        Categories := array{CharacterJumpCategory}
        MinValue := option{0}
        MaxValue := option{10}
    AirJumps<public>:int = 0
    # Time after walking off the ground during which a jump still counts as a ground jump (seconds). 0 disables. Default 0.12
    @editable_number(float):
        ToolTip := JumpCoyoteToolTip
        Categories := array{CharacterJumpCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    CoyoteSeconds<public>:float = 0.12
    # Time to remember a jump pressed before landing (seconds). 0 disables. Default 0.12
    @editable_number(float):
        ToolTip := JumpBufferToolTip
        Categories := array{CharacterJumpCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    BufferSeconds<public>:float = 0.12
    # Wall kick (the action cells' WallKick): when jump is pressed in the air, looks for a wall within this distance (cm). Default 35
    @editable_number(float):
        ToolTip := JumpWallKickReachToolTip
        Categories := array{CharacterJumpCategory}
        MinValue := option{1.0}
        MaxValue := option{500.0}
    WallKickReachCm<public>:float = 35.0
    # Wall kick: speed away from the wall (cm/s). Default 750
    @editable_number(float):
        ToolTip := JumpWallKickAwayToolTip
        Categories := array{CharacterJumpCategory}
        MinValue := option{0.0}
        MaxValue := option{20000.0}
    WallKickAwaySpeedCmPerSecond<public>:float = 750.0
    # Wall kick: upward speed (cm/s. The modifiers' jump multiplier also applies). Default 950
    @editable_number(float):
        ToolTip := JumpWallKickUpToolTip
        Categories := array{CharacterJumpCategory}
        MinValue := option{0.0}
        MaxValue := option{20000.0}
    WallKickUpSpeedCmPerSecond<public>:float = 950.0
    # Multiplier on the upward speed when released while rising (1 leaves it unchanged). Default 0.5
    @editable_number(float):
        ToolTip := JumpReleaseCutToolTip
        Categories := array{CharacterJumpCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    ReleaseCutRatio<public>:float = 0.5
    # Apex hang: while held after a jump, gravity is weakened while the vertical speed (absolute) is below this (cm/s). 0 disables. Default 150
    @editable_number(float):
        ToolTip := JumpApexSpeedToolTip
        Categories := array{CharacterJumpCategory}
        MinValue := option{0.0}
        MaxValue := option{5000.0}
    ApexSpeedThresholdCmPerSecond<public>:float = 150.0
    # Multiplier on gravity during the apex hang (replaces the body's FallGravityMultiplier). 1 does not weaken. Default 0.5
    @editable_number(float):
        ToolTip := JumpApexGravityToolTip
        Categories := array{CharacterJumpCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    ApexGravityMultiplier<public>:float = 0.5

    var<private> Motor:?character_motor_component = false
    var<private> Subscriptions:[]cancelable = array{}
    Button<private>:character_button_tracker = character_button_tracker{}
    var<private> AirJumpsLeft:int = 0
    var<private> SecondsSinceGrounded:float = 1000.0
    # Whether height control has already been applied (or disabled) for this jump. Set to false only at the moment of jumping
    var<private> CutApplied:logic = true
    # Extra air jumps read from the body on the previous frame
    var<private> LastExtraAirJumps:int = 0
    # true from jumping until landing (the apex hang works only then)
    var<private> InJump:logic = false
    # Jumped by Jump from code and neither ReleaseJump nor landing has happened yet (counted as held)
    var<private> HeldByCode:logic = false
    # Counter incremented every OnPreMove, and its value at the last jump (no two jumps in one frame)
    var<private> FrameIndex:int = 0
    var<private> LaunchFrame:int = -1

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := Entity.FindCharacterMotorAbove[]):
            set Motor = option{Found}
            set Subscriptions += array{Found.PreMoveEvent.Subscribe(OnPreMove)}
        else:
            Print("[character_jump_component] character_motor_component not found (place it on the same entity or an ancestor)")

    OnSimulate<override>()<suspends>:void =
        if (Found := Motor?, Owner := Found.FindOwner[]):
            MaybeInput := Owner.AwaitPlayerInput()
            if (PlayerInput := MaybeInput?):
                set Subscriptions += Button.Listen(PlayerInput, JumpAction)

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        (super:)OnEndSimulation()

    # Jumps without input (uses ground, coyote time, then remaining air jumps). false if it cannot jump (also while locked by the body's LockInput, or if it already jumped this frame)
    #   After jumping, counted as held until ReleaseJump is called or the body lands (no height control, the apex hang works). A touch UI, for example, calls Jump on press and ReleaseJump on release
    Jump<public>():logic =
        Jumped := TryJump()
        if (Jumped?):
            set HeldByCode = true
        Jumped

    # Releases the jump from code (only meaningful after jumping with Jump). Before the next frame's move, applies height control if still rising
    ReleaseJump<public>():void =
        set HeldByCode = false

    TryJump<private>():logic =
        if (Found := Motor?, not Found.IsInputLocked[], LaunchFrame <> FrameIndex):
            # While clinging to a wall / ceiling (ClingKit), jump off the cling first (uses neither ground nor air jump count)
            if (Surface := Found.GetClingSurface[]):
                ClingJump(Found, Surface)
                return true
            if (IsOnGround[Found] or SecondsSinceGrounded <= CoyoteSeconds):
                # Ground jump (including coyote time). Air jumps are not consumed. Coyote time is used up by this jump
                set SecondsSinceGrounded = 1000.0
                Launch(Found, character_action.Jumped)
                return true
            # In the air: wall kick (cell) -> remaining air jumps -> air jump with a cell, in that order
            MaybeCells:?character_action_cell_component = if (FoundCells := Entity.GetComponent[character_action_cell_component]) then option{FoundCells} else false
            if (Cells := MaybeCells?, Cells.CanUse[character_cell_action.WallKick], WallNormal := FindKickWall[Found]):
                Spent := Cells.TrySpend(character_cell_action.WallKick)
                if (Spent?):
                    WallKick(Found, WallNormal)
                    return true
            if (AirJumpsLeft > 0):
                set AirJumpsLeft -= 1
                Launch(Found, character_action.AirJumped)
                return true
            if (Cells := MaybeCells?, Cells.CanUse[character_cell_action.AirJump]):
                Spent := Cells.TrySpend(character_cell_action.AirJump)
                if (Spent?):
                    Launch(Found, character_action.AirJumped)
                    return true
        false

    # Wall to kick: probes WallKickReachCm in the 8 horizontal directions and returns the normal (flattened to length 1) of the first wall hit (non-walkable, nearly vertical surface). Fails if none
    #   Probe order: ignores the input direction; current horizontal velocity direction -> body facing -> the other 6 directions (picks the wall in the direction of travel when there is one)
    FindKickWall<private>(Found:character_motor_component)<decides><transacts>:vector3 =
        Feet := Found.Entity.GetGlobalTransform().Translation
        Reach := Found.GetSkinCm() + WallKickReachCm
        Velocity := Found.GetVelocity()
        Flat := vector3{Forward := Velocity.Forward, Left := Velocity.Left}
        Facing := Found.Entity.GetGlobalTransform().Rotation.GetForwardAxis()
        var Directions:[]vector3 = array{}
        if (Moving := FlatUnit[Flat]):
            set Directions += array{Moving}
        if (Face := FlatUnit[Facing]):
            set Directions += array{Face}
        set Directions += array{vector3{Forward := 1.0}, vector3{Forward := -1.0}, vector3{Left := 1.0}, vector3{Left := -1.0},
            vector3{Forward := 0.7071, Left := 0.7071}, vector3{Forward := 0.7071, Left := -0.7071}, vector3{Forward := -0.7071, Left := 0.7071}, vector3{Forward := -0.7071, Left := -0.7071}}
        Walls := for:
            Direction : Directions
            Hit := Found.ProbeSurfaceFrom[Feet, Direction * Reach]
            not Found.IsWalkableNormal[Hit.ContactNormal]
            Hit.ContactNormal.Up < 0.5
            Hit.ContactNormal.Up > -0.5
            Normal := FlatUnit[Hit.ContactNormal]
        do:
            Normal
        Walls[0]

    # Kicks the wall: away from the wall x WallKickAwaySpeedCmPerSecond, up x WallKickUpSpeedCmPerSecond (x the modifiers' jump multiplier). Counts as a jump (height control on release, apex hang while held)
    WallKick<private>(Found:character_motor_component, WallNormal:vector3):void =
        Found.SetVelocity(WallNormal * WallKickAwaySpeedCmPerSecond + vector3{Up := WallKickUpSpeedCmPerSecond * Found.GetJumpMultiplier()})
        set SecondsSinceGrounded = 1000.0
        set CutApplied = false
        set InJump = true
        set LaunchFrame = FrameIndex
        Found.ReportAction(character_action.WallKicked)

    OnPreMove<private>(DeltaTime:float):void =
        set FrameIndex += 1
        if (Found := Motor?):
            Locked := if (Found.IsInputLocked[]) then true else false
            Extra := Found.GetExtraAirJumps()
            if (Found.IsClinging[]):
                # While clinging (ClingKit): restore the air jumps (double jump is possible after jumping off a wall). Do not allow coyote time (no ground jump after letting go)
                set SecondsSinceGrounded = 1000.0
                set AirJumpsLeft = Max(AirJumps + Extra, 0)
                set InJump = false
                set HeldByCode = false
                set CutApplied = true
            else if (IsOnGround[Found]):
                set SecondsSinceGrounded = 0.0
                set AirJumpsLeft = AirJumps + Extra
                set InJump = false
                set HeldByCode = false
                set CutApplied = true
            else:
                set SecondsSinceGrounded += DeltaTime
                # Extra jumps gained in the air are usable right away. If reduced, clamp the remainder to the cap
                if (Extra > LastExtraAirJumps):
                    set AirJumpsLeft += Extra - LastExtraAirJumps
                set AirJumpsLeft = Min(AirJumpsLeft, Max(AirJumps + Extra, 0))
            set LastExtraAirJumps = Extra
            if (Locked?):
                set HeldByCode = false
            # Presses since the previous frame (DeltaTime) plus up to BufferSeconds before that (buffered input). Presses while input is locked are discarded
            if (Button.ConsumePress[BufferSeconds + DeltaTime]):
                if (not Locked?):
                    set HeldByCode = false
                    Jumped := TryJump()
                    if (not Jumped?):
                        # A press that could not jump stays as a buffered input (BufferSeconds until landing)
                        Button.Rebuffer()
            Held := if (not Locked?, (Button.IsDown[] or HeldByCode?)) then true else false
            Velocity := Found.GetVelocity()
            if (not CutApplied?):
                if (Velocity.Up <= 0.0):
                    # Started falling (or was stopped), so no more height control for this jump
                    set CutApplied = true
                else if (not Held?):
                    set CutApplied = true
                    Found.SetVelocity(vector3{Forward := Velocity.Forward, Left := Velocity.Left, Up := Velocity.Up * ReleaseCutRatio})
            ApplyApexHang(Found, Held)

    # Apex hang: while held after a jump, in the air with the vertical speed below ApexSpeedThresholdCmPerSecond, scales this frame's gravity by ApexGravityMultiplier
    #   The body applies FallGravityMultiplier while falling, so divide it out to get exactly ApexGravityMultiplier on both sides of the apex
    ApplyApexHang<private>(Found:character_motor_component, Held:logic):void =
        Velocity := Found.GetVelocity()
        if (InJump?, Held?, ApexSpeedThresholdCmPerSecond > 0.0, not Found.IsGrounded[], Abs(Velocity.Up) < ApexSpeedThresholdCmPerSecond):
            Multiplier := if (Velocity.Up < 0.0 and Found.FallGravityMultiplier > 0.0) then ApexGravityMultiplier / Found.FallGravityMultiplier else ApexGravityMultiplier
            Found.ScaleGravityThisFrame(Multiplier)

    # Succeeds if counted as grounded. The body's IsGrounded is the previous frame's result, so on the frame right after a jump made outside the frame (Jump from code), not grounded if rising (no ground jump or restoring the count right after jumping)
    IsOnGround<private>(Found:character_motor_component)<decides><transacts>:void =
        Found.IsGrounded[]
        not (LaunchFrame >= FrameIndex - 1 and Found.GetVelocity().Up > 0.0)

    # Jumps off the cling: sets the velocity to the body's GetClingJumpVelocity (decided by ClingKit) and asks the cling component to release (RequestClingRelease)
    #   Wall: counts as a jump (reports Jumped. Height control on release, apex hang while held). Ceiling: just falls (no Jumped)
    ClingJump<private>(Found:character_motor_component, Surface:character_cling_surface):void =
        Found.SetVelocity(Found.GetClingJumpVelocity())
        Found.RequestClingRelease()
        set SecondsSinceGrounded = 1000.0
        set LaunchFrame = FrameIndex
        if (Surface = character_cling_surface.Wall):
            set CutApplied = false
            set InJump = true
            Found.ReportAction(character_action.Jumped)

    Launch<private>(Found:character_motor_component, Action:character_action):void =
        Velocity := Found.GetVelocity()
        Found.SetVelocity(vector3{Forward := Velocity.Forward, Left := Velocity.Left, Up := JumpSpeedCmPerSecond * Found.GetJumpMultiplier()})
        set CutApplied = false
        set InJump = true
        set LaunchFrame = FrameIndex
        Found.ReportAction(Action)

# V flattened to length 1. Fails if the horizontal length is nearly 0
FlatUnit<internal>(V:vector3)<decides><transacts>:vector3 =
    Flat := vector3{Forward := V.Forward, Left := V.Left}
    Length := Flat.Length()
    Length > 0.001
    Flat / Length
