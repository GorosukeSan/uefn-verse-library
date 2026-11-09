using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { GameSequenceSystem }
using { _Test }
using { _Test.ConditionSystemTest }

# 役割：ノードから出た理由を覚える（ExitedEvent の Subscribe に Record を渡す）
test_exit_recorder<public> := class:

    var<private> Count:int = 0
    var<private> LastReason:?game_node_exit_reason = false

    Record<public>(Reason:game_node_exit_reason):void =
        set Count += 1
        set LastReason = option{Reason}

    GetCount<public>()<transacts>:int = Count

    # 最後に出た理由が transitioned なら成功する
    WasTransitioned<public>()<decides><transacts>:void =
        LastReason? = game_node_exit_reason.Transitioned

    # 最後に出た理由が jumped なら成功する
    WasJumped<public>()<decides><transacts>:void =
        LastReason? = game_node_exit_reason.Jumped

    # 最後に出た理由が stopped なら成功する
    WasStopped<public>()<decides><transacts>:void =
        LastReason? = game_node_exit_reason.Stopped

# 役割：流れの状態の変化を覚える（StateChangedEvent の Subscribe に Record を渡す）
test_sequence_state_recorder<public> := class:

    var<private> Seen:[]game_sequence_state = array{}

    Record<public>(State:game_sequence_state):void =
        set Seen += array{State}

    # State を一度でも受けていれば成功する
    HasSeen<public>(State:game_sequence_state)<decides><transacts>:void =
        Seen.Find[State]

