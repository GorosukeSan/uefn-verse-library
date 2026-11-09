using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { CheckpointSystem }
using { CheckpointSystem.EnergyKit }
using { CheckpointSystem.PresenceKit }
using { CheckpointSystem.SpawnKit }
using { EnergySystem }
using { EnergySystem.RestoreKit }
using { GridSystem }
using { MovementSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { SpawnSystem }
using { _Test }

# Role: verification of CheckpointSystem. Creates an invisible checkpoint under the feet of the first player that joined and checks the reached notification / IsStanding, the left notification when the platform is moved sideways, the left notification when the platform is disposed, and the summary of checkpoint_presence_component (standing or not / last reached).
#   Also checks that when standing on 2 overlapping checkpoints and leaving the one reached later, the player still counts as standing on the earlier one (checkpoint_presence_component).
#   Also checks that when 2 checkpoints are watched together and the one that started first (the one running the per-frame check) is disposed, the rest keeps checking.
#   Also checks the tier selection and size of checkpoint_factory_component, and EnergyKit's checkpoint_energy_refill_component (fills energy on the reached notification)
# Test level:
#   - one entity with player_manager_component (if you use scopes, in the same scope as this test's entity)
#   - attach this test component to an entity near a flat floor (the player stands still on the floor)
#   - passing through from below is not checked automatically; a human follows the [HUMAN] steps in the log
# Result: [TEST] CheckpointSystem in the output log
checkpoint_system_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "CheckpointSystem"}
        TestFactory(Results)
        Presence := checkpoint_presence_component{Entity := Entity}
        Entity.AddComponents(array{Presence})
        MaybeAgent := AwaitFirstPlayer()
        if (Agent := MaybeAgent?):
            MaybeCharacter := AwaitOnGround(Agent)
            if (FortCharacter := MaybeCharacter?):
                TestPresence(Results, Presence, Agent, FortCharacter)
                TestOverlap(Results, Presence, Agent, FortCharacter)
                TestSharedTracking(Results, Agent, FortCharacter)
                TestEnergyRefill(Results, Agent)
            else:
                Results.Fail("setup", "the player never stood on the ground within 10 s")
        else:
            Results.Fail("setup", "no player_manager_component or no player")
        Print("[HUMAN] CheckpointSystem: place a checkpoint_component with a 750 x 750 x 250 cm cube mesh 3 m above the floor, jump from below: you should pass through and land on top, and you cannot drop through from above")
        if (Results.Finish[]) {}

    TestFactory<private>(Results:test_log):void =
        SpawnerEntity := entity{}
        Spawner := spawner_component{Entity := SpawnerEntity, FootprintX := 3, FootprintY := 2, FootprintZ := 1, LevelIntervalCells := 10}
        Factory := checkpoint_factory_component{Entity := SpawnerEntity}
        Footprint := Spawner.GetFootprint()
        Results.Check("spawner footprint is FootprintX/Y/Z", if (Footprint.X = 3, Footprint.Y = 2, Footprint.Z = 1) then true else false)
        Band := spawn_band{CenterX := 0, CenterY := 0, HalfX := 2, HalfY := 2, Bottom := 0, SpawnBottom := 5, Top := 25}
        if (Start := Spawner.PickStartCell[Band, 5, 25]):
            Results.CheckInt("first level is the lowest multiple of LevelIntervalCells in the band", Start.Z, 10)
            Grid := grid_component{Entity := entity{}, CellSizeCm := 100.0}
            Inner := MakeGridBox(Start, Footprint)
            if (Reservation := Grid.TryReserve(Inner)?):
                Spawned := Factory.CreateSpawned(spawn_area{Grid := Grid, Inner := Inner, Reservation := Reservation})
                if (Checkpoint := Spawned.GetComponent[checkpoint_component]):
                    Results.CheckFloat("checkpoint width = cells x cell size", Checkpoint.WidthCm, 300.0, 0.5)
                    Results.CheckFloat("checkpoint depth = cells x cell size", Checkpoint.DepthCm, 200.0, 0.5)
                    Results.CheckFloat("checkpoint thickness = cells x cell size", Checkpoint.ThicknessCm, 100.0, 0.5)
                else:
                    Results.Fail("factory adds checkpoint_component", "not found")
                Reservation.Release()
            else:
                Results.Fail("factory test reservation", "TryReserve failed")
        else:
            Results.Fail("first level is the lowest multiple of LevelIntervalCells in the band", "PickStartCell failed")

    TestPresence<private>(Results:test_log, Presence:checkpoint_presence_component, Agent:agent, FortCharacter:fort_character)<suspends>:void =
        if (Feet := FortCharacter.FindGlobalTranslation[]):
            Under := Feet + vector3{Up := -100.0}
            Away := Under + vector3{Forward := 2000.0}
            CheckpointEntity := entity{}
            Checkpoint := checkpoint_component{Entity := CheckpointEntity, WidthCm := 400.0, DepthCm := 400.0, ThicknessCm := 100.0}
            CheckpointEntity.AddComponents(array{Checkpoint})
            Reached := spawn{AwaitWithin(Checkpoint.ReachedEvent, 3.0)}
            Entity.AddEntities(array{CheckpointEntity})
            CheckpointEntity.SetGlobalTransform(MakeTranslationTransform(Under))
            Awaited8 := Reached.Await()
            Results.Check("ReachedEvent when standing on top", if (Got := Awaited8?, Got = Agent) then true else false)
            Results.Check("IsStanding while on top", if (Checkpoint.IsStanding[Agent]) then true else false)
            Results.Check("presence: IsOnAnyCheckpoint", if (Presence.IsOnAnyCheckpoint[Agent]) then true else false)
            Results.Check("presence: FindLastReached", if (LastOne := Presence.FindLastReached[Agent], LastOne = Checkpoint) then true else false)
            Left := spawn{AwaitWithin(Checkpoint.LeftEvent, 2.0)}
            CheckpointEntity.SetGlobalTransform(MakeTranslationTransform(Away))
            Awaited9 := Left.Await()
            Results.Check("LeftEvent when the checkpoint moves away", if (Got := Awaited9?, Got = Agent) then true else false)
            Results.Check("not IsStanding after leaving", if (Checkpoint.IsStanding[Agent]) then false else true)
            Results.Check("presence: not on any after leaving", if (Presence.IsOnAnyCheckpoint[Agent]) then false else true)
            Results.Check("presence: last reached is kept after leaving", if (Presence.FindLastReached[Agent]) then true else false)
            Again := spawn{AwaitWithin(Checkpoint.ReachedEvent, 2.0)}
            CheckpointEntity.SetGlobalTransform(MakeTranslationTransform(Under))
            Awaited10 := Again.Await()
            Results.Check("ReachedEvent again when back under the player", if (Awaited10?) then true else false)
            Removed := spawn{AwaitWithin(Presence.LeftEvent, 2.0)}
            CheckpointEntity.RemoveFromParent()
            Awaited11 := Removed.Await()
            Results.Check("LeftEvent (presence) when the checkpoint is removed", if (Got := Awaited11?, Got.Agent = Agent) then true else false)
            Results.Check("presence: not on any after removal", if (Presence.IsOnAnyCheckpoint[Agent]) then false else true)
        else:
            Results.Fail("setup", "character position not available")

    # Two overlapping checkpoints (First and Second at the same spot under the feet). After reaching First then Second, leaving Second still counts as standing on First (FindStandingCheckpoint is First). Leaving First too means standing on none
    TestOverlap<private>(Results:test_log, Presence:checkpoint_presence_component, Agent:agent, FortCharacter:fort_character)<suspends>:void =
        if (Feet := FortCharacter.FindGlobalTranslation[]):
            Under := Feet + vector3{Up := -100.0}
            Away := Under + vector3{Forward := 2000.0}
            FirstEntity := entity{}
            First := checkpoint_component{Entity := FirstEntity, WidthCm := 400.0, DepthCm := 400.0, ThicknessCm := 100.0}
            FirstEntity.AddComponents(array{First})
            SecondEntity := entity{}
            Second := checkpoint_component{Entity := SecondEntity, WidthCm := 400.0, DepthCm := 400.0, ThicknessCm := 100.0}
            SecondEntity.AddComponents(array{Second})
            FirstReached := spawn{AwaitWithin(First.ReachedEvent, 3.0)}
            Entity.AddEntities(array{FirstEntity})
            FirstEntity.SetGlobalTransform(MakeTranslationTransform(Under))
            GotFirst := FirstReached.Await()
            SecondReached := spawn{AwaitWithin(Second.ReachedEvent, 3.0)}
            Entity.AddEntities(array{SecondEntity})
            SecondEntity.SetGlobalTransform(MakeTranslationTransform(Under))
            GotSecond := SecondReached.Await()
            Results.Check("overlap: both reached", if (GotFirst?, GotSecond?) then true else false)
            Results.Check("overlap: standing on the last reached", if (Presence.FindStandingCheckpoint[Agent] = Second) then true else false)
            SecondLeft := spawn{AwaitWithin(Second.LeftEvent, 2.0)}
            SecondEntity.SetGlobalTransform(MakeTranslationTransform(Away))
            GotSecondLeft := SecondLeft.Await()
            Results.Check("overlap: LeftEvent from the second", if (GotSecondLeft?) then true else false)
            Results.Check("overlap: still on the first after leaving the second", if (Presence.FindStandingCheckpoint[Agent] = First) then true else false)
            Results.Check("overlap: IsOnAnyCheckpoint after leaving the second", if (Presence.IsOnAnyCheckpoint[Agent]) then true else false)
            FirstLeft := spawn{AwaitWithin(First.LeftEvent, 2.0)}
            FirstEntity.SetGlobalTransform(MakeTranslationTransform(Away))
            GotFirstLeft := FirstLeft.Await()
            Results.Check("overlap: LeftEvent from the first", if (GotFirstLeft?) then true else false)
            Results.Check("overlap: not on any after leaving both", if (Presence.IsOnAnyCheckpoint[Agent]) then false else true)
            FirstEntity.RemoveFromParent()
            SecondEntity.RemoveFromParent()
        else:
            Results.Fail("overlap setup", "character position not available")

    # Two checkpoints (A under the feet, B far away). A starts first, so it runs the per-frame check. If a reached notification still arrives when B is moved under the feet after A is disposed, the check was handed over to B
    TestSharedTracking<private>(Results:test_log, Agent:agent, FortCharacter:fort_character)<suspends>:void =
        if (Feet := FortCharacter.FindGlobalTranslation[]):
            Under := Feet + vector3{Up := -100.0}
            Away := Under + vector3{Forward := 2000.0}
            FirstEntity := entity{}
            First := checkpoint_component{Entity := FirstEntity, WidthCm := 400.0, DepthCm := 400.0, ThicknessCm := 100.0}
            FirstEntity.AddComponents(array{First})
            SecondEntity := entity{}
            Second := checkpoint_component{Entity := SecondEntity, WidthCm := 400.0, DepthCm := 400.0, ThicknessCm := 100.0}
            SecondEntity.AddComponents(array{Second})
            FirstReached := spawn{AwaitWithin(First.ReachedEvent, 3.0)}
            Entity.AddEntities(array{FirstEntity})
            FirstEntity.SetGlobalTransform(MakeTranslationTransform(Under))
            Entity.AddEntities(array{SecondEntity})
            SecondEntity.SetGlobalTransform(MakeTranslationTransform(Away))
            GotFirst := FirstReached.Await()
            Results.Check("shared tracking: first checkpoint reached", if (GotFirst?) then true else false)
            Results.Check("shared tracking: the far one is not stood on", if (Second.IsStanding[Agent]) then false else true)
            FirstEntity.RemoveFromParent()
            SecondReached := spawn{AwaitWithin(Second.ReachedEvent, 3.0)}
            SecondEntity.SetGlobalTransform(MakeTranslationTransform(Under))
            GotSecond := SecondReached.Await()
            Results.Check("shared tracking: the rest keeps checking after the first is removed", if (GotSecond?) then true else false)
            SecondEntity.RemoveFromParent()
        else:
            Results.Fail("shared tracking setup", "character position not available")

    # checkpoint_energy_refill_component: checked by sending the reached notification (checkpoint_reached_event) to the scope (the real one is sent by checkpoint_component)
    TestEnergyRefill<private>(Results:test_log, Agent:agent)<suspends>:void =
        Dummy := checkpoint_component{Entity := entity{}}

        # 1. Fills the energy_component on the same entity. Does not fill for an agent not granted the ability on the same entity
        SharedEntity := entity{}
        SharedEnergy := energy_component{Entity := SharedEntity, MaxEnergy := 100.0}
        SharedRefill := checkpoint_energy_refill_component{Entity := SharedEntity}
        Ability := energy_restore_ability_component{Entity := SharedEntity, ConsumeItemOnUse := false}
        SharedEntity.AddComponents(array{SharedEnergy, SharedRefill, Ability})
        Entity.AddEntities(array{SharedEntity})
        TickEvents.PrePhysics.Await()
        SharedEnergy.Consume(60.0)
        Entity.SendScoped(checkpoint_reached_event{Checkpoint := Dummy, Agent := Agent})
        Results.CheckFloat("refill: not for an agent without the ability on the same entity", SharedEnergy.CurrentAmount, 40.0, 0.001)
        Ability.Grant(Agent)
        Refilled := spawn{AwaitWithin(SharedRefill.RefilledEvent, 1.0)}
        Entity.SendScoped(checkpoint_reached_event{Checkpoint := Dummy, Agent := Agent})
        Results.CheckFloat("refill: fills the energy on the same entity", SharedEnergy.CurrentAmount, 100.0, 0.001)
        GotRefilled := Refilled.Await()
        Results.Check("refill: RefilledEvent", if (Got := GotRefilled?, Got(1) = SharedEnergy) then true else false)
        Ability.RevokeAll()
        SharedEntity.RemoveFromParent()

        # 2. When this entity has no energy_component, fills the energy of the agent that reached it
        AgentEnergy := energy_component{Entity := Agent, MaxEnergy := 100.0}
        Agent.AddComponents(array{AgentEnergy})
        RefillEntity := entity{}
        AgentRefill := checkpoint_energy_refill_component{Entity := RefillEntity}
        RefillEntity.AddComponents(array{AgentRefill})
        Entity.AddEntities(array{RefillEntity})
        TickEvents.PrePhysics.Await()
        AgentEnergy.Consume(70.0)
        Entity.SendScoped(checkpoint_reached_event{Checkpoint := Dummy, Agent := Agent})
        Results.CheckFloat("refill: fills the agent's own energy", AgentEnergy.CurrentAmount, 100.0, 0.001)
        AllFull := AgentRefill.TryRefillFor(Agent)
        Results.Check("refill: TryRefillFor is false when everything is full", if (AllFull?) then false else true)
        RefillEntity.RemoveFromParent()
        AgentEnergy.RemoveFromEntity()

    AwaitFirstPlayer<private>()<suspends>:?agent =
        if (Manager := Entity.FindScopedComponent[player_manager_component]):
            if (Slot := Manager.GetSlots()[0]):
                option{Slot.Player}
            else:
                Player := Manager.PlayerAddedEvent.Await()
                option{Player}
        else:
            false

    # Wait until Agent's character stands on the floor (up to 10 seconds)
    AwaitOnGround<private>(Agent:agent)<suspends>:?fort_character =
        var Waited:float = 0.0
        var Result:?fort_character = false
        loop:
            if (Result? or Waited > 10.0):
                break
            if (FortCharacter := Agent.GetFortCharacter[], FortCharacter.IsOnGround[]):
                set Result = option{FortCharacter}
            else:
                set Waited += TickEvents.PrePhysics.Await()
        Result
