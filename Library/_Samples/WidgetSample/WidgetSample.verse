using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Colors }
using { /Verse.org/Input }
using { /Verse.org/Input/UI }
using { /Fortnite.com/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/UI }
using { ActivationSystem }
using { InputSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { WidgetSystem }

# 画面の文言
WidgetSampleTitle<localizes>:message = "画面サンプル（HUD。入力モード None：移動もカメラも使える）"
WidgetSamplePlayerMessage<localizes>(Agent:agent):message = "プレイヤー: {Agent}"
WidgetSampleElapsedMessage<localizes>(Seconds:int):message = "経過: {Seconds} 秒（1 秒ごとに SendToWidgets で更新）"
WidgetSampleLastEventMessage<localizes>(Label:string):message = "最後に受けた知らせ: {Label}"
WidgetSampleHint<localizes>:message = "C（RT）でメニューを開く（widget_sample_opener_component）"
MenuSampleTitle<localizes>:message = "メニュー（入力モード Menu = All）"
MenuSampleBody<localizes>:message = "表示中は移動やカメラの操作が止まり、フォーカスがこの画面に移ります。ボタンを押すと閉じます（Esc でも閉じます）"
MenuSampleClose<localizes>:message = "閉じる"

# HUD の経過時間の更新。widget_sample_component が 1 秒ごとに SendToWidgets する
# 方向：widget_sample_component から自分の表示すべてへ（SendToWidgets → widget_view.ReceivedEvent）。消費しない
widget_sample_tick_event<public> := class(scene_event):
    ElapsedSeconds<public>:int

# メニューを開いた知らせ。開いた人の slot の下へ player_event として送られ、同じ人の HUD（widget_sample_component の表示）の widget_view.ReceivedEvent に届く
# 方向：widget_sample_opener の view から同じ人の slot へ（SendToPlayer）。消費しない
widget_sample_menu_opened_event<public> := class(scene_event):
    Agent<public>:agent

# 役割：1 人分の HUD の表示を、届いた知らせで変える（widget_sample_component が窓口ごとに作り、ReceivedEvent に Subscribe する）
widget_sample_hud_updater<public> := class:
    ElapsedText<public>:text_block
    LastEventText<public>:text_block

    # Forward された知らせ（tick）と、同じ人のほかの view からの player_event の中身が届く
    OnReceived<public>(SceneEvent:scene_event):void =
        if (Tick := widget_sample_tick_event[SceneEvent]):
            ElapsedText.SetText(WidgetSampleElapsedMessage(Tick.ElapsedSeconds))
        else if (widget_sample_menu_opened_event[SceneEvent]):
            LastEventText.SetText(WidgetSampleLastEventMessage("widget_sample_menu_opened_event（player_event で届いた）"))
        else:
            LastEventText.SetText(WidgetSampleLastEventMessage("その他の scene_event"))

    OnHidden<public>(Unused:tuple()):void =
        Print("[widget_sample] HUD を外しました（HiddenEvent）", ?Duration := 3.0)

# 役割：HUD の見本（player_widget_component の派生。Mode = Hud）。起動の合図で全員に名前・経過時間・最後に受けた知らせを出し、1 秒ごとに経過時間を SendToWidgets で全員の表示に渡す（表示ごとに毎フレーム数えない）。同じ人のほかの view から player_event で届いた知らせも表示する
# 置き方：エディターで entity に付け、同じ entity に activate_on_begin_component も付ける（起動の合図で表示が始まる）。区画（または世界）に player_manager_component を 1 つ置く
# 試し方：セッションを始めると左上に名前・経過時間が出る。widget_sample_opener_component を置いて C（RT）を押すと「最後に受けた知らせ」が変わり、MenuEntity に入れた menu_sample_component のメニューがその人にだけ開く
# 知らせ：widget_sample_tick_event を 1 秒ごとに自分の表示へ SendToWidgets する
widget_sample_component<public> := class<final_super>(player_widget_component):

    CreateWidget<override>(View:widget_view):widget =
        ElapsedText := text_block{DefaultText := WidgetSampleElapsedMessage(0), DefaultTextColor := NamedColors.White}
        LastEventText := text_block{DefaultText := WidgetSampleLastEventMessage("（まだ無し）"), DefaultTextColor := NamedColors.White}
        Updater := widget_sample_hud_updater{ElapsedText := ElapsedText, LastEventText := LastEventText}
        View.ReceivedEvent.Subscribe(Updater.OnReceived)
        View.HiddenEvent.Subscribe(Updater.OnHidden)
        Items:[]widget = array:
            text_block{DefaultText := WidgetSampleTitle, DefaultTextColor := NamedColors.White}
            text_block{DefaultText := WidgetSamplePlayerMessage(View.Player), DefaultTextColor := NamedColors.White}
            ElapsedText
            LastEventText
            text_block{DefaultText := WidgetSampleHint, DefaultTextColor := NamedColors.White}
        Lines := MakeStack(Items, orientation.Vertical, 4.0)
        Panel := overlay{}
        Panel.AddWidget(overlay_slot{Widget := color_block{DefaultColor := NamedColors.Black, DefaultOpacity := 0.7}, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill})
        Panel.AddWidget(overlay_slot{Widget := Lines, Padding := margin{Left := 16.0, Top := 12.0, Right := 16.0, Bottom := 12.0}})
        MakeScreenCanvas(Panel, 0.15, 0.2)

    OnSimulate<override>()<suspends>:void =
        StartSeconds := GetSimulationElapsedTime()
        loop:
            Sleep(1.0)
            if (IsShown[]):
                Elapsed := GetSimulationElapsedTime() - StartSeconds
                Seconds := if (Whole := Floor[Elapsed]) then Whole else 0
                SendToWidgets(widget_sample_tick_event{ElapsedSeconds := Seconds})

# 役割：メニューの見本（player_widget_component の派生。Mode = Menu、Audience = Chosen）。OpenFor で開いた人にだけメニューを出し、閉じるボタン（button_loud。Back = Esc でも押せる）を押した人のメニューだけを閉じる。Hud との違い（表示中は移動できない・フォーカスが移る）を見る
# ボタン待ちは View.AwaitClick（閉じると false が返って終わるので、待ちが残らない）
# 置き方：エディターで entity に付ける（widget_sample_opener_component の MenuEntity に入れる）。区画（または世界）に player_manager_component を 1 つ置く
# 試し方：開いているあいだは移動できない。ボタンか Esc（Back。MenuNavigationMapping が有効なとき）で閉じる。閉じると出力ログに出る
menu_sample_component<public> := class<final_super>(player_widget_component):

    # 既定を Menu・Chosen にする（@editable なので変えて比べてもよい）
    Mode<override>:player_widget_mode = player_widget_mode.Menu
    Audience<override>:player_widget_audience = player_widget_audience.Chosen
    ZOrder<override>:int = 1000

    # Agent にだけメニューを開く
    OpenFor<public>(Agent:agent):void =
        ShowFor(Agent)

    CreateWidget<override>(View:widget_view):widget =
        CloseButton := button_loud{DefaultText := MenuSampleClose}
        set CloseButton.TriggeringInputAction = option{Back}
        View.SetDefaultFocus(CloseButton)
        spawn{CloseOnClick(View, CloseButton)}
        Items:[]widget = array:
            text_block{DefaultText := MenuSampleTitle, DefaultTextColor := NamedColors.White}
            text_block{DefaultText := MenuSampleBody, DefaultTextColor := NamedColors.White}
            CloseButton
        Lines := MakeStack(Items, orientation.Vertical, 8.0)
        Panel := overlay{}
        Panel.AddWidget(overlay_slot{Widget := color_block{DefaultColor := NamedColors.Black, DefaultOpacity := 0.85}, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill})
        Panel.AddWidget(overlay_slot{Widget := Lines, Padding := margin{Left := 32.0, Top := 24.0, Right := 32.0, Bottom := 24.0}})
        MakeScreenCanvas(Panel, 0.5, 0.5)

    CloseOnClick<private>(View:widget_view, CloseButton:button_loud)<suspends>:void =
        OnClick := CloseButton.OnClick()
        Clicked := View.AwaitClick(OnClick)
        if (Clicked?):
            Print("[menu_sample] 閉じます（View.Close）", ?Duration := 3.0)
            View.Close()

# 役割：メニューを開く入力の見本（player_view_set で 1 人ずつ）。OpenAction（既定 C / RT）が押されたら、MenuEntity の player_widget_component を押した人にだけ開き（ShowFor）、同じ人の slot の下へ widget_sample_menu_opened_event を player_event として送る（同じ人の HUD に届く）
# 置き方：エディターで entity に付け、MenuEntity に menu_sample_component を付けた entity を入れる。区画（または世界）に player_manager_component を 1 つ置く
# 前提・注意：OpenMapping は停止時に外すので、キャラクター操作の Mapping は選ばない
widget_sample_opener_component<public> := class<final_super>(component):

    # オンなら、シミュレーション開始から受け付ける。オフなら起動の合図を待つ
    @editable
    StartOnBegin<public>:logic = true

    # メニューを開く入力（OpenMapping に含まれているものを選ぶ）
    @editable
    OpenAction<public>:input_action(logic) = NextPage

    # 動いているあいだ各プレイヤーに足すキー割り当て（停止時に外す）
    @editable
    OpenMapping<public>:input_mapping = MenuNavigationMapping

    # menu_sample_component を付けた entity
    @editable
    MenuEntity<public>:?entity = false

    Views<private>:player_view_set = player_view_set{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (StartOnBegin?):
            Views.Activate(Entity, CreateView)

    OnReceive<override>(SceneEvent:scene_event):logic =
        Views.HandleActivation(SceneEvent, Entity, CreateView)
        false

    OnEndSimulation<override>():void =
        Views.Deactivate()
        (super:)OnEndSimulation()

    # view から呼ばれる。Agent にだけメニューを開く
    OpenMenu<internal>(Agent:agent):void =
        if (Target := MenuEntity?):
            for (Widget : Target.GetPlayerWidgets()):
                Widget.ShowFor(Agent)
        else:
            Print("[widget_sample_opener] MenuEntity が未設定です", ?Duration := 4.0)

    CreateView<private>(ViewEntity:entity, Slot:player_slot_component):component =
        widget_sample_opener_view_component{Entity := ViewEntity, Source := Self, Player := Slot.Player}

# 役割：1 人分の開く入力。OpenMapping を足し、OpenAction が押されるたびにメニューを開き、同じ人の HUD へ知らせる
# 置き方：実行時に widget_sample_opener_component が作る（エディターでは置かない）
widget_sample_opener_view_component<public> := class<final_super>(component):

    Source<public>:widget_sample_opener_component
    Player<public>:player

    OnSimulate<override>()<suspends>:void =
        MaybeInput := Player.AwaitPlayerInput()
        if (PlayerInput := MaybeInput?):
            race:
                PlayerInput.HoldInputMapping(Source.OpenMapping, true)
                loop:
                    PlayerInput.AwaitPressed(Source.OpenAction)
                    Print("[widget_sample_opener] メニューを開きます", ?Duration := 3.0)
                    Self.SendToPlayer(widget_sample_menu_opened_event{Agent := Player})
                    Source.OpenMenu(Player)
        else:
            Print("[widget_sample_opener] この人の入力（player_input）が取れません")
