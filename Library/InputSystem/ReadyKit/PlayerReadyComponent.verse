using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { PlayerSystem }
using { SceneGraphSystem }
using { InputSystem.InputKit }
using { InputSystem.TooltipKit }

# 役割：起動している間、各プレイヤーの「準備 OK」を持つ。同じ entity の player_input_component の InputAction が押されるたびに、押した人の準備を切り替え、区画全体へ player_ready_changed_event を送り、ReadyChangedEvent に届ける。停止すると全員の準備は消える
# 置き方：エディターで entity に付ける
# 親：起動の合図が届く場所（ゲームの流れなら、ノードの entity かその子孫）
# 同じ entity：押されたことを知らせる player_input_component を 1 つ（押す操作はその InputAction。複数あるとどれを使うか決まらないので、ほかの入力は別の entity に置く）。無ければ押しても切り替わらない（コードの SetReady だけで動かす）
# いつ：起動の合図（activated_event）から停止の合図（deactivated_event）まで。ActiveOnBegin が true ならシミュレーション開始から。コードから Activate / Deactivate を呼んでもよい
# 知らせ：player_ready_changed_event を区画全体へ送り、ReadyChangedEvent に届ける
# 前提：区画（または世界）に player_manager_component が 1 つ
# 外から：Activate / Deactivate / IsActive / IsReady / SetReady / ToggleReady / ResetAll / GetReadyCount / FindInput
player_ready_component<public> := class<final_super>(component):

    # true ならシミュレーション開始から受け付ける。false なら起動の合図から（既定 false）
    @editable:
        ToolTip := ReadyActiveOnBeginToolTip
        Categories := array{ReadyCategory}
    ActiveOnBegin<public>:logic = false

    ReadyChangedEventInternal<private><final>:event(tuple(agent, logic)) = event(tuple(agent, logic)){}

    # だれかの準備が切り替わるたびに、（その人, 準備 OK か）で届く（Await / Subscribe する。外から Signal はできない）
    ReadyChangedEvent<public><final>:listenable(tuple(agent, logic)) = MakeProxyListenable(ReadyChangedEventInternal)

    Views<private>:player_view_set = player_view_set{}

    # 押されたことを受け取っている player_input_component（同じ entity で最初に見つけたもの）
    var<private> Input:?player_input_component = false
    var<private> InputSubscription:?cancelable = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        ConnectInput()
        if (ActiveOnBegin?):
            Activate()

    OnReceive<override>(SceneEvent:scene_event):logic =
        ConnectInput()
        Views.HandleActivation(SceneEvent, Entity, CreateView)
        false

    # 受け付けを始める（全員「準備 OK でない」から）。もう受け付けていれば何もしない
    Activate<public>():void =
        ConnectInput()
        Views.Activate(Entity, CreateView)

    # 受け付けをやめ、全員の準備を消す（準備 OK だった人の知らせは送らない）。受け付けていなければ何もしない
    Deactivate<public>():void =
        Views.Deactivate()

    # 受け付けているあいだ成功する
    IsActive<public>()<decides><transacts>:void =
        Views.IsActive[]

    OnEndSimulation<override>():void =
        InputSubscription.CancelIfSet()
        set InputSubscription = false
        Views.Deactivate()
        (super:)OnEndSimulation()

    # 押されたことを受け取っている player_input_component。同じ entity に無い（まだ見つけていない）と失敗する
    FindInput<public>()<decides><transacts>:player_input_component =
        Input?

    # Agent が準備 OK なら成功する。受け付けていない・その人の view が無い（参加していない）と失敗する
    IsReady<public>(Agent:agent)<decides><transacts>:void =
        FindView[Agent].IsReady[]

    # Agent の準備を Value にする（変わったときだけ知らせる）。受け付けていない・その人の view が無いときは何もしない
    SetReady<public>(Agent:agent, Value:logic):void =
        if (View := FindView[Agent]):
            View.SetReady(Value)

    # Agent の準備を切り替える（押されたときと同じ）。受け付けていない・その人の view が無いときは何もしない
    ToggleReady<public>(Agent:agent):void =
        if (View := FindView[Agent]):
            View.SetReady(if (View.IsReady[]) then false else true)

    # 全員の準備を取り消す
    ResetAll<public>():void =
        for (ViewEntity : Views.GetViews(), View := ViewEntity.GetComponent[player_ready_view_component]):
            View.SetReady(false)

    # 準備 OK の人数（今いる人の view だけを数える。退出した人は数えない）。停止中は 0
    GetReadyCount<public>()<transacts>:int =
        Ready := for (ViewEntity : Views.GetViews(), View := ViewEntity.GetComponent[player_ready_view_component], View.IsReady[]):
            View
        Ready.Length

    # 同じ entity の player_input_component を探して TriggeredEvent を購読する（購読していれば何もしない）。開始時・合図を受けたとき・Activate で呼ぶ（実行時に component を足す順に左右されないように）
    ConnectInput<private>():void =
        if (not InputSubscription?, Found := Entity.GetComponent[player_input_component]):
            set Input = option{Found}
            set InputSubscription = option{Found.TriggeredEvent.Subscribe(OnInputTriggered)}

    OnInputTriggered<private>(Agent:agent):void =
        ToggleReady(Agent)

    FindView<private>(Agent:agent)<decides><transacts>:player_ready_view_component =
        first:
            ViewEntity : Views.GetViews()
            View := ViewEntity.GetComponent[player_ready_view_component]
            View.Player = Agent
        do:
            View

    CreateView<private>(ViewEntity:entity, Slot:player_slot_component):component =
        player_ready_view_component{Entity := ViewEntity, Source := Self, Player := Slot.Player}

    NotifyReadyChanged<internal>(Player:player, Ready:logic):void =
        Entity.SendScoped(player_ready_changed_event{PlayerReady := Self, Agent := Player, Ready := Ready})
        ReadyChangedEventInternal.Signal((Player, Ready))
