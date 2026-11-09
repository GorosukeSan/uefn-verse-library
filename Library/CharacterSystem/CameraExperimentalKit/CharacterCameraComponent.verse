using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/SceneGraphCameras }
using { CharacterSystem }
using { CharacterSystem.TooltipKit }

# Camera projection
character_camera_projection<public> := enum:
    # Projection with perspective (3D)
    Perspective
    # Projection without perspective (2D, top-down)
    Orthographic

# How the camera moves
character_camera_rig<public> := enum:
    # The owner can orbit around the character with the view input (mouse, right stick) (fort_orbit_camera_modifier)
    Orbit
    # Follows the character at a fixed position and rotation (OffsetCm, YawDegrees, PitchDegrees. Side-scrollers, etc.)
    Fixed

# Role: makes the owner's view a camera showing the custom character. Creates a camera entity as a child of this entity and adds it to the owner's camera_director_component with Priority. Removes and destroys it when stopped
#   Rig = Orbit (default): with fort_orbit_camera_modifier the owner can orbit around the character with the view input (OrbitDistanceCm, OrbitHeightCm, OrbitCollision). The walking direction follows the view with character_walk_component's Space = View
#   Rig = Fixed: the camera follows as a child of this entity at the position / rotation given by OffsetCm, YawDegrees, PitchDegrees (not moved from Verse every frame). Placed on the same entity as character_face_movement_component, it turns along
# Placement: in the editor, attach to the custom character's entity (the same entity as character_motor_component)
# Requirements / notes: uses the @experimental camera API (camera_component, camera_director_component). The island cannot be published (VerseShare distributes it only to projects marked "include experimental")
# ⚠ Unverified: the positive direction of Yaw / Pitch. If the view faces the wrong way, adjust with YawDegrees / PitchDegrees
character_camera_component<public> := class<final_super>(component):

    # How the camera moves. Default Orbit (the owner can rotate it)
    @editable:
        ToolTip := CameraRigToolTip
        Categories := array{CharacterCameraCategory}
    Rig<public>:character_camera_rig = character_camera_rig.Orbit
    # Orbit: distance from the orbit center to the camera (cm). Default 600
    @editable_number(float):
        ToolTip := CameraOrbitDistanceToolTip
        Categories := array{CharacterCameraCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    OrbitDistanceCm<public>:float = 600.0
    # Orbit: height of the orbit center above the character's feet (cm). Default 150
    @editable_number(float):
        ToolTip := CameraOrbitHeightToolTip
        Categories := array{CharacterCameraCategory}
        MinValue := option{-1000.0}
        MaxValue := option{5000.0}
    OrbitHeightCm<public>:float = 150.0
    # Orbit: pull the camera closer so it does not clip into walls. Default off
    #   ⚠ In UEFN v43.00, turning it on pulled the camera back to the orbit center while grounded, giving first person (third person only while jumping. Cause unknown)
    @editable:
        ToolTip := CameraOrbitCollisionToolTip
        Categories := array{CharacterCameraCategory}
    OrbitCollision<public>:logic = false
    # Projection. Default Perspective
    @editable:
        ToolTip := CameraProjectionToolTip
        Categories := array{CharacterCameraCategory}
    Projection<public>:character_camera_projection = character_camera_projection.Perspective
    # Fixed: camera position (offset from the character's feet, cm). Default 600 behind, 250 up
    @editable:
        ToolTip := CameraOffsetToolTip
        Categories := array{CharacterCameraCategory}
    OffsetCm<public>:vector3 = vector3{Forward := -600.0, Up := 250.0}
    # Fixed: horizontal camera rotation (degrees). Default 0 (the character's front)
    @editable_number(float):
        ToolTip := CameraYawToolTip
        Categories := array{CharacterCameraCategory}
        MinValue := option{-360.0}
        MaxValue := option{360.0}
    YawDegrees<public>:float = 0.0
    # Fixed: vertical camera rotation (degrees. Negative looks down). Default -15
    @editable_number(float):
        ToolTip := CameraPitchToolTip
        Categories := array{CharacterCameraCategory}
        MinValue := option{-89.0}
        MaxValue := option{89.0}
    PitchDegrees<public>:float = -15.0
    # Horizontal field of view for the perspective projection (degrees). Default 90
    @editable_number(float):
        ToolTip := CameraFieldOfViewToolTip
        Categories := array{CharacterCameraCategory}
        MinValue := option{10.0}
        MaxValue := option{170.0}
    FieldOfViewDegrees<public>:float = 90.0
    # Length shown across the screen width in the orthographic projection (cm). Default 3000
    @editable_number(float):
        ToolTip := CameraOrthographicWidthToolTip
        Categories := array{CharacterCameraCategory}
        MinValue := option{100.0}
        MaxValue := option{100000.0}
    OrthographicWidthCm<public>:float = 3000.0
    # Priority over other cameras (higher wins). Default 10
    @editable_number(int):
        ToolTip := CameraPriorityToolTip
        Categories := array{CharacterCameraCategory}
        MinValue := option{0}
        MaxValue := option{1000}
    Priority<public>:int = 10

    var<private> CameraEntity:?entity = false
    var<private> PivotEntity:?entity = false
    var<private> CameraBody:?camera_component = false
    var<private> Owner:?player = false
    var<private> Handle:?cancelable = false
    var<private> OrbitHandle:?cancelable = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Motor := Entity.FindCharacterMotorAbove[], Found := Motor.FindOwner[]):
            set Owner = option{Found}
            CreateCamera()
        else:
            Print("[character_camera_component] no owning custom character found (place it inside a loadout, on the same entity as character_motor_component)")

    # Stack the modifier and add to the owner's director after the camera entity has entered the scene (one frame later).
    #   An Orbit stacked on a camera_component before it entered the scene had no effect and stayed first person from the body's position (UEFN v43.00)
    OnSimulate<override>()<suspends>:void =
        Sleep(0.0)
        if (Body := CameraBody?, Found := Owner?):
            Activate(Body, Found)

    # The camera entity created (fails if none). For diagnostics (reading the camera position / rotation)
    FindCameraEntity<public>()<decides><transacts>:entity = CameraEntity?

    # Whether the Orbit modifier could be stacked. For diagnostics
    HasOrbit<public>()<decides><transacts>:void = OrbitHandle?

    OnEndSimulation<override>():void =
        if (Current := OrbitHandle?):
            Current.Cancel()
        set OrbitHandle = false
        if (Current := Handle?):
            Current.Cancel()
        set Handle = false
        if (Current := CameraEntity?):
            Current.RemoveFromParent()
        set CameraEntity = false
        if (Current := PivotEntity?):
            Current.RemoveFromParent()
        set PivotEntity = false
        set CameraBody = false
        (super:)OnEndSimulation()

    CreateCamera<private>():void =
        Camera := entity{}
        if (Rig = character_camera_rig.Fixed):
            Camera.SetLocalTransform(transform{Translation := OffsetCm, Rotation := MakeRotationFromYawPitchRollDegrees(YawDegrees, PitchDegrees, 0.0), Scale := vector3{Forward := 1.0, Left := 1.0, Up := 1.0}})
        Body := MakeCamera(Camera)
        Camera.AddComponents(array{Body})
        Entity.AddEntities(array{Camera})
        set CameraEntity = option{Camera}
        set CameraBody = option{Body}
        if (Rig = character_camera_rig.Orbit):
            # The orbit center is not the feet but a child entity OrbitHeightCm above the feet.
            #   With the feet (body root) as center, the root sinks slightly into the floor while grounded, the camera collision starts inside the floor and the camera got pulled back to the feet (third person only while jumping, first person on landing. UEFN v43.00)
            Pivot := entity{}
            Pivot.SetLocalTransform(transform{Translation := vector3{Up := OrbitHeightCm}, Rotation := IdentityRotation(), Scale := vector3{Forward := 1.0, Left := 1.0, Up := 1.0}})
            Entity.AddEntities(array{Pivot})
            set PivotEntity = option{Pivot}

    Activate<private>(Body:camera_component, Found:player):void =
        Directors := for (Director : Found.FindDescendantComponents(camera_director_component)):
            Director
        if (Director := Directors[0], Added := Director.AddCamera[Body, Priority]):
            set Handle = option{Added}
            if (Rig = character_camera_rig.Orbit, Pivot := PivotEntity?):
                Orbit := fort_orbit_camera_modifier:
                    TargetEntity := Pivot
                    CameraDistanceCentimeters := OrbitDistanceCm
                    CameraHeightCentimeters := 0.0
                    EnableCollision := OrbitCollision
                # Stack on the camera's own CameraModifiers (Main layer). Stack after the camera entity has entered the scene (stacked before, it had no effect: UEFN v43.00)
                Stack := Body.CameraModifiers
                set OrbitHandle = option{Stack.AddModifier(Orbit, Stack.LastPosition)}
            Print("[character_camera_component] camera added (first of {Directors.Length} directors, priority {Priority}, Rig {if (Rig = character_camera_rig.Orbit) then "Orbit" else "Fixed"})")
        else:
            Print("[character_camera_component] the owner's camera_director_component was not found or the camera could not be added ({Directors.Length} directors)")

    MakeCamera<private>(Camera:entity):camera_component =
        case (Projection):
            character_camera_projection.Orthographic =>
                Ortho := orthographic_camera_component{Entity := Camera}
                set Ortho.OrthographicProjectionWidth = OrthographicWidthCm
                Ortho
            character_camera_projection.Perspective =>
                Perspective := perspective_camera_component{Entity := Camera}
                set Perspective.FieldOfView = FieldOfViewDegrees * PiFloat / 180.0
                Perspective
