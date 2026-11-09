using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { ConditionSystem }
using { SceneGraphSystem }
using { GameSequenceSystem.TooltipKit }

# ノードに入った知らせ（起動の合図 activated_event の派生なので、起動を待つ部品はこれで動き出す）
# 方向：ノードの entity から下へ（SendDown）
# 送り手：game_node_component。受け手：ノードの配下の部品。消費しない
game_node_entered_event<public> := class(activated_event):
    # 入ったノード
    Node<public>:game_node_component

# ノードから出た理由
game_node_exit_reason<public> := enum:
    # 遷移の条件を満たして、次のノードへ進んだ（または流れを終えた）
    Transitioned
    # 流れが止まった（Stop・ラウンドの終わり・シミュレーションの終わり）
    Stopped
    # JumpTo / Restart で別のノードへ移った
    Jumped

# ノードから出た知らせ（停止の合図 deactivated_event の派生なので、起動を待つ部品はこれで止まる）
# 方向：ノードの entity から下へ（SendDown）
# 送り手：game_node_component。受け手：ノードの配下の部品。消費しない
game_node_exited_event<public> := class(deactivated_event):
    # 出たノード
    Node<public>:game_node_component
    # 出た理由
    Reason<public>:game_node_exit_reason

# 役割：ゲームの流れの 1 段階。入ると配下へ起動、出ると停止を知らせ、子の遷移が進めるようになるまで待つ
# 置き方：エディターで entity に付ける
# 親：game_sequence_component の entity の直下
# 子：遷移（game_transition_component）を付けた entity。この段階の間だけ動かしたい機能もここに置く
# 知らせ：game_node_entered_event / game_node_exited_event を下へ送り、EnteredEvent / ExitedEvent に届ける
# 外から：入る・出るは game_sequence_component が決める（Start / JumpTo / Restart / Stop）
game_node_component<public> := class<final_super>(component):

    # game_sequence_component の FirstNode が空のときに、最初のノードを選ぶ順番（小さいほど先）。同じ値が複数あると、どれが選ばれるかは決まらない
    @editable_number(int):
        ToolTip := NodeOrderToolTip
        Categories := array{GameSequenceCategory}
        MinValue := option{0}
        MaxValue := option{1000}
    Order<public>:int = 0

    var<private> Active:logic = false

    EnteredEventInternal<private><final>:event() = event(){}

    # この段階に入ったときに届く（game_node_entered_event と同じタイミング）（Await / Subscribe する。外から Signal はできない）
    EnteredEvent<public><final>:listenable(tuple()) = MakeProxyListenable(EnteredEventInternal)

    ExitedEventInternal<private><final>:event(game_node_exit_reason) = event(game_node_exit_reason){}

    # この段階から出たときに、出た理由で届く（game_node_exited_event と同じタイミング）（Await / Subscribe する。外から Signal はできない）
    ExitedEvent<public><final>:listenable(game_node_exit_reason) = MakeProxyListenable(ExitedEventInternal)

    TransitionChangedEvent<private>:event() = event(){}

    # この段階に入ってから出るまで（game_node_entered_event から game_node_exited_event まで）成功する
    IsActive<public>()<decides><reads>:void =
        Active?

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (condition_changed_event[SceneEvent]):
            TransitionChangedEvent.Signal()
        false

    # game_sequence_component から呼ばれる。もう入っていれば何もしない
    Enter<internal>():void =
        if (Active?):
            return
        set Active = true
        Entity.SendDown(game_node_entered_event{Node := Self})
        EnteredEventInternal.Signal()

    # game_sequence_component から呼ばれる。入っていなければ何もしない
    Exit<internal>(Reason:game_node_exit_reason):void =
        if (not Active?):
            return
        set Active = false
        Entity.SendDown(game_node_exited_event{Node := Self, Reason := Reason})
        ExitedEventInternal.Signal(Reason)

    # 直下の遷移のどれかが進めるようになるまで待ち、その遷移を返す
    AwaitTransition<internal>()<suspends>:game_transition_component =
        loop:
            if (Transition := FindReadyTransition[]):
                return Transition
            TransitionChangedEvent.Await()

    # 今進める遷移のうち、Priority が一番大きいもの。同じ Priority で複数進めるときは、どれが選ばれるかは決まらない（Priority を分ける）
    FindReadyTransition<public>()<decides><transacts>:game_transition_component =
        var Best:?game_transition_component = false
        for:
            Transition : Entity.GetChildComponents(game_transition_component)
            Transition.IsReady[]
        do:
            if (Current := Best?, Current.Priority >= Transition.Priority):
            else:
                set Best = option{Transition}
        Best?
