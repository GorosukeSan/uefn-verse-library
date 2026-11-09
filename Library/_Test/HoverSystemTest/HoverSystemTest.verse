using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { EnergySystem }
using { HoverSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { _Test }

# 役割：HoverSystem の動作確認。hover_ability_component をコードから付与・剥奪し、人の操作でホバーするとイベントが届きエネルギーが減ることを確かめる（チェックポイントでの回復は CheckpointSystem の EnergyKit に移したので CheckpointSystemTest で確かめる）
# テストのレベル：
#   - player_manager_component を付けた entity を 1 つ
#   - テスト用の entity に hover_system_test_component だけを付ける（能力とエネルギーはテストが実行時に子として作る）
# 人の操作：「jump and hold jump in the air」と出たら、30 秒以内にジャンプし、空中でジャンプを 1 秒ほど押し続けて離す
# 結果：出力ログの [TEST] HoverSystem
hover_system_test_component<public> := class<final_super>(component):

    var<private> HoverSceneEventCount:int = 0

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (hover_changed_event[SceneEvent]):
            set HoverSceneEventCount += 1
        false

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "HoverSystem"}
        MaybeAgent := AwaitFirstPlayer()
        if (Agent := MaybeAgent?):
            TestHover(Results, Agent)
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

    TestHover<private>(Results:test_log, Agent:agent)<suspends>:void =
        HoverEntity := entity{}
        Hover := hover_ability_component{Entity := HoverEntity, EnergyPerSecond := 20.0}
        Energy := energy_component{Entity := HoverEntity, MaxEnergy := 100.0}
        HoverEntity.AddComponents(array{Hover, Energy})
        Entity.AddEntities(array{HoverEntity})
        defer:
            Hover.RevokeAll()
            HoverEntity.RemoveFromParent()
        TickEvents.PrePhysics.Await()

        Hover.Grant(Agent)
        Results.Check("Grant from code", if (Hover.IsGranted[Agent]) then true else false)
        Results.Check("not hovering on Grant", if (Hover.IsHovering[Agent]) then false else true)

        Results.CheckFloat("energy is full before hovering", Energy.CurrentAmount, 100.0, 0.001)

        Print("[TEST] HoverSystem: jump and hold jump in the air for about 1 second, then release (30 seconds)")
        Started := AwaitHoverChange(Hover, true, 30.0)
        Results.Check("HoverChangedEvent true (manual)", Started)
        Results.Check("IsHovering while hovering (manual)", if (Hover.IsHovering[Agent]) then true else false)
        Stopped := AwaitHoverChange(Hover, false, 30.0)
        Results.Check("HoverChangedEvent false after release (manual)", Stopped)
        Results.Check("hovering used energy (manual)", if (Energy.CurrentAmount < 100.0) then true else false)
        Results.Check("hover_changed_event sent up (manual)", if (HoverSceneEventCount >= 2) then true else false)

        Hover.Revoke(Agent)
        Results.Check("Revoke from code", if (Hover.IsGranted[Agent]) then false else true)

    # Hover の HoverChangedEvent で、状態が Active になるまで Seconds 秒まで待つ。なれば true
    AwaitHoverChange<private>(Hover:hover_ability_component, Active:logic, Seconds:float)<suspends>:logic =
        race:
            block:
                loop:
                    Changed := Hover.HoverChangedEvent.Await()
                    if (Changed(1) = Active):
                        break
                true
            block:
                Sleep(Seconds)
                false
