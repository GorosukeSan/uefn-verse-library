using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Colors }
using { /UnrealEngine.com/Temporary/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /Fortnite.com/UI }
using { PlayerSystem }
using { SceneGraphSystem }
using { WidgetSystem }
using { WidgetSystem.CardKit }
using { PickupSystem }
using { PickupSystem.TooltipKit }

# 拾った効果の HUD（pickup_effect_hud_component）の見た目と動き。ゲームのテーマで 1 つ作り、Style に入れる（コードで入れる。エディターには出ない）
#   大きさは 1080p のピクセル、位置は画面の割合（左上 0, 0）、時間は秒。効果ごとの色・名前は効果のプレハブの card_info_component が持つ（ここには持たない）
pickup_effect_hud_style<public> := struct:
    # ---- 拾ったときの知らせ（画面の上の方に 1 枚ずつ出す板） ----
    # 板の真ん中を置く位置（画面の横・縦の割合）
    ToastXRatio<public>:float = 0.5
    ToastYRatio<public>:float = 0.24
    # 板の幅・高さ
    ToastWidthPx<public>:float = 560.0
    ToastHeightPx<public>:float = 110.0
    # 左の色の帯（AccentColor。Thumbnail があれば帯の上に画像）の幅
    ToastIconWidthPx<public>:float = 110.0
    # 下の縁の色の線（AccentColor）の太さ。0 なら出さない
    ToastLinePx<public>:float = 4.0
    # 文字の左右の余白
    ToastPaddingPx<public>:float = 18.0
    # 板の色・不透明度（0.0〜1.0）
    ToastBackColor<public>:color = NamedColors.Black
    ToastBackOpacity<public>:float = 0.78
    # 名前の大きさ（色は効果の AccentColor）
    ToastTitleSize<public>:float = 40.0
    # 説明の色・大きさ（帯を除いた幅で折り返す）
    ToastDescriptionColor<public>:color = NamedColors.White
    ToastDescriptionSize<public>:float = 20.0
    # 札（Badge。色の帯の上に出す）の文字の色・大きさ
    ToastBadgeColor<public>:color = NamedColors.White
    ToastBadgeSize<public>:float = 26.0
    # 出る秒数（大きくなりながら濃くなる）・出しておく秒数・消える秒数（上へずれながら薄くなる）
    ToastInSeconds<public>:float = 0.2
    ToastHoldSeconds<public>:float = 1.6
    ToastOutSeconds<public>:float = 0.3
    # 出るときの最初の大きさ（1.0 = ふつう）と、行き過ぎて戻る強さ（0 なら行き過ぎない。1.7 で約 10% 行き過ぎる）
    ToastStartScale<public>:float = 0.6
    ToastOvershoot<public>:float = 1.7
    # 消えるときに上へずらす量
    ToastOutSlidePx<public>:float = 36.0
    # 同じ効果をまた拾ったとき、出ている板を弾ませる大きさ（0.08 = 8% 大きくなって戻る）と秒数
    ToastPulseScale<public>:float = 0.08
    ToastPulseSeconds<public>:float = 0.22
    # 次の知らせが待っているときは、出しておく秒数をここまで縮める
    ToastQueuedHoldSeconds<public>:float = 0.5
    # 待たせておく知らせの数の上限（超えたら古いものから捨てる）
    MaxQueuedToasts<public>:int = 3

    # ---- 続いている効果の一覧（1 行 = 1 つの効果。同じ EffectId は 1 行にまとめる） ----
    # 一覧の左上を置く位置（画面の横・縦の割合）。行は下へ並ぶ
    ListXRatio<public>:float = 0.015
    ListYRatio<public>:float = 0.2
    # 1 行の幅・高さと、行のあいだ
    RowWidthPx<public>:float = 300.0
    RowHeightPx<public>:float = 46.0
    RowGapPx<public>:float = 6.0
    # 行の中の左右の余白
    RowPaddingPx<public>:float = 10.0
    # 行の板の色・不透明度（左の四角は AccentColor。Thumbnail があれば四角の上に画像）
    RowBackColor<public>:color = NamedColors.Black
    RowBackOpacity<public>:float = 0.6
    # 名前の色・大きさ
    RowNameColor<public>:color = NamedColors.White
    RowNameSize<public>:float = 20.0
    # 残り秒（"4.3"）の色・大きさ
    RowTimeColor<public>:color = NamedColors.White
    RowTimeSize<public>:float = 18.0
    # 重なった数（"x2"）の前に付ける文字（大きさは RowTimeSize、色は AccentColor）
    StackPrefix<public>:string = "x"
    # 残り時間の棒の高さ・下地の色・下地の不透明度（中身は AccentColor）
    RowBarHeightPx<public>:float = 6.0
    RowBarBackColor<public>:color = NamedColors.White
    RowBarBackOpacity<public>:float = 0.18
    # 行が出る秒数・消える秒数（どちらも横へずれながら）と、ずらす量
    RowInSeconds<public>:float = 0.22
    RowOutSeconds<public>:float = 0.25
    RowSlidePx<public>:float = 40.0
    # 上の行が消えたときに詰める速さ（1 秒あたりに追いつく割合。大きいほど速い）
    RowMoveSpeed<public>:float = 12.0
    # 残りがこの秒数を切ったら棒を点滅させる（0 なら点滅しない）と、1 秒の点滅の回数
    RowWarnSeconds<public>:float = 2.0
    RowWarnBlinkPerSecond<public>:float = 4.0
    # 拾い直して延びたとき、左の四角と棒を白く光らせる秒数
    RowFlashSeconds<public>:float = 0.35
    # DurationSeconds がこれより短い効果は一覧に並べない（知らせだけ）。Instant の効果はいつも並べない
    MinRowSeconds<public>:float = 2.0
    # ずっと続く効果（DurationSeconds = 0）も並べるか（棒は満タンのまま、秒は出さない）
    ShowEndlessRows<public>:logic = true

    # ---- 見せ方が無いとき ----
    # card_info_component が無い効果の色（名前は EffectId）
    FallbackAccentColor<public>:color = NamedColors.SkyBlue

