using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { CharacterSystem }
using { CharacterSystem.SurfaceKit }
using { MovementSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { _Test }

# Role: test helper. Counts contacts (character_surface_contact)
test_surface_contact_counter<public> := class:
    var<private> Touched:int = 0
    var<private> Untouched:int = 0
    var<private> SteppedOn:int = 0
    var<private> SteppedOff:int = 0

    OnContact<public>(Payload:tuple(character_surface_component, character_surface_contact)):void =
        case (Payload(1)):
            character_surface_contact.Touched => set Touched += 1
            character_surface_contact.Untouched => set Untouched += 1
            character_surface_contact.SteppedOn => set SteppedOn += 1
            character_surface_contact.SteppedOff => set SteppedOff += 1

    GetTouched<public>()<transacts>:int = Touched
    GetUntouched<public>()<transacts>:int = Untouched
    GetSteppedOn<public>()<transacts>:int = SteppedOn
    GetSteppedOff<public>()<transacts>:int = SteppedOff

# Role: verification of CharacterSystem SurfaceKit (character_surface_component / character_touch_component / character_ride_component)
#   Creates an ownerless body (motor + touch + ride) 3 m above and beside the player, drops it onto the floor, and creates an invisible surface (a SizeCm box whose top = floor height) at the landing height
#   Checks stepping on (Touched, SteppedOn once, FindStandingSurface), that ride rides the floor it stands on (GetGroundEntity), that moving a surface without collision 150 cm forward does not carry the body, that SetActive(false) leaves / steps off (Untouched, SteppedOff), and that GetBox matches the size and rotation
# Test level: one entity with player_manager_component and one entity with this component. Start with one player standing on a flat floor (the body falls onto the floor beside them; a 5 m square of floor is needed 3 m ahead)
# Result: [TEST] CharacterSurface in the output log. About 5 seconds
character_surface_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "CharacterSurface"}
        TickEvents.PrePhysics.Await()
        if:
            Manager := Entity.FindScopedComponent[player_manager_component]
            Slot := Manager.GetSlots()[0]
            FortCharacter := Slot.Player.GetFortCharacter[]
            Feet := FortCharacter.FindGlobalTranslation[]
        then:
            Run(Results, Feet)
        else:
            Results.Fail("setup", "no player character")
        CheckBox(Results)
        if (Results.Finish[]) {}

    Run<private>(Results:test_log, Feet:vector3)<suspends>:void =
        Start := Feet + vector3{Forward := 300.0, Up := 300.0}
        Pawn := entity{}
        Pawn.SetGlobalTransform(MakeTranslationTransform(Start))
        Motor := character_motor_component{Entity := Pawn, SpawnAtOwner := false, ResetOnRoundStart := false}
        Touch := character_touch_component{Entity := Pawn, RefreshSeconds := 0.1}
        Ride := character_ride_component{Entity := Pawn}
        Pawn.AddComponents(array{Motor, Touch, Ride})
        Entity.AddEntities(array{Pawn})
        Counter := test_surface_contact_counter{}
        Subscription := Touch.ContactEvent.Subscribe(Counter.OnContact)
        Sleep(2.5)
        Results.Check("falls and becomes grounded", if (Motor.IsGrounded[]) then true else false)
        Landed := Pawn.GetGlobalTransform().Translation

        # invisible surface (400 x 400 x 100 cm) whose top is at floor height
        Pad := entity{}
        Pad.SetGlobalTransform(MakeTranslationTransform(Landed - vector3{Up := 100.0}))
        Surface := character_surface_component{Entity := Pad, SizeCm := vector3{Forward := 400.0, Left := 400.0, Up := 100.0}}
        Pad.AddComponents(array{Surface})
        Entity.AddEntities(array{Pad})
        Touch.SetSearchRoot(option{Entity})
        Sleep(0.5)
        Results.CheckInt("Touched once", Counter.GetTouched(), 1)
        Results.CheckInt("SteppedOn once", Counter.GetSteppedOn(), 1)
        Results.Check("FindStandingSurface", if (Standing := Touch.FindStandingSurface[], Standing = Surface) then true else false)
        Results.Check("IsTouching", if (Touch.IsTouching[Surface]) then true else false)

        # ride rides what the body stands on (the entity hit by the ground sweep = the stationary floor). Moving the collisionless surface box 150 cm forward does not carry the body
        #   Whether a moving floor (a mesh with collision) carries the body is not checked here (this test cannot create meshes); follow "Verifying" in the README and check in UEFN
        Results.Check("GetGroundEntity while grounded", if (Motor.GetGroundEntity[]) then true else false)
        Results.Check("ride tracks the ground entity", if (Riding := Ride.FindRidingEntity[], Ground := Motor.GetGroundEntity[], Riding = Ground) then true else false)
        Before := Pawn.GetGlobalTransform().Translation
        Pad.SetGlobalTransform(MakeTranslationTransform(Landed - vector3{Up := 100.0} + vector3{Forward := 150.0}))
        Sleep(0.3)
        After := Pawn.GetGlobalTransform().Translation
        Results.CheckFloat("ride ignores a moved box without collision", After.Forward - Before.Forward, 0.0, 5.0)
        Results.CheckFloat("ground velocity on a still floor", Motor.GetGroundVelocity().Length(), 0.0, 1.0)

        Surface.SetActive(false)
        Sleep(0.3)
        Results.CheckInt("Untouched once after SetActive(false)", Counter.GetUntouched(), 1)
        Results.CheckInt("SteppedOff once after SetActive(false)", Counter.GetSteppedOff(), 1)
        Results.Check("not standing after SetActive(false)", if (Touch.FindStandingSurface[]) then false else true)
        Subscription.Cancel()
        Pad.RemoveFromParent()
        Pawn.RemoveFromParent()

    # GetBox: a 2 x 1 x 3 mesh with its base at the origin (MeshSizeCm 100) rotated 90 degrees swaps front/back with left/right
    CheckBox<private>(Results:test_log):void =
        Box := entity{}
        Box.SetGlobalTransform(transform{Translation := vector3{Forward := 1000.0, Left := 0.0, Up := 500.0}, Rotation := MakeRotationFromYawPitchRollDegrees(90.0, 0.0, 0.0), Scale := vector3{Forward := 2.0, Left := 1.0, Up := 3.0}})
        Surface := character_surface_component{Entity := Box}
        Box.AddComponents(array{Surface})
        Value := Surface.GetBox()
        Results.CheckFloat("GetBox forward size (rotated)", Value.MaxCm.Forward - Value.MinCm.Forward, 100.0, 1.0)
        Results.CheckFloat("GetBox left size (rotated)", Value.MaxCm.Left - Value.MinCm.Left, 200.0, 1.0)
        Results.CheckFloat("GetBox bottom at pivot", Value.MinCm.Up, 500.0, 1.0)
        Results.CheckFloat("GetBox top", Value.MaxCm.Up, 800.0, 1.0)
