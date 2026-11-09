using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Colors }
using { /Verse.org/Input }
using { /Verse.org/Input/UI }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Input }
using { /Fortnite.com/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/UI }
using { ActivationSystem }
using { InputSystem }
using { PlayerSystem }
using { SceneGraphSystem }

# 画面の文言
InputSampleTitle<localizes>:message = "入力サンプル"
InputSampleStepMessage<localizes>(Index:int, Total:int, Action:string):message = "{Index} / {Total}　{Action}"
InputSampleMappingMessage<localizes>(Mapping:string):message = "Mapping: {Mapping}"
InputSampleKeyMessage<localizes>(Key:string):message = "キー: {Key}（既定の割り当て。設定で変えていると違う）"
InputSampleNoteMessage<localizes>(Note:string):message = "{Note}"
InputSampleWaiting<localizes>(Seconds:int):message = "入力: この入力を押してください（{Seconds} 秒ごとに次へ切り替わります）"
InputSampleDetected<localizes>:message = "入力: 検知しました"
InputSampleNotDetectable<localizes>:message = "入力: この Mapping には Verse から検知できる入力アクションがありません"
InputSampleButtonMessage<localizes>(Mapping:string, Action:string):message = "{Mapping}\n{Action}"
InputSampleButtonWaiting<localizes>:message = "ボタン: 左のボタンの Click を待っています（フォーカスなし。TriggeringInputAction で押せます）"
InputSampleButtonClicked<localizes>:message = "ボタン: Click を検知しました"
InputSampleButtonNoAction<localizes>:message = "ボタン: この入力はボタンに割り当てられません（logic の input_action だけ）"

# 役割：input_sample_component が順に確かめる入力 1 つ分。LogicAction か VectorAction のどちらか 1 つを持つ（どちらも無ければ表示だけ）
input_sample_step<public> := class:
    # 画面に出す入力アクション名
    Label<public>:string
    # 画面に出す Mapping 名
    MappingLabel<public>:string
    # 押すキーの名前（キーボード / パッド）。今の割り当ては Verse から読めないので、既定のキーを書く
    KeyName<public>:string = ""
    # 補足
    Note<public>:string = ""
    # この番のあいだ足す Mapping。キャラクター操作の Mapping は既定で有効なので足さない
    Mapping<public>:?input_mapping = false
    # 番が終わったら Mapping を外すか。既定で有効か分からない Mapping（InteractMapping）は外さない
    RemoveMappingAfter<public>:logic = false
    # 押して検知する入力（logic。BeginDetectEvent = 押した瞬間を待つ）
    LogicAction<public>:?input_action(logic) = false
    # 値が vector3 の入力（Move・PointerSelect・PointerZoom。TriggerActivationEvent を待つ）
    VectorAction<public>:?input_action((/Verse.org/SpatialMath:)vector3) = false

    # 検知できる入力があるか
    IsDetectable<public>()<decides><transacts>:void =
        LogicAction? or VectorAction?

    # 入力が届くまで待つ。検知できる入力が無ければ戻らない
    AwaitTrigger<public>(PlayerInput:player_input)<suspends>:void =
        if (Action := LogicAction?):
            PlayerInput.AwaitPressed(Action)
        else if (Action := VectorAction?):
            Triggered := PlayerInput.GetInputEvents(Action).TriggerActivationEvent.Await()
        else:
            Sleep(Inf)

