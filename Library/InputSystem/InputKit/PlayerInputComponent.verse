using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Verse.org/Input/UI }
using { PlayerSystem }
using { SceneGraphSystem }
using { InputSystem }
using { InputSystem.TooltipKit }

# 役割：起動している間、各プレイヤーに InputMapping を足し、InputAction が押されたら区画全体へ player_input_triggered_event を送り、TriggeredEvent に押した人を届ける
# 置き方：エディターで entity に付ける。1 entity に何個置いてもよい（それぞれ別の割り当てを受け持つ）。同じ InputMapping を複数で使ってもよい（1 つを止めても、まだ動いているほうの入力は切れない）
# 親：起動の合図が届く場所（ゲームの流れなら、ノードの entity かその子孫）
# いつ：起動の合図（activated_event）から停止の合図（deactivated_event）まで。ActiveOnBegin が true ならシミュレーション開始から。コードから Activate / Deactivate を呼んでもよい
# 知らせ：player_input_triggered_event を区画全体へ送り、TriggeredEvent に届ける
# 前提：区画（または世界）に player_manager_component が 1 つ
player_input_component<public> := class<final_super>(component):

    # true ならシミュレーション開始から受け付ける。false なら起動の合図から（既定 false）
    @editable:
        ToolTip := InputActiveOnBeginToolTip
        Categories := array{InputCategory}
    ActiveOnBegin<public>:logic = false

    # 受け付けているあいだ各プレイヤーに足すキー割り当て（既定 MenuNavigationMapping）
    @editable:
        ToolTip := InputMappingToolTip
        Categories := array{InputCategory, InputMappingCategory}
    InputMapping<public>:input_mapping = MenuNavigationMapping
    # 押されたことを知らせる操作。InputMapping に含まれるものを選ぶ（既定 NextTab = E キー、ゲームパッドは RB）
    @editable:
        ToolTip := InputActionToolTip
        Categories := array{InputCategory, InputActionCategory}
    InputAction<public>:input_action(logic) = NextTab

    TriggeredEventInternal<private><final>:event(agent) = event(agent){}

    # InputAction が押されるたびに、押した人で届く（Await / Subscribe する。外から Signal はできない）
    TriggeredEvent<public><final>:listenable(agent) = MakeProxyListenable(TriggeredEventInternal)

    Views<private>:player_view_set = player_view_set{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (ActiveOnBegin?):
            Activate()

    OnReceive<override>(SceneEvent:scene_event):logic =
        Views.HandleActivation(SceneEvent, Entity, CreateView)
        false

    # 受け付けを始める（今いる全員と途中参加の人に InputMapping を足す）。もう受け付けていれば何もしない
    Activate<public>():void =
        Views.Activate(Entity, CreateView)

    # 受け付けをやめる（全員から InputMapping を外す。同じ人でまだ動いているほかの player_input_component の割り当ては足し直す）。受け付けていなければ何もしない
    Deactivate<public>():void =
        Views.Deactivate()

    OnEndSimulation<override>():void =
        Views.Deactivate()
        (super:)OnEndSimulation()

    # 起動しているあいだ成功する
    IsActive<public>()<decides><transacts>:void =
        Views.IsActive[]

    CreateView<private>(ViewEntity:entity, Slot:player_slot_component):component =
        player_input_view_component:
            Entity := ViewEntity
            Source := Self
            Player := Slot.Player

    # view から呼ばれる。押されたことを区画全体と TriggeredEvent に知らせる
    NotifyTriggered<internal>(Player:player):void =
        Entity.SendScoped(player_input_triggered_event{Input := Self, Agent := Player, Action := InputAction})
        TriggeredEventInternal.Signal(Player)

# 役割：1 人分のキー割り当てと、押されたときの知らせを受け持つ
# 置き方：実行時に player_input_component が作る（エディターでは置かない）
# いつ：その人の入力（player_input）が取れるまで 1 フレームずつ待ってから（参加した直後・シミュレーション開始の直後はまだ取れないことがある）、InputMapping を足して InputAction を購読する。取れる前に退出したら何もしない
# 前提・注意：止まるときは InputMapping を外したあと、同じ人（同じ slot の下）でまだ動いているほかの player_input_view_component の InputMapping を足し直す。
#   input_mapping は比べられない（等しいかを調べられない）ので、同じ割り当てかどうかは見分けずに全部足し直す。エンジンは AddInputMapping を数えない前提（InputHelpers の HoldInputMapping と同じ）
#   ⚠ 未検証：エンジンが AddInputMapping を数えて持つなら、足し直した分が最後まで外れずに残る。外して同じフレームで足し直したとき、押している途中の入力が切れないか
player_input_view_component<public> := class<final_super>(component):

    # この view を作った player_input_component
    Source<public>:player_input_component
    # この view が受け持つ人
    Player<public>:player

    var Subscription<private>:?cancelable = false
    # InputMapping を足した相手（足してから外すまで）
    var AddedTo<private>:?player_input = false

    # InputMapping を足していれば成功する（入力が取れる前・止まったあとは失敗する）
    IsMappingAdded<internal>()<decides><transacts>:void =
        AddedTo?

    OnSimulate<override>()<suspends>:void =
        MaybeInput := Player.AwaitPlayerInput()
        if (PlayerInput := MaybeInput?):
            PlayerInput.AddInputMapping(Source.InputMapping)
            set AddedTo = option{PlayerInput}
            ActionSubscription := PlayerInput.GetInputEvents(Source.InputAction).TriggerActivationEvent.Subscribe(OnTriggered)
            set Subscription = option{ActionSubscription}

    OnEndSimulation<override>():void =
        Subscription.CancelIfSet()
        set Subscription = false
        if (PlayerInput := AddedTo?):
            set AddedTo = false
            PlayerInput.RemoveInputMapping(Source.InputMapping)
            RestoreOtherMappings(PlayerInput)
        (super:)OnEndSimulation()

    # 同じ slot の下でまだ動いているほかの view の InputMapping を足し直す（外した割り当てがそれと同じでも、その view の入力が切れないように）
    RestoreOtherMappings<private>(PlayerInput:player_input):void =
        if (Slot := Entity.GetParent[]):
            for:
                ViewEntity : Slot.GetEntities()
                Other := ViewEntity.GetComponent[player_input_view_component]
                Other <> Self
                Other.IsMappingAdded[]
            do:
                PlayerInput.AddInputMapping(Other.Source.InputMapping)

    OnTriggered<private>(Payload:tuple(player, logic)):void =
        if (Payload(1)?):
            Source.NotifyTriggered(Player)
