using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { InteractSystem }
using { InteractSystem.ConditionKit }
using { InteractSystem.GateKit }
using { _Test }

# 役割：InteractSystem の動作確認。interact_gate_component の Open / Close / IsOpen、押したときの InteractedEvent と interacted_event、interacted_condition_component（Trigger で選ぶ形）と Reset を確かめる
# テストのレベル：
#   - ボタンの entity：メッシュ + basic_interactable_component + interact_trigger_component + interact_gate_component（OpenOnBegin はオフ）。プレイヤーの近くに置く
#   - この component を付けた entity を 1 つ置き、Button にボタンの entity を入れる
# 操作：ログに「interact」と出たら 15 秒以内にボタンを押す（押し終わるまで）。押さなければその項目だけ失敗になる
# 結果：出力ログの [TEST] InteractSystem
interact_system_test_component<public> := class<final_super>(component):

    # interact_trigger_component と interact_gate_component を付けたボタンの entity
    @editable
    Button<public>:?entity = false

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "InteractSystem"}
        # ゲートが interactable_component に合わせ終わるまで待つ
        Sleep(0.5)
        if:
            ButtonEntity := Button?
            Trigger := ButtonEntity.GetComponent[interact_trigger_component]
            Gate := ButtonEntity.GetComponent[interact_gate_component]
        then:
            Run(Results, ButtonEntity, Trigger, Gate)
        else:
            Results.Fail("setup", "Button with interact_trigger_component and interact_gate_component is not set")
        if (Results.Finish[]) {}

    Run<private>(Results:test_log, ButtonEntity:entity, Trigger:interact_trigger_component, Gate:interact_gate_component)<suspends>:void =
        ConditionEntity := entity{}
        Condition := interacted_condition_component{Entity := ConditionEntity, Trigger := option{ButtonEntity}}
        ConditionEntity.AddComponents(array{Condition})
        Entity.AddEntities(array{ConditionEntity})

        Results.Check("gate closed at first (OpenOnBegin off)", if (Gate.IsOpen[]) then false else true)
        Gate.Open()
        Results.Check("gate open after Open", if (Gate.IsOpen[]) then true else false)
        Results.Check("condition not satisfied before interact", if (Condition.IsSatisfied[]) then false else true)

        Print("[TEST] InteractSystem: interact with the button within 15 seconds")
        Arrived8 := AwaitWithin(Trigger.InteractedEvent, 15.0)
        if (Arrived8?):
            Results.Pass("InteractedEvent received")
            Results.Check("interacted_condition satisfied (Trigger)", if (Condition.IsSatisfied[]) then true else false)
            Condition.Reset()
            Results.Check("Reset -> not satisfied", if (Condition.IsSatisfied[]) then false else true)
        else:
            Results.Fail("InteractedEvent", "not interacted within 15 s")

        Gate.Close()
        Results.Check("gate closed after Close", if (Gate.IsOpen[]) then false else true)
        ConditionEntity.RemoveFromParent()
