using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }

# Role: makes one player's view a camera orbiting a chosen point (Pivot) (overview map, looking over the stage, photo mode, etc.). Code can change rotation and distance at any time
#   Attach creates a camera entity as a child of Parent and adds it to that player's camera_director_component with Priority. Detach removes and destroys it (the view returns to the previous camera, e.g. the custom character's camera)
#   Rotation: YawDegrees turns left seen from above (0 faces the world's Forward, 90 faces Left. Right-handed, as MakeRotationDegrees), PitchDegrees negative looks down (clamped to MinPitchDegrees..MaxPitchDegrees)
#   The camera is placed DistanceCm from Pivot opposite to the view direction, with Pivot at the center of the screen. No roll (the top of the screen is the sky side)
#   FitDistanceCm: the distance at which all points fit on screen with the current rotation (pass it to SetOrbit to show everything)
#   Positions of markers overlaid on the screen come from WidgetSystem's PointerKit (ProjectToScreenRatio of a widget_screen_projection made with MakeScreenProjectionInView(GetTransform(), FieldOfViewDegrees))
# Placement: not a component (created in code with MakePlayerOrbitCamera). One per player
# Requirements / notes: uses the @experimental camera API (perspective_camera_component, camera_director_component), so the island cannot be published. The camera entity looks along Forward with Up as the top of the screen
#   There is a known issue on v43.00 play servers where camera_director_component is not found. Attach then returns false (the view is unchanged)
# ⚠ Unverified: whether a camera moved with SetGlobalTransform every frame renders smoothly. How the view returns to the previous camera after detaching (transition blend)
player_orbit_camera<public> := class<internal>:
    # The player whose view changes
    Player<public>:player
    # Horizontal field of view at 16:9 (degrees)
    FieldOfViewDegrees<public>:float
    # Priority over other cameras (higher wins. The custom character camera character_camera_component defaults to 10)
    Priority<public>:int
    # Range of the vertical rotation (degrees. Negative looks down)
    MinPitchDegrees<public>:float
    MaxPitchDegrees<public>:float

    var<private> Pivot:vector3 = vector3{}
    var<private> YawDegrees:float = 0.0
    var<private> PitchDegrees:float = -45.0
    var<private> DistanceCm:float = 1000.0
    var<private> CameraEntity:?entity = false
    var<private> Handle:?cancelable = false

    # Creates a camera entity as a child of Parent (position and rotation from the current Pivot, rotation and distance), waits one frame, then adds it to Player's camera_director_component. true if added
    #   If already added, does nothing and returns true. The camera entity disappears together with Parent
    Attach<public>(Parent:entity)<suspends>:logic =
        if (Handle?):
            return true
        Camera := entity{}
        Lens := perspective_camera_component{Entity := Camera}
        set Lens.FieldOfView = Clamp(FieldOfViewDegrees, 1.0, 179.0) * PiFloat / 180.0
        Camera.AddComponents(array{Lens})
        Parent.AddEntities(array{Camera})
        Camera.SetGlobalTransform(GetTransform())
        set CameraEntity = option{Camera}
        # Add after entering the scene (modifiers stacked on a camera before it entered had no effect: CharacterSystem's character_camera_component, UEFN v43.00)
        Sleep(0.0)
        if (not CameraEntity?):
            return false
        # A SetGlobalTransform before entering the scene is sometimes treated as an offset from the parent, so place it again after entering
        Apply()
        Directors := for (Director : Player.FindDescendantComponents(camera_director_component)):
            Director
        if (Director := Directors[0], Added := Director.AddCamera[Lens, Priority]):
            set Handle = option{Added}
            true
        else:
            Print("[player_orbit_camera] the player's camera_director_component was not found or the camera could not be added ({Directors.Length} directors)")
            Detach()
            false

    # Removes and destroys the camera (the view returns to the previous camera). Does nothing if not added
    Detach<public>():void =
        if (Current := Handle?):
            Current.Cancel()
        set Handle = false
        if (Current := CameraEntity?):
            Current.RemoveFromParent()
        set CameraEntity = false

    # Succeeds while added
    IsAttached<public>()<decides><transacts>:void =
        Handle?

    # Changes orbit center, rotation and distance at once (Pitch is clamped to the range. Distance is at least 1 cm)
    SetOrbit<public>(InPivot:vector3, InYawDegrees:float, InPitchDegrees:float, InDistanceCm:float):void =
        set Pivot = InPivot
        set YawDegrees = WrapDegrees(InYawDegrees)
        set PitchDegrees = Clamp(InPitchDegrees, MinPitchDegrees, MaxPitchDegrees)
        set DistanceCm = Max(InDistanceCm, 1.0)
        Apply()

    # Rotates by (DeltaYaw, DeltaPitch) degrees (Pitch is clamped to the range)
    RotateBy<public>(DeltaYawDegrees:float, DeltaPitchDegrees:float):void =
        SetOrbit(Pivot, YawDegrees + DeltaYawDegrees, PitchDegrees + DeltaPitchDegrees, DistanceCm)

    # Changes only the distance
    SetDistance<public>(InDistanceCm:float):void =
        SetOrbit(Pivot, YawDegrees, PitchDegrees, InDistanceCm)

    GetPivot<public>()<transacts>:vector3 = Pivot
    GetYawDegrees<public>()<transacts>:float = YawDegrees
    GetPitchDegrees<public>()<transacts>:float = PitchDegrees
    GetDistanceCm<public>()<transacts>:float = DistanceCm

    # Current rotation (no roll). Forward is the view direction
    GetRotation<public>()<transacts>:rotation =
        OrbitRotation(YawDegrees, PitchDegrees)

    # Current camera position and rotation (world)
    GetTransform<public>()<transacts>:transform =
        Rotation := GetRotation()
        transform:
            Translation := Pivot - Rotation.GetForwardAxis() * DistanceCm
            Rotation := Rotation
            Scale := vector3{Forward := 1.0, Left := 1.0, Up := 1.0}

    # With the current Pivot and rotation, the nearest distance (cm, at least MinDistanceCm) at which all Points are on screen (inside the edge by 1 / MarginRatio)
    #   AspectRatio is screen width / height (default 16:9). The vertical field of view follows from FieldOfViewDegrees at 16:9 (the rule of perspective_camera_component)
    FitDistanceCm<public>(Points:[]vector3, ?MarginRatio:float = 1.1, ?AspectRatio:float = 1.7777778, ?MinDistanceCm:float = 100.0)<transacts>:float =
        Rotation := GetRotation()
        Forward := Rotation.GetForwardAxis()
        Left := Rotation.GetLeftAxis()
        Up := Rotation.GetUpAxis()
        TanV := Tan(Clamp(FieldOfViewDegrees, 1.0, 179.0) * PiFloat / 360.0) * 9.0 / 16.0
        TanH := TanV * Max(AspectRatio, 0.1)
        Margin := Max(MarginRatio, 1.0)
        var Needed:float = MinDistanceCm
        for (Point : Points):
            Offset := Point - Pivot
            Depth := DotProduct(Offset, Forward)
            # Horizontally and vertically, the distance at which |offset| / (distance + depth) <= tan / Margin
            set Needed = Max(Needed, Abs(DotProduct(Offset, Left)) * Margin / TanH - Depth)
            set Needed = Max(Needed, Abs(DotProduct(Offset, Up)) * Margin / TanV - Depth)
        Needed

    # Moves the camera entity to the current position and rotation
    Apply<private>():void =
        if (Camera := CameraEntity?):
            Camera.SetGlobalTransform(GetTransform())

