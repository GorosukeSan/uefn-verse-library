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

# 役割：CheckpointSystem の動作確認。最初に参加したプレイヤーの足元にチェックポイント（見た目の無いもの）を作り、乗った知らせ・IsStanding、離した（足場を横へ動かした）ときの降りた知らせ、足場が消えたときの降りた知らせ、checkpoint_presence_component のまとめ（乗っているか・最後に乗ったもの）を確かめる。
#   重なった 2 つのチェックポイントに乗り、後に乗った方から降りても、まだ先の方に乗っている扱いになること（checkpoint_presence_component）も確かめる。
#   2 つのチェックポイントをまとめて見ているとき、先に始まった方（毎フレームの確認を回している方）を消しても、残りが確かめ続けることも確かめる。
#   checkpoint_factory_component の段の選び方と大きさ、EnergyKit の checkpoint_energy_refill_component（乗った知らせでエネルギーを満たす）も確かめる
# テストのレベル：
#   - player_manager_component を付けた entity を 1 つ（区画を使うなら、このテストの entity と同じ区画に）
#   - このテストの component を、平らな床の近くの entity に付ける（プレイヤーは床の上に立ったまま動かない）
#   - 下から通り抜ける動きは自動では確かめない。ログの [HUMAN] の手順で、人が確かめる
# 結果：出力ログの [TEST] CheckpointSystem
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

    # 重なった 2 つ（First と Second を同じ足元に）。First → Second の順に乗ってから Second を離すと、まだ First に乗っている扱い（FindStandingCheckpoint は First）。First も離すとどれにも乗っていない
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

    # 2 つのチェックポイント（A は足元、B は離れた所）。A が先に始まるので毎フレームの確認を回す。A を消したあと B を足元へ動かしても乗った知らせが来れば、確認が B に引き継がれている
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

    # checkpoint_energy_refill_component：乗った知らせ（checkpoint_reached_event）を区画へ送って確かめる（本物は checkpoint_component が送る）
    TestEnergyRefill<private>(Results:test_log, Agent:agent)<suspends>:void =
        Dummy := checkpoint_component{Entity := entity{}}

        # 1. 同じ entity の energy_component を満たす。同じ entity の能力を付与されていない人では満たさない
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

        # 2. この entity に energy_component が無ければ、乗った人（agent）のエネルギーを満たす
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

    # Agent のキャラクターが床に立つまで待つ（10 秒まで）
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