# 役割：GameSequenceSystem の動作確認。Order で決まる最初のノード、遷移（条件が 2 つなら両方満たすまで進まない）、Finished、Restart、JumpTo、Stop、出た理由、StartOnActivate の流れ（ノードの下に置いた流れが、そのノードに入ると始まり、出ると止まる）、同じフレームの Stop → Start（止まってから始め直す。親が同じノードに入り直したときの子の流れ）を確かめる
# テストのレベル：この component を付けた entity を 1 つ置くだけ（流れ・ノード・遷移・条件はテストが実行時に作る）。プレイヤーは要らない
# 作る流れ：
#   sequence（StartOnRoundStart / StartOnBegin はオフ）
#   ├ B（Order 1）─ 終わり（Target なし）─ 条件 2 つ
#   ├ A（Order 0）─ B へ ─ 条件 1 つ
#   └ C（Order 5）─ 遷移なし（JumpTo でだけ入る）
#     └ inner（StartOnActivate、StartOnRoundStart はオフ）─ D（Order 0）
# 結果：出力ログの [TEST] GameSequenceSystem
game_sequence_system_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "GameSequenceSystem"}
        TickEvents.PrePhysics.Await()
        SequenceEntity := entity{}
        Sequence := game_sequence_component{Entity := SequenceEntity, StartOnRoundStart := false, StartOnBegin := false}
        SequenceEntity.AddComponents(array{Sequence})
        Entity.AddEntities(array{SequenceEntity})

        # 並び順が最初にならないように、B を先に足す
        B := AddNode(SequenceEntity, 1)
        A := AddNode(SequenceEntity, 0)
        C := AddNode(SequenceEntity, 5)
        AToB := AddTransition(A, option{B.Entity})
        CondAB := AddCondition(AToB)
        BEnd := AddTransition(B, false)
        CondEnd1 := AddCondition(BEnd)
        CondEnd2 := AddCondition(BEnd)
        InnerEntity := entity{}
        Inner := game_sequence_component{Entity := InnerEntity, StartOnRoundStart := false, StartOnActivate := true}
        InnerEntity.AddComponents(array{Inner})
        C.Entity.AddEntities(array{InnerEntity})
        D := AddNode(InnerEntity, 0)

        AExits := test_exit_recorder{}
        AExitSubscription := A.ExitedEvent.Subscribe(AExits.Record)

        Results.Check("first node is the lowest Order (not child order)", if (Sequence.FindFirstNode[] = A) then true else false)
        Results.Check("idle before Start", if (Sequence.State = game_sequence_state.Idle) then true else false)
        Results.Check("StartOnActivate: inner sequence idle before C is entered", if (Inner.State = game_sequence_state.Idle) then true else false)

        Sequence.Start()
        Sleep(0.2)
        Results.Check("running after Start", if (Sequence.IsRunning[]) then true else false)
        Results.Check("current node is A", if (Sequence.CurrentNode? = A) then true else false)
        Results.Check("A is active", if (A.IsActive[]) then true else false)

        CondAB.SetSatisfied(true)
        Sleep(0.2)
        Results.Check("moved to B when A's condition is satisfied", if (Sequence.CurrentNode? = B) then true else false)
        Results.Check("A exited with transitioned", if (AExits.WasTransitioned[]) then true else false)
        Results.Check("A is not active", if (A.IsActive[]) then false else true)

        CondEnd1.SetSatisfied(true)
        Sleep(0.2)
        Results.Check("two conditions: one is not enough", if (Sequence.CurrentNode? = B) then true else false)
        CondEnd2.SetSatisfied(true)
        Sleep(0.2)
        Results.Check("two conditions: both -> Finished", if (Sequence.State = game_sequence_state.Finished) then true else false)
        Results.Check("no current node after Finished", if (Sequence.CurrentNode?) then false else true)

        # やり直す前に条件を戻す（戻さないと A からすぐ B、B からすぐ終わりへ進む）
        CondAB.SetSatisfied(false)
        CondEnd1.SetSatisfied(false)
        Sequence.Restart()
        Sleep(0.2)
        Results.Check("Restart starts again from A", if (Sequence.CurrentNode? = A) then true else false)

        Sequence.JumpTo(C)
        Sleep(0.2)
        Results.Check("JumpTo moves to C", if (Sequence.CurrentNode? = C) then true else false)
        Results.Check("A exited with jumped", if (AExits.WasJumped[]) then true else false)
        Results.Check("StartOnActivate: inner sequence starts when C is entered", if (Inner.CurrentNode? = D) then true else false)

        Sequence.Stop()
        Sleep(0.2)
        Results.Check("Stop -> Stopped", if (Sequence.State = game_sequence_state.Stopped) then true else false)
        Results.Check("C is not active after Stop", if (C.IsActive[]) then false else true)
        Results.Check("StartOnActivate: inner sequence stops when C is exited", if (Inner.State = game_sequence_state.Stopped) then true else false)
        Results.Check("StartOnActivate: D is not active after C is exited", if (D.IsActive[]) then false else true)

        Sequence.JumpTo(B)
        Sleep(0.2)
        Results.Check("JumpTo while stopped starts at B", if (Sequence.CurrentNode? = B) then true else false)

        # 同じフレームの Stop → Start：捨てずに、止まってから最初のノード（A）で始め直す
        States := test_sequence_state_recorder{}
        StateSubscription := Sequence.StateChangedEvent.Subscribe(States.Record)
        Sequence.Stop()
        Sequence.Start()
        Sleep(0.2)
        Results.Check("Stop then Start in the same frame: running again", if (Sequence.IsRunning[]) then true else false)
        Results.Check("Stop then Start in the same frame: starts again from A", if (Sequence.CurrentNode? = A) then true else false)
        Results.Check("Stop then Start in the same frame: went through Stopped", if (States.HasSeen[game_sequence_state.Stopped]) then true else false)
        StateSubscription.Cancel()

        # 入れ子：親が同じノード（C）に入り直すと、子の流れは停止と起動の合図を同じフレームで続けて受ける。止まったままにならず、子は D から進む
        Sequence.JumpTo(C)
        Sleep(0.2)
        Sequence.JumpTo(C)
        Sleep(0.2)
        Results.Check("re-enter the same node: inner sequence is running", if (Inner.IsRunning[]) then true else false)
        Results.Check("re-enter the same node: inner sequence is at D", if (Inner.CurrentNode? = D) then true else false)
        Sequence.Stop()

        AExitSubscription.Cancel()
        SequenceEntity.RemoveFromParent()
        if (Results.Finish[]) {}

    AddNode<private>(Parent:entity, Order:int):game_node_component =
        NodeEntity := entity{}
        Node := game_node_component{Entity := NodeEntity, Order := Order}
        NodeEntity.AddComponents(array{Node})
        Parent.AddEntities(array{NodeEntity})
        Node

    AddTransition<private>(Node:game_node_component, Target:?entity):entity =
        Node.Entity.AddTestChild(game_transition_component{Entity := entity{}, Target := Target})

    AddCondition<private>(TransitionEntity:entity):test_condition_component =
        Condition := test_condition_component{Entity := entity{}}
        TransitionEntity.AddTestChild(Condition)
        Condition