# 役割：1 人分の確認画面（Widget Blueprint を使わない Verse UI）。入力モードは None（HUD）のままなので、フォーカスの無い画面で button_loud の TriggeringInputAction が効くかも確かめられる
input_sample_widget<public> := class:

    StepText<public>:text_block = text_block{DefaultTextColor := NamedColors.White}
    MappingText<public>:text_block = text_block{DefaultTextColor := NamedColors.White}
    KeyText<public>:text_block = text_block{DefaultTextColor := NamedColors.White}
    NoteText<public>:text_block = text_block{DefaultTextColor := NamedColors.White}
    ResultText<public>:text_block = text_block{DefaultTextColor := NamedColors.White}
    ButtonResultText<public>:text_block = text_block{DefaultTextColor := NamedColors.White}
    # 文字は Mapping と入力アクション。TriggeringInputAction は番ごとに入れ替える
    ActionButton<public>:button_loud = button_loud{}

    Root<private>:canvas = canvas{}
    var<private> Built:logic = false

    # 画面に出す widget（毎回同じものを返す）
    GetWidget<public>():widget =
        if (not Built?):
            set Built = true
            Root.AddWidget(MakeInfoSlot())
            Root.AddWidget(MakeButtonSlot())
        Root

    MakeInfoSlot<private>():canvas_slot =
        InfoSlots:[]stack_box_slot = array:
            stack_box_slot:
                Widget := text_block{DefaultText := InputSampleTitle, DefaultTextColor := NamedColors.White}
                HorizontalAlignment := horizontal_alignment.Left
                Padding := margin{Bottom := 8.0}
            stack_box_slot{Widget := StepText, HorizontalAlignment := horizontal_alignment.Left, Padding := margin{Bottom := 4.0}}
            stack_box_slot{Widget := MappingText, HorizontalAlignment := horizontal_alignment.Left, Padding := margin{Bottom := 4.0}}
            stack_box_slot{Widget := KeyText, HorizontalAlignment := horizontal_alignment.Left, Padding := margin{Bottom := 4.0}}
            stack_box_slot{Widget := NoteText, HorizontalAlignment := horizontal_alignment.Left, Padding := margin{Bottom := 8.0}}
            stack_box_slot{Widget := ResultText, HorizontalAlignment := horizontal_alignment.Left, Padding := margin{Bottom := 4.0}}
            stack_box_slot{Widget := ButtonResultText, HorizontalAlignment := horizontal_alignment.Left}
        canvas_slot:
            Anchors := anchors{Minimum := vector2{X := 0.5, Y := 0.2}, Maximum := vector2{X := 0.5, Y := 0.2}}
            Alignment := vector2{X := 0.5, Y := 0.5}
            SizeToContent := true
            Widget := overlay:
                Slots := array:
                    overlay_slot:
                        Widget := color_block{DefaultColor := NamedColors.Black, DefaultOpacity := 0.85}
                        HorizontalAlignment := horizontal_alignment.Fill
                        VerticalAlignment := vertical_alignment.Fill
                    overlay_slot:
                        Padding := margin{Left := 32.0, Top := 24.0, Right := 32.0, Bottom := 24.0}
                        Widget := stack_box{Orientation := orientation.Vertical, Slots := InfoSlots}

    MakeButtonSlot<private>():canvas_slot =
        canvas_slot:
            Anchors := anchors{Minimum := vector2{X := 0.05, Y := 0.5}, Maximum := vector2{X := 0.05, Y := 0.5}}
            Alignment := vector2{X := 0.0, Y := 0.5}
            SizeToContent := true
            Widget := ActionButton

