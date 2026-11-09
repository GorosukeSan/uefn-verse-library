using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { EnergySystem }
using { InputSystem }
using { CharacterSystem }
using { CharacterSystem.CellKit }
using { CharacterSystem.TooltipKit }

# Role: a short, sharp dash on input (a dash, not a boost). Moves fast for a fixed time / distance, then drops straight to walking speed when it ends
#   One dash (default values):
#     0 s: pick the direction (walk's input direction -> current horizontal motion -> body facing, in that order). Set the horizontal velocity to that direction x DashSpeedCmPerSecond (2200 cm/s). In the air, zero the vertical speed (dash horizontally)
#     0..DurationSeconds (0.18 s): dash at the same speed every frame. Gravity is scaled by DashGravityScale (0 = an air dash keeps its height). walk leaves the velocity alone (the body's SetMoveOverride)
#       The last frame moves at dash speed only for the remaining seconds, so the distance is DashSpeedCmPerSecond x DurationSeconds (396 cm) regardless of frame length
#     End: the speed along the dash direction is cut to "walk's speed cap (MaxSpeedCmPerSecond x the modifiers' speed multiplier, excluding the run button) x DashEndSpeedRatio (1.0)" and the sideways speed is removed (no dash speed is kept)
#     No further dash until CooldownSeconds (0.8 s, counted from the moment of dashing) has passed
#   Jumping mid-dash (jump's Jumped / AirJumped), locking input (LockInput) or clinging to a wall / ceiling (ClingKit's ClingStart) ends the dash on the spot (speed is cut the same way. No jumping at dash speed)
#   No dash while clinging to a wall / ceiling (the body's IsClinging)
#   A dash replaces momentum: the velocity inherited from moving ground (the body's GetInheritedVelocity) is cleared at the moment of dashing
#   In the air, up to AirDashes times (restored on landing). With energy (EnergySystem. An energy_component on this entity, an ancestor or the owner), spends EnergyCost; cannot dash without enough
# Placement: in the editor, attach to the same entity as character_motor_component
# Notifications: Dashed on character_motor_component's ActionEvent when dashing
# From outside: Dash (dash without input. true if it dashed), IsDashing
#   With RequiresGrant, dashing is possible only while a GrantsDash modifier (e.g. BuffKit's character_move_grant_component) is on the body
#   If Boost of the action cells (CellKit's character_action_cell_component on the same entity) is usable, dashes by spending one cell even without a grant or remaining air dashes (no cell is spent when a grant / air dash allows it)
#   No dash while input is locked by the body's LockInput (neither button nor Dash. Presses are discarded). If locked mid-dash, ends on the spot
# Requirements / notes: gravity is weakened every frame with the body's ScaleGravityThisFrame (SetGravityScale is untouched; does not overwrite a factor set by other components)
character_dash_component<public> := class<final_super>(component):

    # Dash button. Empty if unused (dash from code with Dash)
    @editable:
        ToolTip := DashActionToolTip
        Categories := array{CharacterDashCategory}
    DashAction<public>:?input_action(logic) = false
    # Dash speed (cm/s). Default 2200 (travels the distance DurationSeconds x this, 396 cm)
    @editable_number(float):
        ToolTip := DashSpeedToolTip
        Categories := array{CharacterDashCategory}
        MinValue := option{0.0}
        MaxValue := option{50000.0}
    DashSpeedCmPerSecond<public>:float = 2200.0
    # Dash duration (seconds). Default 0.18
    @editable_number(float):
        ToolTip := DashDurationToolTip
        Categories := array{CharacterDashCategory}
        MinValue := option{0.01}
        MaxValue := option{5.0}
    DurationSeconds<public>:float = 0.18
    # Multiplier on walk's speed cap that the speed along the dash direction is cut to when the dash ends (1 cuts to the walking speed cap, 0 stops on the spot). Default 1
    @editable_number(float):
        ToolTip := DashEndSpeedRatioToolTip
        Categories := array{CharacterDashCategory}
        MinValue := option{0.0}
        MaxValue := option{2.0}
    DashEndSpeedRatio<public>:float = 1.0
    # Multiplier on gravity during the dash (0: an air dash keeps its height, 1: falls as usual). Default 0
    @editable_number(float):
        ToolTip := DashGravityScaleToolTip
        Categories := array{CharacterDashCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    DashGravityScale<public>:float = 0.0
    # Time until the next dash (seconds, counted from the moment of dashing). Default 0.8
    @editable_number(float):
        ToolTip := DashCooldownToolTip
        Categories := array{CharacterDashCategory}
        MinValue := option{0.0}
        MaxValue := option{60.0}
    CooldownSeconds<public>:float = 0.8
    # Number of dashes allowed in the air. Default 1
    @editable_number(int):
        ToolTip := DashAirDashesToolTip
        Categories := array{CharacterDashCategory}
        MinValue := option{0}
        MaxValue := option{10}
    AirDashes<public>:int = 1
    # Energy spent per dash (0 spends none). Default 0
    @editable_number(float):
        ToolTip := DashEnergyCostToolTip
        Categories := array{CharacterDashCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    EnergyCost<public>:float = 0.0
    # When on, dashing is possible only while a modifier "granting dash" (character_modifier's GrantsDash, e.g. BuffKit's character_move_grant_component) is stacked on the body (a pickup ability). Default off
    @editable:
        ToolTip := DashRequiresGrantToolTip
        Categories := array{CharacterDashCategory}
    RequiresGrant<public>:logic = false

    # Walking speed cap when walk is not found (cm/s. Used to decide the end speed)
    FallbackWalkSpeedCmPerSecond<private>:float = 600.0

    var<private> Motor:?character_motor_component = false
    var<private> Subscriptions:[]cancelable = array{}
    Button<private>:character_button_tracker = character_button_tracker{}
    var<private> DashLeftSeconds:float = 0.0
    var<private> CooldownLeftSeconds:float = 0.0
    var<private> AirDashesLeft:int = 0
    var<private> Direction:vector3 = vector3{Forward := 1.0}
    # The last frame moved at dash speed, so cut the speed before the next frame's move
    var<private> CutPending:logic = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := Entity.FindCharacterMotorAbove[]):
            set Motor = option{Found}
            set Subscriptions += array{Found.PreMoveEvent.Subscribe(OnPreMove), Found.ActionEvent.Subscribe(OnAction)}
        else:
            Print("[character_dash_component] character_motor_component not found (place it on the same entity or an ancestor)")

    OnSimulate<override>()<suspends>:void =
        if (Found := Motor?, Owner := Found.FindOwner[], Action := DashAction?):
            MaybeInput := Owner.AwaitPlayerInput()
            if (PlayerInput := MaybeInput?):
                set Subscriptions += Button.Listen(PlayerInput, Action)

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        if (Found := Motor?, (IsDashing[] or CutPending?)):
            Found.SetMoveOverride(false)
        set DashLeftSeconds = 0.0
        set CutPending = false
        (super:)OnEndSimulation()

    # Succeeds while dashing
    IsDashing<public>()<decides><transacts>:void =
        DashLeftSeconds > 0.0

    # Dashes without input. false if on cooldown, out of air dashes or energy, not granted under RequiresGrant, or input is locked by the body's LockInput
    Dash<public>():logic =
        if (Found := Motor?, not Found.IsInputLocked[], not Found.IsClinging[], CooldownLeftSeconds <= 0.0, not IsDashing[]):
            Grounded := logic{Found.IsGrounded[]}
            MaybeCells:?character_action_cell_component = if (FoundCells := Entity.GetComponent[character_action_cell_component]) then option{FoundCells} else false
            # Can we dash normally (granted, and grounded or air dashes remaining)? If not, use Boost of the action cells
            Free := if ((not RequiresGrant? or Found.IsDashGranted[]), (Grounded? or AirDashesLeft > 0)) then true else false
            var UseCell:logic = false
            if (not Free?):
                if (Cells := MaybeCells?, Cells.CanUse[character_cell_action.Boost]):
                    set UseCell = true
                else:
                    return false
            if (EnergyCost > 0.0):
                if (Energy := Entity.FindEnergyAbove[]):
                    if (not Energy.Spend[EnergyCost]):
                        return false
            if (UseCell?):
                if (Cells := MaybeCells?):
                    Spent := Cells.TrySpend(character_cell_action.Boost)
                    if (not Spent?):
                        return false
            else if (not Grounded?):
                set AirDashesLeft -= 1
            set Direction = PickDirection(Found)
            set DashLeftSeconds = DurationSeconds
            set CooldownLeftSeconds = CooldownSeconds
            set CutPending = false
            Velocity := Found.GetVelocity()
            # An air dash zeroes the vertical speed and goes horizontally (on the ground, the vertical speed along the ground is kept)
            StartUp := if (Grounded?) then Velocity.Up else 0.0
            Found.SetVelocity(Direction * DashSpeedCmPerSecond + vector3{Up := StartUp})
            # A dash replaces momentum (also clears the part inherited from moving ground. Not kept as the part walk does not decelerate in the air)
            Found.SetInheritedVelocity(vector3{})
            Found.SetMoveOverride(true)
            Found.ReportAction(character_action.Dashed)
            return true
        false

    OnPreMove<private>(DeltaTime:float):void =
        if (Found := Motor?):
            if (Found.IsGrounded[]):
                set AirDashesLeft = AirDashes
            if (CooldownLeftSeconds > 0.0):
                set CooldownLeftSeconds -= DeltaTime
            if (CutPending?):
                # The dash ended on the previous frame: cut the speed and hand the velocity back to walk
                CutSpeed(Found)
            Locked := if (Found.IsInputLocked[]) then true else false
            # Presses while input is locked are discarded
            if (Button.ConsumePress[0.1]):
                if (not Locked?):
                    Dash()
            if (IsDashing[]):
                if (Locked?):
                    # Input locked: end the dash on the spot
                    EndDash(Found)
                else:
                    RunDash(Found, DeltaTime)

    # Body notifications: jumping or clinging to a wall / ceiling (ClingKit) mid-dash ends it on the spot (no jumping at dash speed, no overwriting the cling velocity)
    OnAction<private>(Action:character_action):void =
        if (Found := Motor?, IsDashing[], (Action = character_action.Jumped or Action = character_action.AirJumped or Action = character_action.ClingStart)):
            EndDash(Found)

    # One frame of the dash: scale gravity by DashGravityScale and set the horizontal velocity to the dash direction x DashSpeedCmPerSecond (vertical speed unchanged)
    #   On the last frame (remaining <= DeltaTime), blend the speed so it moves at dash speed for the remaining seconds and at the end speed for the rest (the distance becomes exactly DashSpeedCmPerSecond x DurationSeconds). Cut the speed before the next frame's move
    RunDash<private>(Found:character_motor_component, DeltaTime:float):void =
        Found.ScaleGravityThisFrame(DashGravityScale)
        Velocity := Found.GetVelocity()
        if (DashLeftSeconds > DeltaTime):
            set DashLeftSeconds -= DeltaTime
            Found.SetVelocity(Direction * DashSpeedCmPerSecond + vector3{Up := Velocity.Up})
        else:
            Share := Clamp(DashLeftSeconds / DeltaTime, 0.0, 1.0)
            Speed := DashSpeedCmPerSecond * Share + GetEndSpeed(Found) * (1.0 - Share)
            set DashLeftSeconds = 0.0
            set CutPending = true
            Found.SetVelocity(Direction * Speed + vector3{Up := Velocity.Up})

    # Ends the dash on the spot (jumped, input locked). Cuts the speed and hands the velocity back to walk
    EndDash<private>(Found:character_motor_component):void =
        set DashLeftSeconds = 0.0
        CutSpeed(Found)

    # Cuts the speed along the dash direction to the end speed (GetEndSpeed) and removes the sideways speed (vertical speed unchanged. Stays 0 if stopped by a wall). Hands the velocity back to walk
    CutSpeed<private>(Found:character_motor_component):void =
        set CutPending = false
        Velocity := Found.GetVelocity()
        Along := Clamp(DotProduct(Velocity, Direction), 0.0, GetEndSpeed(Found))
        Found.SetVelocity(Direction * Along + vector3{Up := Velocity.Up})
        Found.SetMoveOverride(false)

    # End speed (cm/s): walk's speed cap x the speed multiplier of the modifiers on the body x DashEndSpeedRatio (never faster than the dash speed). Without walk, capped at 600 cm/s
    GetEndSpeed<private>(Found:character_motor_component)<transacts>:float =
        WalkSpeed := if (Walk := Found.FindCharacterWalk[]) then Walk.MaxSpeedCmPerSecond else FallbackWalkSpeedCmPerSecond
        Min(DashSpeedCmPerSecond, WalkSpeed * Found.GetSpeedMultiplier() * DashEndSpeedRatio)

    # Dash direction (horizontal unit vector): walk's input direction -> current horizontal motion -> body facing, in that order. The axis locked by the body's AxisLock is removed (if that leaves 0, keep the previous direction)
    PickDirection<private>(Found:character_motor_component)<transacts>:vector3 =
        Input := if (Walk := Found.FindCharacterWalk[]) then Walk.GetInputDirection() else vector3{}
        Velocity := Found.GetVelocity()
        Moving := vector3{Forward := Velocity.Forward, Left := Velocity.Left}
        Raw := if (Input.Length() > 0.1) then Input else if (Moving.Length() > 1.0) then Moving else Flatten(Found.Entity.GetGlobalTransform().Rotation.GetForwardAxis())
        Free := case (Found.AxisLock):
            character_axis_lock.Left => vector3{Forward := Raw.Forward}
            character_axis_lock.Forward => vector3{Left := Raw.Left}
            character_axis_lock.None => vector3{Forward := Raw.Forward, Left := Raw.Left}
        FreeCm := Free.Length()
        if (FreeCm > 0.001) then Free / FreeCm else Direction
