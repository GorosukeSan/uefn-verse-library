using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Verse.org/Input/UI }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { /UnrealEngine.com/Temporary }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }

# Role: Virtual Pointer (on-screen cursor) sample. While running, adds TouchMapping to every player to show the pointer, turns the screen position of a click (the start of a PointerSelect press) into a ray with DeprojectViewportToWorld, and finds the hit location with FindSweepHits
#   (a) Prints the hit position (LUF, cm)
#   (b) With TeleportOnClick, teleports the player there
#   (c) With UseOverheadCamera, creates a perspective_camera_component CameraHeightCm straight above the player and adds it with camera_director_component.AddCamera (a top-down view makes the ground easier to click)
#   On stop, the Mapping and the camera are always removed
# Placement: attach to an empty entity in the editor. Place one player_manager_component in the scope (or the world)
# Try it: when the session starts (StartOnBegin), the pointer appears. Clicking the ground shows the hit position in the output log and on screen. With TeleportOnClick on, you teleport there. With UseOverheadCamera on, you look down from above
# When: with StartOnBegin true, from the start of the simulation. With false, from the activate signal (activated_event) to the deactivate signal (deactivated_event)
# Notifies: ClickedEvent (the player who clicked and the hit world position). Other components can subscribe to it to use the pointer
# Requirements / notes:
#   - The camera components are still @experimental in v43.00 (using them prevents publishing the island). UseOverheadCamera is off by default
#   - There is a known issue (v43.00) where camera_director_component is not found on play servers. When not found, it continues without a camera
#   - The ray starts at the camera's eye position, so hits on the player's own character are excluded
virtual_pointer_sample_component<public> := class<final_super>(component):

    # When on, starts from the start of the simulation. When off, waits for the activate signal
    @editable
    StartOnBegin<public>:logic = true

    # When on, teleports the player to the clicked location
    @editable
    TeleportOnClick<public>:logic = false

    # When on, adds a top-down camera straight above the player (@experimental)
    @editable
    UseOverheadCamera<public>:logic = false

    # Height of the top-down camera (cm)
    @editable
    CameraHeightCm<public>:float = 3000.0

    # Length of the ray that looks for the click target (cm)
    @editable
    MaxTraceDistanceCm<public>:float = 100000.0

    # Height to lift the teleport destination above the hit surface (cm)
    @editable
    LandingOffsetCm<public>:float = 100.0

    ClickedEventInternal<private><final>:event(tuple(agent, vector3)) = event(tuple(agent, vector3)){}

    # Fires with (the player who clicked, the hit world position) every time a click hits something (Await / Subscribe; cannot be Signaled from outside)
    ClickedEvent<public><final>:listenable(tuple(agent, vector3)) = MakeProxyListenable(ClickedEventInternal)

    Views<private>:player_view_set = player_view_set{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (StartOnBegin?):
            Activate()

    OnReceive<override>(SceneEvent:scene_event):logic =
        Views.HandleActivation(SceneEvent, Entity, CreateView)
        false

    OnEndSimulation<override>():void =
        Views.Deactivate()
        (super:)OnEndSimulation()

    # Show the pointer to everyone (late joiners too). Does nothing when already shown
    Activate<public>():void =
        Views.Activate(Entity, CreateView)

    # Remove everyone's pointer and camera
    Deactivate<public>():void =
        Views.Deactivate()

    # Succeeds while running
    IsActive<public>()<decides><transacts>:void =
        Views.IsActive[]

    CreateView<private>(ViewEntity:entity, Slot:player_slot_component):component =
        virtual_pointer_view_component{Entity := ViewEntity, Source := Self, Player := Slot.Player}

    # Called from the view
    NotifyClicked<internal>(Agent:agent, Position:vector3):void =
        ClickedEventInternal.Signal((Agent, Position))

# Role: one player's pointer. Adds TouchMapping, waits for clicks and casts the ray. The top-down camera is also created as a child of this entity (removed together with the view)
# Placement: created at runtime by virtual_pointer_sample_component (never placed in the editor)
virtual_pointer_view_component<public> := class<final_super>(component):

    Source<public>:virtual_pointer_sample_component
    Player<public>:player

    var<private> CameraEntity:?entity = false

    OnSimulate<override>()<suspends>:void =
        if (PlayerInput := GetPlayerInput[Player]):
            PlayerInput.AddInputMapping(TouchMapping)
            defer:
                PlayerInput.RemoveInputMapping(TouchMapping)
            if (Source.UseOverheadCamera?):
                CameraComponent := MakeOverheadCamera()
                if (Director := FindCameraDirector[], CameraHandle := Director.AddCamera[CameraComponent, 1000]):
                    defer:
                        CameraHandle.Cancel()
                    RunPointer(PlayerInput)
                else:
                    Print("[virtual_pointer_sample] Could not add the camera (no camera_director_component). Continuing without a camera", ?Duration := 6.0)
                    RunPointer(PlayerInput)
            else:
                RunPointer(PlayerInput)
        else:
            Print("[virtual_pointer_sample] Cannot get this player's input (player_input)")

    OnEndSimulation<override>():void =
        if (Camera := CameraEntity?):
            Camera.RemoveFromParent()
        set CameraEntity = false
        (super:)OnEndSimulation()

    RunPointer<private>(PlayerInput:player_input)<suspends>:void =
        Print("[virtual_pointer_sample] The pointer is shown. Click the ground", ?Duration := 6.0)
        loop:
            Clicked := PlayerInput.GetInputEvents(PointerSelect).BeginDetectEvent.Await()
            ScreenPosition := Clicked(1)
            Ray := Player.DeprojectViewportToWorld(ScreenPosition)
            if (Hit := FindHit[Ray]):
                Print("[virtual_pointer_sample] Hit position (cm): L={Hit.Left} U={Hit.Up} F={Hit.Forward}", ?Duration := 4.0)
                Source.NotifyClicked(Player, Hit)
                if (Source.TeleportOnClick?):
                    Teleport(Hit)
            else:
                Print("[virtual_pointer_sample] Nothing was hit at the click (screen position L={ScreenPosition.Left} U={ScreenPosition.Up})", ?Duration := 4.0)

    # Cast the ray and return the position of the nearest hit, excluding the player's own character
    FindHit<private>(Ray:deproject_results)<decides><transacts>:vector3 =
        var Best:?vector3 = false
        var BestDistance:float = Source.MaxTraceDistanceCm
        Start := transform{Translation := Ray.Origin, Rotation := IdentityRotation(), Scale := vector3{Forward := 1.0, Left := 1.0, Up := 1.0}}
        Probe := collision_sphere{Radius := 20.0}
        for (Hit : Entity.FindSweepHits(Ray.Direction * Source.MaxTraceDistanceCm, Start, Probe)):
            if (not IsOwnBody[Hit.TargetComponent.Entity], Hit.SourceHitDistance < BestDistance):
                set Best = option{Hit.ContactPosition}
                set BestDistance = Hit.SourceHitDistance
        Best?

    # Succeeds when HitEntity is the player (the player entity or the character entity) or a descendant of it
    IsOwnBody<private>(HitEntity:entity)<decides><transacts>:void =
        var Current:entity = HitEntity
        var Found:logic = false
        loop:
            if (Current = Player):
                set Found = true
                break
            if (FortCharacter := Player.GetFortCharacter[], CharacterEntity := FortCharacter.GetEntity[], Current = CharacterEntity):
                set Found = true
                break
            if (Parent := Current.GetParent[]):
                set Current = Parent
            else:
                break
        Found?

    Teleport<private>(Hit:vector3):void =
        Landing := Hit + vector3{Up := Source.LandingOffsetCm}
        if (FortCharacter := Player.GetFortCharacter[]):
            if (FortCharacter.TeleportTo[SpatialMath.FromVector3(Landing), SpatialMath.FromRotation(IdentityRotation())]):
                Print("[virtual_pointer_sample] Teleported", ?Duration := 3.0)
                PlaceCameraAbove(Landing)
            else:
                Print("[virtual_pointer_sample] Cannot teleport there (e.g. a place where you would get stuck)", ?Duration := 3.0)

    # Create the top-down camera entity as a child of this entity and place it straight above the player (the caller adds it to camera_director_component)
    MakeOverheadCamera<private>():perspective_camera_component =
        Camera := entity{}
        CameraComponent := perspective_camera_component{Entity := Camera}
        Camera.AddComponents(array{CameraComponent})
        Entity.AddEntities(array{Camera})
        set CameraEntity = option{Camera}
        if (FortCharacter := Player.GetFortCharacter[], CharacterEntity := FortCharacter.GetEntity[]):
            PlaceCameraAbove(CharacterEntity.GetGlobalTransform().Translation)
        CameraComponent

    # The player's camera_director_component (a descendant of the player entity). Fails when there is none (also fails because of the known issue on v43.00 play servers)
    FindCameraDirector<private>()<decides><transacts>:camera_director_component =
        first (Found : Player.FindDescendantComponents(camera_director_component)):
            Found

    # Place the top-down camera straight above Position, looking straight down
    PlaceCameraAbove<private>(Position:vector3)<transacts>:void =
        if (Camera := CameraEntity?):
            Camera.SetGlobalTransform(transform:
                Translation := Position + vector3{Up := Source.CameraHeightCm}
                Rotation := MakeRotationFromYawPitchRollDegrees(0.0, -90.0, 0.0)
                Scale := vector3{Forward := 1.0, Left := 1.0, Up := 1.0}
            )
