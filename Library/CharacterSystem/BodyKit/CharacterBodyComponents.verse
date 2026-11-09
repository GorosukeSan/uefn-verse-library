using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Input }
using { /Verse.org/Assets }
using { /Fortnite.com/Characters }
using { InputSystem }
using { MovementSystem }
using { PlayerSystem }
using { CharacterSystem }
using { CharacterSystem.MoveKit }
using { CharacterSystem.TooltipKit }

# Role: turns the character's facing (the body = horizontal facing of the character_motor_component entity) at TurnSpeedDegreesPerSecond. Where to face is decided by the side-input style (GetSideStyle) of the body's walk (character_walk_component on the body entity or a descendant)
#   Turn: toward the movement direction (unchanged while standing still). Also used when there is no walk
#     In the air (with AirFacesInput): toward walk's input direction (GetInputDirection). Unchanged without input (does not turn toward speed inherited from a moving floor or a knockback direction)
#   Strafe: toward the front of walk's walking direction (GetWalkFront. The view direction when Space = View). Turns while standing still too. Unchanged in SideView, which has no front
#   TankTurn: does nothing (walk turns with the side input)
#   Does not turn while input is locked by the body's LockInput
#   While clinging to a wall (ClingKit. The body's GetClingSurface = Wall), faces the wall regardless of style. While clinging to a ceiling, the rules above apply (airborne, so Turn faces the input direction)
# Placement: in the editor, attach to the same entity as character_motor_component (put the visual mesh as a child so it turns along)
# ⚠ Unverified: the positive direction of Yaw (left or right turn). If it faces backward, place the visual mesh rotated 180 degrees
character_face_movement_component<public> := class<final_super>(component):

    # Degrees turned per second. 0 faces instantly. Default 720
    @editable_number(float):
        ToolTip := FaceTurnSpeedToolTip
        Categories := array{CharacterBodyCategory}
        MinValue := option{0.0}
        MaxValue := option{100000.0}
    TurnSpeedDegreesPerSecond<public>:float = 720.0
    # When on, with Turn, in the air turn toward the input direction instead of the movement direction (unchanged without input). When off, toward the movement direction in the air too. Default on
    @editable:
        ToolTip := FaceAirFacesInputToolTip
        Categories := array{CharacterBodyCategory}
    AirFacesInput<public>:logic = true

    # Interval (seconds) between retries when walk is not found
    WalkSearchIntervalSeconds<private>:float = 1.0

    var<private> Motor:?character_motor_component = false
    var<private> Subscription:?cancelable = false
    var<private> CachedWalk:?character_walk_component = false
    var<private> NextWalkSearchAt:float = -1000.0

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := Entity.FindCharacterMotorAbove[]):
            set Motor = option{Found}
            set Subscription = option{Found.PostMoveEvent.Subscribe(OnPostMove)}

    OnEndSimulation<override>():void =
        if (Current := Subscription?):
            Current.Cancel()
        set Subscription = false
        (super:)OnEndSimulation()

    OnPostMove<private>(DeltaTime:float):void =
        # Do not turn while input is locked by the body's LockInput (so the facing does not follow the view or movement on the lobby / result screens)
        if (Found := Motor?, not Found.IsInputLocked[]):
            # While clinging to a wall (ClingKit), face the wall regardless of side-input style (on a ceiling, the usual rules below)
            if (Surface := Found.GetClingSurface[], Surface = character_cling_surface.Wall):
                Normal := Found.GetClingNormal()
                IntoWall := vector3{Forward := -Normal.Forward, Left := -Normal.Left}
                if (IntoWall.Length() > 0.1):
                    TurnToward(Found, IntoWall, DeltaTime)
                return
            MaybeWalk := FindWalk(Found)
            Style := if (Walk := MaybeWalk?) then Walk.GetSideStyle() else character_side_style.Turn
            # When adding a value to character_side_style, add how to face here (no _ is written, so forgetting fails to compile)
            #   Turn: toward the movement direction. Strafe: toward the front of walk's walking direction. TankTurn: walk turns with the side input, so do not face (false)
            Target:?vector3 = case (Style):
                character_side_style.Turn => TurnDirection(Found, MaybeWalk)
                character_side_style.Strafe => WalkFrontDirection(MaybeWalk)
                character_side_style.TankTurn => false
            if (Direction := Target?):
                TurnToward(Found, Direction, DeltaTime)

    # Where Turn faces: on the ground, the movement direction. In the air (AirFacesInput with a walk), the input direction (false = unchanged without input)
    TurnDirection<private>(Found:character_motor_component, MaybeWalk:?character_walk_component)<transacts>:?vector3 =
        if (AirFacesInput?, not Found.IsGrounded[], Walk := MaybeWalk?):
            Input := Walk.GetInputDirection()
            if (Input.Length() > 0.1) then option{Input} else false
        else:
            MovementDirection(Found)

    # Horizontal movement direction (false = unchanged when still)
    MovementDirection<private>(Found:character_motor_component)<transacts>:?vector3 =
        Velocity := Found.GetVelocity()
        Horizontal := vector3{Forward := Velocity.Forward, Left := Velocity.Left}
        if (Horizontal.Length() > 1.0) then option{Horizontal} else false

    # Where Strafe faces: the front of walk's walking direction (false = unchanged without walk or in SideView, which has no front)
    WalkFrontDirection<private>(MaybeWalk:?character_walk_component)<transacts>:?vector3 =
        if (Walk := MaybeWalk?, Front := Walk.GetWalkFront(), Front.Length() > 0.5) then option{Front} else false

    # The body's walk (on the body entity or a descendant. FindCharacterWalk). Remembered once found; while missing, retried every WalkSearchIntervalSeconds
    FindWalk<private>(Found:character_motor_component):?character_walk_component =
        if (Cached := CachedWalk?, Cached.IsInScene[]):
            return option{Cached}
        set CachedWalk = false
        Now := GetSimulationElapsedTime()
        if (Now < NextWalkSearchAt):
            return false
        set NextWalkSearchAt = Now + WalkSearchIntervalSeconds
        if (Walk := Found.FindCharacterWalk[]):
            set CachedWalk = option{Walk}
        CachedWalk

    # Turns the body's horizontal facing toward Direction (horizontal) at TurnSpeedDegreesPerSecond (0 faces instantly)
    TurnToward<private>(Found:character_motor_component, Direction:vector3, DeltaTime:float):void =
        # ArcTan is "positive when turning left". The positive yaw direction of MakeRotationFromYawPitchRollDegrees is checked with the forward axis rotated 90 degrees and matched (YawSign, directly under CharacterSystem)
        #   (UEFN v43.00: passing it as is faced the opposite way when moving sideways = positive yaw turns right)
        Target := ArcTan(Direction.Left, Direction.Forward) * 180.0 / PiFloat * YawSign()
        Current := Found.Entity.GetGlobalTransform()
        Yaw := Current.Rotation.GetYawPitchRollDegrees()(0)
        Next := if (TurnSpeedDegreesPerSecond <= 0.0) then Target else StepAngle(Yaw, Target, TurnSpeedDegreesPerSecond * DeltaTime)
        # Do not rewrite if already facing (while standing still with Strafe, do not write the same facing every frame)
        if (Abs(Next - Yaw) < 0.01):
            return
        Found.Entity.SetGlobalTransform(transform{Translation := Current.Translation, Rotation := MakeRotationFromYawPitchRollDegrees(Next, 0.0, 0.0), Scale := Current.Scale})

