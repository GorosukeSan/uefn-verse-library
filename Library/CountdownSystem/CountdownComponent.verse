using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { CountdownSystem.TooltipKit }

# 残りの秒数（整数に切り上げた値）が変わった知らせ。数え始め・1 秒ごと・AddSeconds で届く（0 になったときは届かず、countdown_finished_event が届く）
# 方向：countdown_component の entity から下へ（SendDown）。AlsoSendUp がオンなら、親から上へ（SendUp）も送る
# 送り手：countdown_component。受け手：子孫の countdown_finished_condition_component・残り秒数を出す画面など（AlsoSendUp なら祖先のノード・HUD も）。消費しない
countdown_remaining_changed_event<public> := class(scene_event):
    # 送ったカウントダウン
    Countdown<public>:countdown_component
    # 残りの秒数（切り上げた整数。1 以上）
    RemainingWholeSeconds<public>:int

# 数え終わった（残りが 0 になった）知らせ。Stop や停止の合図で止めたときは届かない
# 方向：countdown_component の entity から下へ（SendDown）。AlsoSendUp がオンなら、親から上へ（SendUp）も送る
# 送り手：countdown_component。受け手：子孫の countdown_finished_condition_component など（AlsoSendUp なら祖先も）。消費しない
countdown_finished_event<public> := class(scene_event):
    # 送ったカウントダウン
    Countdown<public>:countdown_component

