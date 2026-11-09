using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Game }
using { ActivationSystem }
using { SceneGraphSystem }
using { GameSequenceSystem.TooltipKit }

# ゲームの流れ（game_sequence_component）の状態
game_sequence_state<public> := enum:
    # まだ始めていない
    Idle
    # ノードを進めている
    Running
    # Stop・ラウンドの終わりで止まった
    Stopped
    # 最後の遷移（Target が空）まで進んだ
    Finished
    # 最初のノードが無い・Target にノードが無いなどで止まった
    Failed

# 状態の名前（"Idle" など、英語のまま）。デバッグ表示・ログ用
(State:game_sequence_state).ToString<public>()<computes>:string =
    case (State):
        game_sequence_state.Idle => "Idle"
        game_sequence_state.Running => "Running"
        game_sequence_state.Stopped => "Stopped"
        game_sequence_state.Finished => "Finished"
        game_sequence_state.Failed => "Failed"

# ゲームの流れの状態が変わった知らせ
# 方向：game_sequence_component の entity から根へ（SendUp）
# 送り手：game_sequence_component。受け手：祖先の component（流れの外の進行役など）。消費しない
game_sequence_state_changed_event<public> := class(scene_event):
    # 送った流れ
    Sequence<public>:game_sequence_component
    # 変わったあとの状態
    State<public>:game_sequence_state

