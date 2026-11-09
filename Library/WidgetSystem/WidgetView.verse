using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/UI }
using { /Fortnite.com/UI }

# 役割：1 人の画面に出した widget の窓口。player_widget_component が出すたびに作り、CreateWidget に渡す（利用者は作らない）
#   閉じた知らせ（HiddenEvent）、作った component から転送された知らせ（ReceivedEvent）、ボタン待ち（AwaitClick / AwaitChoice / AwaitButtonChoice）、Close / Focus を持つ
#   待っているボタンの一覧（GetWaitingButtons）と、コードから押す入口（PressButton。本物のクリックと同じく AwaitClick / AwaitChoice に届く。MCPSystem の WidgetKit が使う）
# 前提・注意：閉じたあと（IsShown が失敗したあと）の待ちはすぐ false で戻る。ボタン待ちは必ずこの窓口を通す（閉じたのに待ちが残らない）
widget_view<public> := class<internal>:
    # この表示を出している人
    Player<public>:player
    # この表示を出した component
    Owner<public>:player_widget_component

    var<private> Shown:logic = true
    var<private> DefaultFocus:?widget = false
    # 今 AwaitClick / AwaitChoice で待っているボタン（コードから押す PressButton の行き先）
    var<private> Waits:[]widget_wait = array{}

    HiddenEventInternal<private><final>:event() = event(){}
    PointerFedInternal<private><final>:event(tuple(float, float, logic)) = event(tuple(float, float, logic)){}

    # コードから差し込んだポインター（画面の割合 X, Y（左上 0,0 〜 右下 1,1）、押しているか）。InjectPointer で届く。
    #   PointerKit の RunCardPointerPress は、Virtual Pointer の押下と同じに扱う（MCPSystem の widget.pointer で、マウス無しに押し込みを試せる）
    PointerFed<public><final>:listenable(tuple(float, float, logic)) = MakeProxyListenable(PointerFedInternal)

    # ポインターを差し込む（X, Y は画面の割合、Down が true なら押している・false なら離した）。画面に出ていなければ何もしない
    InjectPointer<public>(X:float, Y:float, Down:logic):void =
        if (Shown?):
            PointerFedInternal.Signal((X, Y, Down))
    ReceivedEventInternal<private><final>:event(scene_event) = event(scene_event){}

    # 画面から消えたときに 1 回届く（Close・HideFor・Deactivate・退出・メニューの入れ替え・停止）（Await / Subscribe する。外から Signal はできない）
    HiddenEvent<public><final>:listenable(tuple()) = MakeProxyListenable(HiddenEventInternal)

    # Owner が SendToWidgets / SendToWidgetFor で渡した知らせと、同じ人のほかの view からの player_event の中身が届く
    ReceivedEvent<public><final>:listenable(scene_event) = MakeProxyListenable(ReceivedEventInternal)

    # まだ画面に出ているあいだ成功する
    IsShown<public>()<decides><transacts>:void =
        Shown?

    # この人の画面からこの表示を閉じる（Owner.HideFor と同じ）
    Close<public>():void =
        Owner.HideFor(Player)

    # Target にフォーカスを移す（パッドで操作するメニューのボタンなど。canvas ではなく中のボタンを渡す）。画面に出ていなければ何もしない
    Focus<public>(Target:widget):void =
        if (Shown?, PlayerUI := GetPlayerUI[Player]):
            PlayerUI.SetFocus(Target)

    # 表示した直後にフォーカスを移す先を決める（CreateWidget の中で呼ぶ。Mode = Menu のとき、出した次のフレームで Focus する）
    SetDefaultFocus<public>(Target:widget):void =
        set DefaultFocus = option{Target}

    # この人が OnClick を押すまで待つ。押されたら true、先に閉じたら false（閉じていればすぐ false）
    # 使い方：Clicked := View.AwaitClick(Button.OnClick())
    #   待っているあいだ、このボタンは GetWaitingButtons に出て、コードから PressButton で押せる（MCPSystem の WidgetKit など。本物のクリックと同じく true で返る）
    #   ButtonId はコードから押すときの ID（空なら "0"）、Label は一覧に出す文字（ボタンの文字。空でもよい）
    AwaitClick<public>(OnClick:listenable(widget_message), ?ButtonId:string = "", ?Label:string = "")<suspends>:logic =
        if (not Shown?):
            return false
        Pressed := event(int){}
        Wait := widget_wait{Ids := array{if (ButtonId = "") then "0" else ButtonId}, Labels := array{Label}, Buttons := array{}, Target := Pressed}
        AddWait(Wait)
        defer:
            RemoveWait(Wait)
        race:
            block:
                loop:
                    Message := OnClick.Await()
                    if (Message.Player = Player):
                        break
                true
            block:
                Pressed.Await()
                true
            block:
                HiddenEventInternal.Await()
                false

    # Buttons のどれかをこの人が押すまで待ち、押されたボタンの番号（0 から）を返す。先に閉じたら false
    #   待っているあいだ、ボタンは GetWaitingButtons に出て、コードから PressButton で押せる（本物のクリックと同じ番号が返る）
    #   ButtonIds はコードから押すときの ID（Buttons と同じ並び。足りない番号は "0"・"1" … の番号の文字）
    AwaitChoice<public>(Buttons:[]text_button_base, ?ButtonIds:[]string = array{})<suspends>:?int =
        Clicks := for (Button : Buttons) { array{Button.OnClick()} }
        AwaitChoiceOf(Clicks, Buttons, Buttons, ButtonIds, array{})

    # 中身を自由に入れられる button（カードなど）のどれかをこの人が押すまで待ち、押されたボタンの番号（0 から）を返す。先に閉じたら false
    #   AwaitChoice と同じく、GetWaitingButtons に出て PressButton で押せる。Labels は一覧に出す文字（button には文字が無いので渡す。足りない番号は空）
    AwaitButtonChoice<public>(Buttons:[]button, ?ButtonIds:[]string = array{}, ?Labels:[]string = array{})<suspends>:?int =
        Clicks := for (Button : Buttons) { array{Button.OnClick()} }
        AwaitChoiceOf(Clicks, Buttons, array{}, ButtonIds, Labels)

    # 1 つの選択肢が複数の button でできているとき（カードの上に敷いたホバーのマスなど）、どれかが押されたら、その選択肢の番号（Groups の番号）を返す。先に閉じたら false
    #   GetWaitingButtons・PressButton では選択肢 1 つにつき 1 つ（押せるかは、その選択肢の最初の button で見る）
    AwaitButtonGroupChoice<public>(Groups:[][]button, ?ButtonIds:[]string = array{}, ?Labels:[]string = array{})<suspends>:?int =
        Clicks := for (Group : Groups) { for (Button : Group) { Button.OnClick() } }
        Firsts := for (Group : Groups, First := Group[0]) { First }
        AwaitChoiceOf(Clicks, Firsts, array{}, ButtonIds, Labels)

    AwaitChoiceOf<private>(Clicks:[][]listenable(widget_message), Widgets:[]widget, TextButtons:[]text_button_base, ButtonIds:[]string, Labels:[]string)<suspends>:?int =
        if (not Shown?):
            return false
        Chosen := event(int){}
        Ids := for (Index -> Click : Clicks):
            if (Id := ButtonIds[Index], Id <> "") then Id else "{Index}"
        Wait := widget_wait{Ids := Ids, Labels := Labels, Buttons := TextButtons, Widgets := Widgets, Target := Chosen}
        AddWait(Wait)
        var Handlers:[]cancelable = array{}
        for (Index -> Group : Clicks, Click : Group):
            Handler := widget_choice_handler{Index := Index, Player := Player, Target := Chosen}
            set Handlers += array{Click.Subscribe(Handler.Handle)}
        defer:
            RemoveWait(Wait)
            for (Subscription : Handlers):
                Subscription.Cancel()
        race:
            block:
                Index := Chosen.Await()
                option{Index}
            block:
                HiddenEventInternal.Await()
                false

    # 今 AwaitClick / AwaitChoice で待っているボタン（待ちが重なっていれば、始めた順に並べる）。待っていなければ空
    GetWaitingButtons<public>():[]widget_button_info =
        var Out:[]widget_button_info = array{}
        for (Wait : Waits):
            set Out += Wait.GetInfos()
        Out

    # コードからボタンを押す（本物のクリックと同じく、待っている AwaitClick / AwaitChoice に届く）
    #   Key はボタンの ID（AwaitClick の ButtonId・AwaitChoice の ButtonIds）か、ボタンの文字か、番号の文字（"0" から）。最初に合ったボタンを押す
    #   結果：Pressed（押した）/ NotShown（もう閉じた）/ NotWaiting（ボタンを待っていない）/ NoButton（合うボタンが無い）/ Disabled（ボタンが無効）
    PressButton<public>(Key:string):widget_press_result =
        if (not Shown?):
            return widget_press_result.NotShown
        if (Waits.Length = 0):
            return widget_press_result.NotWaiting
        var Result:widget_press_result = widget_press_result.NoButton
        var Done:logic = false
        for (Wait : Waits):
            if (not Done?):
                Found := Wait.FindButton(Key)
                if (Found >= 0):
                    set Done = true
                    Disabled := Wait.IsDisabledAt(Found)
                    if (Disabled?):
                        set Result = widget_press_result.Disabled
                    else:
                        Wait.Target.Signal(Found)
                        set Result = widget_press_result.Pressed
        Result

    AddWait<private>(Wait:widget_wait):void =
        set Waits += array{Wait}

    RemoveWait<private>(Wait:widget_wait):void =
        set Waits = for (Other : Waits, Other <> Wait) { Other }

    # player_widget_view_component から呼ばれる
    NotifyShown<internal>()<suspends>:void =
        if (Target := DefaultFocus?):
            Sleep(0.0)
            Focus(Target)

    NotifyHidden<internal>():void =
        if (Shown?):
            set Shown = false
            HiddenEventInternal.Signal()

    NotifyReceived<internal>(SceneEvent:scene_event):void =
        ReceivedEventInternal.Signal(SceneEvent)

