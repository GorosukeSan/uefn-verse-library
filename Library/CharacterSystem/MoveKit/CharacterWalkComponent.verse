using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Input }
using { InputSystem }
using { MovementSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { CharacterSystem }
using { CharacterSystem.TooltipKit }

# What the walking direction is aligned to
character_walk_space<public> := enum:
    # The horizontal direction of the owner's view (camera) is forward (3D action)
    View
    # World directions (forward = Forward, left = Left). Side-scrollers and top-down games
    World
    # The character's facing (this entity's forward)
    Facing
    # 2D seen from the side (side-scroller). Side input moves along the world's forward / back (right = forward); forward / back input is unused. Use with the body's AxisLock set to Left
    SideView

# Role: walk / run horizontally on input. On the ground, accelerates toward the input direction (forward / back, left / right) at AccelerationCmPerSecondSquared up to MaxSpeedCmPerSecond, and brakes at BrakingCmPerSecondSquared without input
#   Three kinds of input (summed): MoveAction (direction input, input_action(vector3)), ForwardAction / BackAction / LeftAction / RightAction (4 buttons), SetMoveInput from code (touch UI, AI, the experimental Character.Move, etc.)
#   While SprintAction is held, SprintMultiplier applies. The modifiers on the body (character_modifier's SpeedMultiplier. BuffKit) also multiply
#   Turnaround (ground): if the input direction opposes the current motion, acceleration is multiplied by TurnAroundMultiplier
#   Air: acceleration is AccelerationCmPerSecondSquared x AirControlRatio, turnaround is further scaled by up to AirTurnAroundMultiplier depending on how opposed the input is (instead of TurnAroundMultiplier), braking without input is BrakingCmPerSecondSquared x AirBrakingRatio (small, so momentum is kept)
#     With KeepAirMomentum, speed above the cap (gained from knockback or a launch) is only bent toward the input direction, never reduced (reduced only when the input opposes it). Input never exceeds the cap. Dash speed does not remain, because dash cuts it to the cap when it ends
#     The velocity inherited from moving ground (the body's GetInheritedVelocity. SurfaceKit's character_ride_component) is not braked even without input (jumping keeps moving with the floor). It shrinks when opposed by input or hitting a wall, and the lost part does not come back
#   While another component (dash, ClingKit's cling) sets the velocity (the body's IsMoveOverridden), the velocity is left alone (input direction and input are still recorded, for the cling component to read). While clinging to a wall, the body is not turned even with TankTurn
#   While input is locked by the body's LockInput, every input is treated as 0 (only braking continues. In the air, the weak AirBrakingRatio braking. No turning even with TankTurn)
#   The side-input style (character_side_style) lives here: Turn (move sideways, the body turns toward the movement), Strafe (move sideways, the body keeps facing forward), TankTurn (side input turns in place, forward / back move along the body's facing)
#   Current style = the modifier on the body (character_modifier's SideStyle) if any, otherwise the base (SideStyle. Changed by SetSideStyle / SideStyleToggleAction). Changes arrive on SideStyleChangedEvent
#   The body's facing is turned by BodyKit's character_face_movement_component for Turn / Strafe (it reads this style). For TankTurn, this component turns it
# Placement: in the editor, attach to the same entity as character_motor_component
# Requirements: there must be an owner (inside a loadout, etc.) and the input mapping (input_mapping) must be added to that player (BodyKit's character_input_mapping_component can add it)
# Requirements / notes: when a modifier on the body changes the side-input style, SideStyleChangedEvent arrives before the next frame's move (the code that adds a modifier cannot notify, so it is compared every frame)
# ⚠ Unverified: the direction of MoveAction's value (read as Forward = forward, Left = left)
character_walk_component<public> := class<final_super>(component):

    # Direction input (forward / back, left / right). Empty if unused
    @editable:
        ToolTip := WalkMoveActionToolTip
        Categories := array{CharacterWalkCategory}
    MoveAction<public>:?input_action(vector3) = false
    # Button to move forward. Empty if unused
    @editable:
        ToolTip := WalkButtonToolTip
        Categories := array{CharacterWalkCategory}
    ForwardAction<public>:?input_action(logic) = false
    # Button to move back
    @editable:
        ToolTip := WalkButtonToolTip
        Categories := array{CharacterWalkCategory}
    BackAction<public>:?input_action(logic) = false
    # Button to move left
    @editable:
        ToolTip := WalkButtonToolTip
        Categories := array{CharacterWalkCategory}
    LeftAction<public>:?input_action(logic) = false
    # Button to move right
    @editable:
        ToolTip := WalkButtonToolTip
        Categories := array{CharacterWalkCategory}
    RightAction<public>:?input_action(logic) = false
    # Button to run while held. Empty if unused
    @editable:
        ToolTip := WalkSprintActionToolTip
        Categories := array{CharacterWalkCategory}
    SprintAction<public>:?input_action(logic) = false
    # What the walking direction is aligned to. Default View
    @editable:
        ToolTip := WalkSpaceToolTip
        Categories := array{CharacterWalkCategory}
    Space<public>:character_walk_space = character_walk_space.View
    # Walking speed cap (cm/s). Default 600
    @editable_number(float):
        ToolTip := WalkMaxSpeedToolTip
        Categories := array{CharacterWalkCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    MaxSpeedCmPerSecond<public>:float = 600.0
    # Acceleration (cm/s^2). Default 4000
    @editable_number(float):
        ToolTip := WalkAccelerationToolTip
        Categories := array{CharacterWalkCategory}
        MinValue := option{0.0}
        MaxValue := option{100000.0}
    AccelerationCmPerSecondSquared<public>:float = 4000.0
    # Braking without input (cm/s^2). Default 5000
    @editable_number(float):
        ToolTip := WalkBrakingToolTip
        Categories := array{CharacterWalkCategory}
        MinValue := option{0.0}
        MaxValue := option{100000.0}
    BrakingCmPerSecondSquared<public>:float = 5000.0
    # Multiplier on acceleration (AccelerationCmPerSecondSquared) when accelerating toward the input direction in the air (0: no air control, 1: same as the ground). Braking without input is AirBrakingRatio. Default 0.6
    @editable_number(float):
        ToolTip := WalkAirControlToolTip
        Categories := array{CharacterWalkCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    AirControlRatio<public>:float = 0.6
    # Multiplier on braking (BrakingCmPerSecondSquared) without input in the air (0: no braking, 1: same as the ground). Smaller keeps more momentum. Default 0.2
    #   By default 1000 cm/s^2 (about 0.6 s from 600 cm/s to 0. A short jump keeps momentum, a long jump nearly stops at the end. At 0.1 it kept drifting like on ice)
    @editable_number(float):
        ToolTip := WalkAirBrakingToolTip
        Categories := array{CharacterWalkCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    AirBrakingRatio<public>:float = 0.2
    # Upper bound of the multiplier on air acceleration on an air turnaround (instead of the ground's TurnAroundMultiplier). The more the input opposes the current horizontal motion, the more applies (1x at a right angle, this multiplier when fully opposed). Default 2
    #   By default 4800 cm/s^2 when fully opposed (about 0.25 s from 600 cm/s to 600 cm/s the other way. 0.6x the ground turnaround of 8000 cm/s^2 = consistent with AirControlRatio)
    @editable_number(float):
        ToolTip := WalkAirTurnAroundToolTip
        Categories := array{CharacterWalkCategory}
        MinValue := option{1.0}
        MaxValue := option{10.0}
    AirTurnAroundMultiplier<public>:float = 2.0
    # When on, speed above the cap in the air (gained from knockback or a launch) is only bent toward the input direction, never reduced (reduced only when the input opposes it). When off, approaches the input speed in the air too (reduced to the cap). Default on
    #   Dash speed does not remain here, because dash cuts it to the cap when it ends
    @editable:
        ToolTip := WalkKeepAirMomentumToolTip
        Categories := array{CharacterWalkCategory}
    KeepAirMomentum<public>:logic = true
    # Speed multiplier while running. Default 1.6
    @editable_number(float):
        ToolTip := WalkSprintMultiplierToolTip
        Categories := array{CharacterWalkCategory}
        MinValue := option{1.0}
        MaxValue := option{10.0}
    SprintMultiplier<public>:float = 1.6
    # Multiplier on acceleration on a ground turnaround (input direction more than 90 degrees from the current horizontal motion). 1 is the same as normal acceleration. In the air, AirTurnAroundMultiplier. Default 2
    @editable_number(float):
        ToolTip := WalkTurnAroundToolTip
        Categories := array{CharacterWalkCategory}
        MinValue := option{1.0}
        MaxValue := option{10.0}
    TurnAroundMultiplier<public>:float = 2.0
    # What to do with side input (base value). Turn = move sideways, the body turns toward the movement; Strafe = move sideways, the body keeps facing forward (crab walk); TankTurn = side input turns in place, forward / back move along the body's facing. Default Turn
    @editable:
        ToolTip := WalkSideStyleToolTip
        Categories := array{CharacterWalkCategory}
    SideStyle<public>:character_side_style = character_side_style.Turn
    # With TankTurn, degrees turned per second by side input. Default 180
    @editable_number(float):
        ToolTip := WalkTankTurnSpeedToolTip
        Categories := array{CharacterWalkCategory}
        MinValue := option{0.0}
        MaxValue := option{3600.0}
    TankTurnDegreesPerSecond<public>:float = 180.0
    # Button that toggles the (base) side-input style between SideStyle and ToggleSideStyle on each press. Empty if unused
    @editable:
        ToolTip := WalkSideStyleToggleActionToolTip
        Categories := array{CharacterWalkCategory}
    SideStyleToggleAction<public>:?input_action(logic) = false
    # The style the SideStyleToggleAction toggles to. Default Strafe
    @editable:
        ToolTip := WalkToggleSideStyleToolTip
        Categories := array{CharacterWalkCategory}
    ToggleSideStyle<public>:character_side_style = character_side_style.Strafe

    # Toggle button presses within this many seconds are accepted (checked every frame, so anything longer than one frame works)
    ToggleBufferSeconds<private>:float = 0.25

    var<private> Motor:?character_motor_component = false
    var<private> ExternalInput:vector3 = vector3{}
    var<private> Subscriptions:[]cancelable = array{}
    # Base side-input style changed by SetSideStyle / toggle (false keeps SideStyle)
    var<private> BaseSideStyle:?character_side_style = false
    # Current style last reported on SideStyleChangedEvent (or at start)
    var<private> NotifiedSideStyle:?character_side_style = false
    # Input direction of the last frame (world horizontal. Length 0..1. GetInputDirection)
    var<private> InputDirection:vector3 = vector3{}
    # Input of the last frame (before converting to the walking direction. Forward = forward, Left = left. Length 0..1. GetMoveInput)
    var<private> MoveInput:vector3 = vector3{}
    Axis<private>:character_axis_tracker = character_axis_tracker{}
    Forward<private>:character_button_tracker = character_button_tracker{}
    Back<private>:character_button_tracker = character_button_tracker{}
    Left<private>:character_button_tracker = character_button_tracker{}
    Right<private>:character_button_tracker = character_button_tracker{}
    Sprint<private>:character_button_tracker = character_button_tracker{}
    SideToggle<private>:character_button_tracker = character_button_tracker{}

    SideStyleChangedEventInternal<private><final>:event(character_side_style) = event(character_side_style){}

    # Arrives with the new style whenever the current side-input style (GetSideStyle) changes (whether by SetSideStyle, the toggle button or a modifier on the body)
    SideStyleChangedEvent<public><final>:listenable(character_side_style) = MakeProxyListenable(SideStyleChangedEventInternal)

    # Sets the walking input from code (Forward = forward, Left = left. Length up to 1). The value stays until the next call (vector3{} to stop)
    SetMoveInput<public>(Input:vector3):void =
        set ExternalInput = Input

    # Current side-input style. The modifier on the body (character_modifier's SideStyle) if any, otherwise the base (GetBaseSideStyle)
    GetSideStyle<public>()<transacts>:character_side_style =
        if (Found := Motor?, Override := Found.GetSideStyleOverride[]) then Override else GetBaseSideStyle()

    # Base side-input style (changed by SetSideStyle / toggle. SideStyle if unchanged)
    GetBaseSideStyle<public>()<transacts>:character_side_style =
        if (Base := BaseSideStyle?) then Base else SideStyle

    # Sets the base side-input style to Style. While a modifier on the body decides the SideStyle, it takes effect once that modifier is removed. If the current style changes, SideStyleChangedEvent arrives
    SetSideStyle<public>(Style:character_side_style):void =
        set BaseSideStyle = option{Style}
        NotifySideStyle()

    # Toggles the base between SideStyle and ToggleSideStyle (same as pressing SideStyleToggleAction. If the base is ToggleSideStyle, to SideStyle; otherwise to ToggleSideStyle)
    SwitchSideStyle<public>():void =
        SetSideStyle(if (GetBaseSideStyle() = ToggleSideStyle) then SideStyle else ToggleSideStyle)

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := Entity.FindCharacterMotorAbove[]):
            set Motor = option{Found}
            set Subscriptions += array{Found.PreMoveEvent.Subscribe(OnPreMove)}
        else:
            Print("[character_walk_component] character_motor_component not found (place it on the same entity or an ancestor)")
        # The style at start is not reported (only changes are)
        set NotifiedSideStyle = option{GetSideStyle()}

    OnSimulate<override>()<suspends>:void =
        if (Found := Motor?, Owner := Found.FindOwner[]):
            MaybeInput := Owner.AwaitPlayerInput()
            if (PlayerInput := MaybeInput?):
                if (Action := MoveAction?):
                    set Subscriptions += Axis.Listen(PlayerInput, Action)
                if (Action := ForwardAction?):
                    set Subscriptions += Forward.Listen(PlayerInput, Action)
                if (Action := BackAction?):
                    set Subscriptions += Back.Listen(PlayerInput, Action)
                if (Action := LeftAction?):
                    set Subscriptions += Left.Listen(PlayerInput, Action)
                if (Action := RightAction?):
                    set Subscriptions += Right.Listen(PlayerInput, Action)
                if (Action := SprintAction?):
                    set Subscriptions += Sprint.Listen(PlayerInput, Action)
                if (Action := SideStyleToggleAction?):
                    set Subscriptions += SideToggle.Listen(PlayerInput, Action)

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        (super:)OnEndSimulation()

    OnPreMove<private>(DeltaTime:float):void =
        # While input is locked by the body's LockInput, treat input as 0 (toggle button presses are discarded. Only braking to a stop continues)
        Locked := if (Found := Motor?, Found.IsInputLocked[]) then true else false
        if (SideToggle.ConsumePress[ToggleBufferSeconds]):
            if (not Locked?):
                SwitchSideStyle()
        # Modifiers on the body being added or removed are also detected and reported here
        NotifySideStyle()
        if (Found := Motor?):
            Raw := if (Locked?) then vector3{} else GetRawInput()
            set MoveInput = LimitLength(Raw)
            TurnsBody := SideInputTurnsBody(GetSideStyle())
            # While clinging to a wall (ClingKit), do not turn the body even with TankTurn (the body faces the wall and side input moves sideways along the wall)
            OnWall := if (Surface := Found.GetClingSurface[], Surface = character_cling_surface.Wall) then true else false
            # TankTurn: side input only turns the body (turn first, then forward / back move along that facing). Raw is 0 while input is locked, so no turning
            if (TurnsBody?, not OnWall?):
                TurnBody(Found, Clamp(Raw.Left, -1.0, 1.0), DeltaTime)
            Input := if (TurnsBody?) then vector3{Forward := Clamp(Raw.Forward, -1.0, 1.0)} else LimitLength(Raw)
            Basis := GetBasis(Found)
            Direction := Basis(0) * Input.Forward + Basis(1) * Input.Left
            set InputDirection = Direction
            # While another component (dash, ClingKit's cling) sets the velocity, leave it alone (only record the input direction. The dash distance does not depend on update order)
            if (Found.IsMoveOverridden[]):
                return
            BaseSpeed := if (Sprint.IsDown[]) then MaxSpeedCmPerSecond * SprintMultiplier else MaxSpeedCmPerSecond
            # Multiply by the modifiers (buffs) on the body
            Speed := BaseSpeed * Found.GetSpeedMultiplier()
            Desired := Direction * Speed
            Velocity := Found.GetVelocity()
            Horizontal := vector3{Forward := Velocity.Forward, Left := Velocity.Left}
            HasInput := if (Input.LengthSquared() > 0.0001) then true else false
            Next := if (Found.IsGrounded[]) then GroundStep(Horizontal, Desired, HasInput, DeltaTime) else AirStep(Found, Horizontal, Desired, HasInput, DeltaTime)
            Found.SetVelocity(vector3{Forward := Next.Forward, Left := Next.Left, Up := Velocity.Up})

    # Ground: accelerate toward the input direction (TurnAroundMultiplier on a turnaround), brake at BrakingCmPerSecondSquared without input. Above the cap, reduce to the input speed
    GroundStep<private>(Horizontal:vector3, Desired:vector3, HasInput:logic, DeltaTime:float)<transacts>:vector3 =
        # Turnaround: if the input direction opposes the current horizontal motion (more than 90 degrees apart), multiply acceleration by TurnAroundMultiplier (changes direction faster than stopping and starting again)
        Acceleration := if (DotProduct(Desired, Horizontal) < 0.0) then AccelerationCmPerSecondSquared * TurnAroundMultiplier else AccelerationCmPerSecondSquared
        Rate := if (HasInput?) then Acceleration else BrakingCmPerSecondSquared
        MoveToward(Horizontal, Desired, Rate * DeltaTime)

    # Air: split Horizontal into the part inherited from moving ground (along the body's GetInheritedVelocity, up to its length) and the body's own part, and change only the own part with input
    #   If the inherited part shrank from input (opposing) or a wall, shrink the body's inherited velocity to match (the lost part does not come back. It used to come back as a non-braked part when input in the same direction followed)
    #   No input: the own part goes to 0 at BrakingCmPerSecondSquared x AirBrakingRatio (the inherited part is not reduced)
    #   Turnaround: the more the input opposes the own part, the more AirTurnAroundMultiplier applies to acceleration (1x at a right angle, AirTurnAroundMultiplier when fully opposed. It used to change abruptly at 90 degrees)
    #   Above the cap (with KeepAirMomentum): only bend toward the input direction (speed unchanged). Otherwise: toward the input speed at AccelerationCmPerSecondSquared x AirControlRatio (input never exceeds the cap)
    #   Dash speed does not remain here (dash cuts it to the walking speed cap when it ends). What remains above the cap is speed added from outside, such as knockback or a launch
    AirStep<private>(Found:character_motor_component, Horizontal:vector3, Desired:vector3, HasInput:logic, DeltaTime:float)<transacts>:vector3 =
        Inherited := Found.GetInheritedVelocity()
        InheritedCm := Inherited.Length()
        Carried := if (InheritedCm > 0.01) then Inherited * (Clamp(DotProduct(Horizontal, Inherited) / InheritedCm, 0.0, InheritedCm) / InheritedCm) else vector3{}
        if (InheritedCm > 0.01):
            Found.SetInheritedVelocity(Carried)
        Own := Horizontal - Carried
        if (not HasInput?):
            return Carried + MoveToward(Own, vector3{}, BrakingCmPerSecondSquared * AirBrakingRatio * DeltaTime)
        Cap := Desired.Length()
        OwnCm := Own.Length()
        # Degree of opposition (0 = right angle or same direction, 1 = fully opposed)
        Opposition := if (OwnCm > 0.01 and Cap > 0.0001) then Max(-DotProduct(Desired, Own) / (Cap * OwnCm), 0.0) else 0.0
        Reversing := if (Opposition > 0.0) then true else false
        Rate := AccelerationCmPerSecondSquared * AirControlRatio * (1.0 + (AirTurnAroundMultiplier - 1.0) * Opposition)
        Step := Rate * DeltaTime
        if (Reversing? or not KeepAirMomentum? or OwnCm <= Cap or Cap <= 0.0001):
            return Carried + MoveToward(Own, Desired, Step)
        # Above the cap: push toward the input direction by Step, then restore the original speed (bends, but neither faster nor slower)
        Bent := Own + Desired * (Step / Cap)
        BentCm := Bent.Length()
        Carried + (if (BentCm > 0.0001) then Bent * (OwnCm / BentCm) else Own)

    # Input direction of the last frame (world horizontal direction x input strength. Length 0..1). vector3{} without input or while locked by LockInput. With TankTurn, forward / back input only (along the body's facing)
    #   BodyKit's character_face_movement_component uses it to face the body toward the input in the air
    GetInputDirection<public>()<transacts>:vector3 = InputDirection

    # Input of the last frame (before converting to the walking direction. Forward = forward, Left = left. Length 0..1). vector3{} without input or while locked by LockInput. Includes the side part even with TankTurn
    #   ClingKit's character_cling_component uses it on a wall with TankTurn (forward = up, left / right = left / right along the wall)
    GetMoveInput<public>()<transacts>:vector3 = MoveInput

    # Diagnostics: the raw value currently read from the input mapping (MoveAction) (before conversion. The side sign is still inverted = positive Left means right)
    GetRawMoveAxis<public>()<transacts>:vector3 = Axis.GetValue()

    # Unit vectors (horizontal) of the current walking direction (forward, left). Input (forward, left) is converted to world directions with these. With TankTurn, the body's facing (Space is not used). In SideView, forward is vector3{}
    GetWalkBasis<public>()<transacts>:tuple(vector3, vector3) =
        if (Found := Motor?) then GetBasis(Found) else (vector3{Forward := 1.0}, vector3{Left := 1.0})

    # Forward of the current walking direction (horizontal unit vector. The forward of GetWalkBasis). With Strafe, character_face_movement_component turns the body toward it. vector3{} in SideView (no forward)
    GetWalkFront<public>()<transacts>:vector3 =
        GetWalkBasis()(0)

    # If the current style (GetSideStyle) differs from the last reported one, reports it on SideStyleChangedEvent
    NotifySideStyle<private>():void =
        Current := GetSideStyle()
        if (Previous := NotifiedSideStyle?, Previous = Current):
            return
        set NotifiedSideStyle = option{Current}
        SideStyleChangedEventInternal.Signal(Current)

    # TankTurn: turns the body's (the motor entity's) horizontal facing by Turn (-1..1. Positive turns left) x TankTurnDegreesPerSecond
    TurnBody<private>(Found:character_motor_component, Turn:float, DeltaTime:float):void =
        if (Turn = 0.0 or TankTurnDegreesPerSecond <= 0.0):
            return
        Current := Found.Entity.GetGlobalTransform()
        Yaw := Current.Rotation.GetYawPitchRollDegrees()(0)
        # Match the "positive when turning left" angle to the yaw direction (YawSign, directly under CharacterSystem)
        Next := Yaw + Turn * TankTurnDegreesPerSecond * DeltaTime * YawSign()
        Found.Entity.SetGlobalTransform(transform{Translation := Current.Translation, Rotation := MakeRotationFromYawPitchRollDegrees(Next, 0.0, 0.0), Scale := Current.Scale})

    # Sum of the inputs (Forward = forward, Left = left). The length is not limited
    GetRawInput<private>()<transacts>:vector3 =
        Axis2 := Axis.GetValue()
        # The side sign of MoveAction (Character.Move) is inverted (UEFN v43.00: A gives Left = -1, D gives Left = +1. It arrives with UE's "right is positive"), so flip it
        var Sum:vector3 = vector3{Forward := Axis2.Forward + ExternalInput.Forward, Left := -Axis2.Left + ExternalInput.Left}
        if (Forward.IsDown[]):
            set Sum = Sum + vector3{Forward := 1.0}
        if (Back.IsDown[]):
            set Sum = Sum + vector3{Forward := -1.0}
        if (Left.IsDown[]):
            set Sum = Sum + vector3{Left := 1.0}
        if (Right.IsDown[]):
            set Sum = Sum + vector3{Left := -1.0}
        Sum

    # Unit vectors (horizontal) of the walking direction (forward, left)
    GetBasis<private>(Found:character_motor_component)<transacts>:tuple(vector3, vector3) =
        # TankTurn (side input turns the body): forward / back along the body's facing (Space is not used)
        if (SideInputTurnsBody(GetSideStyle())?):
            Facing := Flatten(Found.Entity.GetGlobalTransform().Rotation.GetForwardAxis())
            return (Facing, CrossProduct(vector3{Up := 1.0}, Facing))
        if (Space = character_walk_space.SideView):
            return (vector3{}, vector3{Forward := -1.0})
        Front := case (Space):
            character_walk_space.SideView => vector3{Forward := 1.0}
            character_walk_space.World => vector3{Forward := 1.0}
            character_walk_space.Facing => Flatten(Found.Entity.GetGlobalTransform().Rotation.GetForwardAxis())
            character_walk_space.View =>
                if (Owner := Found.FindOwner[], OwnerCharacter := Owner.GetFortCharacter[]):
                    Flatten(OwnerCharacter.GetViewDirection())
                else:
                    vector3{Forward := 1.0}
        (Front, CrossProduct(vector3{Up := 1.0}, Front))

# The walk Motor uses. First one attached to the body (Motor's entity), otherwise one attached to a descendant (any one. Which descendant is unspecified). Fails if none
#   BodyKit's character_face_movement_component finds it this way (your own components and MCP can use it too)
(Motor:character_motor_component).FindCharacterWalk<public>()<decides><transacts>:character_walk_component =
    Candidates := for (Each : Motor.Entity.FindDescendantComponents(character_walk_component)):
        Each
    OnBody := for (Each : Candidates, Each.Entity = Motor.Entity):
        Each
    (OnBody + Candidates)[0]

# Removes the vertical component of V and normalizes to length 1 (forward if nearly straight up or down)
Flatten<internal>(V:vector3)<transacts>:vector3 =
    Horizontal := vector3{Forward := V.Forward, Left := V.Left}
    Length := Horizontal.Length()
    if (Length > 0.0001) then Horizontal / Length else vector3{Forward := 1.0}

# Shrinks V to length 1 at most
LimitLength<internal>(V:vector3)<transacts>:vector3 =
    Magnitude := V.Length()
    if (Magnitude > 1.0) then V / Magnitude else V

# Vector moved from Current toward Target by at most MaxStep in length
MoveToward<internal>(Current:vector3, Target:vector3, MaxStep:float)<transacts>:vector3 =
    Gap := Target - Current
    Length := Gap.Length()
    if (Length <= MaxStep or Length <= 0.0001) then Target else Current + Gap * (MaxStep / Length)