# 役割：最初のノードからゲームの流れを進める。ノードの遷移が進めるようになるたびに次のノードへ移り、Target の無い遷移で終わる
# 置き方：エディターで entity に付ける。1 つの流れに 1 つ。レベルにいくつ置いてもよい（それぞれ自分の直下のノードだけを進め、ほかの流れとは混ざらない。世界や区画から探されることもないので、区画も要らない）
# 子：ノード（game_node_component）を付けた entity を直下に
# いつ始めるか：StartOnRoundStart が true ならラウンドの開始で始め、ラウンドの終わりで止める（true の流れはどれも同時に始まる）。StartOnActivate が true なら起動の合図で始め、停止の合図で止める（ほかの流れのノードの下に置けば、そのノードのあいだだけ進む）。StartOnBegin が true ならシミュレーション開始で始める。どれも false にして、コードから Start を呼んでもよい
# 同じレベルに複数のゲームを置くとき：StartOnRoundStart をオフにして、そのゲームの始まり（StartOnActivate の合図か Start）で始める
# 知らせ：game_sequence_state_changed_event を上へ送り、StateChangedEvent に届ける
# 外から：Start / Stop / Restart / JumpTo。IsRunning / State / CurrentNode で今の状態を問い合わせる
# 前提・注意：ノードを移るときは 1 フレーム空ける（同じフレームで遷移が回り続けないように）。Stop と Start / Restart / JumpTo が同じフレームに続けて来たら、来た順に処理する（止めてから、改めて始める）
game_sequence_component<public> := class<final_super>(component):

    # 最初に入るノード（game_node_component を付けた entity）。空なら直下の子のノードで Order が一番小さいもの。既定 空
    @editable:
        ToolTip := FirstNodeToolTip
        Categories := array{GameSequenceCategory}
    FirstNode<public>:?entity = false

    # true ならラウンドの開始で始め、ラウンドの終わりで止める。既定 true
    @editable:
        ToolTip := SequenceStartOnRoundStartToolTip
        Categories := array{GameSequenceCategory}
    StartOnRoundStart<public>:logic = true

    # true なら起動の合図（activated_event。親のノードに入った・activate_on_round_component のラウンドの始まりなど）で始め、停止の合図（deactivated_event）で止める。受けた合図はここで止め、配下のノードの部品へは届けない（部品はノードに入ったときの合図で動く）。既定 false
    @editable:
        ToolTip := SequenceStartOnActivateToolTip
        Categories := array{GameSequenceCategory}
    StartOnActivate<public>:logic = false

    # true ならシミュレーション開始で始める（1 フレーム待ってから）。既定 false
    @editable:
        ToolTip := SequenceStartOnBeginToolTip
        Categories := array{GameSequenceCategory}
    StartOnBegin<public>:logic = false

    # 今の状態。まだ始めていなければ Idle
    var<private> State<public>:game_sequence_state = game_sequence_state.Idle
    # 今入っているノード。入っていなければ false
    var<private> CurrentNode<public>:?game_node_component = false
    # 最後に Failed になったときの理由。Failed でなくなっても次に失敗するまで残る。一度も失敗していなければ false
    var<private> LastError<public>:?game_node_error = false
    Rounds<private>:round_watcher = round_watcher{}
    # Stop が呼ばれ、まだ流れが止まっていない（RunFrom が見て止まる。そのあとに来た Start などの依頼は、止まってから受け付ける）
    var<private> StopRequested:logic = false

    # まだ受け付けていない Start / Restart / JumpTo の依頼があるか
    var<private> HasRequest:logic = false
    # 依頼で入るノード。false なら最初のノード
    var<private> RequestedNode:?game_node_component = false
    # 今のノードの遷移が進めるようになったときの結果（RunFrom の中だけで使う）
    var<private> Transition:?game_transition_component = false

    StateChangedEventInternal<private><final>:event(game_sequence_state) = event(game_sequence_state){}

    # 状態が変わるたびに、新しい状態で届く（game_sequence_state_changed_event と同じタイミング）（Await / Subscribe する。外から Signal はできない）
    StateChangedEvent<public><final>:listenable(game_sequence_state) = MakeProxyListenable(StateChangedEventInternal)

    RequestEvent<private>:event() = event(){}
    StopEvent<private>:event() = event(){}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (StartOnRoundStart?):
            Started := Rounds.Start(Entity, OnRoundStarted, Stop)
            if (not Started?):
                Print("[game_sequence_component] fort_round_manager が見つかりません（StartOnRoundStart は効きません）")

    OnEndSimulation<override>():void =
        Rounds.Stop()
        (super:)OnEndSimulation()

    # StartOnActivate のとき、起動の合図で Start、停止の合図で Stop し、合図を消費する（配下のノードの部品へ届けない）
    OnReceive<override>(SceneEvent:scene_event):logic =
        if (not StartOnActivate?):
            false
        else if (activated_event[SceneEvent]):
            Start()
            true
        else if (deactivated_event[SceneEvent]):
            Stop()
            true
        else:
            false

    OnSimulate<override>()<suspends>:void =
        if (StartOnBegin?):
            # 同じ木のノードがみな OnBeginSimulation を終えてから入るように、1 フレーム待つ
            TickEvents.PrePhysics.Await()
            Start()
        loop:
            if (HasRequest?):
                StartNode := RequestedNode
                set HasRequest = false
                set RequestedNode = false
                RunSequence(StartNode)
            else:
                RequestEvent.Await()

    # 流れを最初のノードから始める。もう進めているなら何もしない（最初からやり直すなら Restart）。Stop のすぐあと（まだ止まりきっていない）なら、止まってから始める
    Start<public>():void =
        if (IsRunning[], not StopRequested?):
            return
        Request(false)

    # 流れを止める（今のノードからは Reason が Stopped で出る）。状態は Stopped になる。進めていなければ何もしない
    Stop<public>():void =
        set HasRequest = false
        set RequestedNode = false
        if (IsRunning[]):
            set StopRequested = true
            StopEvent.Signal()

    # 最初のノードからやり直す。進めていなければ Start と同じ。Stop のすぐあとなら、止まってから始める
    Restart<public>():void =
        Request(false)

    # Node へ移る（今のノードからは Reason が Jumped で出る）。進めていなければ Node から始める。Node はこの流れの直下でなくてもよい。Stop のすぐあとなら、止まってから（Reason は Stopped）Node から始める
    JumpTo<public>(Node:game_node_component):void =
        Request(option{Node})

    # ノードを進めているあいだ（State が Running のあいだ）成功する
    IsRunning<public>()<decides><transacts>:void =
        State = game_sequence_state.Running

    # 最初のノード。FirstNode を決めていればその entity の game_node_component（付いていなければ失敗し、子へは探しにいかない）。空なら直下の子のノードで Order が一番小さいもの（孫は見ない）。無ければ失敗する
    FindFirstNode<public>()<decides><transacts>:game_node_component =
        if (FirstNodeEntity := FirstNode?):
            FirstNodeEntity.GetComponent[game_node_component]
        else:
            var Best:?game_node_component = false
            for (Node : Entity.GetChildComponents(game_node_component)):
                if (Current := Best?, Current.Order <= Node.Order):
                else:
                    set Best = option{Node}
            Best?

    OnRoundStarted<private>()<suspends>:void =
        Start()

    # 依頼を受ける。止める途中（StopRequested）なら下ろさずに残し、RunFrom が止まってから OnSimulate のループがこの依頼で始め直す（来た順に処理する）
    Request<private>(Node:?game_node_component):void =
        set HasRequest = true
        set RequestedNode = Node
        RequestEvent.Signal()

    RunSequence<private>(StartNode:?game_node_component)<suspends>:void =
        if (Node := StartNode?):
            RunFrom(Node)
        else if (First := FindFirstNode[]):
            RunFrom(First)
        else:
            Fail(game_node_empty_error{})

    RunFrom<private>(StartNode:game_node_component)<suspends>:void =
        SetState(game_sequence_state.Running)
        var Node:game_node_component = StartNode
        defer:
            if (LastNode := CurrentNode?):
                LastNode.Exit(game_node_exit_reason.Stopped)
            set CurrentNode = false
            # 流れが終わったので、残っている止める依頼は済んだ扱い（Finished / Failed で終わったときに残さない）
            set StopRequested = false
            if (State = game_sequence_state.Running):
                SetState(game_sequence_state.Stopped)
        loop:
            # Stop / JumpTo は待っていないあいだ（ノードに入る途中・次のフレームを待つあいだ）に届くこともあるので、フラグで見る
            # 止める依頼を先に見る（Stop のあとに来た依頼は HasRequest に残り、止まってから OnSimulate のループが受ける）
            if (StopRequested?):
                set StopRequested = false
                return
            if (HasRequest?):
                Requested := RequestedNode
                set HasRequest = false
                set RequestedNode = false
                if (Target := Requested?):
                    set Node = Target
                else if (First := FindFirstNode[]):
                    set Node = First
                else:
                    Fail(game_node_empty_error{})
                    return
            set CurrentNode = option{Node}
            Node.Enter()
            set Transition = false
            if (not StopRequested?, not HasRequest?):
                race:
                    block:
                        Ready := Node.AwaitTransition()
                        set Transition = option{Ready}
                    StopEvent.Await()
                    RequestEvent.Await()
            if (Ready := Transition?):
                set Transition = false
                Node.Exit(game_node_exit_reason.Transitioned)
                set CurrentNode = false
                if (Target := Ready.Target?):
                    if (NextNode := Target.GetComponent[game_node_component]):
                        set Node = NextNode
                    else:
                        Fail(game_node_not_found_error{Target := Target})
                        return
                else:
                    SetState(game_sequence_state.Finished)
                    return
                # 同じフレームで遷移が回り続けないように、次のノードへは次のフレームで入る（その間の Stop / JumpTo はループの先頭で見る）
                TickEvents.PrePhysics.Await()
            else:
                Node.Exit(if (StopRequested?) then game_node_exit_reason.Stopped else game_node_exit_reason.Jumped)
                set CurrentNode = false

    SetState<private>(NewState:game_sequence_state):void =
        set State = NewState
        Entity.SendUp(game_sequence_state_changed_event{Sequence := Self, State := NewState})
        StateChangedEventInternal.Signal(NewState)

    Fail<private>(Error:game_node_error):void =
        set LastError = option{Error}
        SetState(game_sequence_state.Failed)
