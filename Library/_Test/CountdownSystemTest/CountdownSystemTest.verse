using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { CountdownSystem }
using { _Test }

# 役割：RemainingChangedEvent などの int の知らせを数える（Subscribe に Record を渡す）
test_int_recorder<public> := class:

    var<private> Count:int = 0
    var<private> LastValue:int = 0

    Record<public>(Value:int):void =
        set Count += 1
        set LastValue = Value

    GetCount<public>()<transacts>:int = Count

    GetLast<public>()<transacts>:int = LastValue

# 役割：祖先で受けた countdown の scene_event を数える（AlsoSendUp の確認用。テストが実行時に親の entity に付ける）
test_countdown_event_counter<public> := class<final_super>(component):

    var<private> RemainingCount:int = 0
    var<private> FinishedCount:int = 0

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (countdown_remaining_changed_event[SceneEvent]):
            set RemainingCount += 1
        else if (countdown_finished_event[SceneEvent]):
            set FinishedCount += 1
        false

    GetRemainingCount<public>()<transacts>:int = RemainingCount

    GetFinishedCount<public>()<transacts>:int = FinishedCount

# 役割：CountdownSystem の動作確認。Start から FinishedEvent までの実時間、残り秒数の知らせの回数と値、Pause / Resume、AddSeconds、Stop、起動の合図での開始とやり直し、Restart（途中・秒数を渡す・1 秒未満）、AlsoSendUp を確かめる
# テストのレベル：この component を付けた entity を 1 つ置くだけ（countdown_component はテストが実行時に作る）。プレイヤーは要らない
# かかる時間：約 20 秒
# 結果：出力ログの [TEST] CountdownSystem
countdown_system_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "CountdownSystem"}
        TickEvents.PrePhysics.Await()
        TestTiming(Results)
        TestPauseResume(Results)
        TestAddSeconds(Results)
        TestStop(Results)
        TestActivation(Results)
        TestRestart(Results)
        TestAlsoSendUp(Results)
        if (Results.Finish[]) {}

    MakeCountdown<private>(DurationSeconds:float, StartOnActivated:logic):countdown_component =
        MakeCountdownUnder(Entity, DurationSeconds, StartOnActivated, false)

    MakeCountdownUnder<private>(Parent:entity, DurationSeconds:float, StartOnActivated:logic, AlsoSendUp:logic):countdown_component =
        CountdownEntity := entity{}
        Countdown := countdown_component{Entity := CountdownEntity, DurationSeconds := DurationSeconds, StartOnActivated := StartOnActivated, AlsoSendUp := AlsoSendUp}
        CountdownEntity.AddComponents(array{Countdown})
        Parent.AddEntities(array{CountdownEntity})
        Countdown

    TestTiming<private>(Results:test_log)<suspends>:void =
        Countdown := MakeCountdown(3.0, false)
        Recorder := test_int_recorder{}
        Subscription := Countdown.RemainingChangedEvent.Subscribe(Recorder.Record)
        Results.Check("timing: not running before Start", if (Countdown.IsRunning[]) then false else true)
        StartTime := GetSimulationElapsedTime()
        Countdown.Start()
        Results.Check("timing: running after Start", if (Countdown.IsRunning[]) then true else false)
        Results.CheckInt("timing: first RemainingChangedEvent is 3", Recorder.GetLast(), 3)
        Results.CheckInt("timing: GetRemainingWholeSeconds right after Start", Countdown.GetRemainingWholeSeconds(), 3)
        Arrived1 := AwaitWithin(Countdown.FinishedEvent, 5.0)
        if (Arrived1?):
            Results.CheckFloat("timing: finished after 3 s", GetSimulationElapsedTime() - StartTime, 3.0, 0.15)
        else:
            Results.Fail("timing: FinishedEvent", "not received within 5 s")
        Results.CheckInt("timing: RemainingChangedEvent count (3, 2, 1)", Recorder.GetCount(), 3)
        Results.CheckInt("timing: last RemainingChangedEvent is 1", Recorder.GetLast(), 1)
        Results.Check("timing: not running after finish", if (Countdown.IsRunning[]) then false else true)
        Results.CheckInt("timing: remaining 0 after finish", Countdown.GetRemainingWholeSeconds(), 0)
        Subscription.Cancel()
        Countdown.Entity.RemoveFromParent()

    TestPauseResume<private>(Results:test_log)<suspends>:void =
        Countdown := MakeCountdown(3.0, false)
        StartTime := GetSimulationElapsedTime()
        Countdown.Start()
        Sleep(1.0)
        Countdown.Pause()
        Results.Check("pause: IsPaused", if (Countdown.IsPaused[]) then true else false)
        Results.Check("pause: not IsRunning while paused", if (Countdown.IsRunning[]) then false else true)
        Before := Countdown.GetRemainingSeconds()
        Sleep(2.0)
        Results.CheckFloat("pause: remaining does not decrease while paused", Countdown.GetRemainingSeconds(), Before, 0.001)
        Countdown.Resume()
        Results.Check("resume: IsRunning", if (Countdown.IsRunning[]) then true else false)
        Arrived2 := AwaitWithin(Countdown.FinishedEvent, 4.0)
        if (Arrived2?):
            # 3 秒 + 一時停止の 2 秒
            Results.CheckFloat("resume: finished after 3 s + 2 s paused", GetSimulationElapsedTime() - StartTime, 5.0, 0.2)
        else:
            Results.Fail("resume: FinishedEvent", "not received within 4 s after Resume")
        Countdown.Entity.RemoveFromParent()

    TestAddSeconds<private>(Results:test_log)<suspends>:void =
        Countdown := MakeCountdown(2.0, false)
        Recorder := test_int_recorder{}
        Subscription := Countdown.RemainingChangedEvent.Subscribe(Recorder.Record)
        StartTime := GetSimulationElapsedTime()
        Countdown.Start()
        Countdown.AddSeconds(2.0)
        Results.CheckInt("add: remaining 4 after AddSeconds(2)", Countdown.GetRemainingWholeSeconds(), 4)
        Results.CheckInt("add: RemainingChangedEvent with 4", Recorder.GetLast(), 4)
        Arrived3 := AwaitWithin(Countdown.FinishedEvent, 6.0)
        if (Arrived3?):
            Results.CheckFloat("add: finished after 4 s", GetSimulationElapsedTime() - StartTime, 4.0, 0.15)
        else:
            Results.Fail("add: FinishedEvent", "not received within 6 s")
        Subscription.Cancel()
        # 残りより多く減らすと、その場で終わる
        Countdown.Start()
        var Finished:logic = false
        race:
            block:
                Arrived4 := AwaitWithin(Countdown.FinishedEvent, 0.5)
                if (Arrived4?):
                    set Finished = true
            block:
                Countdown.AddSeconds(-10.0)
                Sleep(1.0)
        Results.Check("add: negative beyond remaining finishes at once", Finished)
        Countdown.Entity.RemoveFromParent()

    TestStop<private>(Results:test_log)<suspends>:void =
        Countdown := MakeCountdown(1.0, false)
        Countdown.Start()
        Countdown.Stop()
        Results.Check("stop: not running", if (Countdown.IsRunning[]) then false else true)
        Arrived5 := AwaitWithin(Countdown.FinishedEvent, 1.5)
        Results.Check("stop: no FinishedEvent after Stop", if (Arrived5?) then false else true)
        Countdown.Entity.RemoveFromParent()

    TestActivation<private>(Results:test_log)<suspends>:void =
        Countdown := MakeCountdown(5.0, true)
        Countdown.Entity.SendActivated()
        Results.Check("activation: activated_event starts", if (Countdown.IsRunning[]) then true else false)
        Countdown.Entity.SendDeactivated()
        Results.Check("activation: deactivated_event stops", if (Countdown.IsRunning[]) then false else true)
        # 数えている途中の起動の合図は、最初から数え直す
        Countdown.Entity.SendActivated()
        Countdown.AddSeconds(-3.0)
        Countdown.Entity.SendActivated()
        Results.CheckInt("activation: activated_event while running restarts", Countdown.GetRemainingWholeSeconds(), 5)
        Countdown.Entity.RemoveFromParent()

    TestRestart<private>(Results:test_log)<suspends>:void =
        Countdown := MakeCountdown(3.0, false)
        Countdown.Start()
        Sleep(1.0)
        # 数えている途中の Start は何もしない
        Countdown.Start()
        Results.CheckInt("restart: Start while running does nothing", Countdown.GetRemainingWholeSeconds(), 2)
        StartTime := GetSimulationElapsedTime()
        Countdown.Restart()
        Results.CheckInt("restart: Restart while running starts over", Countdown.GetRemainingWholeSeconds(), 3)
        Arrived6 := AwaitWithin(Countdown.FinishedEvent, 5.0)
        if (Arrived6?):
            Results.CheckFloat("restart: finished 3 s after Restart", GetSimulationElapsedTime() - StartTime, 3.0, 0.15)
        else:
            Results.Fail("restart: FinishedEvent", "not received within 5 s")
        # 秒数を渡すと今回だけその長さ（1 秒未満も）
        HalfStart := GetSimulationElapsedTime()
        Countdown.Restart(?Seconds := option{0.5})
        Results.CheckInt("restart: Restart(0.5) shows 1", Countdown.GetRemainingWholeSeconds(), 1)
        Arrived7 := AwaitWithin(Countdown.FinishedEvent, 2.0)
        if (Arrived7?):
            Results.CheckFloat("restart: Restart(0.5) finishes after 0.5 s", GetSimulationElapsedTime() - HalfStart, 0.5, 0.1)
        else:
            Results.Fail("restart: FinishedEvent after Restart(0.5)", "not received within 2 s")
        # 渡さなければ DurationSeconds に戻る
        Countdown.Restart()
        Results.CheckFloat("restart: Restart() uses DurationSeconds again", Countdown.GetRemainingSeconds(), 3.0, 0.05)
        Countdown.Stop()
        Countdown.Entity.RemoveFromParent()

    TestAlsoSendUp<private>(Results:test_log)<suspends>:void =
        Parent := entity{}
        Counter := test_countdown_event_counter{Entity := Parent}
        Parent.AddComponents(array{Counter})
        Entity.AddEntities(array{Parent})
        Countdown := MakeCountdownUnder(Parent, 1.0, false, true)
        Countdown.Start()
        Arrived8 := AwaitWithin(Countdown.FinishedEvent, 2.0)
        Results.Check("send up: FinishedEvent", if (Arrived8?) then true else false)
        Results.CheckInt("send up: parent got countdown_remaining_changed_event", Counter.GetRemainingCount(), 1)
        Results.CheckInt("send up: parent got countdown_finished_event", Counter.GetFinishedCount(), 1)
        Quiet := MakeCountdownUnder(Parent, 0.5, false, false)
        Quiet.Start()
        AwaitWithin(Quiet.FinishedEvent, 1.5)
        Results.CheckInt("send up: off by default (no more events on parent)", Counter.GetFinishedCount(), 1)
        Parent.RemoveFromParent()
