using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/UI }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { WidgetSystem.TooltipKit }

# 画面表示が操作を受け取るか
player_widget_mode<public> := enum:
    # 操作を奪わない表示（HUD）。表示中も移動やカメラの操作はそのまま使える
    Hud
    # 操作を受け取る画面（メニュー）。1 人に同時に 1 枚だけ（MenuConflict）。表示するとフォーカスを移す
    Menu

# Hud なら ui_input_mode.None、Menu なら ui_input_mode.All
(Mode:player_widget_mode).ToInputMode<public>()<computes>:ui_input_mode =
    case (Mode):
        player_widget_mode.Hud => ui_input_mode.None
        player_widget_mode.Menu => ui_input_mode.All

# だれの画面に出すか
player_widget_audience<public> := enum:
    # 起動したら区画の全員に出す（途中参加の人にも）
    Everyone
    # ShowFor で決めた人にだけ出す（同じ entity の widget_show_*_component や、利用者のコードが ShowFor / HideFor を呼ぶ）
    Chosen

# player_ui_slot.ZOrder などが受け取る型（0 以上の int）
widget_zorder<public> := type{_X:int where 0 <= _X, _X <= 2147483647}

# ZOrder（範囲外は 0 か上限に丸める）と入力モードから player_ui_slot を作る
MakePlayerUISlot<public>(ZOrder:int, InputMode:ui_input_mode)<transacts>:player_ui_slot =
    Clamped := Clamp(ZOrder, 0, 2147483647)
    if (Z := widget_zorder[Clamped]):
        player_ui_slot{ZOrder := Z, InputMode := InputMode}
    else:
        player_ui_slot{ZOrder := 0, InputMode := InputMode}

# 同じ人にもう別のメニュー（Mode = Menu）が出ているときにどうするか
player_widget_menu_conflict<public> := enum:
    # 前のメニューを閉じて、こちらを出す
    CloseOther
    # 前のメニューを残し、こちらは出さない
    KeepOther

