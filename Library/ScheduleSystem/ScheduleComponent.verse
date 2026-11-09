using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Verse }
using { ActivationSystem }
using { SceneGraphSystem }
using { ScheduleSystem.TooltipKit }

# 繰り返しの種類
schedule_kind<public> := enum:
    # 毎日、現地時刻の StartHour:StartMinute:StartSecond から DurationSeconds 秒
    Daily
    # EpochAnchorSeconds から IntervalSeconds ごとに DurationSeconds 秒
    FixedInterval
    # EpochAnchorSeconds から DurationSeconds 秒、1 回だけ
    OneShot

# 役割：実時刻のスケジュール（データ）。「時刻 T での状態」を計算で答える（Evaluate）。ループは持たず、区画の realtime_clock_component に登録されて毎秒 1 回評価される
# 置き方：エディターで entity に付ける。区画（または世界）に realtime_clock_component が 1 つ要る
# 子：スケジュールに合わせて動かすもの（Kit の component、countdown_component、画面表示、能力の付与（GrantOnBegin オフ）など）を、この entity かその子孫に置く
# 知らせ：
#   - 状態か回が変わったときだけ：schedule_state_changed_event を下へ送り、StateChangedEvent に届ける（最初の評価も 1 回）。Active に入るとき activated_event、Active から出るとき deactivated_event も下へ送る（SendActivation がオン）
#   - 毎秒：SecondEvent に snapshot を届ける（表示向け。購読する component の数だけ毎秒の処理が増えるので、状態だけ要るなら StateChangedEvent を使う）
# 外から：Evaluate（純粋な計算。テストや予告の表示に）、GetCurrentSnapshot、IsActive、FindClock
# 前提・注意：
#   - 値はすべて時計の GetNowEpochSeconds() から計算する。途中参加・サーバの再起動・デバッグの時刻移動でも「今の位置」が出る（開始の合図からの再生ではない）。サーバが期間の途中で立ち上がったときは、最初の評価で Active になり ElapsedSeconds > 0 の activated_event が届く
#   - 実時刻は止められない（Pause は無い）
#   - デバッグで時刻を飛ばしたとき、途中の変化はまとめて 1 回の変化（飛んだ先の状態）になる
#   - Daily の長さは 86400 未満、FixedInterval の長さは間隔未満にする（それ以上だと常に Active）
schedule_component<public> := class<final_super>(component):

    # 繰り返しの種類（Daily / FixedInterval / OneShot）。既定 Daily
    @editable:
        ToolTip := ScheduleKindToolTip
        Categories := array{ScheduleCategory}
    Kind<public>:schedule_kind = schedule_kind.Daily

    # Daily の開始時刻の時（0〜23。現地時刻。時間帯は時計の設定）。既定 20
    @editable_number(int):
        ToolTip := ScheduleStartHourToolTip
        Categories := array{ScheduleCategory}
        MinValue := option{0}
        MaxValue := option{23}
    StartHour<public>:int = 20

    # Daily の開始時刻の分（0〜59）。既定 0
    @editable_number(int):
        ToolTip := ScheduleStartMinuteToolTip
        Categories := array{ScheduleCategory}
        MinValue := option{0}
        MaxValue := option{59}
    StartMinute<public>:int = 0

    # Daily の開始時刻の秒（0〜59）。既定 0
    @editable_number(int):
        ToolTip := ScheduleStartSecondToolTip
        Categories := array{ScheduleCategory}
        MinValue := option{0}
        MaxValue := option{59}
    StartSecond<public>:int = 0

    # 期間（Active）の長さ（秒）。Daily では 86400 未満、FixedInterval では間隔未満にする。既定 600
    @editable_number(float):
        ToolTip := ScheduleDurationToolTip
        Categories := array{ScheduleCategory}
        MinValue := option{0.0}
    DurationSeconds<public>:float = 600.0

    # FixedInterval の間隔（秒）。0 以下なら 1 回だけ（OneShot と同じ）。既定 3600
    @editable_number(float):
        ToolTip := ScheduleIntervalToolTip
        Categories := array{ScheduleCategory}
        MinValue := option{0.0}
    IntervalSeconds<public>:float = 3600.0

    # FixedInterval の基準の時刻、OneShot の開始の時刻（エポック秒）。既定 0
    @editable_number(float):
        ToolTip := ScheduleEpochAnchorToolTip
        Categories := array{ScheduleCategory}
        MinValue := option{0.0}
    EpochAnchorSeconds<public>:float = 0.0

    # オンなら Active に入るとき activated_event、出るとき deactivated_event を自分と子孫へ送る。既定オン
    @editable:
        ToolTip := ScheduleSendActivationToolTip
        Categories := array{ScheduleCategory}
    SendActivation<public>:logic = true

    var<private> Clock:?realtime_clock_component = false
    # 最後に配った値（まだ評価していなければ false）
    var<private> LastSnapshot:?schedule_snapshot = false
    # 今の tick で配る予定の値（Advance で入れ、NotifySecond で配る）
    var<private> PendingSecond:?schedule_snapshot = false

    StateChangedEventInternal<private><final>:event(schedule_snapshot) = event(schedule_snapshot){}
    SecondEventInternal<private><final>:event(schedule_snapshot) = event(schedule_snapshot){}

    # 状態（Before / Active / After）か回が変わったときだけ、新しい値で届く。最初の評価でも 1 回届く。期間外は何も届かない（Await / Subscribe する。外から Signal はできない）
    StateChangedEvent<public><final>:listenable(schedule_snapshot) = MakeProxyListenable(StateChangedEventInternal)

    # 毎秒 1 回、今の値で届く（残り時間の表示向け。購読者の数だけ毎秒の処理が増える）。同じ秒の StateChangedEvent より後に届く（Await / Subscribe する。外から Signal はできない）
    SecondEvent<public><final>:listenable(schedule_snapshot) = MakeProxyListenable(SecondEventInternal)

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        TryRegister()

    OnSimulate<override>()<suspends>:void =
        if (not Clock?):
            # 時計が自分より後に始まった（実行時に足された）かもしれないので、1 フレーム待って探し直す
            TickEvents.PrePhysics.Await()
            TryRegister()
        if (not Clock?):
            # まだ無ければ、見つかるまで 1 秒ごとに探す（プレハブで後から足された時計も拾う）。1 秒たっても無ければ 1 回だけ知らせる
            race:
                block:
                    Found := Entity.AwaitScopedComponent(realtime_clock_component)
                    UseClock(Found)
                block:
                    Sleep(1.0)
                    Print("[schedule_component] realtime_clock_component が区画（または世界）に見つかりません。見つかるまで 1 秒ごとに探します（それまでは評価されません）")
                    Sleep(Inf)

    OnEndSimulation<override>():void =
        if (Found := Clock?):
            Found.Unregister(Self)
        set Clock = false
        set LastSnapshot = false
        set PendingSecond = false
        (super:)OnEndSimulation()

    # 登録先の時計。見つからなければ失敗する（OnBeginSimulation より前・時計が無いとき）
    FindClock<public>()<decides><transacts>:realtime_clock_component =
        Clock?

    # 計算に使う時間帯のずれ（秒）。時計があればその設定、無ければ DefaultTimeZoneOffsetSeconds
    GetTimeZoneOffsetSeconds<public>()<transacts>:int =
        if (Found := Clock?):
            Found.GetTimeZoneOffsetSeconds()
        else:
            DefaultTimeZoneOffsetSeconds

    # 最後に評価した値。まだ評価していなければ失敗する（時計の最初の tick より前）
    FindLastSnapshot<public>()<decides><transacts>:schedule_snapshot =
        LastSnapshot?

    # 今の値。時計があれば GetNowEpochSeconds() で計算し直す（最後の評価から 1 秒未満のずれを無くす）。無ければ最後の値か、実時刻（デバッグのずらし無し）で計算する
    GetCurrentSnapshot<public>()<transacts>:schedule_snapshot =
        if (Found := Clock?):
            Evaluate(Found.GetNowEpochSeconds())
        else if (Previous := LastSnapshot?):
            Previous
        else:
            Evaluate(GetSecondsSinceEpoch())

    # 今 Active なら成功する（GetCurrentSnapshot で判定）
    IsActive<public>()<decides><transacts>:void =
        GetCurrentSnapshot().IsActive[]

    # 時刻 T（エポック秒）での値を計算する。状態を変えない純粋な計算（時間帯は GetTimeZoneOffsetSeconds）
    Evaluate<public>(T:float)<transacts>:schedule_snapshot =
        EvaluateWithOffset(T, GetTimeZoneOffsetSeconds())

    # 時刻 T での値を、時間帯のずれ TimeZoneOffsetSeconds で計算する。状態を変えない純粋な計算（テスト・別の時間帯の予告に）
    EvaluateWithOffset<public>(T:float, TimeZoneOffsetSeconds:int)<transacts>:schedule_snapshot =
        case (Kind):
            schedule_kind.Daily => EvaluateDaily(T, TimeZoneOffsetSeconds)
            schedule_kind.FixedInterval => EvaluateInterval(T)
            schedule_kind.OneShot => EvaluateOneShot(T)

    EvaluateDaily<private>(T:float, TimeZoneOffsetSeconds:int)<transacts>:schedule_snapshot =
        Duration := Max(DurationSeconds, 0.0)
        StartOfDay := MakeSecondsOfDay(StartHour, StartMinute, StartSecond) * 1.0
        DayIndex := GetDayIndex(T, TimeZoneOffsetSeconds)
        TodayStart := GetDayStartSeconds(DayIndex, TimeZoneOffsetSeconds) + StartOfDay
        YesterdayStart := TodayStart - SecondsPerDay * 1.0
        if (T < YesterdayStart + Duration):
            # 前日の回が日付をまたいでまだ続いている
            MakeActive(T, DayIndex - 1, YesterdayStart, Duration, option{TodayStart})
        else if (T < TodayStart):
            MakeBefore(T, DayIndex, TodayStart)
        else if (T < TodayStart + Duration):
            MakeActive(T, DayIndex, TodayStart, Duration, option{TodayStart + SecondsPerDay * 1.0})
        else:
            MakeBefore(T, DayIndex + 1, TodayStart + SecondsPerDay * 1.0)

    EvaluateInterval<private>(T:float)<transacts>:schedule_snapshot =
        if (IntervalSeconds <= 0.0):
            return EvaluateOneShot(T)
        Duration := Max(DurationSeconds, 0.0)
        Anchor := EpochAnchorSeconds
        if (T < Anchor):
            return MakeBefore(T, 0, Anchor)
        CycleIndex := FloorToInt((T - Anchor) / IntervalSeconds)
        CycleStart := Anchor + CycleIndex * IntervalSeconds
        if (T < CycleStart + Duration):
            MakeActive(T, CycleIndex, CycleStart, Duration, option{CycleStart + IntervalSeconds})
        else:
            MakeBefore(T, CycleIndex + 1, CycleStart + IntervalSeconds)

    EvaluateOneShot<private>(T:float)<transacts>:schedule_snapshot =
        Duration := Max(DurationSeconds, 0.0)
        Start := EpochAnchorSeconds
        if (T < Start):
            MakeBefore(T, 0, Start)
        else if (T < Start + Duration):
            MakeActive(T, 0, Start, Duration, false)
        else:
            schedule_snapshot:
                NowSeconds := T
                State := schedule_state.After
                CycleIndex := 0
                CycleStartSeconds := Start

    MakeBefore<private>(T:float, CycleIndex:int, CycleStart:float)<transacts>:schedule_snapshot =
        schedule_snapshot:
            NowSeconds := T
            State := schedule_state.Before
            CycleIndex := CycleIndex
            CycleStartSeconds := CycleStart
            SecondsToStart := CycleStart - T
            HasNextStart := true

    MakeActive<private>(T:float, CycleIndex:int, CycleStart:float, Duration:float, NextStart:?float)<transacts>:schedule_snapshot =
        schedule_snapshot:
            NowSeconds := T
            State := schedule_state.Active
            CycleIndex := CycleIndex
            CycleStartSeconds := CycleStart
            ElapsedSeconds := T - CycleStart
            SecondsToEnd := CycleStart + Duration - T
            SecondsToStart := if (Next := NextStart?) then Next - T else 0.0
            HasNextStart := if (NextStart?) then true else false

    # 区画の realtime_clock_component を探して覚え、初めて見つけたときに登録する（覚えていれば何もしない）
    TryRegister<private>():void =
        if (not Clock?, Found := Entity.ResolveScopedComponent(Clock, realtime_clock_component)?):
            UseClock(Found)

    # Found を登録先の時計として覚え、登録する（もう覚えていれば何もしない）
    UseClock<private>(Found:realtime_clock_component):void =
        if (not Clock?):
            set Clock = option{Found}
            Found.Register(Self)

    # 時計が毎秒呼ぶ。評価して、状態か回が前回と違えば知らせる（最初の評価も知らせる）
    Advance<internal>(T:float):void =
        Current := Evaluate(T)
        set PendingSecond = option{Current}
        Previous := LastSnapshot
        if (PreviousValue := Previous?, PreviousValue.IsSameStateAndCycle[Current]):
            return
        set LastSnapshot = option{Current}
        Entity.SendDown(schedule_state_changed_event{Schedule := Self, Previous := Previous, Current := Current})
        if (SendActivation?):
            WasActive := if (PreviousValue := Previous?, PreviousValue.IsActive[]) then true else false
            if (Current.IsActive[] and not WasActive?):
                Entity.SendActivated()
            else if (WasActive? and not Current.IsActive[]):
                Entity.SendDeactivated()
        StateChangedEventInternal.Signal(Current)

    # 時計が毎秒、全スケジュールの Advance のあとに呼ぶ
    NotifySecond<internal>():void =
        if (Current := PendingSecond?):
            set PendingSecond = false
            SecondEventInternal.Signal(Current)