# 役割：標準の入力アクション（/Fortnite.com/Input と /Verse.org/Input のすべて）を StepSeconds ごとに 1 つずつ画面に出し、押されたら「検知しました」と出す見本。logic の入力は押した瞬間（BeginDetectEvent）、vector3 の入力（Move・PointerSelect・PointerZoom）は TriggerActivationEvent で検知する。PointerSelect / PointerZoom の番では TouchMapping を足して Virtual Pointer を出す。左の button_loud には同じ入力を TriggeringInputAction に入れ、フォーカスの無い画面でもキーで Click が起きることを確かめる
# 置き方：エディターで空の entity に付ける。区画（または世界）に player_manager_component を 1 つ置く
# 試し方：セッションを始めると（StartOnBegin）、画面上部に「n / 総数　アクション名」「Mapping」「キー」が出る。書かれたキーを押すと「検知しました」に変わり、出力ログにも出る。StepSeconds ごとに次の入力へ進み、最後まで行くと先頭へ戻る
# いつ：StartOnBegin が true ならシミュレーション開始から。false なら起動の合図（activated_event）から停止の合図（deactivated_event）まで
# 前提・注意：キャラクター操作の Mapping は外さない（外すと動けなくなる）。UI 用の Mapping は番のあいだだけ足して外す。今のキー割り当ては Verse から読めないので、画面のキー名は既定のもの
input_sample_component<public> := class<final_super>(component):

    # オンなら、シミュレーション開始から始める。オフなら起動の合図を待つ
    @editable
    StartOnBegin<public>:logic = true

    # 次の入力へ切り替える間隔（秒）
    @editable
    StepSeconds<public>:float = 6.0

    Views<private>:player_view_set = player_view_set{}

    # 順に確かめる入力
    Steps<public>:[]input_sample_step = array:
        # --- /Fortnite.com/Input/Character（既定で有効。Mapping は触らない） ---
        input_sample_step{Label := "Reload", KeyName := "R / X", MappingLabel := "Character.RangedWeaponMapping", LogicAction := option{Character.Reload}}
        input_sample_step{Label := "WeaponPrimary", KeyName := "左クリック / RT", MappingLabel := "Character.RangedWeaponMapping", LogicAction := option{Character.WeaponPrimary}}
        input_sample_step{Label := "WeaponSecondary", KeyName := "右クリック / LT", MappingLabel := "Character.RangedWeaponMapping", LogicAction := option{Character.WeaponSecondary}}
        input_sample_step{Label := "Crouch", KeyName := "左Ctrl / 右スティック押し込み", MappingLabel := "Character.TraversalMapping", LogicAction := option{Character.Crouch}}
        input_sample_step{Label := "Sprint", KeyName := "左Shift / 左スティック押し込み", MappingLabel := "Character.TraversalMapping", LogicAction := option{Character.Sprint}}
        input_sample_step{Label := "Jump", KeyName := "Space / A", MappingLabel := "Character.TraversalMapping", LogicAction := option{Character.Jump}}
        # @experimental。InteractMapping が既定で有効か分からないので、足すだけで外さない
        input_sample_step:
            Label := "Interact（experimental）"
            KeyName := "E / X"
            MappingLabel := "Character.InteractMapping（experimental）"
            Note := "この番で InteractMapping を足します（外しません）"
            Mapping := option{Character.InteractMapping}
            LogicAction := option{Character.Interact}
        # @experimental。所属する Mapping は API に出ていない
        input_sample_step{Label := "Move（experimental）", KeyName := "W A S D / 左スティック", MappingLabel := "Character（所属 Mapping は API に無し）", VectorAction := option{Character.Move}}

        # --- /Verse.org/Input/Gameplay（検知できるアクションが無い） ---
        input_sample_step{Label := "（アクション無し）", MappingLabel := "Gameplay.HotbarMapping", KeyName := "（なし）"}

        # --- /Verse.org/Input/UI（この番だけ Mapping を足し、終わったら外す） ---
        input_sample_step{Label := "NextTab", KeyName := "E / RB", MappingLabel := "UI.MenuNavigationMapping", Mapping := option{MenuNavigationMapping}, RemoveMappingAfter := true, LogicAction := option{NextTab}}
        input_sample_step{Label := "PreviousTab", KeyName := "Q / LB", MappingLabel := "UI.MenuNavigationMapping", Mapping := option{MenuNavigationMapping}, RemoveMappingAfter := true, LogicAction := option{PreviousTab}}
        input_sample_step{Label := "NextPage", KeyName := "C / RT", MappingLabel := "UI.MenuNavigationMapping", Mapping := option{MenuNavigationMapping}, RemoveMappingAfter := true, LogicAction := option{NextPage}}
        input_sample_step{Label := "PreviousPage", KeyName := "Z / LT", MappingLabel := "UI.MenuNavigationMapping", Mapping := option{MenuNavigationMapping}, RemoveMappingAfter := true, LogicAction := option{PreviousPage}}
        input_sample_step{Label := "Back", KeyName := "Escape / Back", MappingLabel := "UI.MenuNavigationMapping", Mapping := option{MenuNavigationMapping}, RemoveMappingAfter := true, LogicAction := option{Back}, Note := "Esc は Fortnite のメニューに取られて届かないことがあります"}
        input_sample_step{Label := "Use", KeyName := "F / Y", MappingLabel := "UI.InventoryMenuMapping", Mapping := option{InventoryMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Use}}
        input_sample_step{Label := "Inspect", KeyName := "I / X", MappingLabel := "UI.InventoryMenuMapping", Mapping := option{InventoryMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Inspect}}
        input_sample_step{Label := "Sort", KeyName := "V / 右スティック押し込み", MappingLabel := "UI.InventoryMenuMapping", Mapping := option{InventoryMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Sort}}
        input_sample_step{Label := "Drop", KeyName := "X / 左スティック押し込み", MappingLabel := "UI.InventoryMenuMapping", Mapping := option{InventoryMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Drop}}
        input_sample_step{Label := "Craft", KeyName := "F / Y", MappingLabel := "UI.CraftingMenuMapping", Mapping := option{CraftingMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Craft}}
        input_sample_step{Label := "Inspect", KeyName := "I / X", MappingLabel := "UI.CraftingMenuMapping", Mapping := option{CraftingMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Inspect}}
        input_sample_step{Label := "Favorite", KeyName := "V / 右スティック押し込み", MappingLabel := "UI.CraftingMenuMapping", Mapping := option{CraftingMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Favorite}}
        input_sample_step{Label := "Scrap", KeyName := "X / 左スティック押し込み", MappingLabel := "UI.CraftingMenuMapping", Mapping := option{CraftingMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Scrap}}
        input_sample_step{Label := "Track", KeyName := "F / Y", MappingLabel := "UI.MapMenuMapping", Mapping := option{MapMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Track}}
        input_sample_step{Label := "PlaceMarker", KeyName := "P / X", MappingLabel := "UI.MapMenuMapping", Mapping := option{MapMenuMapping}, RemoveMappingAfter := true, LogicAction := option{PlaceMarker}}
        input_sample_step{Label := "Reset", KeyName := "R / 左スティック押し込み", MappingLabel := "UI.MapMenuMapping", Mapping := option{MapMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Reset}}
        input_sample_step{Label := "ToggleView", KeyName := "V / 右スティック押し込み", MappingLabel := "UI.MapMenuMapping", Mapping := option{MapMenuMapping}, RemoveMappingAfter := true, LogicAction := option{ToggleView}}
        input_sample_step{Label := "ZoomIn", KeyName := "Z / LT", MappingLabel := "UI.MapMenuMapping", Mapping := option{MapMenuMapping}, RemoveMappingAfter := true, LogicAction := option{ZoomIn}}
        input_sample_step{Label := "ZoomOut", KeyName := "X / RT", MappingLabel := "UI.MapMenuMapping", Mapping := option{MapMenuMapping}, RemoveMappingAfter := true, LogicAction := option{ZoomOut}}
        # TouchMapping を足すと Virtual Pointer（画面のカーソル）が出る
        input_sample_step:
            Label := "PointerSelect"
            KeyName := "タッチ / クリック"
            MappingLabel := "UI.TouchMapping"
            Note := "TouchMapping を足すと画面にポインターが出ます。クリック位置（画面座標 cm）が値で届きます"
            Mapping := option{TouchMapping}
            RemoveMappingAfter := true
            VectorAction := option{PointerSelect}
        # @experimental
        input_sample_step:
            Label := "PointerZoom（experimental）"
            KeyName := "ピンチ / ホイール"
            MappingLabel := "UI.TouchMapping"
            Mapping := option{TouchMapping}
            RemoveMappingAfter := true
            VectorAction := option{PointerZoom}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (StartOnBegin?):
            Activate()

    OnReceive<override>(SceneEvent:scene_event):logic =
        Views.HandleActivation(SceneEvent, Entity, CreateView)
        false

    OnEndSimulation<override>():void =
        Views.Deactivate()
        (super:)OnEndSimulation()

    # 全員（途中参加も）に確認画面を出して巡回を始める。もう始めていれば何もしない
    Activate<public>():void =
        Views.Activate(Entity, CreateView)

    # 全員の確認画面を消して巡回をやめる
    Deactivate<public>():void =
        Views.Deactivate()

    # 動いているあいだ成功する
    IsActive<public>()<decides><transacts>:void =
        Views.IsActive[]

    CreateView<private>(ViewEntity:entity, Slot:player_slot_component):component =
        input_sample_view_component{Entity := ViewEntity, Source := Self, Player := Slot.Player}

