using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { CharacterSystem }
using { CharacterSystem.TooltipKit }

# Kinds of deformation added by character_squash_stretch_component.Pulse (amounts are that component's @editable values)
character_look_pulse<public> := enum:
    # Jump from the ground (stretches vertically. JumpScale)
    Jump
    # Air jump (stretches more. AirJumpScale)
    AirJump
    # Landing (squashes. Same as landing at the speed halfway between LandMinSpeedCmPerSecond and LandFullSpeedCmPerSecond. Use PulseLanding to match the speed)
    Land
    # Dash (stretches toward the current horizontal velocity. DashStretch, DashHoldSeconds)
    Dash
    # Hit a wall (squashes along the previous frame's horizontal velocity. HitWallSquash)
    HitWall

# Role: squashes and stretches the custom character's visual shell (Shell) to match its motion (squash and stretch). The core (Core) inside the shell is kept at the center of the deformed shell
#   Every frame (the body's PostMoveEvent): moves the shell's scale factors toward the shape (target) decided from the current state with a per-axis (forward, left, up) spring (SpringStiffness / SpringDamping). Being a spring, it overshoots a little and settles
#     Still on the ground: slow breathing (vertically +/-IdleBreathAmount, one cycle per IdleBreathSeconds)
#     Running on the ground: small vertical bob (+/-RunBobAmount. One cycle per RunBobStrideCm traveled) and a slight lean toward the travel direction around the feet (RunLeanDegrees). Both peak at RunFullSpeedCmPerSecond and blend with breathing while slower
#     In the air: stretches vertically with the vertical speed (AirStretchPer1000CmPerSecond per 1000 cm/s, up to AirStretchMax). The lean returns to zero
#   On events (the body's ActionEvent / LandedEvent), snaps to that shape, holds it briefly (PulseHoldSeconds), then springs back (same as Pulse)
#     Jumped -> JumpScale, AirJumped -> AirJumpScale, landing -> from the base shape to LandSquashScale by landing speed (LandMinSpeedCmPerSecond..LandFullSpeedCmPerSecond),
#     Dashed -> 1 + DashStretch toward the travel direction (held for DashHoldSeconds), HitWall -> 1 - HitWallSquash along the direction traveled before the hit (only when the horizontal speed then was at least HitWallMinSpeedCmPerSecond. It arrives every frame while pressed against a wall, so at most once per 0.3 s)
#   With PreserveVolume, the three axis factors are normalized so their product is 1 before applying to the shell (roughly preserves volume. JumpScale (0.8, 0.8, 1.3) becomes (0.85, 0.85, 1.38))
#   Rule for stretching toward the travel direction (dash, wall): scale factors can only be applied along the shell's axes (forward, left, up) (no stretching along a skewed direction), so the travel direction is split into the shell's axes and each axis is stretched by the square of its share
#     If the body faces the travel direction (Turn of BodyKit's character_face_movement_component), only the shell's forward axis stretches. When moving diagonally (Strafe, etc.), forward and left stretch by their shares (no rhombus)
# Placement: in the editor, attach to the custom character's body (the character_motor_component entity or a descendant), set Shell to the shell entity (a descendant of the body) and Core to the core entity (a child of the same parent as the shell)
#   Put the shell mesh's origin at the feet (bottom center) (so the feet stay on the ground through squash / stretch and lean). The position, rotation and scale of the shell and core as placed in the editor are the base shape (read one frame after start)
# From outside: Pulse(Kind), PulseLanding(landing speed), Squash(amount), PulseShape(shape, seconds) add a deformation (bounced by a gimmick, damage, ...). GetDeformation gives the current factors
# Requirements / notes: writes the local transforms of shell and core every frame (do not move the shell or core from other components. Move the parent entity instead). Restores the base shape when stopping (OnEndSimulation)
#   The body's facing (yaw) belongs to the body entity, so the velocity is read in the orientation of the shell's parent (a child of the body)
character_squash_stretch_component<public> := class<final_super>(component):

    # The shell entity to squash and stretch. Does nothing if empty
    @editable:
        ToolTip := LookShellToolTip
        Categories := array{CharacterLookCategory}
    Shell<public>:?entity = false
    # The core entity kept at the center of the shell. If empty, only the shell moves
    @editable:
        ToolTip := LookCoreToolTip
        Categories := array{CharacterLookCategory}
    Core<public>:?entity = false
    # Height of the core mesh at scale 1 (cm). Default 100
    @editable_number(float):
        ToolTip := LookMeshHeightToolTip
        Categories := array{CharacterLookCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    MeshHeightCm<public>:float = 100.0
    # When on, the core mesh's origin is at the bottom center; when off, at the center. Default on
    @editable:
        ToolTip := LookMeshPivotAtBottomToolTip
        Categories := array{CharacterLookCategory}
    MeshPivotAtBottom<public>:logic = true
    # Fraction by which the core also follows the shell's deformation (0..1). Default 0
    @editable_number(float):
        ToolTip := LookCoreDeformRatioToolTip
        Categories := array{CharacterLookCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    CoreDeformRatio<public>:float = 0.0
    # Spring stiffness. Default 260
    @editable_number(float):
        ToolTip := LookSpringStiffnessToolTip
        Categories := array{CharacterLookCategory}
        MinValue := option{1.0}
        MaxValue := option{5000.0}
    SpringStiffness<public>:float = 260.0
    # Spring damping. Default 14
    @editable_number(float):
        ToolTip := LookSpringDampingToolTip
        Categories := array{CharacterLookCategory}
        MinValue := option{0.0}
        MaxValue := option{200.0}
    SpringDamping<public>:float = 14.0
    # When on, roughly preserves volume. Default on
    @editable:
        ToolTip := LookPreserveVolumeToolTip
        Categories := array{CharacterLookCategory}
    PreserveVolume<public>:logic = true
    # Seconds to hold the jump / landing / wall shape. Default 0.05
    @editable_number(float):
        ToolTip := LookPulseHoldToolTip
        Categories := array{CharacterLookCategory}
        MinValue := option{0.0}
        MaxValue := option{2.0}
    PulseHoldSeconds<public>:float = 0.05
    # Shape at the moment of jumping from the ground (forward, left, up factors)
    @editable:
        ToolTip := LookJumpScaleToolTip
        Categories := array{CharacterLookCategory}
    JumpScale<public>:vector3 = vector3{Forward := 0.8, Left := 0.8, Up := 1.3}
    # Shape at the moment of an air jump
    @editable:
        ToolTip := LookAirJumpScaleToolTip
        Categories := array{CharacterLookCategory}
    AirJumpScale<public>:vector3 = vector3{Forward := 0.75, Left := 0.75, Up := 1.35}
    # Shape at the moment of a fast landing
    @editable:
        ToolTip := LookLandSquashScaleToolTip
        Categories := array{CharacterLookCategory}
    LandSquashScale<public>:vector3 = vector3{Forward := 1.3, Left := 1.3, Up := 0.65}
    # Landing speed at which squashing starts (cm/s). Default 250
    @editable_number(float):
        ToolTip := LookLandMinSpeedToolTip
        Categories := array{CharacterLookCategory}
        MinValue := option{0.0}
        MaxValue := option{20000.0}
    LandMinSpeedCmPerSecond<public>:float = 250.0
    # Landing speed at which squashing is strongest (cm/s). Default 1800
    @editable_number(float):
        ToolTip := LookLandFullSpeedToolTip
        Categories := array{CharacterLookCategory}
        MinValue := option{1.0}
        MaxValue := option{20000.0}
    LandFullSpeedCmPerSecond<public>:float = 1800.0
    # Amount of stretch toward the travel direction on a dash. Default 0.45
    @editable_number(float):
        ToolTip := LookDashStretchToolTip
        Categories := array{CharacterLookCategory}
        MinValue := option{0.0}
        MaxValue := option{2.0}
    DashStretch<public>:float = 0.45
    # Seconds to hold the dash stretch. Default 0.15
    @editable_number(float):
        ToolTip := LookDashHoldToolTip
        Categories := array{CharacterLookCategory}
        MinValue := option{0.0}
        MaxValue := option{2.0}
    DashHoldSeconds<public>:float = 0.15
    # Amount of squash on hitting a wall. Default 0.25
    @editable_number(float):
        ToolTip := LookHitWallSquashToolTip
        Categories := array{CharacterLookCategory}
        MinValue := option{0.0}
        MaxValue := option{0.8}
    HitWallSquash<public>:float = 0.25
    # Minimum horizontal speed before the hit for the wall squash (cm/s). Default 350
    @editable_number(float):
        ToolTip := LookHitWallMinSpeedToolTip
        Categories := array{CharacterLookCategory}
        MinValue := option{0.0}
        MaxValue := option{20000.0}
    HitWallMinSpeedCmPerSecond<public>:float = 350.0
    # Vertical stretch in the air per 1000 cm/s of vertical speed. Default 0.15
    @editable_number(float):
        ToolTip := LookAirStretchToolTip
        Categories := array{CharacterLookCategory}
        MinValue := option{0.0}
        MaxValue := option{2.0}
    AirStretchPer1000CmPerSecond<public>:float = 0.15
    # Maximum vertical stretch in the air. Default 0.25
    @editable_number(float):
        ToolTip := LookAirStretchMaxToolTip
        Categories := array{CharacterLookCategory}
        MinValue := option{0.0}
        MaxValue := option{2.0}
    AirStretchMax<public>:float = 0.25
    # Vertical bob while running (one side). Default 0.04
    @editable_number(float):
        ToolTip := LookRunBobAmountToolTip
        Categories := array{CharacterLookCategory}
        MinValue := option{0.0}
        MaxValue := option{0.5}
    RunBobAmount<public>:float = 0.04
    # Distance traveled per bob cycle (cm). Default 160
    @editable_number(float):
        ToolTip := LookRunBobStrideToolTip
        Categories := array{CharacterLookCategory}
        MinValue := option{10.0}
        MaxValue := option{10000.0}
    RunBobStrideCm<public>:float = 160.0
    # Horizontal speed at which bob and lean are strongest (cm/s). Default 600
    @editable_number(float):
        ToolTip := LookRunFullSpeedToolTip
        Categories := array{CharacterLookCategory}
        MinValue := option{1.0}
        MaxValue := option{20000.0}
    RunFullSpeedCmPerSecond<public>:float = 600.0
    # Maximum lean toward the travel direction while running (degrees). Default 5
    @editable_number(float):
        ToolTip := LookRunLeanToolTip
        Categories := array{CharacterLookCategory}
        MinValue := option{0.0}
        MaxValue := option{45.0}
    RunLeanDegrees<public>:float = 5.0
    # Breathing amount while still (one side). Default 0.025
    @editable_number(float):
        ToolTip := LookIdleBreathAmountToolTip
        Categories := array{CharacterLookCategory}
        MinValue := option{0.0}
        MaxValue := option{0.5}
    IdleBreathAmount<public>:float = 0.025
    # Seconds per breathing cycle. Default 2.4
    @editable_number(float):
        ToolTip := LookIdleBreathSecondsToolTip
        Categories := array{CharacterLookCategory}
        MinValue := option{0.1}
        MaxValue := option{60.0}
    IdleBreathSeconds<public>:float = 2.4

    # Seconds per spring step (long frames are advanced in slices. Stays stable with stiff springs / strong damping)
    SpringStepSeconds<private>:float = 0.008
    # Maximum spring seconds advanced per frame (no jumps on a long, hitched frame)
    MaxSpringSeconds<private>:float = 0.1
    # Speed at which the lean approaches its target (fraction per second)
    LeanResponse<private>:float = 10.0
    # Seconds before the next HitWall deformation is accepted (it arrives every frame while pressed against a wall)
    HitWallCooldownSeconds<private>:float = 0.3
    # Lower / upper bounds of the per-axis factor (no inversion when the spring overshoots)
    MinAxisScale<private>:float = 0.2
    MaxAxisScale<private>:float = 3.0

    var<private> Motor:?character_motor_component = false
    var<private> Subscriptions:[]cancelable = array{}
    # Base shape of shell and core (local transforms read one frame after start). false before reading and after stopping
    var<private> ShellBase:?transform = false
    var<private> CoreBase:?transform = false
    # Current factors (spring position. Forward, left, up) and their rate of change
    var<private> Deform:vector3 = vector3{Forward := 1.0, Left := 1.0, Up := 1.0}
    var<private> DeformVelocity:vector3 = vector3{}
    # Shape held by Pulse and the seconds left
    var<private> HoldShape:vector3 = vector3{Forward := 1.0, Left := 1.0, Up := 1.0}
    var<private> HoldLeftSeconds:float = 0.0
    # Lean (horizontal vector in the orientation of the shell's parent. Direction = lean direction, length = degrees)
    var<private> Lean:vector3 = vector3{}
    var<private> ElapsedSeconds:float = 0.0
    var<private> BobPhase:float = 0.0
    # Previous frame's velocity (in the orientation of the shell's parent). Used for the direction and speed before hitting a wall
    var<private> LastLocalVelocity:vector3 = vector3{}
    var<private> LastHitWallAt:float = -1000.0

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := Entity.FindCharacterMotorAbove[]):
            set Motor = option{Found}
        else:
            Print("[character_squash_stretch_component] character_motor_component not found (place it on the body entity or a descendant)")

    # The base shape of shell and core is read one frame after start, and only then does the animation begin
    #   Inside OnBeginSimulation, the prefab's children may not be in the scene yet and may not follow when moved (UEFN v43.00: same as the body's SpawnAtOwner)
    OnSimulate<override>()<suspends>:void =
        Sleep(0.0)
        Start()

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        RestoreBase()
        (super:)OnEndSimulation()

    # Adds a preset deformation (amounts are this component's @editable values). May be called from game code independently of the body's motion events
    Pulse<public>(Kind:character_look_pulse):void =
        case (Kind):
            character_look_pulse.Jump => PulseShape(JumpScale, PulseHoldSeconds)
            character_look_pulse.AirJump => PulseShape(AirJumpScale, PulseHoldSeconds)
            character_look_pulse.Land => PulseLanding((LandMinSpeedCmPerSecond + LandFullSpeedCmPerSecond) * 0.5)
            character_look_pulse.Dash => PulseShape(DirectionalShape(GetTravelDirection(), DashStretch), DashHoldSeconds)
            character_look_pulse.HitWall => PulseShape(DirectionalShape(FlatOf(LastLocalVelocity), -HitWallSquash), PulseHoldSeconds)

    # Squashes as if landing at downward speed SpeedCmPerSecond (cm/s) (does nothing if slower than LandMinSpeedCmPerSecond)
    PulseLanding<public>(SpeedCmPerSecond:float):void =
        Range := Max(LandFullSpeedCmPerSecond - LandMinSpeedCmPerSecond, 1.0)
        Ratio := Clamp((SpeedCmPerSecond - LandMinSpeedCmPerSecond) / Range, 0.0, 1.0)
        if (Ratio > 0.0):
            Neutral := vector3{Forward := 1.0, Left := 1.0, Up := 1.0}
            PulseShape(Neutral + (LandSquashScale - Neutral) * Ratio, PulseHoldSeconds)

    # Squashes vertically (Amount 0..0.8. 0.35 gives 0.65x height, 1.24x width). Negative stretches vertically (-0.3 gives 1.3x height, 0.88x width). Springs back
    Squash<public>(Amount:float):void =
        PulseShape(VerticalShape(1.0 - Clamp(Amount, -2.0, 0.8)), PulseHoldSeconds)

    # Snaps the shell's scale factors to Shape (forward, left, up. 1 keeps the base), holds for HoldSeconds, then springs back (with PreserveVolume, volume is normalized when applied)
    #   Shape's axes are the shell's axes (forward, left, up of the shell's base rotation). Successive calls replace the previous one
    PulseShape<public>(Shape:vector3, HoldSeconds:float):void =
        Safe := ClampShape(Shape)
        set Deform = Safe
        set DeformVelocity = vector3{}
        set HoldShape = Safe
        set HoldLeftSeconds = Max(HoldSeconds, 0.0)

    # The factors currently applied to the shell's base scale (forward, left, up. After normalizing with PreserveVolume)
    GetDeformation<public>()<reads>:vector3 =
        NormalizeVolume(Deform)

    Start<private>():void =
        if (Found := Motor?):
            if (ShellEntity := Shell?):
                set ShellBase = option{ShellEntity.GetLocalTransform()}
                if (CoreEntity := Core?):
                    set CoreBase = option{CoreEntity.GetLocalTransform()}
                    if (not HaveSameParent[ShellEntity, CoreEntity]):
                        Print("[character_squash_stretch_component] Core is not a child of the same parent as Shell (the core will drift from the center of the shell)")
                else:
                    Print("[character_squash_stretch_component] Core is empty (only the shell will squash and stretch)")
                set Subscriptions += array{Found.PostMoveEvent.Subscribe(OnPostMove), Found.ActionEvent.Subscribe(OnAction), Found.LandedEvent.Subscribe(OnLanded)}
            else:
                Print("[character_squash_stretch_component] Shell is empty (doing nothing)")

    # Restores shell and core to the base shape and clears the deformation
    RestoreBase<private>():void =
        if (ShellEntity := Shell?, Base := ShellBase?):
            ShellEntity.SetLocalTransform(Base)
        if (CoreEntity := Core?, Base := CoreBase?):
            CoreEntity.SetLocalTransform(Base)
        set ShellBase = false
        set CoreBase = false
        set Deform = vector3{Forward := 1.0, Left := 1.0, Up := 1.0}
        set DeformVelocity = vector3{}
        set HoldLeftSeconds = 0.0
        set Lean = vector3{}

    OnAction<private>(Action:character_action):void =
        if (Action = character_action.Jumped):
            Pulse(character_look_pulse.Jump)
        else if (Action = character_action.AirJumped):
            Pulse(character_look_pulse.AirJump)
        else if (Action = character_action.Dashed):
            Pulse(character_look_pulse.Dash)
        else if (Action = character_action.HitWall):
            # Arrives every frame while pressed against a wall, so only on a fast hit and with a gap in between
            if (HitWallSquash > 0.0, ElapsedSeconds - LastHitWallAt >= HitWallCooldownSeconds, FlatOf(LastLocalVelocity).Length() >= HitWallMinSpeedCmPerSecond):
                set LastHitWallAt = ElapsedSeconds
                Pulse(character_look_pulse.HitWall)

    OnLanded<private>(SpeedCmPerSecond:float):void =
        PulseLanding(SpeedCmPerSecond)

    OnPostMove<private>(DeltaTime:float):void =
        if (Found := Motor?, ShellEntity := Shell?, Base := ShellBase?, DeltaTime > 0.0):
            set ElapsedSeconds += DeltaTime
            LocalVelocity := ToShellParent(ShellEntity, Found.GetVelocity())
            Grounded := logic{Found.IsGrounded[]}
            if (Grounded?):
                set BobPhase += 2.0 * PiFloat * FlatOf(LocalVelocity).Length() * DeltaTime / Max(RunBobStrideCm, 1.0)
                if (BobPhase > 2.0 * PiFloat):
                    set BobPhase -= 2.0 * PiFloat
            Target := if (HoldLeftSeconds > 0.0) then HoldShape else StateShape(LocalVelocity, Grounded)
            set HoldLeftSeconds = Max(HoldLeftSeconds - DeltaTime, 0.0)
            StepSpring(Target, DeltaTime)
            UpdateLean(LocalVelocity, Grounded, DeltaTime)
            set LastLocalVelocity = LocalVelocity
            Apply(ShellEntity, Base)

    # Shape (target) for the current state: on the ground, breathing and run bob blended by speed; in the air, vertical stretch by vertical speed
    StateShape<private>(LocalVelocity:vector3, Grounded:logic)<reads>:vector3 =
        if (Grounded?):
            Run := Clamp(FlatOf(LocalVelocity).Length() / Max(RunFullSpeedCmPerSecond, 1.0), 0.0, 1.0)
            Breath := IdleBreathAmount * Sin(2.0 * PiFloat * ElapsedSeconds / Max(IdleBreathSeconds, 0.1))
            Bob := RunBobAmount * Sin(BobPhase)
            VerticalShape(1.0 + Breath * (1.0 - Run) + Bob * Run)
        else:
            Stretch := Min(Abs(LocalVelocity.Up) * AirStretchPer1000CmPerSecond / 1000.0, AirStretchMax)
            VerticalShape(1.0 + Stretch)

    # Advances the spring (per axis) by DeltaTime seconds, moving the factors toward Target. In slices of SpringStepSeconds
    StepSpring<private>(Target:vector3, DeltaTime:float):void =
        var Remaining:float = Min(DeltaTime, MaxSpringSeconds)
        loop:
            if (Remaining <= 0.0):
                break
            Step := Min(Remaining, SpringStepSeconds)
            Acceleration := (Target - Deform) * SpringStiffness - DeformVelocity * SpringDamping
            set DeformVelocity = DeformVelocity + Acceleration * Step
            set Deform = ClampShape(Deform + DeformVelocity * Step)
            set Remaining -= Step

    # While running on the ground, leans toward the travel direction with speed (RunLeanDegrees at RunFullSpeedCmPerSecond). Returns to zero in the air or when still
    UpdateLean<private>(LocalVelocity:vector3, Grounded:logic, DeltaTime:float):void =
        Flat := FlatOf(LocalVelocity)
        Speed := Flat.Length()
        Target := if (Grounded?, Speed > 1.0) then Flat * (Min(Speed / Max(RunFullSpeedCmPerSecond, 1.0), 1.0) * RunLeanDegrees / Speed) else vector3{}
        set Lean = Lean + (Target - Lean) * Min(DeltaTime * LeanResponse, 1.0)

    # Writes the local transforms of shell and core
    #   Shell: origin (feet) unchanged, scale = base scale x factors, rotation = base rotation then lean (leans around the feet)
    #   Core: the core's center in the base shape, measured from the shell's origin along the shell's axes, is moved by the same factors and leaned the same way (ends up at the center of the deformed shell)
    Apply<private>(ShellEntity:entity, Base:transform):void =
        Shape := NormalizeVolume(Deform)
        Tilt := LeanRotation()
        ShellEntity.SetLocalTransform(transform{Translation := Base.Translation, Rotation := Base.Rotation * Tilt, Scale := ScaleEach(Base.Scale, Shape)})
        if (CoreEntity := Core?, CoreStart := CoreBase?):
            StartCenter := CoreStart.Translation + CorePivotToCenter(CoreStart.Rotation, CoreStart.Scale)
            InShell := (StartCenter - Base.Translation) * Base.Rotation.Invert()
            MovedCenter := Base.Translation + (ScaleEach(InShell, Shape) * Base.Rotation) * Tilt
            Neutral := vector3{Forward := 1.0, Left := 1.0, Up := 1.0}
            CoreScale := ScaleEach(CoreStart.Scale, Neutral + (Shape - Neutral) * CoreDeformRatio)
            CoreRotation := CoreStart.Rotation * Tilt
            CoreEntity.SetLocalTransform(transform{Translation := MovedCenter - CorePivotToCenter(CoreRotation, CoreScale), Rotation := CoreRotation, Scale := CoreScale})

    # Offset from the core mesh's origin to its center (in the orientation of the shell's parent). 0 if the origin is the center
    CorePivotToCenter<private>(Rotation:rotation, Scale:vector3)<reads>:vector3 =
        if (MeshPivotAtBottom?) then vector3{Up := MeshHeightCm * 0.5 * Scale.Up} * Rotation else vector3{}

    # Rotation for the lean Lean (direction and degrees). A rotation that tips the up axis toward Lean's direction (the sign is checked by rotating the up axis)
    LeanRotation<private>()<reads>:rotation =
        Degrees := Lean.Length()
        if (Degrees < 0.01):
            return IdentityRotation()
        Direction := Lean / Degrees
        Axis := vector3{Forward := -Direction.Left, Left := Direction.Forward}
        Candidate := MakeRotationDegrees(Axis, Degrees)
        if (DotProduct(vector3{Up := 1.0} * Candidate, Direction) >= 0.0) then Candidate else MakeRotationDegrees(Axis, -Degrees)

    # Shape scaled by 1 + Amount (negative shrinks) toward Direction in the orientation of the shell's parent
    #   Direction is split into the shell's axes (forward, left, up of the base rotation) and each axis is stretched by the square of its share (a direction along an axis stretches that axis only). Without a direction, toward the shell's forward
    DirectionalShape<private>(Direction:vector3, Amount:float)<reads>:vector3 =
        DirectionCm := Direction.Length()
        if (DirectionCm < 0.001):
            return vector3{Forward := 1.0 + Amount, Left := 1.0, Up := 1.0}
        Unit := Direction / DirectionCm
        InShell := if (Base := ShellBase?) then Unit * Base.Rotation.Invert() else Unit
        vector3:
            Forward := 1.0 + Amount * InShell.Forward * InShell.Forward
            Left := 1.0 + Amount * InShell.Left * InShell.Left
            Up := 1.0 + Amount * InShell.Up * InShell.Up

    # Current horizontal travel direction (in the orientation of the shell's parent). The body's velocity, or the previous frame's velocity when still
    GetTravelDirection<private>()<transacts>:vector3 =
        if (Found := Motor?, ShellEntity := Shell?):
            Now := FlatOf(ToShellParent(ShellEntity, Found.GetVelocity()))
            if (Now.Length() > 1.0) then Now else FlatOf(LastLocalVelocity)
        else:
            FlatOf(LastLocalVelocity)

    # Shape with Up vertically and a horizontal factor that keeps the volume (1 / sqrt(Up))
    VerticalShape<private>(Up:float)<reads>:vector3 =
        Safe := Clamp(Up, MinAxisScale, MaxAxisScale)
        Side := 1.0 / Sqrt(Safe)
        vector3{Forward := Side, Left := Side, Up := Safe}

    # Clamps the per-axis factors to MinAxisScale..MaxAxisScale
    ClampShape<private>(Shape:vector3)<reads>:vector3 =
        vector3:
            Forward := Clamp(Shape.Forward, MinAxisScale, MaxAxisScale)
            Left := Clamp(Shape.Left, MinAxisScale, MaxAxisScale)
            Up := Clamp(Shape.Up, MinAxisScale, MaxAxisScale)

    # With PreserveVolume, normalizes so the product of the three axes is 1
    NormalizeVolume<private>(Shape:vector3)<reads>:vector3 =
        Product := Shape.Forward * Shape.Left * Shape.Up
        if (PreserveVolume?, Product > 0.0001):
            Shape * Pow(Product, -1.0 / 3.0)
        else:
            Shape

    # Converts a world-space vector to the orientation of the shell's parent (unchanged if there is no parent)
    ToShellParent<private>(ShellEntity:entity, World:vector3)<transacts>:vector3 =
        if (Parent := ShellEntity.GetParent[]) then World * Parent.GetGlobalTransform().Rotation.Invert() else World

# Succeeds if A and B are children of the same parent (fails if neither has a parent)
HaveSameParent<internal>(A:entity, B:entity)<decides><transacts>:void =
    A.GetParent[] = B.GetParent[]

# Horizontal part of V (vertical set to 0)
FlatOf<internal>(V:vector3)<computes>:vector3 =
    vector3{Forward := V.Forward, Left := V.Left}

# Per-axis product of A and B
ScaleEach<internal>(A:vector3, B:vector3)<computes>:vector3 =
    vector3{Forward := A.Forward * B.Forward, Left := A.Left * B.Left, Up := A.Up * B.Up}