# Effect の見せ方（名前・説明・札・画像・色）。効果のプレハブの根（Effect の entity）の card_info_component から作る（Title が空なら EffectId）
#   card_info_component が無ければ、名前 = EffectId、色 = FallbackColor のカード（EffectId も空なら名前も空）
(Effect:pickup_effect_component).GetPickupEffectCard<public>(?FallbackColor:color = NamedColors.SkyBlue)<transacts>:widget_card =
    if (Info := Effect.Entity.GetComponent[card_info_component]):
        Info.GetCard(Effect.EffectId)
    else:
        widget_card{Id := Effect.EffectId, Title := Effect.EffectId, AccentColor := FallbackColor}

# 役割：拾った効果を、持ち主の画面に出す HUD（操作は奪わない）
#   拾ったとき：画面の上の方に、効果の名前（AccentColor の大きい文字）・説明・色の帯（Thumbnail があれば画像、Badge があれば札）の板を、大きくなりながら出し、しばらくして上へ薄れて消す
#     続けて拾ったら順に出す（次が待っているあいだは短く切り上げる）。同じ効果を拾い直したら、出ている板を弾ませて出しておく時間を数え直す
#   続いているあいだ：画面の左に 1 行ずつ、色の四角・名前・重なった数・残り秒・残り時間の棒（毎フレーム縮む）。行は横から出て、終わったら薄れて消え、下の行が詰める
#     Instant の効果と、DurationSeconds が Style.MinRowSeconds より短い効果は並べない（知らせだけ）
#   見せ方の持ち主は、効果のプレハブの根の card_info_component（WidgetSystem の CardKit）だけ（GetPickupEffectCard）。無ければ名前 = EffectId
# 置き方：持ち主の slot の下（ロードアウトのプレハブ・独自キャラクターの体など）に置くと、持ち主にだけ出る（Audience = Everyone のまま）
#   slot の祖先（player_manager_component の entity など）に置くと、出している全員に、それぞれの効果を出す（拾い直し（Renewed）は届かないので、延びたことは棒だけで分かる）
# いつ：既定で開始から出す（ActiveOnBegin。ラウンドの途中だけ）。出し始めたときに、もう続いている効果も並べる
# 知らせを受ける：pickup_effect_owner_event（持ち主の slot から SendDown。Started / Renewed / Ended）、pickup_effect_changed_event（slot の祖先に置いたときだけ）
# 外から：ShowToastFor / TrackEffectFor、var Style（見た目。出し始めたときに写すので、出す前に入れる）
pickup_effect_hud_component<public> := class<final_super>(player_widget_component):

    ActiveOnBegin<override>:logic = true
    ZOrder<override>:int = 100

    # オンなら、効果を拾ったとき（拾い直したときも）画面の上の方に名前と説明を出す。既定オン
    @editable:
        ToolTip := PickupHudShowToastsToolTip
        Categories := array{PickupHudCategory}
    ShowToasts<public>:logic = true
    # オンなら、続いている効果を 1 行ずつ並べ、残り時間の棒と秒を出す。既定オン
    @editable:
        ToolTip := PickupHudShowListToolTip
        Categories := array{PickupHudCategory}
    ShowEffectList<public>:logic = true

    # 見た目と動き（色・大きさ・位置・秒数）。エディターには出ない。ゲームのテーマで作り、作るときの Style := か set Hud.Style = で入れる
    var Style<public>:pickup_effect_hud_style = pickup_effect_hud_style{}

    var<private> Screens:[agent]pickup_effect_hud_screen = map{}

    # Agent の画面に、Card の知らせを出す（拾ったときと同じ板。コードから出すとき）。その人に出していなければ何もしない
    ShowToastFor<public>(Agent:agent, Card:widget_card):void =
        if (Screen := Screens[Agent]):
            Screen.PushToast(Card)

    # Agent の画面の一覧に Effect を並べる（知らせの届かない場所から効果を与えたときなど）。続いていない・並べない効果・その人に出していないなら何もしない
    TrackEffectFor<public>(Agent:agent, Effect:pickup_effect_component):void =
        if (Screen := Screens[Agent]):
            Screen.Track(Effect, false)

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Notice := pickup_effect_owner_event[SceneEvent]):
            Handle(Notice.Agent, Notice.Effect, Notice.Picked, Notice.Notice)
        else if (Changed := pickup_effect_changed_event[SceneEvent]):
            # slot の祖先に置いたとき（持ち主の側の知らせは届かない）。slot の下なら、同じことが pickup_effect_owner_event で届く
            if (not Entity.FindOwningSlot[]):
                Kind := if (Changed.Started?) then pickup_effect_notice.Started else pickup_effect_notice.Ended
                Handle(Changed.Agent, Changed.Effect, Changed.Effect, Kind)
        (super:)OnReceive(SceneEvent)

    CreateWidget<override>(View:widget_view):widget =
        Root := canvas{}
        Screen := pickup_effect_hud_screen{Root := Root, Style := Style}
        if (set Screens[View.Player] = Screen) {}
        # 出し始める前から続いている効果も並べる（知らせは出さない）
        if (ShowEffectList?):
            for (Effect : Entity.GetActivePickupEffects(View.Player)):
                Screen.Track(Effect, false)
        spawn{RunScreen(View, Screen)}
        Root

    Handle<private>(Agent:agent, Effect:pickup_effect_component, Picked:pickup_effect_component, Notice:pickup_effect_notice):void =
        if (Screen := Screens[Agent]):
            if (Notice = pickup_effect_notice.Started or Notice = pickup_effect_notice.Renewed):
                if (ShowToasts?):
                    Screen.PushToast(Picked.GetPickupEffectCard(?FallbackColor := Screen.Style.FallbackAccentColor))
                if (ShowEffectList?):
                    Screen.Track(Effect, if (Notice = pickup_effect_notice.Renewed) then true else false)
            # 終わった効果の行は、毎フレームの確かめで消える（Ended は起こすだけ）
            Screen.Wake()

    RunScreen<private>(View:widget_view, Screen:pickup_effect_hud_screen)<suspends>:void =
        race:
            View.HiddenEvent.Await()
            Screen.Run()
        # 出し直した（ShowFor）ときは新しい画面が入っているので消さない
        if (Current := Screens[View.Player], Current = Screen):
            set Screens = Screens.RemoveKey(View.Player)

