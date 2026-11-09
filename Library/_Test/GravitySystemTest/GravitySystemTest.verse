using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { GravitySystem }
using { MovementSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { _Test }

# Role: verification of GravitySystem. Checks that gravity_well_component pulls the player, that gravity_point_ability_component can be granted / revoked from code, Toggle (place / remove), expiry, and placing by human input
# Test level:
#   - one entity with player_manager_component
#   - the test entity carries only gravity_system_test_component (the point and the ability are created by the test at runtime)
#   - start the session in an open place with nothing 3 m above the player's head (the player is pulled upwards)
# Human input: when "press fire" appears, press the fire button within 30 seconds
# Result: [TEST] GravitySystem in the output log
gravity_system_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "GravitySystem"}
        MaybeAgent := AwaitFirstPlayer()
        if (Agent := MaybeAgent?):
            TestWellPull(Results, Agent)
            TestAbility(Results, Agent)
        else:
            Results.Fail("setup", "player_manager_component missing")
        if (Results.Finish[]) {}

    AwaitFirstPlayer<private>()<suspends>:?agent =
        if (Manager := Entity.FindScopedComponent[player_manager_component]):
            if (Slot := Manager.GetSlots()[0]):
                option{Slot.Player}
            else:
                Player := Manager.PlayerAddedEvent.Await()
                option{Player}
        else:
            false

    # Places a strong point 300 cm above the player and checks that the player rises by 50 cm or more within 1 second
    TestWellPull<private>(Results:test_log, Agent:agent)<suspends>:void =
        if (FortCharacter := Agent.GetFortCharacter[], Start := FortCharacter.FindGlobalTranslation[], SimulationEntity := Entity.GetSimulationEntity[]):
            WellEntity := entity{}
            WellEntity.AddComponents(array{gravity_well_component{Entity := WellEntity, RadiusCm := 1000.0, StrengthCmPerSecondSquared := 10000.0}})
            SimulationEntity.AddEntities(array{WellEntity})
            WellEntity.SetGlobalTransform(WellEntity.GetGlobalTransform().WithTranslation(Start + vector3{Up := 300.0}))
            defer:
                WellEntity.RemoveFromParent()
            Sleep(1.0)
            if (Now := FortCharacter.FindGlobalTranslation[]):
                Results.Check("gravity_well_component pulls the player up", if (Now.Up - Start.Up > 50.0) then true else false)
            else:
                Results.Fail("gravity_well_component pulls the player up", "character position not available")
        else:
            Results.Fail("gravity_well_component pulls the player up", "player character not available")

    TestAbility<private>(Results:test_log, Agent:agent)<suspends>:void =
        AbilityEntity := entity{}
        Ability := gravity_point_ability_component{Entity := AbilityEntity, DurationSeconds := 3.0, StrengthCmPerSecondSquared := 0.0}
        AbilityEntity.AddComponents(array{Ability})
        Entity.AddEntities(array{AbilityEntity})
        defer:
            Ability.RevokeAll()
            AbilityEntity.RemoveFromParent()
        TickEvents.PrePhysics.Await()

        Ability.Grant(Agent)
        Results.Check("Grant from code", if (Ability.IsGranted[Agent]) then true else false)
        Results.Check("no well at start", if (Ability.FindWell[Agent]) then false else true)
        Placed := spawn{AwaitWithin(Ability.PlacedEvent, 1.0)}
        Ability.Toggle(Agent)
        PlacedPayload := Placed.Await()
        Results.Check("Toggle places a well (PlacedEvent)", if (PlacedPayload?) then true else false)
        Results.Check("FindWell after placing", if (Ability.FindWell[Agent]) then true else false)
        Removed := spawn{AwaitWithin(Ability.RemovedEvent, 1.0)}
        Ability.Toggle(Agent)
        RemovedPayload := Removed.Await()
        Results.Check("Toggle again removes it (RemovedEvent)", if (RemovedPayload?) then true else false)
        Results.Check("no well after removing", if (Ability.FindWell[Agent]) then false else true)

        Ability.Toggle(Agent)
        Expired := AwaitWithin(Ability.RemovedEvent, 5.0)
        Results.Check("well expires after DurationSeconds", if (Expired?) then true else false)

        Print("[TEST] GravitySystem: press fire (WeaponPrimary) within 30 seconds")
        Pressed := AwaitWithin(Ability.PlacedEvent, 30.0)
        Results.Check("pressing fire places a well (manual)", if (Pressed?) then true else false)

        Ability.Revoke(Agent)
        Results.Check("Revoke from code", if (Ability.IsGranted[Agent]) then false else true)
