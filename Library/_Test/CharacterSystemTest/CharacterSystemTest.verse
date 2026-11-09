using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { CharacterSystem }
using { MovementSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { _Test }

# Role: test helper. Counts what happened to the custom character
test_character_action_counter<public> := class:
    var<private> Landed:int = 0

    OnAction<public>(Action:character_action):void =
        if (Action = character_action.Landed):
            set Landed += 1

    GetLandedCount<public>()<transacts>:int = Landed

# Role: verification of the CharacterSystem body (character_motor_component). Creates an ownerless body 3 m above and beside the player and checks that it falls under gravity and lands (IsGrounded, Landed, landing speed), that LockInput stacks and releases, that AxisLock keeps the sideways position, that SetVelocity moves it forward and that TeleportTo moves it
# Test level: one entity with player_manager_component and one entity with this component. Start with one player standing on a flat floor (the body falls onto the floor beside them)
# Result: [TEST] CharacterSystem in the output log
character_system_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "CharacterSystem"}
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
        if (Results.Finish[]) {}

    Run<private>(Results:test_log, Feet:vector3)<suspends>:void =
        Start := Feet + vector3{Forward := 300.0, Up := 300.0}
        Pawn := entity{}
        Pawn.SetGlobalTransform(MakeTranslationTransform(Start))
        Motor := character_motor_component{Entity := Pawn, AxisLock := character_axis_lock.Left, SpawnAtOwner := false}
        Pawn.AddComponents(array{Motor})
        Entity.AddEntities(array{Pawn})
        Counter := test_character_action_counter{}
        Subscription := Motor.ActionEvent.Subscribe(Counter.OnAction)

        Results.Check("no owner outside a slot", if (Motor.FindOwner[]) then false else true)
        Sleep(3.0)
        Results.Check("falls and becomes grounded", if (Motor.IsGrounded[]) then true else false)
        Results.CheckInt("Landed once", Counter.GetLandedCount(), 1)
        Landed := Pawn.GetGlobalTransform().Translation
        Results.Check("fell below the start", if (Landed.Up < Start.Up - 100.0) then true else false)
        # After a 3 m fall the landing speed is far above 100 cm/s (about 1370 cm/s with gravity 1960 x FallGravityMultiplier 1.6)
        Results.Check("landing speed recorded", if (Motor.GetLastLandingSpeed() > 100.0) then true else false)

        # LockInput: locked independently; input returns only when every lock is released
        FirstLock := Motor.LockInput()
        SecondLock := Motor.LockInput()
        Results.Check("input locked", if (Motor.IsInputLocked[]) then true else false)
        FirstLock.Cancel()
        FirstLock.Cancel()
        Results.Check("still locked by the other", if (Motor.IsInputLocked[]) then true else false)
        SecondLock.Cancel()
        Results.Check("unlocked after all canceled", if (Motor.IsInputLocked[]) then false else true)

        Motor.SetVelocity(vector3{Forward := 300.0, Left := 300.0})
        Sleep(0.5)
        Moved := Pawn.GetGlobalTransform().Translation
        Results.Check("moves forward with SetVelocity", if (Moved.Forward > Landed.Forward + 10.0) then true else false)
        Results.CheckFloat("AxisLock keeps Left", Moved.Left, Start.Left, 1.0)

        Motor.TeleportTo(Start)
        Teleported := Pawn.GetGlobalTransform().Translation
        Results.CheckFloat("TeleportTo moves", Teleported.Up, Start.Up, 1.0)
        Subscription.Cancel()
        Pawn.RemoveFromParent()