# 役割：起動しているあいだ、プレイヤーの画面に widget を出す基底。派生は CreateWidget（1 人分の widget を作る）だけを書く
#   だれに出すかは Audience（全員 / ShowFor で決めた人）。持ち主のいる entity（CharacterSystem のキャラクターの中など）なら、Everyone は「持ち主だけ」になる。操作を受け取るかは Mode（Hud / Menu）で決める。「アイテムを持っている人」「ボリュームの中の人」などは、同じ entity に置く widget_show_*_component で選ぶ
#   1 人分の窓口（widget_view）が CreateWidget に渡る。閉じた知らせ（HiddenEvent）、この component が転送した知らせ（ReceivedEvent）、ボタン待ち（AwaitClick / AwaitChoice）、Close / Focus を持つ
# 置き方：直接は置かない（派生を置く。MenuKit の choice_menu_component、HudKit の text_hud_component など）。1 entity に何個置いてもよい
# 親：起動の合図が届く場所（ゲームの流れなら、ノードの entity かその子孫）
# ラウンド：必ず fort_round_manager を挟む（オフにする設定は無い）。出すのはラウンドの途中だけ（OnRoundStarted から OnRoundEnded まで）。ActiveOnBegin の画面は OnRoundStarted で出し、OnRoundEnded で全員から消す（UEFN の編集中に画面が残らない）。round manager が無ければ（テストなど）開始時に出し、いつでも出せる
# いつ：ActiveOnBegin なら開始から。起動の合図（activated_event）か Activate で出し始め、停止の合図（deactivated_event）か Deactivate で全員から消す。Audience が Chosen で、だれが起こしたかの分かる起動の合図（activated_by_agent_event。インタラクト・ボリューム・メニューの Targets など）なら、その人に出す（ShowFor）
# 外から：Activate / Deactivate / ShowFor / HideFor / IsShown / IsShownFor / IsOutsideRound / IsOtherMenuShownFor / CanShowTo / FindView / SendToWidgets / SendToWidgetFor
# 絞り込み：同じ entity に widget_audience_filter_component の派生（ShowKit の widget_show_in_group_component など）があれば、それが許す人にだけ出す
# 前提・注意：同じ人の同じ component からは 1 枚しか出さない（ShowFor を何度呼んでも 1 枚）。Mode = Menu は 1 人に同時に 1 枚（MenuConflict）。区画（または世界）に player_manager_component が 1 つ
player_widget_component<public> := class<abstract><final_super>(component):

    # Hud は操作を奪わない表示、Menu は操作を受け取り表示した瞬間にフォーカスを移す（既定 Hud）
    @editable:
        ToolTip := PlayerWidgetModeToolTip
        Categories := array{PlayerWidgetCategory}
    Mode<public>:player_widget_mode = player_widget_mode.Hud
    # だれに出すか。Everyone は起動で全員、Chosen は ShowFor で決めた人だけ（既定 Everyone）
    @editable:
        ToolTip := PlayerWidgetAudienceToolTip
        Categories := array{PlayerWidgetCategory}
    Audience<public>:player_widget_audience = player_widget_audience.Everyone
    # 画面に重ねる順（大きいほど手前。目安：HUD 0〜100、メニュー 1000、通知 10000）。既定 0
    @editable_number(int):
        ToolTip := PlayerWidgetZOrderToolTip
        Categories := array{PlayerWidgetCategory}
        MinValue := option{0}
        MaxValue := option{100000}
    ZOrder<public>:int = 0
    # 同じ人にもう別のメニューが出ているとき、前を閉じるか（CloseOther）、こちらを出さないか（KeepOther）。Mode = Menu のときだけ（既定 CloseOther）
    @editable:
        ToolTip := PlayerWidgetMenuConflictToolTip
        Categories := array{PlayerWidgetCategory}
    MenuConflict<public>:player_widget_menu_conflict = player_widget_menu_conflict.CloseOther
    # オンなら、ゲームの開始から出す（Audience が Chosen なら ShowFor を受け付け始める）。既定オフ
    @editable:
        ToolTip := PlayerWidgetActiveOnBeginToolTip
        Categories := array{PlayerWidgetCategory}
    ActiveOnBegin<public>:logic = false
    # オンなら、この entity に届いた知らせ（起動・停止の合図以外の scene_event）を、出している全員の widget_view.ReceivedEvent へ渡す。既定オフ
    @editable:
        ToolTip := PlayerWidgetForwardToolTip
        Categories := array{PlayerWidgetCategory}
    ForwardReceivedEvents<public>:logic = false
    Views<private>:player_view_set = player_view_set{}
    RoundWatch<private>:round_watcher = round_watcher{}
    # fort_round_manager があるか（無ければ、テストなどとしていつでも出せる）
    var<private> HasRoundManager:logic = false
    # ラウンドの途中（OnRoundStarted から OnRoundEnded まで）なら true。このあいだだけ出す
    var<private> InRound:logic = false

    # 派生が実装する。View.Player の画面に出す widget（いちばん外側）を作って返す。出すたびに 1 回呼ばれる。
    # ボタンを待つなら spawn{...} で View.AwaitClick / AwaitChoice を使う（閉じると false が返って終わる）。表示を変える知らせは View.ReceivedEvent を購読する
    CreateWidget<protected>(View:widget_view):widget

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        # 画面は必ずラウンドを挟む（オフにする設定は持たない）。ActiveOnBegin の画面も OnRoundStarted で出す
        # （SubscribeRoundStarted は、ラウンドの途中なら購読した直後に呼ばれるので取りこぼさない）
        set HasRoundManager = RoundWatch.Start(Entity, OnRoundStarted, OnRoundEnded)
        if (ActiveOnBegin?, not HasRoundManager?):
            Activate()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            # Chosen で、だれが起こしたかの分かる合図（ボタンを押した人など）なら、その人に出す
            if (Audience = player_widget_audience.Chosen, Agent := SceneEvent.FindActivatingAgent[]):
                ShowFor(Agent)
            else:
                Activate()
        else if (deactivated_event[SceneEvent]):
            Deactivate()
        else if (ForwardReceivedEvents?, not player_view_source_event[SceneEvent], not player_event[SceneEvent]):
            SendToWidgets(SceneEvent)
        false

    OnEndSimulation<override>():void =
        RoundWatch.Stop()
        Views.Deactivate()
        (super:)OnEndSimulation()

    OnRoundStarted<private>()<suspends>:void =
        set InRound = true
        if (ActiveOnBegin?):
            Activate()

    OnRoundEnded<private>():void =
        set InRound = false
        Views.Deactivate()

    # Agent に、この component 以外のメニュー（Mode = Menu）が出ているなら成功する。自分のメニューを出し直す前に確かめる（ほかのメニューと 1 枚を取り合わないため）
    IsOtherMenuShownFor<public>(Agent:agent)<decides><transacts>:void =
        Player := player[Agent]
        NoManager:?player_manager_component = false
        Manager := Entity.ResolveScopedComponent(NoManager, player_manager_component)?
        PlayerSlot := Manager.FindSlot[Player]
        Others := for:
            Child : PlayerSlot.Entity.GetEntities()
            Other := Child.GetComponent[player_widget_view_component]
            Other.View.Owner <> Self
            Other.Slot.InputMode = ui_input_mode.All
            Other.View.IsShown[]
        do:
            Other
        Others.Length > 0

    # ラウンドの外（始まる前・終わってから次が始まるまで）なら成功する。このあいだは出さない。fort_round_manager が無ければ失敗する（いつでも出せる）
    IsOutsideRound<public>()<decides><transacts>:void =
        HasRoundManager?
        not InRound?
        # 同じラウンドの始まりで、ほかの部品が先に ShowFor / Activate を呼んでも出せるよう、round manager の番号でも確かめる
        not RoundWatch.IsInRound[]

    # 出し始める（Everyone なら全員に出す。Chosen なら ShowFor を受け付け始める）。もう起動していれば何もしない
    Activate<public>():void =
        if (IsOutsideRound[]):
            return
        # 持ち主のいる entity（キャラクターの中など）なら、持ち主にだけ出す
        if (OwningPlayer := Entity.FindOwningPlayer[]):
            if (not Views.IsActive[]):
                Views.Activate(Entity, CreateView, ?Everyone := false, ?ViewFilter := option{widget_view_filter{Widget := Self}})
                if (Audience = player_widget_audience.Everyone):
                    Views.ShowFor(OwningPlayer)
        else:
            Views.Activate(Entity, CreateView, ?Everyone := if (Audience = player_widget_audience.Everyone) then true else false, ?ViewFilter := option{widget_view_filter{Widget := Self}})

    # 全員の画面から消す（停止の合図と同じ）。widget の中（閉じるボタンなど）からは View.Close を使う
    Deactivate<public>():void =
        Views.Deactivate()

    # Agent の画面に出す（もう出ていれば何もしない）。Chosen で起動していなければ、起動してから出す。Everyone で HideFor した人を戻すときにも使う
    ShowFor<public>(Agent:agent):void =
        if (IsOutsideRound[]):
            return
        if (not Views.IsActive[], Audience = player_widget_audience.Chosen):
            Activate()
        Views.ShowFor(Agent)

    # Agent に出してよいなら成功する（同じ entity の widget_audience_filter_component（widget_show_in_group_component など）がすべて許すとき。1 つも無ければ全員に出してよい）
    CanShowTo<public>(Agent:agent)<decides><transacts>:void =
        Blocking := for (Component : Entity.GetComponents(), Filter := widget_audience_filter_component[Component], not Filter.AllowsWidgetFor[Agent]):
            Filter
        Blocking.Length = 0

    # Agent の画面からだけ消す（ほかの人には出たまま）。出ていなければ何もしない
    HideFor<public>(Agent:agent):void =
        Views.HideFor(Agent)

    # Agent の画面に出ているなら成功する
    IsShownFor<public>(Agent:agent)<decides><transacts>:void =
        Views.FindViewFor[Agent]

    # 起動している（Everyone なら全員に出している、Chosen なら ShowFor を受け付けている）あいだ成功する
    IsShown<public>()<decides><transacts>:void =
        Views.IsActive[]

    # Agent に出している 1 人分の窓口。出ていなければ失敗する
    FindView<public>(Agent:agent)<decides><transacts>:widget_view =
        Views.FindViewFor[Agent].GetComponent[player_widget_view_component].View

    # 出している全員の widget_view.ReceivedEvent へ SceneEvent を渡す（表示を変える知らせ）
    SendToWidgets<public>(SceneEvent:scene_event):void =
        Views.SendToViews(SceneEvent)

    # Agent に出している widget_view.ReceivedEvent へだけ SceneEvent を渡す。出ていなければ何もしない
    SendToWidgetFor<public>(Agent:agent, SceneEvent:scene_event):void =
        if (ViewEntity := Views.FindViewFor[Agent]):
            ViewEntity.SendDown(player_view_source_event{Event := SceneEvent})

    CreateView<private>(ViewEntity:entity, Slot:player_slot_component):component =
        View := widget_view{Player := Slot.Player, Owner := Self}
        Root := CreateWidget(View)
        player_widget_view_component:
            Entity := ViewEntity
            View := View
            Root := Root
            Slot := MakePlayerUISlot(ZOrder, Mode.ToInputMode())

# だれに widget を出してよいかを絞る component の基底。同じ entity の player_widget_component（すべて）は、これが許す人にだけ出す（全員に出すときも、ShowFor でも）
#   派生は AllowsWidgetFor を書く。許す人が増えたら同じ entity の widget の ShowFor、減ったら HideFor を呼ぶ（出ている人を入れ替えるのは派生の役目）
# 置き方：直接は置かない（派生を置く。ShowKit の widget_show_in_group_component など）
widget_audience_filter_component<public> := class<abstract><final_super>(component):
    # Agent に出してよいなら成功する
    AllowsWidgetFor<public>(Agent:agent)<decides><transacts>:void

# player_widget_component が player_view_set に渡す、だれに出してよいかの窓口
widget_view_filter<internal> := class<internal>(player_view_filter):
    Widget<internal>:player_widget_component

    AllowsView<override>(Agent:agent)<decides><transacts>:void =
        Widget.CanShowTo[Agent]

# InEntity に付いている player_widget_component（の派生）をすべて返す。widget_show_*_component が同じ entity の widget を探すときに使う
(InEntity:entity).GetPlayerWidgets<public>()<reads>:[]player_widget_component =
    for (Component : InEntity.GetComponents(), Widget := player_widget_component[Component]):
        Widget