# 1 人分の画面（pickup_effect_hud_component が出すたびに作る）。知らせの待ち行列・出ている板・一覧の行を持ち、毎フレーム動かす（何も無いあいだは止まって待つ）
pickup_effect_hud_screen<internal> := class<unique><internal>:
    Root<internal>:canvas
    Style<internal>:pickup_effect_hud_style
    WakeEvent<internal>:event() = event(){}
    var Queue<internal>:[]widget_card = array{}
    var Current<internal>:?pickup_effect_hud_toast = false
    var Rows<internal>:[]pickup_effect_hud_row = array{}

    # 知らせを出す（待ち行列に足す）。同じ効果（Id が同じ）の板が出ていれば、出し直さずに弾ませる。名前も説明も空なら出さない
    PushToast<internal>(Card:widget_card):void =
        if (Card.Title = "" and Card.Description = ""):
            return
        Now := GetSimulationElapsedTime()
        # 同じ効果がもう待っているなら足さない
        AlreadyQueued := if (Card.Id <> "", IsQueued[Card.Id]) then true else false
        if (Toast := Current?, Toast.OutStart < 0.0, Card.Id <> "", Toast.Card.Id = Card.Id):
            set Toast.HoldFrom = Max(Now, Toast.StartTime + Style.ToastInSeconds)
            set Toast.PulseStart = Now
        else if (not AlreadyQueued?):
            set Queue += array{Card}
            Limit := Max(Style.MaxQueuedToasts, 1)
            if (Queue.Length > Limit, Rest := Queue.Slice[Queue.Length - Limit]):
                set Queue = Rest
        Wake()

    # Effect を一覧に並べる（同じ EffectId の行があればそこへ足す）。Flash なら行を光らせる（拾い直して延びたとき）
    Track<internal>(Effect:pickup_effect_component, Flash:logic):void =
        if (not Effect.IsActive[]):
            return
        Now := GetSimulationElapsedTime()
        Remaining := Effect.GetRemainingSeconds()
        if (Row := FindRowFor(Effect)?):
            if (not Row.Effects.Find[Effect]):
                set Row.Effects += array{Effect}
            if (Remaining > Row.TotalSeconds):
                set Row.TotalSeconds = Remaining
            if (Flash?):
                set Row.FlashStart = Now
        else if (ShouldList(Effect)?):
            Card := Effect.GetPickupEffectCard(?FallbackColor := Style.FallbackAccentColor)
            Row := MakePickupHudRow(Card, Effect.EffectId, Style, Now)
            set Row.Effects = array{Effect}
            set Row.TotalSeconds = Max(Effect.DurationSeconds, Remaining)
            Y := (Rows.Length * 1.0) * (Style.RowHeightPx + Style.RowGapPx)
            set Row.CurrentY = Y
            set Row.PlacedY = Y
            set Row.PlacedX = -Style.RowSlidePx
            Row.Apply(0.0, 0.0, 0.0)
            Root.AddWidget(MakePickupHudSlot(Row.Layers, Style.ListXRatio, Style.ListYRatio, 0.0, 0.0, Row.PlacedX, Y, 0))
            set Rows += array{Row}
        Wake()

    # 止まって待っているなら動かし始める
    Wake<internal>():void =
        WakeEvent.Signal()

    # 毎フレーム、板と行を動かす。何も無いあいだは Wake まで止まる
    Run<internal>()<suspends>:void =
        var PreviousTime:float = GetSimulationElapsedTime()
        loop:
            if (IsIdle[]):
                WakeEvent.Await()
                set PreviousTime = GetSimulationElapsedTime()
            Now := GetSimulationElapsedTime()
            Dt := Clamp(Now - PreviousTime, 0.0, 0.1)
            set PreviousTime = Now
            StepToast(Now)
            StepRows(Now, Dt)
            Sleep(0.0)

    IsIdle<private>()<decides><transacts>:void =
        not Current?
        Queue.Length = 0
        Rows.Length = 0

    IsQueued<private>(Id:string)<decides><transacts>:void =
        Matches := for (Each : Queue, Each.Id = Id):
            Each
        Matches.Length > 0

    # 並べる効果か（Instant は並べない。ずっと続く効果は Style.ShowEndlessRows、ほかは MinRowSeconds 以上）
    ShouldList<private>(Effect:pickup_effect_component)<transacts>:logic =
        if (Effect.Instant?) then false
        else if (Effect.DurationSeconds <= 0.0) then Style.ShowEndlessRows
        else if (Effect.DurationSeconds < Style.MinRowSeconds) then false
        else true

    # Effect を受け持つ行（消えかけの行は除く）
    FindRowFor<private>(Effect:pickup_effect_component)<transacts>:?pickup_effect_hud_row =
        var Found:?pickup_effect_hud_row = false
        for (Row : Rows):
            if (not Found?, Row.LeaveStart < 0.0, Row.Matches(Effect)?):
                set Found = option{Row}
        Found

    StepToast<private>(Now:float):void =
        if (not Current?):
            if (Next := Queue[0]):
                set Queue = if (Rest := Queue.Slice[1]) then Rest else array{}
                Made := MakePickupHudToast(Next, Style, Now)
                Made.Apply(Style.ToastStartScale, 0.0, 0.0)
                Root.AddWidget(MakePickupHudSlot(Made.Layers, Style.ToastXRatio, Style.ToastYRatio, 0.5, 0.5, 0.0, 0.0, 10))
                set Current = option{Made}
        if (Toast := Current?):
            Finished := StepToastOf(Toast, Now)
            if (Finished?):
                Root.RemoveWidget(Toast.Layers)
                set Current = false

    # 板 1 枚を 1 フレーム進める。消え終わったら true
    StepToastOf<private>(Toast:pickup_effect_hud_toast, Now:float):logic =
        InSeconds := Max(Style.ToastInSeconds, 0.01)
        T := Now - Toast.StartTime
        if (Toast.OutStart < 0.0):
            Hold := if (Queue.Length > 0) then Min(Style.ToastHoldSeconds, Style.ToastQueuedHoldSeconds) else Style.ToastHoldSeconds
            if (T >= InSeconds and Now - Toast.HoldFrom >= Hold):
                set Toast.OutStart = Now
        var Scale:float = 1.0
        var Alpha:float = 1.0
        var TextAlpha:float = 1.0
        var OffsetY:float = 0.0
        var Done:logic = false
        if (T < InSeconds):
            # 出る：大きくなりながら（少し行き過ぎて戻る）濃くなる。文字は板が広がってから
            P := Clamp(T / InSeconds, 0.0, 1.0)
            set Scale = Style.ToastStartScale + (1.0 - Style.ToastStartScale) * PickupHudEaseBack(P, Style.ToastOvershoot)
            set Alpha = PickupHudEaseOut(P)
            set TextAlpha = Clamp((P - 0.35) / 0.65, 0.0, 1.0)
        if (Toast.PulseStart >= 0.0):
            Q := (Now - Toast.PulseStart) / Max(Style.ToastPulseSeconds, 0.01)
            if (Q < 1.0):
                set Scale = Scale * (1.0 + Style.ToastPulseScale * Sin(Q * PiFloat))
            else:
                set Toast.PulseStart = -1.0
        if (Toast.OutStart >= 0.0):
            # 消える：上へずれながら薄くなる
            Q := Clamp((Now - Toast.OutStart) / Max(Style.ToastOutSeconds, 0.01), 0.0, 1.0)
            E := Q * Q
            set Alpha = 1.0 - E
            set TextAlpha = Min(TextAlpha, Alpha)
            set OffsetY = -Style.ToastOutSlidePx * E
            set Scale = Scale * (1.0 - 0.04 * E)
            if (Q >= 1.0):
                set Done = true
        Toast.Apply(Scale, Alpha, TextAlpha)
        Moved := OffsetY - Toast.PlacedOffsetY
        if (not Done?, Moved > 0.25 or Moved < -0.25):
            Root.RemoveWidget(Toast.Layers)
            Root.AddWidget(MakePickupHudSlot(Toast.Layers, Style.ToastXRatio, Style.ToastYRatio, 0.5, 0.5, 0.0, OffsetY, 10))
            set Toast.PlacedOffsetY = OffsetY
        Done

    StepRows<private>(Now:float, Dt:float):void =
        var Kept:[]pickup_effect_hud_row = array{}
        for (Row : Rows):
            Finished := StepRow(Row, Now, Dt, Kept.Length)
            if (Finished?):
                Root.RemoveWidget(Row.Layers)
            else:
                set Kept += array{Row}
        set Rows = Kept

    # 行 1 つを 1 フレーム進める（Index は上から何番目か）。消え終わったら true
    StepRow<private>(Row:pickup_effect_hud_row, Now:float, Dt:float, Index:int):logic =
        Active := for (Effect : Row.Effects, Effect.IsActive[]):
            Effect
        set Row.Effects = Active
        if (Row.LeaveStart < 0.0 and Active.Length = 0):
            set Row.LeaveStart = Now
        # 残り（重なっていれば一番長いもの。ずっと続くものがあれば Endless）
        var Remaining:float = 0.0
        var Endless:logic = false
        for (Effect : Active):
            Seconds := Effect.GetRemainingSeconds()
            if (Seconds < 0.0):
                set Endless = true
            else if (Seconds > Remaining):
                set Remaining = Seconds
        if (Remaining > Row.TotalSeconds):
            set Row.TotalSeconds = Remaining
        Leaving := if (Row.LeaveStart >= 0.0) then true else false
        if (not Leaving?):
            Ratio := if (Endless?) then 1.0 else if (Row.TotalSeconds > 0.0) then Clamp(Remaining / Row.TotalSeconds, 0.0, 1.0) else 0.0
            # 延びたときは数フレームかけて伸ばし、縮むときはそのまま（毎フレーム縮む）
            if (Ratio > Row.ShownRatio + 0.002):
                set Row.ShownRatio = Row.ShownRatio + (Ratio - Row.ShownRatio) * Min(Dt * 14.0, 1.0)
            else:
                set Row.ShownRatio = Ratio
            Tenths := if (Endless?) then -2 else PickupHudTenths(Remaining)
            if (Tenths <> Row.ShownTenths):
                set Row.ShownTenths = Tenths
                Row.TimeText.SetText(StringToMessage(if (Endless?) then "" else PickupHudTenthsText(Tenths)))
            Count := Active.Length
            if (Count <> Row.ShownCount):
                set Row.ShownCount = Count
                Row.CountText.SetText(StringToMessage(if (Count > 1) then "{Style.StackPrefix}{Count}" else ""))
        # 出る・消える（横へずれながら）
        InE := PickupHudEaseOut((Now - Row.AppearStart) / Max(Style.RowInSeconds, 0.01))
        var Alpha:float = InE
        var OffsetX:float = -Style.RowSlidePx * (1.0 - InE)
        var Done:logic = false
        if (Leaving?):
            Q := Clamp((Now - Row.LeaveStart) / Max(Style.RowOutSeconds, 0.01), 0.0, 1.0)
            set Alpha = Alpha * (1.0 - Q)
            set OffsetX = OffsetX - Style.RowSlidePx * Q * Q
            if (Q >= 1.0):
                set Done = true
        # 残りが少ない：棒を点滅させる
        var BarAlpha:float = Alpha
        if (not Leaving?, not Endless?, Style.RowWarnSeconds > 0.0, Remaining < Style.RowWarnSeconds):
            Pulse := 0.5 + 0.5 * Sin(Now * 2.0 * PiFloat * Style.RowWarnBlinkPerSecond)
            set BarAlpha = Alpha * (0.3 + 0.7 * Pulse)
        # 拾い直して延びた：白く光らせる
        var Flash:float = 0.0
        if (Row.FlashStart >= 0.0):
            F := (Now - Row.FlashStart) / Max(Style.RowFlashSeconds, 0.01)
            if (F < 1.0):
                set Flash = 0.8 * (1.0 - F)
            else:
                set Row.FlashStart = -1.0
        Row.Apply(Alpha, BarAlpha, Flash)
        # 縦の位置（上の行が消えたら詰める）
        TargetY := (Index * 1.0) * (Style.RowHeightPx + Style.RowGapPx)
        Diff := TargetY - Row.CurrentY
        if (Diff > 0.5 or Diff < -0.5):
            set Row.CurrentY = Row.CurrentY + Diff * Min(Dt * Style.RowMoveSpeed, 1.0)
        else:
            set Row.CurrentY = TargetY
        MovedX := OffsetX - Row.PlacedX
        MovedY := Row.CurrentY - Row.PlacedY
        if (not Done?, MovedX > 0.25 or MovedX < -0.25 or MovedY > 0.25 or MovedY < -0.25):
            Root.RemoveWidget(Row.Layers)
            Root.AddWidget(MakePickupHudSlot(Row.Layers, Style.ListXRatio, Style.ListYRatio, 0.0, 0.0, OffsetX, Row.CurrentY, 0))
            set Row.PlacedX = OffsetX
            set Row.PlacedY = Row.CurrentY
        Done

