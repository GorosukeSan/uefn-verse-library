using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { _Test }

# 役割：起動・停止の合図を受けた回数を数える
# 置き方：テストのコードが実行時に作る
test_activation_probe_component<public> := class<final_super>(component):

    var<private> ActivatedCount:int = 0
    var<private> DeactivatedCount:int = 0

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            set ActivatedCount += 1
        else if (deactivated_event[SceneEvent]):
            set DeactivatedCount += 1
        false

    GetActivatedCount<public>()<transacts>:int = ActivatedCount

    GetDeactivatedCount<public>()<transacts>:int = DeactivatedCount

# 役割：ActivationSystem の動作確認。SendActivated / SendDeactivated が子孫に届くこと、activate_on_begin_component が開始の次のフレームで 1 回だけ起動の合図を送ることを確かめる
# テストのレベル：この component を付けた entity を 1 つ置くだけ。プレイヤーは要らない
# 結果：出力ログの [TEST] ActivationSystem
activation_system_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "ActivationSystem"}
        TickEvents.PrePhysics.Await()

        # 親 ─ 子（probe）。親から送ると子に届く
        Parent := entity{}
        Entity.AddEntities(array{Parent})
        ChildEntity := entity{}
        Probe := test_activation_probe_component{Entity := ChildEntity}
        ChildEntity.AddComponents(array{Probe})
        Parent.AddEntities(array{ChildEntity})
        Parent.SendActivated()
        Results.CheckInt("SendActivated reaches a child", Probe.GetActivatedCount(), 1)
        Parent.SendDeactivated()
        Results.CheckInt("SendDeactivated reaches a child", Probe.GetDeactivatedCount(), 1)
        Parent.RemoveFromParent()

        # activate_on_begin_component と probe を同じ entity に
        BeginEntity := entity{}
        BeginProbe := test_activation_probe_component{Entity := BeginEntity}
        BeginEntity.AddComponents(array{activate_on_begin_component{Entity := BeginEntity}, BeginProbe})
        Entity.AddEntities(array{BeginEntity})
        Results.CheckInt("activate_on_begin: not yet in the same frame", BeginProbe.GetActivatedCount(), 0)
        Sleep(0.2)
        Results.CheckInt("activate_on_begin: activated once", BeginProbe.GetActivatedCount(), 1)
        BeginEntity.RemoveFromParent()
        if (Results.Finish[]) {}