# 役割：DurationSeconds 秒を数え、残り秒数（整数）が変わるたびと、数え終わりを子孫へ知らせる
# 置き方：エディターで entity に付ける。ゲームの流れの外でも使える
# いつ始めるか：StartOnActivated が true なら起動の合図（activated_event）で最初から数え直し（数えている途中でもやり直す）、停止の合図（deactivated_event）で止める（ゲームの流れなら、ノードに入ってから出るまで）。StartOnBegin が true ならシミュレーション開始で始める。どちらも false にして、コードから Start / Restart / Stop を呼んでもよい
# 子：残り秒数を使うもの（countdown_finished_condition など）は、この entity かその子孫に置く
# 知らせ：countdown_remaining_changed_event / countdown_finished_event を下へ送り（AlsoSendUp なら上へも）、RemainingChangedEvent / FinishedEvent に届ける
# 外から：Start / Restart / Stop / Pause / Resume / AddSeconds。IsRunning / IsPaused / GetRemainingSeconds（小数）/ GetRemainingWholeSeconds（切り上げた整数）で今の状態を問い合わせる
# 前提・注意：残りは「終わる時刻 − 今のシミュレーション時刻」で決める（フレームの数や待ちの積み重ねで数えないので、ずれない）。一時停止中は残りが減らない
countdown_component<public> := class<final_super>(component):

    # 数える秒数（0.1〜3600 秒。小数可）。0 になると数え終わる。既定 5.0（今回だけ違う長さは Restart(?Seconds := …) で）
    @editable_number(float):
        ToolTip := CountdownDurationToolTip
        Categories := array{CountdownCategory}
        MinValue := option{0.1}
        MaxValue := option{3600.0}
    DurationSeconds<public>:float = 5.0

    # true なら起動の合図で最初から数え直し（数えている途中でもやり直す）、停止の合図で止める。false なら合図を無視する。既定 true
    @editable:
        ToolTip := CountdownStartOnActivatedToolTip
        Categories := array{CountdownCategory}
    StartOnActivated<public>:logic = true

    # true ならシミュレーション開始と同時に数え始める（ゲームの流れを使わないとき）。既定 false
    @editable:
        ToolTip := CountdownStartOnBeginToolTip
        Categories := array{CountdownCategory}
    StartOnBegin<public>:logic = false

    # true なら知らせ（countdown_remaining_changed_event / countdown_finished_event）を、子孫へ（SendDown）に加えて、親から祖先へ（SendUp）も送る（ノードの外の HUD・祖先の部品が受けるとき）。自分の entity には SendDown の 1 回だけ届く。既定 false
    @editable:
        ToolTip := CountdownAlsoSendUpToolTip
        Categories := array{CountdownCategory}
    AlsoSendUp<public>:logic = false

    var<private> Running:logic = false
    var<private> Paused:logic = false
    # 数えている途中（一時停止していない）ときの、終わるシミュレーション時刻（秒）
    var<private> EndTimeSeconds:float = 0.0
    # 一時停止しているときの残り（秒）
    var<private> PausedRemainingSeconds:float = 0.0
    # 最後に知らせた残り秒数（切り上げ）。まだ知らせていなければ -1
    var<private> LastNotifiedSeconds:int = -1

    RemainingChangedEventInternal<private><final>:event(int) = event(int){}

    # 残り秒数（切り上げた整数）が変わるたび（数え始め・1 秒ごと・AddSeconds）に、その値で届く（Await / Subscribe する。外から Signal はできない）
    RemainingChangedEvent<public><final>:listenable(int) = MakeProxyListenable(RemainingChangedEventInternal)

    FinishedEventInternal<private><final>:event() = event(){}

    # 数え終わったときに届く（Stop・停止の合図で止めたときは届かない）（Await / Subscribe する。外から Signal はできない）
    FinishedEvent<public><final>:listenable(tuple()) = MakeProxyListenable(FinishedEventInternal)

    # 状態が変わった（始めた・止めた・一時停止・再開・増減）ことを数えるループに伝える
    WakeEvent<private>:event() = event(){}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (StartOnBegin?):
            Start()

    OnEndSimulation<override>():void =
        set Running = false
        set Paused = false
        (super:)OnEndSimulation()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (StartOnActivated?):
            if (activated_event[SceneEvent]):
                Restart()
            else if (deactivated_event[SceneEvent]):
                Stop()
        false

    OnSimulate<override>()<suspends>:void =
        loop:
            if (Running? and not Paused?):
                Refresh()
            if (Running? and not Paused?):
                # 残り秒数（切り上げ）が次に変わるまで待つ。途中で状態が変われば計算し直す
                Remaining := GetRemainingSeconds()
                Whole := CeilWholeSeconds(Remaining)
                WaitSeconds := Max(Remaining - (Whole - 1) * 1.0, 0.0)
                race:
                    Sleep(WaitSeconds)
                    WakeEvent.Await()
            else:
                WakeEvent.Await()

    # 数えていなければ DurationSeconds 秒から数え始める。数えている途中（一時停止中も含む）なら何もしない（やり直すなら Restart）
    Start<public>():void =
        if (not Running?):
            Restart()

    # 最初から数え直す（数えている途中・一時停止中・数え終わったあとでも）。Seconds を渡すと今回だけその秒数（小数可。0 以下ならその場で数え終わる）、渡さなければ DurationSeconds。始めた時点の残り秒数を知らせる
    Restart<public>(?Seconds:?float = false):void =
        Duration := if (Override := Seconds?) then Override else DurationSeconds
        set Running = true
        set Paused = false
        set EndTimeSeconds = GetSimulationElapsedTime() + Duration
        set LastNotifiedSeconds = -1
        Refresh()
        WakeEvent.Signal()

    # 数えるのをやめる（FinishedEvent は届かない）。数えていなければ何もしない
    Stop<public>():void =
        if (not Running?):
            return
        set Running = false
        set Paused = false
        WakeEvent.Signal()

    # 数えている途中（一時停止中を除く）なら成功する。始める前・止めたあと・数え終わったあと・一時停止中は失敗する
    IsRunning<public>()<decides><transacts>:void =
        Running?
        not Paused?

    # 数えている途中で一時停止しているなら成功する
    IsPaused<public>()<decides><transacts>:void =
        Running?
        Paused?

    # 数えている途中なら一時停止する（残りはそのまま止まる）。数えていない・もう一時停止しているなら何もしない
    Pause<public>():void =
        if (not Running? or Paused?):
            return
        set PausedRemainingSeconds = Max(EndTimeSeconds - GetSimulationElapsedTime(), 0.0)
        set Paused = true
        WakeEvent.Signal()

    # 一時停止しているなら、止めたときの残りから再開する。一時停止していないなら何もしない
    Resume<public>():void =
        if (not Running? or not Paused?):
            return
        set EndTimeSeconds = GetSimulationElapsedTime() + PausedRemainingSeconds
        set Paused = false
        Refresh()
        WakeEvent.Signal()

    # 数えている途中（一時停止中も含む）なら、残りを DeltaSeconds 秒増やす（マイナスなら減らす）。残りが 0 以下になると、その場で数え終わる（一時停止中なら再開したとき）。残り秒数が変われば知らせる。数えていないときは何もしない
    AddSeconds<public>(DeltaSeconds:float):void =
        if (not Running?):
            return
        if (Paused?):
            set PausedRemainingSeconds = Max(PausedRemainingSeconds + DeltaSeconds, 0.0)
            NotifyRemaining(CeilWholeSeconds(PausedRemainingSeconds))
        else:
            set EndTimeSeconds += DeltaSeconds
            Refresh()
        WakeEvent.Signal()

    # 残りの秒数（小数）。数えていない・数え終わったあとは 0.0。一時停止中は止めたときの残り
    GetRemainingSeconds<public>()<transacts>:float =
        if (not Running?):
            0.0
        else if (Paused?):
            PausedRemainingSeconds
        else:
            Max(EndTimeSeconds - GetSimulationElapsedTime(), 0.0)

    # 残りの秒数を整数に切り上げた値（画面に出す値。RemainingChangedEvent と同じ）。数えていない・数え終わったあとは 0
    GetRemainingWholeSeconds<public>()<transacts>:int =
        CeilWholeSeconds(GetRemainingSeconds())

    # 残りが 0 なら数え終わり、そうでなければ残り秒数（切り上げ）が変わったときだけ知らせる
    Refresh<private>():void =
        if (not Running? or Paused?):
            return
        Whole := CeilWholeSeconds(GetRemainingSeconds())
        if (Whole <= 0):
            Finish()
        else:
            NotifyRemaining(Whole)

    NotifyRemaining<private>(Whole:int):void =
        if (Whole <= 0 or Whole = LastNotifiedSeconds):
            return
        set LastNotifiedSeconds = Whole
        Send(countdown_remaining_changed_event{Countdown := Self, RemainingWholeSeconds := Whole})
        RemainingChangedEventInternal.Signal(Whole)

    Finish<private>():void =
        set Running = false
        set Paused = false
        set LastNotifiedSeconds = -1
        Send(countdown_finished_event{Countdown := Self})
        FinishedEventInternal.Signal()

    # 自分と子孫へ送る。AlsoSendUp なら親から祖先へも送る（自分の entity に 2 回届かないよう、上へは親から）
    Send<private>(SceneEvent:scene_event):void =
        Entity.SendDown(SceneEvent)
        if (AlsoSendUp?, Parent := Entity.GetParent[]):
            Parent.SendUp(SceneEvent)

# 秒（小数）を切り上げた整数にする。ほぼ整数の値（誤差 0.001 秒未満）はその整数にする。0 以下は 0
CeilWholeSeconds<internal>(TimeSeconds:float)<transacts>:int =
    if (TimeSeconds <= 0.001):
        0
    else if (Whole := Ceil[TimeSeconds - 0.001]):
        Whole
    else:
        0