# AwaitChoice の中で、ボタンごとに番号を覚えておく
widget_choice_handler<internal> := class<internal>:
    Index<internal>:int
    Player<internal>:player
    Target<internal>:event(int)

    Handle<internal>(Message:widget_message):void =
        if (Message.Player = Player):
            Target.Signal(Index)

# PressButton の結果
widget_press_result<public> := enum:
    # 押した（待っている AwaitClick / AwaitChoice に届いた）
    Pressed
    # もう画面から消えている
    NotShown
    # 出ているが、ボタンを待っていない（AwaitClick / AwaitChoice の外）
    NotWaiting
    # Key に合うボタンが無い
    NoButton
    # ボタンが無効（SetEnabled(false)）
    Disabled

# 待っているボタン 1 つの情報（GetWaitingButtons）
widget_button_info<public> := struct:
    # コードから押すときの ID
    Id<public>:string = ""
    # 待ちの中の番号（AwaitChoice なら返る番号。AwaitClick は 0）
    Index<public>:int = 0
    # ボタンの文字（取れなければ空）
    Label<public>:string = ""
    # 押せるか（SetEnabled(false) なら false）
    Enabled<public>:logic = true

# AwaitClick / AwaitChoice の 1 回の待ち（コードから押すときの行き先）
widget_wait<internal> := class<unique><internal>:
    Ids<internal>:[]string
    # AwaitClick / AwaitButtonChoice で渡された文字（AwaitChoice は文字のボタンから読む）
    Labels<internal>:[]string
    # 文字のボタン（AwaitChoice。文字を一覧に出す）
    Buttons<internal>:[]text_button_base
    # 押せるかを見るボタン（AwaitChoice・AwaitButtonChoice。AwaitClick は空）
    Widgets<internal>:[]widget = array{}
    Target<internal>:event(int)

    GetLabel<internal>(Index:int):string =
        if (Button := Buttons[Index]) then Button.GetText() else if (Label := Labels[Index]) then Label else ""

    # Index のボタンが無効なら true（AwaitClick のボタンは分からないので false）
    IsDisabledAt<internal>(Index:int):logic =
        if (Widget := Widgets[Index]):
            Enabled := Widget.IsEnabled()
            if (Enabled?) then false else true
        else:
            false

    GetInfos<internal>():[]widget_button_info =
        for (Index -> Id : Ids):
            Disabled := IsDisabledAt(Index)
            Enabled := if (Disabled?) then false else true
            widget_button_info{Id := Id, Index := Index, Label := GetLabel(Index), Enabled := Enabled}

    # Key に合うボタンの番号（ID → 文字 → 番号の文字の順に見る）。無ければ -1
    FindButton<internal>(Key:string):int =
        var Found:int = -1
        for (Index -> Id : Ids, Found < 0, Id = Key):
            set Found = Index
        if (Found < 0):
            for (Index -> Id : Ids):
                if (Found < 0):
                    Label := GetLabel(Index)
                    if (Label <> "", Label = Key):
                        set Found = Index
        if (Found < 0, Number := WidgetParseIndex[Key], Number >= 0, Number < Ids.Length):
            set Found = Number
        Found

# "0"〜"999" の番号の文字を int にする。番号でなければ失敗する
WidgetParseIndex<internal>(Key:string)<decides><transacts>:int =
    Key.Length > 0
    Key.Length <= 3
    var N:int = 0
    var Bad:int = 0
    for (C : Key):
        var Digit:int = -1
        for (Index -> D : "0123456789", D = C):
            set Digit = Index
        if (Digit >= 0):
            set N = N * 10 + Digit
        else:
            set Bad += 1
    Bad = 0
    N