# Angle (degrees) turned from From toward To along the shorter way, by at most MaxStep degrees
StepAngle<internal>(From:float, To:float, MaxStep:float)<transacts>:float =
    var Delta:float = To - From
    loop:
        if (Delta <= 180.0):
            break
        set Delta -= 360.0
    loop:
        if (Delta >= -180.0):
            break
        set Delta += 360.0
    if (Abs(Delta) <= MaxStep) then To else From + (if (Delta > 0.0) then MaxStep else -MaxStep)

# Role: while the custom character is running, pins the owner's Fortnite character in place with PutInStasis and hides it. Restores it when stopped
#   The custom character has its own physics, collision and movement and moves independently of the Fortnite character. The Fortnite character is neither moved nor made to follow (and there is no setting for that)
# Placement: in the editor, attach to the same entity as character_motor_component
# Requirements / notes: the owner's Fortnite character is excluded from the custom character's collision. While pinned, the Fortnite character's movement and view input have no effect (the custom character receives its input separately through input_action). Point the view at the custom character with CameraExperimentalKit's character_camera_component or similar
character_owner_stasis_component<public> := class<final_super>(component):

    # Re-pin when the Fortnite character has moved further than this from the pinned position (cm)
    ReparkDistanceCm<private>:float = 50.0

    var<private> Motor:?character_motor_component = false
    var<private> Subscription:?cancelable = false
    var<private> Parked:?fort_character = false
    # Position of the Fortnite character when pinned. Re-pin when it has moved away from here (e.g. pinned mid-spawn and then moved to a spawn pad)
    var<private> ParkedAt:vector3 = vector3{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := Entity.FindCharacterMotorAbove[]):
            set Motor = option{Found}
            set Subscription = option{Found.PostMoveEvent.Subscribe(OnPostMove)}
        else:
            Print("[character_owner_stasis_component] character_motor_component not found (place it on the same entity or an ancestor)")

    OnEndSimulation<override>():void =
        if (Current := Subscription?):
            Current.Cancel()
        set Subscription = false
        Release()
        (super:)OnEndSimulation()

    # The Fortnite character currently pinned (fails if none)
    FindParkedCharacter<public>()<decides><transacts>:fort_character = Parked?

    # Re-pin when the owner's Fortnite character changes (respawn, etc.). Only "is it the same character" is checked every frame
    OnPostMove<private>(DeltaTime:float):void =
        if (Found := Motor?, Owner := Found.FindOwner[], OwnerCharacter := Owner.GetFortCharacter[]):
            if (Current := Parked?, Current = OwnerCharacter):
                # Even for the same character, if it has moved away from the pinned position the pin is gone (UEFN v43.00: pinned mid-spawn, it could walk after being moved to the spawn pad)
                if (Body := OwnerCharacter.GetEntity[], Distance(Body.GetGlobalTransform().Translation, ParkedAt) > ReparkDistanceCm):
                    Park(OwnerCharacter)
            else:
                Release()
                Park(OwnerCharacter)

    # AllowTurning keeps the view input alive (Orbit camera, walking direction with Space = View). The body is hidden, so turning is not visible
    Park<private>(OwnerCharacter:fort_character):void =
        OwnerCharacter.PutInStasis(stasis_args{AllowTurning := true, AllowFalling := false, AllowEmotes := false})
        OwnerCharacter.Hide()
        set Parked = option{OwnerCharacter}
        if (Body := OwnerCharacter.GetEntity[]):
            set ParkedAt = Body.GetGlobalTransform().Translation

    Release<private>():void =
        if (Current := Parked?):
            Current.ReleaseFromStasis()
            Current.Show()
        set Parked = false

