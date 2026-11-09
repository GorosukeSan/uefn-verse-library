using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { ScheduleSystem }
using { ScheduleSystem.ConditionKit }
using { _Test }

# Role: counts schedule_component's StateChangedEvent / SecondEvent and the activated_event / deactivated_event reaching children
# Placement: created by the test code at runtime (child of the schedule entity)
test_schedule_probe_component<public> := class<final_super>(component):

    var<private> ActivatedCount:int = 0
    var<private> DeactivatedCount:int = 0
    var<private> StateChangedCount:int = 0
    var<private> SecondCount:int = 0
    var<private> SceneEventCount:int = 0

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            set ActivatedCount += 1
        else if (deactivated_event[SceneEvent]):
            set DeactivatedCount += 1
        else if (schedule_state_changed_event[SceneEvent]):
            set SceneEventCount += 1
        false

    RecordStateChanged<public>(Snapshot:schedule_snapshot):void =
        set StateChangedCount += 1

    RecordSecond<public>(Snapshot:schedule_snapshot):void =
        set SecondCount += 1

    GetActivatedCount<public>()<transacts>:int = ActivatedCount
    GetDeactivatedCount<public>()<transacts>:int = DeactivatedCount
    GetStateChangedCount<public>()<transacts>:int = StateChangedCount
    GetSecondCount<public>()<transacts>:int = SecondCount
    GetSceneEventCount<public>()<transacts>:int = SceneEventCount

# True when the Snapshot's state is State
IsState(Snapshot:schedule_snapshot, State:schedule_state):logic =
    if (Snapshot.State = State) then true else false

# True when the two strings are equal
SameString(Actual:string, Expected:string):logic =
    if (Actual = Expected) then true else false

# True when between Low and High inclusive
InRange(Value:int, Low:int, High:int):logic =
    if (Value >= Low and Value <= High) then true else false

