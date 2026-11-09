using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { EnergySystem }
using { EnergySystem.RestoreKit }
using { PlayerSystem }
using { SceneGraphSystem }
using { _Test }

# 役割：EnergySystem の動作確認。energy_component（量の増減・丸め・Spend[]・SetAmount・StartFull・SetMax・知らせ）と、FindEnergy / FindEnergyFor、energy_restore_ability_component（コードからの RestoreFor・付与・押して回復）を確かめる
# テストのレベル：
#   - player_manager_component を付けた entity を 1 つ
#   - テスト用の entity に energy_system_test_component だけを付ける（energy_component や能力はテストが実行時に子として作る）
# 人の操作：最後に「射撃のボタンを押す」と出たら、20 秒以内に押す（押さなければその項目だけ [FAIL]）
# 前提・注意：プレイヤー（agent の entity）に energy_component を一時的に付けて、プレイヤーごとのエネルギーを確かめる（終わったら外す）
# 結果：出力ログの [TEST] EnergySystem
energy_system_test_component<public> := class<final_super>(component):

    var<private> ChangedCount:int = 0
    var<private> LastChanged:float = -1.0
    var<private> SceneEventCount:int = 0
    var<private> LastSceneAmount:float = -1.0
    var<private> LastSceneDelta:float = 0.0

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Changed := energy_changed_event[SceneEvent]):
            set SceneEventCount += 1
            set LastSceneAmount = Changed.Amount
            set LastSceneDelta = Changed.Delta
        false

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "EnergySystem"}
        TestEnergyComponent(Results)
        MaybeAgent := AwaitFirstPlayer()
        if (Agent := MaybeAgent?):
            TestRestoreAbility(Results, Agent)
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

    OnChanged<private>(Value:float):void =
        set ChangedCount += 1
        set LastChanged = Value

    TestEnergyComponent<private>(Results:test_log)<suspends>:void =
        EnergyEntity := entity{}
        Energy := energy_component{Entity := EnergyEntity, MaxEnergy := 100.0}
        EnergyEntity.AddComponents(array{Energy})
        Entity.AddEntities(array{EnergyEntity})
        Subscription := Energy.ChangedEvent.Subscribe(OnChanged)
        defer:
            Subscription.Cancel()
            EnergyEntity.RemoveFromParent()
        TickEvents.PrePhysics.Await()
        Results.CheckFloat("starts full", Energy.CurrentAmount, 100.0, 0.001)
        Results.Check("IsFull at start", if (Energy.IsFull[]) then true else false)
        Results.CheckFloat("GetRatio at start", Energy.GetRatio(), 1.0, 0.001)
        Results.Check("FindEnergy finds the child", if (Found := Entity.FindEnergy[], Found.Entity = EnergyEntity) then true else false)

        Energy.Consume(30.0)
        Results.CheckFloat("Consume 30", Energy.CurrentAmount, 70.0, 0.001)
        Results.CheckInt("ChangedEvent once per change", ChangedCount, 1)
        Results.CheckFloat("ChangedEvent carries the new amount", LastChanged, 70.0, 0.001)
        Results.CheckInt("energy_changed_event sent up", SceneEventCount, 1)
        Energy.Consume(1000.0)
        Results.CheckFloat("Consume clamps at 0", Energy.CurrentAmount, 0.0, 0.001)
        Results.Check("IsEmpty at 0", if (Energy.IsEmpty[]) then true else false)
        Energy.Restore(25.0)
        Results.CheckFloat("Restore 25", Energy.CurrentAmount, 25.0, 0.001)
        Energy.Restore(1000.0)
        Results.CheckFloat("Restore clamps at max", Energy.CurrentAmount, 100.0, 0.001)

        Results.CheckFloat("energy_changed_event Amount", LastSceneAmount, 100.0, 0.001)
        Results.CheckFloat("energy_changed_event Delta", LastSceneDelta, 75.0, 0.001)

        Energy.Consume(40.0)
        Before := ChangedCount
        BeforeScene := SceneEventCount
        Results.Check("Spend 40 with 60 succeeds", if (Energy.Spend[40.0]) then true else false)
        Results.CheckFloat("Spend took 40 at once", Energy.CurrentAmount, 20.0, 0.001)
        Results.CheckInt("Spend notifies later (not yet)", ChangedCount, Before)
        Results.Check("Spend 21 with 20 fails", if (Energy.Spend[21.0]) then false else true)
        Results.Check("Spend negative fails", if (Energy.Spend[-1.0]) then false else true)
        Results.CheckFloat("failed Spend keeps amount", Energy.CurrentAmount, 20.0, 0.001)
        # 失敗した Spend は量を変えない（if の中で巻き戻る）。2 つまとめて成功しなければ両方とも戻る
        Results.Check("Spend 15 + 15 with 20 fails as a whole", if (Energy.Spend[15.0], Energy.Spend[15.0]) then false else true)
        Results.CheckFloat("rolled back Spend keeps amount", Energy.CurrentAmount, 20.0, 0.001)
        TickEvents.PrePhysics.Await()
        TickEvents.PrePhysics.Await()
        Results.CheckInt("Spend notifies once after physics", ChangedCount, Before + 1)
        Results.CheckInt("Spend sends energy_changed_event once", SceneEventCount, BeforeScene + 1)
        Results.CheckFloat("Spend notification carries the new amount", LastChanged, 20.0, 0.001)
        Results.CheckFloat("Spend notification Delta", LastSceneDelta, -40.0, 0.001)
        Results.Check("HasEnough 20", if (Energy.HasEnough[20.0]) then true else false)
        Results.Check("not HasEnough 20.5", if (Energy.HasEnough[20.5]) then false else true)

        Energy.SetAmount(55.0)
        Results.CheckFloat("SetAmount 55", Energy.CurrentAmount, 55.0, 0.001)
        Results.CheckFloat("SetAmount notifies at once", LastChanged, 55.0, 0.001)
        Energy.SetAmount(-10.0)
        Results.CheckFloat("SetAmount clamps at 0", Energy.CurrentAmount, 0.0, 0.001)
        Energy.SetAmount(1000.0)
        Results.CheckFloat("SetAmount clamps at max", Energy.CurrentAmount, 100.0, 0.001)

        Energy.Fill()
        Energy.SetMax(50.0)
        Results.CheckFloat("SetMax lowers max", Energy.GetMax(), 50.0, 0.001)
        Results.CheckFloat("SetMax clamps amount", Energy.CurrentAmount, 50.0, 0.001)
        Energy.SetMax(200.0)
        Results.CheckFloat("SetMax raise keeps amount", Energy.CurrentAmount, 50.0, 0.001)
        Results.CheckFloat("GetRatio after raise", Energy.GetRatio(), 0.25, 0.001)
        Energy.Fill()
        Results.CheckFloat("Fill to new max", Energy.CurrentAmount, 200.0, 0.001)
        Results.CheckFloat("MaxEnergy keeps editor value", Energy.MaxEnergy, 100.0, 0.001)

        EmptyEntity := entity{}
        EmptyStart := energy_component{Entity := EmptyEntity, MaxEnergy := 50.0, StartFull := false}
        EmptyEntity.AddComponents(array{EmptyStart})
        Entity.AddEntities(array{EmptyEntity})
        TickEvents.PrePhysics.Await()
        Results.CheckFloat("StartFull false starts at 0", EmptyStart.CurrentAmount, 0.0, 0.001)
        Results.Check("StartFull false IsEmpty", if (EmptyStart.IsEmpty[]) then true else false)
        EmptyStart.Fill()
        Results.CheckFloat("Fill from empty start", EmptyStart.CurrentAmount, 50.0, 0.001)
        EmptyEntity.RemoveFromParent()

    TestRestoreAbility<private>(Results:test_log, Agent:agent)<suspends>:void =
        AbilityEntity := entity{}
        Ability := energy_restore_ability_component{Entity := AbilityEntity, RestoreAmount := 30.0, ConsumeItemOnUse := false}
        AbilityEntity.AddComponents(array{Ability})
        Entity.AddEntities(array{AbilityEntity})
        AgentEnergy := energy_component{Entity := Agent, MaxEnergy := 100.0}
        Agent.AddComponents(array{AgentEnergy})
        defer:
            Ability.RevokeAll()
            AbilityEntity.RemoveFromParent()
            AgentEnergy.RemoveFromEntity()
        TickEvents.PrePhysics.Await()

        Results.Check("FindEnergyFor falls back to the player's energy", if (Found := AbilityEntity.FindEnergyFor[Agent], Found.Entity = Agent) then true else false)
        Results.Check("nothing to restore while full", if (Ability.FindRestoreTarget[Agent]) then false else true)
        Failed := spawn{AwaitWithin(Ability.FailedEvent, 1.0)}
        WhileFull := Ability.TryRestoreFor(Agent)
        Results.Check("TryRestoreFor fails while full", if (WhileFull?) then false else true)
        FailedPayload := Failed.Await()
        Results.Check("FailedEvent when nothing to restore", if (FailedPayload?) then true else false)

        AgentEnergy.Consume(100.0)
        Restored := spawn{AwaitWithin(Ability.RestoredEvent, 1.0)}
        Results.Check("TryRestoreFor succeeds when empty", Ability.TryRestoreFor(Agent))
        RestoredPayload := Restored.Await()
        Results.Check("RestoredEvent", if (RestoredPayload?) then true else false)
        Results.CheckFloat("restored RestoreAmount", AgentEnergy.CurrentAmount, 30.0, 0.001)

        Ability.Grant(Agent)
        Results.Check("Grant from code", if (Ability.IsGranted[Agent]) then true else false)
        Print("[TEST] EnergySystem: press the fire button (WeaponPrimary) within 20 seconds")
        Pressed := AwaitWithin(Ability.RestoredEvent, 20.0)
        Results.Check("pressing fire restores (manual)", if (Pressed?) then true else false)
        Results.CheckFloat("restored again by pressing (manual)", AgentEnergy.CurrentAmount, 60.0, 0.001)
        Ability.Revoke(Agent)
        Results.Check("Revoke from code", if (Ability.IsGranted[Agent]) then false else true)