# 拾ったときの知らせの板 1 枚（MakePickupHudToast が作る）
pickup_effect_hud_toast<internal> := class<unique><internal>:
    Card<internal>:widget_card
    Style<internal>:pickup_effect_hud_style
    Layers<internal>:overlay
    Back<internal>:color_block
    Strip<internal>:color_block
    Line<internal>:color_block
    Icon<internal>:?texture_block
    Badge<internal>:?text_block
    Title<internal>:text_block
    Description<internal>:?text_block
    StartTime<internal>:float
    # 出しておく時間を数え始めた時刻（出終わったとき。拾い直しで今に戻す）
    var HoldFrom<internal>:float = 0.0
    # 消え始めた時刻（まだなら負）
    var OutStart<internal>:float = -1.0
    # 弾ませ始めた時刻（弾ませていなければ負）
    var PulseStart<internal>:float = -1.0
    var PlacedOffsetY<internal>:float = 0.0

    # 大きさ Scale（1.0 = Style のまま）・板の濃さ Alpha・文字の濃さ TextAlpha で見た目をそろえる
    Apply<internal>(Scale:float, Alpha:float, TextAlpha:float):void =
        W := Style.ToastWidthPx * Scale
        H := Style.ToastHeightPx * Scale
        Back.SetDesiredSize(vector2{X := W, Y := H})
        Back.SetOpacity(ToOpacity(Style.ToastBackOpacity * Alpha))
        Strip.SetDesiredSize(vector2{X := Style.ToastIconWidthPx * Scale, Y := H})
        Strip.SetOpacity(ToOpacity(Alpha))
        Line.SetDesiredSize(vector2{X := W, Y := Style.ToastLinePx * Scale})
        Line.SetOpacity(ToOpacity(if (Style.ToastLinePx > 0.0) then Alpha else 0.0))
        if (Found := Icon?):
            Side := Min(Style.ToastIconWidthPx, Style.ToastHeightPx) * 0.78 * Scale
            Found.SetDesiredSize(vector2{X := Side, Y := Side})
            # 画像は薄くできないので、半分より薄いあいだは隠す
            Found.SetVisibility(if (Alpha >= 0.5) then widget_visibility.Visible else widget_visibility.Hidden)
        if (Found := Badge?):
            Found.SetTextSize(Style.ToastBadgeSize * Scale)
            Found.SetTextOpacity(ToOpacity(TextAlpha))
        Title.SetTextSize(Style.ToastTitleSize * Scale)
        Title.SetTextOpacity(ToOpacity(TextAlpha))
        if (Found := Description?):
            Found.SetTextSize(Style.ToastDescriptionSize * Scale)
            Found.SetTextOpacity(ToOpacity(TextAlpha))