# Role: adds input mappings (input_mapping holding the custom character's button / direction inputs) to the owner and removes them when stopped
# Placement: in the editor, attach to the custom character's entity (the same entity as character_motor_component or a descendant). Place where there is an owner (inside a loadout)
# Requirements / notes: up to 2 mappings (asset arrays cannot be written through MCP, so one field each). For 3 or more, put another of this component on a child entity. Turn RemoveOnEnd on only for mappings dedicated to the custom character (removing a Fortnite mapping such as TraversalMapping disables other controls too)
character_input_mapping_component<public> := class<final_super>(component):

    # Input mapping to add (empty if unused)
    @editable:
        ToolTip := InputMappingsToolTip
        Categories := array{CharacterBodyCategory}
    Mapping<public>:?input_mapping = false
    # Second input mapping to add (empty if unused)
    @editable:
        ToolTip := InputMappingsToolTip
        Categories := array{CharacterBodyCategory}
    SecondMapping<public>:?input_mapping = false
    # When on, removed when stopped. Default on
    @editable:
        ToolTip := InputMappingsRemoveToolTip
        Categories := array{CharacterBodyCategory}
    RemoveOnEnd<public>:logic = true

    OnSimulate<override>()<suspends>:void =
        if (Owner := Entity.FindOwningPlayer[]):
            MaybeInput := Owner.AwaitPlayerInput()
            if (PlayerInput := MaybeInput?):
                Mappings := GetMappings()
                for (Each : Mappings):
                    PlayerInput.AddInputMapping(Each)
                defer:
                    if (RemoveOnEnd?):
                        for (Each : Mappings):
                            PlayerInput.RemoveInputMapping(Each)
                Sleep(Inf)
        else:
            Print("[character_input_mapping_component] no owner (place it where there is an owner, e.g. inside a loadout)")

    GetMappings<private>()<transacts>:[]input_mapping =
        var Result:[]input_mapping = array{}
        if (First := Mapping?):
            set Result += array{First}
        if (Second := SecondMapping?):
            set Result += array{Second}
        Result