# Creates a camera that rotates Player's view (not added yet. Set the rotation with SetOrbit, then Attach)
#   FieldOfViewDegrees is the horizontal field of view at 16:9 (degrees), Priority the priority over other cameras, Min / MaxPitchDegrees the range of the vertical rotation (negative looks down)
MakePlayerOrbitCamera<public>(Player:player, ?FieldOfViewDegrees:float = 60.0, ?Priority:int = 100, ?MinPitchDegrees:float = -89.0, ?MaxPitchDegrees:float = 89.0):player_orbit_camera =
    player_orbit_camera:
        Player := Player
        FieldOfViewDegrees := FieldOfViewDegrees
        Priority := Priority
        MinPitchDegrees := Min(MinPitchDegrees, MaxPitchDegrees)
        MaxPitchDegrees := Max(MinPitchDegrees, MaxPitchDegrees)

# Rotation without roll for (Yaw turning left seen from above, Pitch positive looking up. Degrees). Pitch first (around the world's Left axis), then Yaw (around the world's Up axis)
OrbitRotation<internal>(YawDegrees:float, PitchDegrees:float)<transacts>:rotation =
    # A positive turn around the Left axis tips Forward downward (right-handed), so the sign is flipped to make looking up positive
    MakeRotationDegrees(vector3{Left := 1.0}, -PitchDegrees) * MakeRotationDegrees(vector3{Up := 1.0}, YawDegrees)

# Wraps an angle into -180..180 degrees (0 for a non-number)
WrapDegrees<internal>(Degrees:float)<transacts>:float =
    if (Turns := Floor[(Degrees + 180.0) / 360.0]) then Degrees - 360.0 * Turns else 0.0