# 一覧の 1 行（MakePickupHudRow が作る）。同じ EffectId の効果をまとめて受け持つ（EffectId が空なら、その効果だけ）
pickup_effect_hud_row<internal> := class<unique><internal>:
    Key<internal>:string
    Card<internal>:widget_card
    Style<internal>:pickup_effect_hud_style
    Layers<internal>:overlay
    Back<internal>:color_block
    Chip<internal>:color_block
    Icon<internal>:?texture_block
    NameText<internal>:text_block
    CountText<internal>:text_block
    TimeText<internal>:text_block
    BarBack<internal>:color_block
    BarFill<internal>:color_block
    BarWidthPx<internal>:float
    AppearStart<internal>:float
    var Effects<internal>:[]pickup_effect_component = array{}
    # 棒の満タンにあたる秒数（拾い直して延びたら増える）
    var TotalSeconds<internal>:float = 0.0
    var ShownRatio<internal>:float = 1.0
    var ShownTenths<internal>:int = -1
    var ShownCount<internal>:int = 1
    # 消え始めた時刻（まだなら負）
    var LeaveStart<internal>:float = -1.0
    # 光らせ始めた時刻（光らせていなければ負）
    var FlashStart<internal>:float = -1.0
    var CurrentY<internal>:float = 0.0
    var PlacedX<internal>:float = 0.0
    var PlacedY<internal>:float = 0.0

    # Effect をこの行が受け持つなら true（もう持っているか、同じ EffectId）
    Matches<internal>(Effect:pickup_effect_component)<transacts>:logic =
        if (Effects.Find[Effect]) then true
        else if (Key <> "", Effect.EffectId = Key) then true
        else false

    # 行の濃さ Alpha・棒の濃さ BarAlpha・白く光らせる量 Flash（0〜1）と、ShownRatio の棒の長さで見た目をそろえる
    Apply<internal>(Alpha:float, BarAlpha:float, Flash:float):void =
        Lit := PickupHudMix(Card.AccentColor, NamedColors.White, Flash)
        Back.SetOpacity(ToOpacity(Style.RowBackOpacity * Alpha))
        Chip.SetColor(Lit)
        Chip.SetOpacity(ToOpacity(Alpha))
        if (Found := Icon?):
            Found.SetVisibility(if (Alpha >= 0.5) then widget_visibility.Visible else widget_visibility.Hidden)
        NameText.SetTextOpacity(ToOpacity(Alpha))
        CountText.SetTextOpacity(ToOpacity(Alpha))
        TimeText.SetTextOpacity(ToOpacity(Alpha))
        BarBack.SetOpacity(ToOpacity(Style.RowBarBackOpacity * Alpha))
        BarFill.SetColor(Lit)
        BarFill.SetOpacity(ToOpacity(BarAlpha))
        BarFill.SetDesiredSize(vector2{X := BarWidthPx * Clamp(ShownRatio, 0.0, 1.0), Y := Style.RowBarHeightPx})