# Role: verification of ScheduleSystem. Checks Evaluate's pure math (daily / fixed interval / one-shot, day boundaries, 45 days -> 45), clock monotonicity and debug time travel, that StateChangedEvent arrives only on change, activated_event / deactivated_event to children, and the condition Kit
# Test level: just one entity with this component (the clock, schedule and children are created by the test at runtime). Do not place another realtime_clock_component in the level (with 2 in the world, which one is used is undefined). No player needed
# Duration: about 12 seconds
# Result: [TEST] ScheduleSystem in the output log
schedule_system_test_component<public> := class<final_super>(component):

    # 2026-01-01 00:00 UTC
    EpochOf20260101:float = 1767225600.0
    TimeZone:int = 32400

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "ScheduleSystem"}
        TickEvents.PrePhysics.Await()
        TestTimeHelpers(Results)
        TestDaily(Results)
        TestInterval(Results)
        TestOneShot(Results)
        Clock := MakeClock()
        TickEvents.PrePhysics.Await()
        TestClock(Results, Clock)
        TestRuntime(Results, Clock)
        Clock.Entity.RemoveFromParent()
        if (Results.Finish[]) {}

    MakeClock<private>():realtime_clock_component =
        ClockEntity := entity{}
        Clock := realtime_clock_component{Entity := ClockEntity, TimeZoneOffsetSeconds := TimeZone}
        ClockEntity.AddComponents(array{Clock})
        Entity.AddEntities(array{ClockEntity})
        Clock

    # For the pure math tests. Attached to an entity that is not added to the world (Evaluate works without a clock)
    MakeDaily<private>(Hour:int, Minute:int, Duration:float):schedule_component =
        schedule_component{Entity := entity{}, Kind := schedule_kind.Daily, StartHour := Hour, StartMinute := Minute, StartSecond := 0, DurationSeconds := Duration}

    TestTimeHelpers<private>(Results:test_log):void =
        Results.CheckInt("days: 45 days + 100 s -> 45", DaysBetween(0.0, 45.0 * 86400.0 + 100.0), 45)
        Results.CheckInt("days: 59 days -> 59", DaysBetween(1000.0, 1000.0 + 59.0 * 86400.0), 59)
        Results.CheckInt("days: 0.9 day -> 0", DaysBetween(0.0, 80000.0), 0)
        # 2026-01-01 00:00 JST is 15:00 on the previous day in UTC. Japan's "day number" switches there while UTC's is still the previous day
        LocalMidnight := EpochOf20260101 - TimeZone * 1.0
        Results.CheckInt("day index: changes at local midnight (after)", GetDayIndex(LocalMidnight, TimeZone) - GetDayIndex(LocalMidnight - 1.0, TimeZone), 1)
        Results.CheckInt("day index: UTC does not change at JST midnight", GetDayIndex(LocalMidnight, 0) - GetDayIndex(LocalMidnight - 1.0, 0), 0)
        Results.CheckInt("day index: 2026-01-01 JST = 20454", GetDayIndex(LocalMidnight, TimeZone), 20454)
        Results.CheckFloat("seconds of day: 20:00 JST", GetSecondsOfDay(LocalMidnight + 72000.0, TimeZone), 72000.0, 0.001)
        Results.Check("format: 3661 -> 01:01:01", SameString(FormatHoursMinutesSeconds(3661), "01:01:01"))
        Results.Check("format: 3661 -> 61:01", SameString(FormatMinutesSeconds(3661), "61:01"))
        Results.Check("format: 90061 -> 1d 01:01:01", SameString(FormatDaysHoursMinutesSeconds(90061), "1d 01:01:01"))
        Results.Check("format: 90061 -> 1 day", SameString(FormatDays(90061), "1"))
        Results.Check("format: negative -> 00:00:00", SameString(FormatHoursMinutesSeconds(-5), "00:00:00"))
        Results.CheckInt("digit: tens of 45", GetDigit(45, 2), 4)
        Results.CheckInt("digit: hundreds of 45", GetDigit(45, 3), 0)
        Results.Check("digit: hundreds of 45 is a leading zero", if (IsLeadingZero[45, 3]) then true else false)
        Results.Check("digit: tens of 45 is not a leading zero", if (IsLeadingZero[45, 2]) then false else true)
        Results.CheckInt("whole seconds: 0.3 -> 1", ToWholeSeconds(0.3), 1)
        Results.CheckInt("whole seconds: 0 -> 0", ToWholeSeconds(0.0), 0)
        Results.CheckInt("whole seconds: 599.9999 -> 600", ToWholeSeconds(599.9999), 600)

    TestDaily<private>(Results:test_log):void =
        Schedule := MakeDaily(20, 0, 600.0)
        LocalMidnight := EpochOf20260101 - TimeZone * 1.0
        Day := GetDayIndex(LocalMidnight, TimeZone)
        Start := LocalMidnight + 72000.0
        Before := Schedule.EvaluateWithOffset(Start - 1.0, TimeZone)
        Results.Check("daily: Before 1 s before start", IsState(Before, schedule_state.Before))
        Results.CheckInt("daily: cycle is today's day index", Before.CycleIndex, Day)
        Results.CheckFloat("daily: 1 s to start", Before.SecondsToStart, 1.0, 0.001)
        Results.Check("daily: has next start", Before.HasNextStart)
        AtStart := Schedule.EvaluateWithOffset(Start, TimeZone)
        Results.Check("daily: Active at start", IsState(AtStart, schedule_state.Active))
        Results.CheckFloat("daily: elapsed 0 at start", AtStart.ElapsedSeconds, 0.0, 0.001)
        Results.CheckFloat("daily: 600 s to end at start", AtStart.SecondsToEnd, 600.0, 0.001)
        Results.CheckFloat("daily: next start in 1 day", AtStart.SecondsToStart, 86400.0, 0.001)
        Mid := Schedule.EvaluateWithOffset(Start + 599.0, TimeZone)
        Results.Check("daily: Active 1 s before end", IsState(Mid, schedule_state.Active))
        Results.CheckInt("daily: same cycle during show", Mid.CycleIndex, Day)
        AtEnd := Schedule.EvaluateWithOffset(Start + 600.0, TimeZone)
        Results.Check("daily: Before again at end", IsState(AtEnd, schedule_state.Before))
        Results.CheckInt("daily: cycle advances to tomorrow at end", AtEnd.CycleIndex, Day + 1)
        Results.CheckFloat("daily: 86400 - 600 to next start", AtEnd.SecondsToStart, 85800.0, 0.001)
        # Day boundary: a 20-minute run starting at 23:50 continues as the previous day's run past midnight
        Late := MakeDaily(23, 50, 1200.0)
        AfterMidnight := Late.EvaluateWithOffset(LocalMidnight + 300.0, TimeZone)
        Results.Check("daily: show crossing midnight is Active", IsState(AfterMidnight, schedule_state.Active))
        Results.CheckInt("daily: crossing midnight keeps yesterday's cycle", AfterMidnight.CycleIndex, Day - 1)
        Results.CheckFloat("daily: crossing midnight elapsed 900", AfterMidnight.ElapsedSeconds, 900.0, 0.001)
        # The same instant is a different day / state in a different time zone
        Utc := Schedule.EvaluateWithOffset(Start, 0)
        Results.Check("daily: same instant is 11:00 UTC -> Before", IsState(Utc, schedule_state.Before))

    TestInterval<private>(Results:test_log):void =
        Schedule := schedule_component{Entity := entity{}, Kind := schedule_kind.FixedInterval, EpochAnchorSeconds := 1000.0, IntervalSeconds := 10.0, DurationSeconds := 4.0}
        Results.Check("interval: Before before anchor", IsState(Schedule.Evaluate(999.0), schedule_state.Before))
        Results.CheckInt("interval: cycle 0 before anchor", Schedule.Evaluate(999.0).CycleIndex, 0)
        Results.CheckFloat("interval: 1 s to anchor", Schedule.Evaluate(999.0).SecondsToStart, 1.0, 0.001)
        Results.Check("interval: Active at anchor", IsState(Schedule.Evaluate(1000.0), schedule_state.Active))
        Results.Check("interval: Active just before end", IsState(Schedule.Evaluate(1003.9), schedule_state.Active))
        AtEnd := Schedule.Evaluate(1004.0)
        Results.Check("interval: Before at end", IsState(AtEnd, schedule_state.Before))
        Results.CheckInt("interval: cycle 1 after first end", AtEnd.CycleIndex, 1)
        Results.CheckFloat("interval: 6 s to next start", AtEnd.SecondsToStart, 6.0, 0.001)
        Third := Schedule.Evaluate(1021.0)
        Results.Check("interval: Active in cycle 2", IsState(Third, schedule_state.Active))
        Results.CheckInt("interval: cycle index 2", Third.CycleIndex, 2)
        Results.CheckFloat("interval: elapsed 1 in cycle 2", Third.ElapsedSeconds, 1.0, 0.001)
        Results.CheckFloat("interval: 3 s to end in cycle 2", Third.SecondsToEnd, 3.0, 0.001)
        Results.CheckFloat("interval: 9 s to next start in cycle 2", Third.SecondsToStart, 9.0, 0.001)
        Results.CheckInt("interval: cycle 3 waiting", Schedule.Evaluate(1025.0).CycleIndex, 3)
        Results.CheckFloat("interval: remaining UntilEnd while Active", Third.GetRemainingSeconds(schedule_remaining_kind.UntilEnd), 3.0, 0.001)
        Results.CheckFloat("interval: remaining UntilStart while Active", Third.GetRemainingSeconds(schedule_remaining_kind.UntilStart), 9.0, 0.001)
        Results.CheckFloat("interval: remaining UntilEnd while Before = to start", AtEnd.GetRemainingSeconds(schedule_remaining_kind.UntilEnd), 6.0, 0.001)

    TestOneShot<private>(Results:test_log):void =
        Schedule := schedule_component{Entity := entity{}, Kind := schedule_kind.OneShot, EpochAnchorSeconds := 1000.0, DurationSeconds := 5.0}
        Results.Check("oneshot: Before", IsState(Schedule.Evaluate(999.0), schedule_state.Before))
        Active := Schedule.Evaluate(1002.0)
        Results.Check("oneshot: Active", IsState(Active, schedule_state.Active))
        Results.Check("oneshot: no next start while Active", if (Active.HasNextStart?) then false else true)
        Results.CheckFloat("oneshot: UntilStart is 0 while Active", Active.GetRemainingSeconds(schedule_remaining_kind.UntilStart), 0.0, 0.001)
        After := Schedule.Evaluate(1005.0)
        Results.Check("oneshot: After", IsState(After, schedule_state.After))
        Results.Check("oneshot: no next start after", if (After.HasNextStart?) then false else true)
        Results.CheckFloat("oneshot: UntilEnd is 0 after", After.GetRemainingSeconds(schedule_remaining_kind.UntilEnd), 0.0, 0.001)
        Results.Check("oneshot: After is not Active", if (After.IsActive[]) then false else true)

    TestClock<private>(Results:test_log, Clock:realtime_clock_component)<suspends>:void =
        First := Clock.GetNowEpochSeconds()
        Sleep(0.1)
        Second := Clock.GetNowEpochSeconds()
        Results.Check("clock: Now does not go backwards", if (Second >= First) then true else false)
        Results.Check("clock: Now advances with real time", if (Second > First) then true else false)
        Results.CheckInt("clock: day index matches helper", Clock.GetDayIndex(Second), GetDayIndex(Second, TimeZone))
        Clock.JumpTo(Second + 1000.0)
        Jumped := Clock.GetNowEpochSeconds()
        Results.CheckFloat("clock: JumpTo moves Now forward", Jumped - Second, 1000.0, 0.5)
        Results.CheckFloat("clock: debug offset is 1000", Clock.DebugOffsetSeconds, 1000.0, 0.5)
        Clock.SetDebugOffsetSeconds(0.0)
        Restored := Clock.GetNowEpochSeconds()
        Results.Check("clock: offset 0 restores real time", if (Abs(Restored - Second) < 1.0) then true else false)
        Arrived := AwaitWithin(Clock.SecondEvent, 1.5)
        Results.Check("clock: SecondEvent arrives within 1.5 s", if (Arrived?) then true else false)

    TestRuntime<private>(Results:test_log, Clock:realtime_clock_component)<suspends>:void =
        # Schedule repeating 2 seconds Active / 2 seconds Before from the next whole second. Probe and condition Kit as children
        FlooredNow := if (Floored := Floor[Clock.GetNowEpochSeconds()]) then Floored else 0
        Anchor := (FlooredNow + 1) * 1.0
        ScheduleEntity := entity{}
        Schedule := schedule_component{Entity := ScheduleEntity, Kind := schedule_kind.FixedInterval, EpochAnchorSeconds := Anchor, IntervalSeconds := 4.0, DurationSeconds := 2.0}
        ScheduleEntity.AddComponents(array{Schedule})
        ChildEntity := entity{}
        Probe := test_schedule_probe_component{Entity := ChildEntity}
        Condition := schedule_active_condition_component{Entity := ChildEntity}
        ChildEntity.AddComponents(array{Probe, Condition})
        ScheduleEntity.AddEntities(array{ChildEntity})
        Entity.AddEntities(array{ScheduleEntity})
        Subscriptions := array:
            Schedule.StateChangedEvent.Subscribe(Probe.RecordStateChanged)
            Schedule.SecondEvent.Subscribe(Probe.RecordSecond)
        Results.Check("runtime: schedule found the clock", if (Schedule.FindClock[]) then true else false)
        Results.CheckInt("runtime: clock lists the schedule", Clock.GetSchedules().Length, 1)
        Results.Check("runtime: condition not satisfied before start", if (Condition.IsSatisfied[]) then false else true)

        # After 1.5 seconds: midway through the first Active run. The first evaluation (Before) and the change to Active make 2 change notifications
        Sleep(1.5)
        Results.Check("runtime: Active during first cycle", if (Schedule.IsActive[]) then true else false)
        Results.Check("runtime: condition satisfied while Active", if (Condition.IsSatisfied[]) then true else false)
        Results.CheckInt("runtime: activated_event reached child once", Probe.GetActivatedCount(), 1)
        Results.Check("runtime: state changes so far are 1 or 2", InRange(Probe.GetStateChangedCount(), 1, 2))

        # After 2 seconds: Before (the first run ended)
        Sleep(2.0)
        Results.Check("runtime: Before after first cycle", if (Schedule.IsActive[]) then false else true)
        Results.Check("runtime: condition not satisfied after cycle", if (Condition.IsSatisfied[]) then false else true)
        Results.CheckInt("runtime: deactivated_event reached child once", Probe.GetDeactivatedCount(), 1)

        # 6 more seconds: Active (+5 to +7) -> Before (+7 to) -> Active (+9 to). About 9.5 seconds in total, 5 to 6 changes, 9 to 11 second notifications
        Sleep(6.0)
        Results.Check("runtime: StateChangedEvent only on changes (5..6 in 9.5 s)", InRange(Probe.GetStateChangedCount(), 5, 6))
        Results.CheckInt("runtime: scene event count equals StateChangedEvent count", Probe.GetSceneEventCount(), Probe.GetStateChangedCount())
        Results.Check("runtime: SecondEvent about once per second (8..11)", InRange(Probe.GetSecondCount(), 8, 11))
        Results.Check("runtime: activated 2..3 times", InRange(Probe.GetActivatedCount(), 2, 3))
        Results.Check("runtime: condition follows IsActive", if (Condition.IsSatisfied[]) then (if (Schedule.IsActive[]) then true else false) else (if (Schedule.IsActive[]) then false else true))
        if (Latest := Schedule.FindLastSnapshot[]):
            Results.Check("runtime: last snapshot cycle >= 2", if (Latest.CycleIndex >= 2) then true else false)
        else:
            Results.Fail("runtime: FindLastSnapshot", "no snapshot after 9.5 s")

        # Debug time travel re-evaluates on the spot (intermediate changes are not replayed; it is one change)
        CountBeforeJump := Probe.GetStateChangedCount()
        Clock.JumpTo(Anchor + 400.0 + 0.5)
        Sleep(0.1)
        Results.CheckInt("runtime: jump re-evaluates at once", Probe.GetStateChangedCount(), CountBeforeJump + 1)
        Results.Check("runtime: Active right after jump into a cycle", if (Schedule.IsActive[]) then true else false)
        if (Latest := Schedule.FindLastSnapshot[]):
            Results.CheckInt("runtime: cycle 100 after jump", Latest.CycleIndex, 100)
        Clock.SetDebugOffsetSeconds(0.0)

        for (Subscription : Subscriptions):
            Subscription.Cancel()
        ScheduleEntity.RemoveFromParent()
        Sleep(0.1)
        Results.CheckInt("runtime: unregistered on removal", Clock.GetSchedules().Length, 0)