# 役割：1 人分の巡回。Source の Steps を先頭から順に表示し、入力とボタンの Click を待つ
# 置き方：実行時に input_sample_component が作る（エディターでは置かない）
input_sample_view_component<public> := class<final_super>(component):

    Source<public>:input_sample_component
    Player<public>:player

    Widget<private>:input_sample_widget = input_sample_widget{}
    var<private> Shown:logic = false

    OnSimulate<override>()<suspends>:void =
        if (Source.Steps.Length = 0):
            return
        if (PlayerInput := GetPlayerInput[Player]):
            var Index:int = 0
            loop:
                if (Step := Source.Steps[Index]):
                    RunStep(PlayerInput, Step, Index)
                set Index = if (Index + 1 < Source.Steps.Length) then Index + 1 else 0
        else:
            Print("[input_sample] この人の入力（player_input）が取れません")

    OnEndSimulation<override>():void =
        Hide()
        (super:)OnEndSimulation()

    # 1 つの入力を StepSeconds のあいだ表示する。入力と、同じ入力を TriggeringInputAction に入れた左のボタンの Click を別々に待ち、届いたほうから「検知」に変える
    # 途中で止められても（view が消える）、defer で Mapping を戻す
    RunStep<private>(PlayerInput:player_input, Step:input_sample_step, Index:int)<suspends>:void =
        Widget.StepText.SetText(InputSampleStepMessage(Index + 1, Source.Steps.Length, Step.Label))
        Widget.MappingText.SetText(InputSampleMappingMessage(Step.MappingLabel))
        Widget.KeyText.SetText(InputSampleKeyMessage(Step.KeyName))
        Widget.NoteText.SetText(InputSampleNoteMessage(Step.Note))
        Widget.ActionButton.SetText(InputSampleButtonMessage(Step.MappingLabel, Step.Label))
        set Widget.ActionButton.TriggeringInputAction = Step.LogicAction
        if (Step.IsDetectable[]):
            Widget.ResultText.SetText(InputSampleWaiting(if (Seconds := Round[Source.StepSeconds]) then Seconds else 0))
        else:
            Widget.ResultText.SetText(InputSampleNotDetectable)
        if (Step.LogicAction?):
            Widget.ButtonResultText.SetText(InputSampleButtonWaiting)
        else:
            Widget.ButtonResultText.SetText(InputSampleButtonNoAction)

        if (Mapping := Step.Mapping?):
            PlayerInput.AddInputMapping(Mapping)
        defer:
            if (Step.RemoveMappingAfter?, Mapping := Step.Mapping?):
                PlayerInput.RemoveInputMapping(Mapping)
        Show()

        race:
            Sleep(Source.StepSeconds)
            block:
                Step.AwaitTrigger(PlayerInput)
                Widget.ResultText.SetText(InputSampleDetected)
                Print("[input_sample] 入力を検知: {Step.MappingLabel} > {Step.Label}")
                Sleep(Inf)
            block:
                Clicked := Widget.ActionButton.OnClick().Await()
                Widget.ButtonResultText.SetText(InputSampleButtonClicked)
                Print("[input_sample] ボタンの Click を検知: {Step.MappingLabel} > {Step.Label}")
                Sleep(Inf)

    Show<private>():void =
        if (not Shown?, PlayerUI := GetPlayerUI[Player]):
            set Shown = true
            PlayerUI.AddWidget(Widget.GetWidget(), player_ui_slot{InputMode := ui_input_mode.None})

    Hide<private>():void =
        if (Shown?, PlayerUI := GetPlayerUI[Player]):
            set Shown = false
            PlayerUI.RemoveWidget(Widget.GetWidget())