# 知らせの板を作る（まだ透明。Apply で出す）
MakePickupHudToast<internal>(Card:widget_card, Style:pickup_effect_hud_style, Now:float):pickup_effect_hud_toast =
    Back := color_block{DefaultColor := Style.ToastBackColor, DefaultOpacity := ToOpacity(0.0), DefaultDesiredSize := vector2{X := Style.ToastWidthPx, Y := Style.ToastHeightPx}}
    Strip := color_block{DefaultColor := Card.AccentColor, DefaultOpacity := ToOpacity(0.0), DefaultDesiredSize := vector2{X := Style.ToastIconWidthPx, Y := Style.ToastHeightPx}}
    Line := color_block{DefaultColor := Card.AccentColor, DefaultOpacity := ToOpacity(0.0), DefaultDesiredSize := vector2{X := Style.ToastWidthPx, Y := Style.ToastLinePx}}
    StripLayers := overlay{}
    StripLayers.AddWidget(overlay_slot{Widget := Strip, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Center})
    var Icon:?texture_block = false
    if (Image := Card.Image?):
        Side := Min(Style.ToastIconWidthPx, Style.ToastHeightPx) * 0.78
        MadeIcon := texture_block{DefaultImage := Image, DefaultDesiredSize := vector2{X := Side, Y := Side}}
        MadeIcon.SetVisibility(widget_visibility.Hidden)
        StripLayers.AddWidget(overlay_slot{Widget := MadeIcon, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Center})
        set Icon = option{MadeIcon}
    var Badge:?text_block = false
    if (Card.Badge <> ""):
        MadeBadge := text_block:
            DefaultText := StringToMessage(Card.Badge)
            DefaultTextColor := Style.ToastBadgeColor
            DefaultTextSize := Style.ToastBadgeSize
            DefaultTextOpacity := ToOpacity(0.0)
        # 画像があれば下に寄せる（画像に重ねない）
        BadgeAlign := if (Icon?) then vertical_alignment.Bottom else vertical_alignment.Center
        StripLayers.AddWidget(overlay_slot{Widget := MadeBadge, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := BadgeAlign, Padding := margin{Bottom := 4.0}})
        set Badge = option{MadeBadge}
    Title := text_block:
        DefaultText := StringToMessage(Card.Title)
        DefaultTextColor := Card.AccentColor
        DefaultTextSize := Style.ToastTitleSize
        DefaultTextOpacity := ToOpacity(0.0)
        DefaultJustification := text_justification.Left
    TextColumn := stack_box{Orientation := orientation.Vertical}
    TextColumn.AddWidget(stack_box_slot{Widget := Title, HorizontalAlignment := horizontal_alignment.Left})
    var Description:?text_block = false
    if (Card.Description <> ""):
        MadeDescription := text_block:
            DefaultText := StringToMessage(Card.Description)
            DefaultTextColor := Style.ToastDescriptionColor
            DefaultTextSize := Style.ToastDescriptionSize
            DefaultTextOpacity := ToOpacity(0.0)
            DefaultJustification := text_justification.Left
        set MadeDescription.AutoWrap = true
        set MadeDescription.WrapWidth = Max(Style.ToastWidthPx - Style.ToastIconWidthPx - Style.ToastPaddingPx * 2.0, 40.0)
        TextColumn.AddWidget(stack_box_slot{Widget := MadeDescription, HorizontalAlignment := horizontal_alignment.Left, Padding := margin{Top := 2.0}})
        set Description = option{MadeDescription}
    Content := stack_box{Orientation := orientation.Horizontal}
    Content.AddWidget(stack_box_slot{Widget := StripLayers, VerticalAlignment := vertical_alignment.Center})
    Content.AddWidget(stack_box_slot{Widget := TextColumn, VerticalAlignment := vertical_alignment.Center, Padding := margin{Left := Style.ToastPaddingPx, Right := Style.ToastPaddingPx}})
    Layers := overlay{}
    Layers.AddWidget(overlay_slot{Widget := Back, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Center})
    Layers.AddWidget(overlay_slot{Widget := Content, HorizontalAlignment := horizontal_alignment.Left, VerticalAlignment := vertical_alignment.Center})
    Layers.AddWidget(overlay_slot{Widget := Line, HorizontalAlignment := horizontal_alignment.Left, VerticalAlignment := vertical_alignment.Bottom})
    pickup_effect_hud_toast:
        Card := Card
        Style := Style
        Layers := Layers
        Back := Back
        Strip := Strip
        Line := Line
        Icon := Icon
        Badge := Badge
        Title := Title
        Description := Description
        StartTime := Now
        HoldFrom := Now + Style.ToastInSeconds

