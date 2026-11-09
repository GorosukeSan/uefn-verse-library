using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Verse }
using { ScheduleSystem.TooltipKit }

# 役割：実時刻（エポック秒）の時計。区画（または世界）に 1 つ。登録されたスケジュール（schedule_component）をまとめて、整数秒の境目のすぐあとに 1 回ずつ評価し、結果を配る。ループを持つのはこの component だけ（スケジュールごとのループは無い）
# 置き方：エディターで entity に付ける。区画（game_scope_component の配下）か世界に 1 つ（schedule_component が FindScopedComponent で探す）
# 知らせ：SecondEvent（毎秒 1 回、評価に使った時刻）。スケジュールの状態の知らせは、同じ tick の中で SecondEvent より先に配られる
# 外から：GetNowEpochSeconds / GetTimeZoneOffsetSeconds / GetDayIndex / GetSecondsOfDay。デバッグで時刻をずらすなら SetDebugOffsetSeconds / JumpTo（1 か所にだけある。公開する島では利用者の判断で止める）
# 前提・注意：
#   - GetSecondsSinceEpoch は同じトランザクションの中では同じ値を返す（1 tick の中で全スケジュールの時刻がそろう）
#   - 実時刻は止められない（一時停止が要るものは CountdownSystem などシミュレーション時間のものを使う）
#   - 時計（OS）が逆に戻っても GetNowEpochSeconds は戻らない（前回の値を保つ）。デバッグのずらしで戻すのは別で、戻せる
#   - 毎フレームの処理は無い。1 秒に 1 回起きて、スケジュールの数だけ計算する
realtime_clock_component<public> := class<final_super>(component):

    # 現地時刻と UTC のずれ（秒）。既定 32400（日本標準時 +9 時間）。夏時間は考えない
    @editable_number(int):
        ToolTip := ClockTimeZoneOffsetToolTip
        Categories := array{ScheduleClockCategory}
        MinValue := option{-50400}
        MaxValue := option{50400}
    TimeZoneOffsetSeconds<public>:int = DefaultTimeZoneOffsetSeconds

    # 整数秒の境目から、どれだけ遅れて起きるか（秒）。小さすぎると 1 秒ずれることがある。既定 0.02
    @editable_number(float):
        ToolTip := ClockWakeMarginToolTip
        Categories := array{ScheduleClockCategory}
        MinValue := option{0.0}
        MaxValue := option{0.5}
    WakeMarginSeconds<public>:float = 0.02

    # デバッグで時刻にずらしている秒数（0.0 なら実時刻のまま）
    var<private> DebugOffsetSeconds<public>:float = 0.0
    # OS の時計が最後に返した値（逆に戻ったときに保つため）
    var<private> LastRawSeconds:float = 0.0
    # 最後に評価した整数秒（同じ秒で 2 回評価しないため）。まだなら -1
    var<private> LastTickedSecond:int = -1
    var<private> Schedules:[]schedule_component = array{}

    SecondEventInternal<private><final>:event(float) = event(float){}

    # 整数秒の境目のすぐあとに、毎秒 1 回、評価に使った時刻（GetNowEpochSeconds）で届く。同じ tick で登録されたスケジュールの知らせを配ったあとに届く（Await / Subscribe する。外から Signal はできない）
    SecondEvent<public><final>:listenable(float) = MakeProxyListenable(SecondEventInternal)

    # 評価をやり直したい（デバッグで時刻を動かした）ことをループに伝える
    WakeEvent<private>:event() = event(){}

    OnEndSimulation<override>():void =
        set Schedules = array{}
        (super:)OnEndSimulation()

    OnSimulate<override>()<suspends>:void =
        # 同じ木の component がみな OnBeginSimulation を終えて（スケジュールが登録を済ませて）から最初の評価をする
        TickEvents.PrePhysics.Await()
        loop:
            T := GetNowEpochSeconds()
            Second := FloorToInt(T)
            if (Second <> LastTickedSecond):
                set LastTickedSecond = Second
                Tick(T)
            # 次の整数秒の境目の少しあとに起きる（Sleep はフレーム単位なので、少し遅れて起きることはあっても早く起きることはない前提。早く起きたら上の判定で評価せず待ち直す）
            WaitSeconds := Max((Second + 1) * 1.0 - T + WakeMarginSeconds, 0.0)
            race:
                Sleep(WaitSeconds)
                WakeEvent.Await()

    # 今の時刻（エポック秒 ＋ デバッグのずらし）。同じトランザクションの中では同じ値。OS の時計が逆に戻っても前の値を保つ
    GetNowEpochSeconds<public>()<transacts>:float =
        Raw := GetSecondsSinceEpoch()
        Clamped := if (Raw > LastRawSeconds) then Raw else LastRawSeconds
        set LastRawSeconds = Clamped
        Clamped + DebugOffsetSeconds

    # この時計の時間帯のずれ（秒）
    GetTimeZoneOffsetSeconds<public>()<computes>:int =
        TimeZoneOffsetSeconds

    # EpochSeconds の時点が、この時計の時間帯で「何日目」か（現地 0 時で切り替わる）
    GetDayIndex<public>(EpochSeconds:float)<transacts>:int =
        ScheduleSystem.GetDayIndex(EpochSeconds, TimeZoneOffsetSeconds)

    # EpochSeconds の時点の、この時計の時間帯での現地 0 時からの経過秒
    GetSecondsOfDay<public>(EpochSeconds:float)<transacts>:float =
        ScheduleSystem.GetSecondsOfDay(EpochSeconds, TimeZoneOffsetSeconds)

    # 時刻を OffsetSeconds 秒ずらす（デバッグ用。マイナスで過去へ）。その場で全スケジュールを評価し直す（途中の変化は再生せず、「飛んだ」として今の状態だけが配られる）
    SetDebugOffsetSeconds<public>(OffsetSeconds:float):void =
        set DebugOffsetSeconds = OffsetSeconds
        set LastTickedSecond = -1
        WakeEvent.Signal()

    # 今の時刻が EpochSeconds になるようにずらす（デバッグ用）。SetDebugOffsetSeconds と同じく、その場で評価し直す
    JumpTo<public>(EpochSeconds:float):void =
        SetDebugOffsetSeconds(EpochSeconds - (GetNowEpochSeconds() - DebugOffsetSeconds))

    # 登録されているスケジュール（並び順は登録順）
    GetSchedules<public>()<transacts>:[]schedule_component =
        Schedules

    # スケジュールを登録する（schedule_component が OnBeginSimulation で呼ぶ）。次の整数秒から評価される。もう登録されていれば何もしない
    Register<internal>(Schedule:schedule_component):void =
        for (Existing : Schedules, Existing = Schedule):
            return
        set Schedules += array{Schedule}

    # 登録を外す（schedule_component が OnEndSimulation で呼ぶ）
    Unregister<internal>(Schedule:schedule_component):void =
        set Schedules = for (Existing : Schedules, Existing <> Schedule):
            Existing

    # 1 秒に 1 回。全スケジュールの状態の変化を配ってから、全スケジュールの SecondEvent、最後に自分の SecondEvent
    Tick<private>(T:float):void =
        Current := Schedules
        for (Schedule : Current):
            Schedule.Advance(T)
        for (Schedule : Current):
            Schedule.NotifySecond()
        SecondEventInternal.Signal(T)
