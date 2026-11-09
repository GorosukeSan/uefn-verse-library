using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/UI }
using { /Fortnite.com/UI }
using { ActivationSystem }
using { WidgetSystem }
using { WidgetSystem.TooltipKit }

# 選択メニューで選ばれた知らせ
# 方向：choice_menu_component の entity から根へ（SendUp）
# 送り手：choice_menu_component（Menu）。受け手：祖先の component（条件・ゲームの流れ・利用者の component）。消費しない
widget_choice_event<public> := class(scene_event):
    # 送ったメニュー
    Menu<public>:choice_menu_component
    # 選んだ人
    Agent<public>:agent
    # 選んだ項目の番号（Options の並び。0 から）
    Index<public>:int

# 役割：コードを書かずに置ける選択メニュー。Title の下に Options のボタンを縦に並べ、押された項目を知らせる。
#   押されたら widget_choice_event を上へ送り、ChoiceEvent に届け、Targets[番号] の entity へ起動の合図（activated_event）を送る。CloseOnChoice なら、そのあとその人のメニューを閉じる
#   ShowCloseButton なら最後に「閉じる」ボタン（CloseText）を足す（押すと何も選ばずに閉じる）
# 置き方：エディターで entity に付ける。だれに・いつ出すかは player_widget_component の設定（Audience・ActiveOnBegin・起動の合図）と、同じ entity の widget_show_*_component で決める
# 親：起動の合図が届く場所（インタラクトで開くなら interact_trigger_component の Targets にこの entity を入れる）
# 外から：OpenFor(Agent)（ShowFor と同じ）、HideFor(Agent) で閉じる。ChoiceEvent を購読する
# 前提・注意：Mode は既定で Menu（操作を受け取り、表示中は移動できない）。パッドではいちばん上のボタンにフォーカスが移る
choice_menu_component<public> := class<final_super>(player_widget_component):

    Mode<override>:player_widget_mode = player_widget_mode.Menu
    ZOrder<override>:int = 1000

    # メニューの上に出す見出し。空なら出さない
    @editable:
        ToolTip := ChoiceMenuTitleToolTip
        Categories := array{ChoiceMenuCategory}
    Title<public>:string = ""
    # 並べる項目（上から順に、番号 0, 1, 2 ...）
    @editable:
        ToolTip := ChoiceMenuOptionsToolTip
        Categories := array{ChoiceMenuCategory}
    Options<public>:[]string = array{"OK"}
    # 項目ごとに起動の合図を送る entity（Options と同じ並び。足りない・空の項目は送らない）
    @editable:
        ToolTip := ChoiceMenuTargetsToolTip
        Categories := array{ChoiceMenuCategory}
    Targets<public>:[]entity = array{}
    # オンなら、選んだらその人のメニューを閉じる。既定オン
    @editable:
        ToolTip := ChoiceMenuCloseOnChoiceToolTip
        Categories := array{ChoiceMenuCategory}
    CloseOnChoice<public>:logic = true
    # オンなら、最後に何も選ばずに閉じるボタンを足す。既定オン
    @editable:
        ToolTip := ChoiceMenuShowCloseToolTip
        Categories := array{ChoiceMenuCategory}
    ShowCloseButton<public>:logic = true
    # 閉じるボタンの文字
    @editable:
        ToolTip := ChoiceMenuCloseTextToolTip
        Categories := array{ChoiceMenuCategory}
    CloseText<public>:string = "Close"
    # メニューを置く位置（画面の横の割合 0.0〜1.0）。既定 0.5（真ん中）
    @editable_number(float):
        ToolTip := WidgetPositionXToolTip
        Categories := array{ChoiceMenuCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionXRatio<public>:float = 0.5
    # メニューを置く位置（画面の縦の割合 0.0〜1.0）。既定 0.5（真ん中）
    @editable_number(float):
        ToolTip := WidgetPositionYToolTip
        Categories := array{ChoiceMenuCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionYRatio<public>:float = 0.5

    ChoiceEventInternal<private><final>:event(tuple(agent, int)) = event(tuple(agent, int)){}

    # だれかが項目を選ぶたびに、（その人, 項目の番号）で届く（Await / Subscribe する。外から Signal はできない）
    ChoiceEvent<public><final>:listenable(tuple(agent, int)) = MakeProxyListenable(ChoiceEventInternal)

    # Agent にメニューを開く（ShowFor と同じ）
    OpenFor<public>(Agent:agent):void =
        ShowFor(Agent)

    CreateWidget<override>(View:widget_view):widget =
        var Items:[]widget = array{}
        if (Title <> ""):
            set Items += array{text_block{DefaultText := StringToMessage(Title)}}
        Buttons := for (Option : Options):
            button_regular{DefaultText := StringToMessage(Option)}
        for (Button : Buttons):
            set Items += array{Button}
        CloseButton := button_quiet{DefaultText := StringToMessage(CloseText)}
        if (ShowCloseButton?):
            set Items += array{CloseButton}
        if (First := Buttons[0]):
            View.SetDefaultFocus(First)
        else if (ShowCloseButton?):
            View.SetDefaultFocus(CloseButton)
        Choices := if (ShowCloseButton?) then Buttons + array{CloseButton} else Buttons
        spawn{RunChoices(View, Choices, Buttons.Length)}
        MakeScreenCanvas(MakeStack(Items, orientation.Vertical, 8.0), PositionXRatio, PositionYRatio)

    # 押されるたびに知らせる。CloseCount 番（閉じるボタン）なら閉じる。閉じたら終わる
    RunChoices<private>(View:widget_view, Buttons:[]text_button_base, OptionCount:int)<suspends>:void =
        loop:
            MaybeIndex := View.AwaitChoice(Buttons)
            if (Index := MaybeIndex?):
                if (Index >= OptionCount):
                    View.Close()
                    return
                Choose(View.Player, Index)
                if (CloseOnChoice?):
                    View.Close()
                    return
            else:
                return

    Choose<private>(Agent:agent, Index:int):void =
        Entity.SendUp(widget_choice_event{Menu := Self, Agent := Agent, Index := Index})
        ChoiceEventInternal.Signal((Agent, Index))
        if (Target := Targets[Index]):
            Target.SendActivatedBy(Agent)
