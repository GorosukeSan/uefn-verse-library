using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { ActivationSystem }
using { GridSystem }
using { SceneGraphSystem }
using { SpawnSystem }
using { SpawnSystem.PrefabKit }
using { _Test }

# 役割：SpawnSystem の動作確認。spawner（中身は prefab_spawn_factory_component、基準は spawner 自身の位置）が、起動で Count 個を出して保つこと、出したものが帯の中にあり、グリッドの借用と数が合うこと、出した・消えたの知らせ、消えた分を RefillNow ですぐ足すこと、ClearAll / Stop で消えて借用が返ること、起動・停止の合図で動き出す・止まることを確かめる。
#   PrefabKit の spawn_prefab_component が、出す場所（spawn_point_component の Order の順）に出すこと、起動の合図で SpawnOnActivate 個、MaxCount で止まること、TrySpawnAt、Despawn / DespawnAll と知らせ、停止の合図で消えることと、関数の SpawnPrefab を確かめる
# テストのレベル：このテストの component を、まわり 10 メートルに何も無い entity に付けるだけ（区画・グリッド・spawner・spawn_prefab_component はテストが自分の子に作る。出すものは見た目の無い entity）
# 結果：出力ログの [TEST] SpawnSystem
spawn_system_test_component<public> := class<final_super>(component):

    SpawnCount<private>:int = 3
    RangeCells<private>:int = 3
    MaxHeightCells<private>:int = 4

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "SpawnSystem"}
        Origin := Entity.GetGlobalTranslation()
        Root := entity{}
        Root.AddComponents(array{game_scope_component{Entity := Root}})
        GridEntity := entity{}
        Grid := grid_component{Entity := GridEntity, CellSizeCm := 100.0}
        GridEntity.AddComponents(array{Grid})
        SpawnerEntity := entity{}
        Spawner := spawner_component:
            Entity := SpawnerEntity
            Count := SpawnCount
            RefillSeconds := 0.25
            RangeCells := RangeCells
            MinHeightCells := 0
            MaxHeightCells := MaxHeightCells
            GapCells := 0
            AppearSeconds := 0.0
            StartOnBegin := false
        SpawnerEntity.AddComponents(array{Spawner, prefab_spawn_factory_component{Entity := SpawnerEntity}})
        Root.AddEntities(array{GridEntity, SpawnerEntity})
        Entity.AddEntities(array{Root})
        Root.SetGlobalTransform(MakeTranslationTransform(Origin))
        GridEntity.SetGlobalTransform(MakeTranslationTransform(Origin))
        SpawnerEntity.SetGlobalTransform(MakeTranslationTransform(Origin))
        TickEvents.PrePhysics.Await()
        Results.Check("not running before Start (StartOnBegin = false)", if (Spawner.IsRunning[]) then false else true)
        Results.CheckInt("nothing spawned before Start", Spawner.GetSpawnedCount(), 0)
        TestFill(Results, Spawner, Grid)
        TestRefill(Results, Spawner, Grid)
        TestStop(Results, Spawner, Grid)
        TestActivation(Results, Spawner, SpawnerEntity)
        TestPrefab(Results, Root, Origin)
        Root.RemoveFromParent()
        if (Results.Finish[]) {}

    TestFill<private>(Results:test_log, Spawner:spawner_component, Grid:grid_component)<suspends>:void =
        FirstSpawn := spawn{AwaitWithin(Spawner.SpawnedEvent, 2.0)}
        Spawner.Start()
        Awaited6 := FirstSpawn.Await()
        Results.Check("SpawnedEvent after Start", if (Awaited6?) then true else false)
        Results.Check("IsRunning after Start", if (Spawner.IsRunning[]) then true else false)
        WaitSeconds(0.6)
        Results.CheckInt("keeps Count spawned", Spawner.GetSpawnedCount(), SpawnCount)
        Results.CheckInt("one grid reservation per spawned", Grid.GetReservationCount(), SpawnCount)
        var InBand:logic = true
        for (Marker : Spawner.GetSpawned()):
            Inner := Marker.Area.Inner
            if (Abs(Inner.Start.X) > RangeCells + 1 or Abs(Inner.Start.Y) > RangeCells + 1 or Inner.Start.Z < 0 or Inner.Start.Z > MaxHeightCells):
                set InBand = false
            if (Marker.Spawner <> Spawner):
                set InBand = false
        Results.Check("spawned areas are inside the band and know their spawner", InBand)

    TestRefill<private>(Results:test_log, Spawner:spawner_component, Grid:grid_component)<suspends>:void =
        if (Victim := Spawner.GetSpawned()[0]):
            Despawned := spawn{AwaitWithin(Spawner.DespawnedEvent, 1.0)}
            Victim.Entity.RemoveFromParent()
            Awaited7 := Despawned.Await()
            Results.Check("DespawnedEvent when a spawned entity is removed", if (Got := Awaited7?, Got = Victim.Entity) then true else false)
            TickEvents.PrePhysics.Await()
            Results.CheckInt("removed entity's reservation is released", Grid.GetReservationCount(), SpawnCount - 1)
            Spawner.RefillNow()
            Results.CheckInt("RefillNow refills at once", Spawner.GetSpawnedCount(), SpawnCount)
        else:
            Results.Fail("DespawnedEvent when a spawned entity is removed", "nothing spawned")

    TestStop<private>(Results:test_log, Spawner:spawner_component, Grid:grid_component)<suspends>:void =
        Spawner.ClearAll()
        TickEvents.PrePhysics.Await()
        Results.CheckInt("ClearAll removes everything", Spawner.GetSpawnedCount(), 0)
        WaitSeconds(0.6)
        Results.CheckInt("still running after ClearAll, so it refills", Spawner.GetSpawnedCount(), SpawnCount)
        Spawner.Stop()
        TickEvents.PrePhysics.Await()
        Results.Check("not running after Stop", if (Spawner.IsRunning[]) then false else true)
        Results.CheckInt("Stop removes everything", Spawner.GetSpawnedCount(), 0)
        Results.CheckInt("all reservations released after Stop", Grid.GetReservationCount(), 0)
        WaitSeconds(0.6)
        Results.CheckInt("nothing comes back while stopped", Spawner.GetSpawnedCount(), 0)

    TestActivation<private>(Results:test_log, Spawner:spawner_component, SpawnerEntity:entity)<suspends>:void =
        SpawnerEntity.SendDown(activated_event{})
        WaitSeconds(0.6)
        Results.Check("activated_event starts the spawner", if (Spawner.IsRunning[]) then true else false)
        Results.CheckInt("activated_event spawns Count", Spawner.GetSpawnedCount(), SpawnCount)
        SpawnerEntity.SendDown(deactivated_event{})
        TickEvents.PrePhysics.Await()
        Results.Check("deactivated_event stops the spawner", if (Spawner.IsRunning[]) then false else true)
        Results.CheckInt("deactivated_event removes everything", Spawner.GetSpawnedCount(), 0)

    # Seconds 秒待つ（DeltaTime の足し合わせ）
    WaitSeconds<private>(Seconds:float)<suspends>:void =
        var Left:float = Seconds
        loop:
            if (Left <= 0.0):
                break
            set Left -= TickEvents.PrePhysics.Await()

    # PrefabKit の spawn_prefab_component と、関数の SpawnPrefab
    TestPrefab<private>(Results:test_log, Root:entity, Origin:vector3)<suspends>:void =
        PrefabEntity := entity{}
        Prefabs := spawn_prefab_component{Entity := PrefabEntity, SpawnOnActivate := 2, MaxCount := 3}
        PrefabEntity.AddComponents(array{Prefabs})
        # 並び順が最初にならないように、Order 1 の点を先に足す
        LaterPoint := entity{}
        LaterPoint.AddComponents(array{spawn_point_component{Entity := LaterPoint, Order := 1}})
        FirstPoint := entity{}
        FirstPoint.AddComponents(array{spawn_point_component{Entity := FirstPoint, Order := 0}})
        PrefabEntity.AddEntities(array{LaterPoint, FirstPoint})
        Root.AddEntities(array{PrefabEntity})
        PrefabEntity.SetGlobalTransform(MakeTranslationTransform(Origin))
        FirstPosition := Origin + vector3{Forward := 300.0}
        LaterPosition := Origin + vector3{Left := 300.0}
        FirstPoint.SetGlobalTransform(MakeTranslationTransform(FirstPosition))
        LaterPoint.SetGlobalTransform(MakeTranslationTransform(LaterPosition))
        TickEvents.PrePhysics.Await()

        Results.CheckInt("prefab: GetSpawnPoints finds both points", Prefabs.GetSpawnPoints().Length, 2)
        FirstSpawned := Prefabs.Spawn(1)
        Results.CheckInt("prefab: Spawn(1) spawns one", FirstSpawned.Length, 1)
        if (Spawned := FirstSpawned[0]):
            Results.CheckFloat("prefab: first spawn at the Order 0 point", Distance(Spawned.GetGlobalTranslation(), FirstPosition), 0.0, 1.0)
        SecondSpawned := Prefabs.Spawn(1)
        if (Spawned := SecondSpawned[0]):
            Results.CheckFloat("prefab: next spawn at the Order 1 point", Distance(Spawned.GetGlobalTranslation(), LaterPosition), 0.0, 1.0)
        Results.CheckInt("prefab: GetSpawnedCount after two", Prefabs.GetSpawnedCount(), 2)

        PrefabEntity.SendDown(activated_event{})
        Results.CheckInt("prefab: activated_event spawns up to MaxCount", Prefabs.GetSpawnedCount(), 3)
        Results.Check("prefab: IsFull at MaxCount", if (Prefabs.IsFull[]) then true else false)
        Results.CheckInt("prefab: Spawn does nothing when full", Prefabs.Spawn(1).Length, 0)
        WhenFull := Prefabs.TrySpawnAt(MakeTranslationTransform(Origin))
        Results.Check("prefab: TrySpawnAt fails when full", if (WhenFull?) then false else true)

        if (Victim := Prefabs.GetSpawned()[0]):
            Despawned := spawn{AwaitWithin(Prefabs.DespawnedEvent, 1.0)}
            Prefabs.Despawn(Victim)
            Results.CheckInt("prefab: Despawn lowers the count at once", Prefabs.GetSpawnedCount(), 2)
            Awaited8 := Despawned.Await()
            Results.Check("prefab: DespawnedEvent after Despawn", if (Got := Awaited8?, Got = Victim) then true else false)
        AtPosition := Origin + vector3{Up := 500.0}
        Placed := Prefabs.TrySpawnAt(MakeTranslationTransform(AtPosition))
        if (Spawned := Placed?):
            Results.CheckFloat("prefab: TrySpawnAt places at the transform", Distance(Spawned.GetGlobalTranslation(), AtPosition), 0.0, 1.0)
        else:
            Results.Fail("prefab: TrySpawnAt places at the transform", "returned false")

        Prefabs.DespawnAll()
        Results.CheckInt("prefab: DespawnAll removes everything at once", Prefabs.GetSpawnedCount(), 0)
        PrefabEntity.SendDown(activated_event{})
        Results.CheckInt("prefab: activated_event spawns SpawnOnActivate", Prefabs.GetSpawnedCount(), 2)
        PrefabEntity.SendDown(deactivated_event{})
        Results.CheckInt("prefab: deactivated_event removes everything", Prefabs.GetSpawnedCount(), 0)
        TickEvents.PrePhysics.Await()
        Results.CheckInt("prefab: removed entities are gone from the children", PrefabEntity.GetChildComponents(prefab_spawned_component).Length, 0)

        FunctionPosition := Origin + vector3{Forward := -300.0}
        Made := Root.SpawnPrefab(entity, MakeTranslationTransform(FunctionPosition))
        Results.CheckFloat("SpawnPrefab places the new entity", Distance(Made.GetGlobalTranslation(), FunctionPosition), 0.0, 1.0)
        Results.Check("SpawnPrefab adds it under the parent", if (Parent := Made.GetParent[], Parent = Root) then true else false)
        Made.RemoveFromParent()
