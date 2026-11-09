using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/UI }
using { /Fortnite.com/UI }
using { ActivationSystem }
using { WidgetSystem }
using { WidgetSystem.CardKit }
using { WidgetSystem.PointerKit }
using { WidgetSystem.TooltipKit }

# カードのメニューで選ばれた知らせ
# 方向：card_menu_component の entity から根へ（SendUp）
# 送り手：card_menu_component（Menu）。受け手：祖先の component（条件・ゲームの流れ・利用者の component）。消費しない
widget_card_chosen_event<public> := class(scene_event):
    # 送ったメニュー
    Menu<public>:card_menu_component
    # 選んだ人
    Agent<public>:agent
    # 選ばれたカードの entity（card_info_component の entity）
    Chosen<public>:entity

# 役割：コードを書かずに置けるカードのメニュー。子 entity の card_info_component をカードにして Order の順に並べ、押されたカードの entity へ起動の合図を送る
#   押されたら widget_card_chosen_event を上へ送り、ChosenEvent に届け、そのカードの entity へ起動の合図（SendActivatedBy）を送る。CloseOnChoice なら、そのあとその人のメニューを閉じる
#   マウスが乗る・パッドのフォーカスが来たカードは枠の色で分かる（選ばれている表示）。Virtual Pointer で押したカードは奥へ沈む（PointerKit。押し込みを優先）
#   カードを足す・消すときは子 entity を足す・消すだけ（このメニューの設定は変えない）。出すたびに子を探し直す
# 置き方：エディターで entity に付け、子 entity にカードごとの card_info_component（と、選ばれたら動かす部品）を置く
# 外から：OpenFor(Agent)（ShowFor と同じ）、HideFor(Agent) で閉じる。ChosenEvent を購読する。見た目は Style（コードで差し替える）
# MCP：MCPSystem の WidgetKit から押すときのボタンの ID は、カードの entity の card_info_component の Title（空なら番号）
card_menu_component<public> := class<final_super>(player_widget_component):

    Mode<override>:player_widget_mode = player_widget_mode.Menu
    ZOrder<override>:int = 1000

    # 上に出す見出し。空なら出さない
    @editable:
        ToolTip := CardMenuTitleToolTip
        Categories := array{CardMenuCategory}
    Title<public>:string = ""
    # 1 行に並べるカードの数。既定 4
    @editable_number(int):
        ToolTip := CardMenuColumnsToolTip
        Categories := array{CardMenuCategory}
        MinValue := option{1}
        MaxValue := option{12}
    Columns<public>:int = 4
    # オンなら、選んだらその人のメニューを閉じる。既定オン
    @editable:
        ToolTip := ChoiceMenuCloseOnChoiceToolTip
        Categories := array{CardMenuCategory}
    CloseOnChoice<public>:logic = true
    # オンなら、下に何も選ばずに閉じるボタンを足す。既定オン
    @editable:
        ToolTip := ChoiceMenuShowCloseToolTip
        Categories := array{CardMenuCategory}
    ShowCloseButton<public>:logic = true
    # 閉じるボタンの文字
    @editable:
        ToolTip := ChoiceMenuCloseTextToolTip
        Categories := array{CardMenuCategory}
    CloseText<public>:string = "Close"
    # メニューを置く位置（画面の横の割合 0.0〜1.0）。既定 0.5（真ん中）
    @editable_number(float):
        ToolTip := WidgetPositionXToolTip
        Categories := array{CardMenuCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionXRatio<public>:float = 0.5
    # メニューを置く位置（画面の縦の割合 0.0〜1.0）。既定 0.5（真ん中）
    @editable_number(float):
        ToolTip := WidgetPositionYToolTip
        Categories := array{CardMenuCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionYRatio<public>:float = 0.5
    # Virtual Pointer で押したカードを押し込むときの、カメラの水平の画角（度。押した位置を画面の割合に直すのに使う）。既定 90
    @editable_number(float):
        ToolTip := CardMenuPointerFovToolTip
        Categories := array{CardMenuCategory}
        MinValue := option{10.0}
        MaxValue := option{170.0}
    PointerFieldOfViewDegrees<public>:float = 90.0

    # カードの見た目（コードで差し替える。次に出すときから効く）
    var Style<public>:widget_card_style = widget_card_style{}

    ChosenEventInternal<private><final>:event(tuple(agent, entity)) = event(tuple(agent, entity)){}

    # だれかがカードを選ぶたびに、（その人, カードの entity）で届く（Await / Subscribe する。外から Signal はできない）
    ChosenEvent<public><final>:listenable(tuple(agent, entity)) = MakeProxyListenable(ChosenEventInternal)

    # Agent にメニューを開く（ShowFor と同じ）
    OpenFor<public>(Agent:agent):void =
        ShowFor(Agent)

    # 今の子 entity のカード（Order の小さい順）
    GetCardInfos<public>()<transacts>:[]card_info_component =
        Found := for (Child : Entity.GetEntities(), Info := Child.GetComponent[card_info_component]):
            Info
        SortCards(Found)

    CreateWidget<override>(View:widget_view):widget =
        Infos := GetCardInfos()
        Cards := for (Index -> Info : Infos):
            Info.GetCard(Info.GetTitle(?Fallback := "{Index}"))
        Views := for (Card : Cards):
            MakeCardView(Card, Style)
        Buttons := for (CardView : Views):
            CardView.Button
        var Items:[]widget = array{}
        if (Title <> ""):
            set Items += array{text_block{DefaultText := StringToMessage(Title)}}
        set Items += array{MakeCardGrid(Buttons, Columns, 16.0)}
        CloseButton := button_quiet{DefaultText := StringToMessage(CloseText)}
        if (ShowCloseButton?):
            set Items += array{CloseButton}
        if (First := Buttons[0]):
            View.SetDefaultFocus(First)
        else if (ShowCloseButton?):
            View.SetDefaultFocus(CloseButton)
        for (CardView : Views):
            spawn{CardView.TrackHighlight(View)}
        Rects := for (Index -> Card : Cards):
            CardGridRect(Index, Cards.Length, Columns, 16.0, Style, PositionXRatio, PositionYRatio)
        spawn{RunCardPointerPress(View, Views, Rects, PointerFieldOfViewDegrees)}
        spawn{RunChoices(View, Buttons, Cards, Infos, CloseButton)}
        MakeScreenCanvas(MakeStack(Items, orientation.Vertical, 8.0), PositionXRatio, PositionYRatio)

    # 押されるたびに知らせる。閉じるボタンなら閉じる。閉じたら終わる
    RunChoices<private>(View:widget_view, Buttons:[]button, Cards:[]widget_card, Infos:[]card_info_component, CloseButton:button_quiet)<suspends>:void =
        loop:
            # カードなら番号、閉じるボタンなら -1、先に閉じたら false
            Picked:?int = race:
                View.AwaitButtonChoice(Buttons, ?ButtonIds := for (Card : Cards) { Card.Id }, ?Labels := for (Card : Cards) { Card.Title })
                AwaitClose(View, CloseButton)
            if (Index := Picked?):
                if (Index < 0):
                    View.Close()
                    return
                if (Info := Infos[Index]):
                    Choose(View.Player, Info.Entity)
                if (CloseOnChoice?):
                    View.Close()
                    return
            else:
                return

    # 閉じるボタンが押されたら -1、先に閉じたら false。閉じるボタンを出していなければ待ち続ける
    AwaitClose<private>(View:widget_view, CloseButton:button_quiet)<suspends>:?int =
        if (not ShowCloseButton?):
            Sleep(Inf)
        Clicked := View.AwaitClick(CloseButton.OnClick(), ?ButtonId := "close", ?Label := CloseText)
        if (Clicked?) then option{-1} else false

    Choose<private>(Agent:agent, Chosen:entity):void =
        Entity.SendUp(widget_card_chosen_event{Menu := Self, Agent := Agent, Chosen := Chosen})
        ChosenEventInternal.Signal((Agent, Chosen))
        Chosen.SendActivatedBy(Agent)