# 一覧の 1 行を作る（まだ透明。Apply で出す）
MakePickupHudRow<internal>(Card:widget_card, Key:string, Style:pickup_effect_hud_style, Now:float):pickup_effect_hud_row =
    H := Style.RowHeightPx
    BarW := Max(Style.RowWidthPx - H - Style.RowPaddingPx * 2.0, 20.0)
    Back := color_block{DefaultColor := Style.RowBackColor, DefaultOpacity := ToOpacity(0.0), DefaultDesiredSize := vector2{X := Style.RowWidthPx, Y := H}}
    Chip := color_block{DefaultColor := Card.AccentColor, DefaultOpacity := ToOpacity(0.0), DefaultDesiredSize := vector2{X := H, Y := H}}
    ChipLayers := overlay{}
    ChipLayers.AddWidget(overlay_slot{Widget := Chip, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Center})
    var Icon:?texture_block = false
    if (Image := Card.Image?):
        MadeIcon := texture_block{DefaultImage := Image, DefaultDesiredSize := vector2{X := H * 0.78, Y := H * 0.78}}
        MadeIcon.SetVisibility(widget_visibility.Hidden)
        ChipLayers.AddWidget(overlay_slot{Widget := MadeIcon, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Center})
        set Icon = option{MadeIcon}
    NameText := text_block:
        DefaultText := StringToMessage(Card.Title)
        DefaultTextColor := Style.RowNameColor
        DefaultTextSize := Style.RowNameSize
        DefaultTextOpacity := ToOpacity(0.0)
        DefaultJustification := text_justification.Left
    CountText := text_block:
        DefaultText := StringToMessage("")
        DefaultTextColor := Card.AccentColor
        DefaultTextSize := Style.RowTimeSize
        DefaultTextOpacity := ToOpacity(0.0)
    TimeText := text_block:
        DefaultText := StringToMessage("")
        DefaultTextColor := Style.RowTimeColor
        DefaultTextSize := Style.RowTimeSize
        DefaultTextOpacity := ToOpacity(0.0)
        DefaultJustification := text_justification.Right
    NameLine := stack_box{Orientation := orientation.Horizontal}
    NameLine.AddWidget(stack_box_slot{Widget := NameText, VerticalAlignment := vertical_alignment.Center})
    NameLine.AddWidget(stack_box_slot{Widget := CountText, VerticalAlignment := vertical_alignment.Center, Padding := margin{Left := 6.0}})
    # 名前の行の幅を棒にそろえる（透明な板）。名前は左、残り秒は右
    Spacer := color_block{DefaultColor := Style.RowBackColor, DefaultOpacity := ToOpacity(0.0), DefaultDesiredSize := vector2{X := BarW, Y := Style.RowNameSize * 1.3}}
    TopLine := overlay{}
    TopLine.AddWidget(overlay_slot{Widget := Spacer, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill})
    TopLine.AddWidget(overlay_slot{Widget := NameLine, HorizontalAlignment := horizontal_alignment.Left, VerticalAlignment := vertical_alignment.Center})
    TopLine.AddWidget(overlay_slot{Widget := TimeText, HorizontalAlignment := horizontal_alignment.Right, VerticalAlignment := vertical_alignment.Center})
    BarBack := color_block{DefaultColor := Style.RowBarBackColor, DefaultOpacity := ToOpacity(0.0), DefaultDesiredSize := vector2{X := BarW, Y := Style.RowBarHeightPx}}
    BarFill := color_block{DefaultColor := Card.AccentColor, DefaultOpacity := ToOpacity(0.0), DefaultDesiredSize := vector2{X := BarW, Y := Style.RowBarHeightPx}}
    Bar := overlay{}
    Bar.AddWidget(overlay_slot{Widget := BarBack, HorizontalAlignment := horizontal_alignment.Left, VerticalAlignment := vertical_alignment.Center})
    Bar.AddWidget(overlay_slot{Widget := BarFill, HorizontalAlignment := horizontal_alignment.Left, VerticalAlignment := vertical_alignment.Center})
    Column := stack_box{Orientation := orientation.Vertical}
    Column.AddWidget(stack_box_slot{Widget := TopLine, HorizontalAlignment := horizontal_alignment.Fill})
    Column.AddWidget(stack_box_slot{Widget := Bar, HorizontalAlignment := horizontal_alignment.Left, Padding := margin{Top := 3.0}})
    Content := stack_box{Orientation := orientation.Horizontal}
    Content.AddWidget(stack_box_slot{Widget := ChipLayers, VerticalAlignment := vertical_alignment.Center})
    Content.AddWidget(stack_box_slot{Widget := Column, VerticalAlignment := vertical_alignment.Center, Padding := margin{Left := Style.RowPaddingPx, Right := Style.RowPaddingPx}})
    Layers := overlay{}
    Layers.AddWidget(overlay_slot{Widget := Back, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill})
    Layers.AddWidget(overlay_slot{Widget := Content, HorizontalAlignment := horizontal_alignment.Left, VerticalAlignment := vertical_alignment.Center})
    pickup_effect_hud_row:
        Key := Key
        Card := Card
        Style := Style
        Layers := Layers
        Back := Back
        Chip := Chip
        Icon := Icon
        NameText := NameText
        CountText := CountText
        TimeText := TimeText
        BarBack := BarBack
        BarFill := BarFill
        BarWidthPx := BarW
        AppearStart := Now

# Widget を、画面の割合 (XRatio, YRatio) から (OffsetX, OffsetY) ピクセルずらした位置に、(AlignX, AlignY)（左上 0, 0・真ん中 0.5, 0.5）を合わせて中身の大きさで置く canvas_slot
MakePickupHudSlot<internal>(Widget:widget, XRatio:float, YRatio:float, AlignX:float, AlignY:float, OffsetX:float, OffsetY:float, ZOrder:int)<transacts>:canvas_slot =
    canvas_slot:
        Anchors := anchors{Minimum := vector2{X := XRatio, Y := YRatio}, Maximum := vector2{X := XRatio, Y := YRatio}}
        Offsets := margin{Left := OffsetX, Top := OffsetY, Right := 0.0, Bottom := 0.0}
        Alignment := vector2{X := AlignX, Y := AlignY}
        SizeToContent := true
        ZOrder := if (Z := slot_zorder[ZOrder]) then Z else 0
        Widget := Widget

# 残り秒を 0.1 秒きざみに切り上げた数（4.21 秒 → 43）
PickupHudTenths<internal>(Seconds:float)<transacts>:int =
    if (Tenths := Ceil[Max(Seconds, 0.0) * 10.0]) then Tenths else 0

# 0.1 秒きざみの数を文字にする（43 → "4.3"）
PickupHudTenthsText<internal>(Tenths:int)<transacts>:string =
    if (Whole := Quotient[Tenths, 10], Rest := Mod[Tenths, 10]) then "{Whole}.{Rest}" else "0.0"

# 0→1 を、速く始まりゆっくり止まる 0→1 にする（3 次）
PickupHudEaseOut<internal>(T:float)<computes>:float =
    U := 1.0 - Clamp(T, 0.0, 1.0)
    1.0 - U * U * U

# 0→1 を、少し行き過ぎて戻る 0→1 にする（Overshoot が行き過ぎの強さ。0 なら EaseOut と同じ形）
PickupHudEaseBack<internal>(T:float, Overshoot:float)<computes>:float =
    U := Clamp(T, 0.0, 1.0) - 1.0
    1.0 + (Overshoot + 1.0) * U * U * U + Overshoot * U * U

# From と To の色を Amount（0〜1）で混ぜる
PickupHudMix<internal>(From:color, To:color, Amount:float)<computes>:color =
    T := Clamp(Amount, 0.0, 1.0)
    color{R := From.R + (To.R - From.R) * T, G := From.G + (To.G - From.G) * T, B := From.B + (To.B - From.B) * T}
