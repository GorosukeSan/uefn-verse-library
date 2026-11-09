using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Verse }
using { ActivationSystem }
using { SceneGraphSystem }
using { ScheduleSystem.TooltipKit }

# Kind of repetition
schedule_kind<public> := enum:
    # Every day, DurationSeconds seconds from local time StartHour:StartMinute:StartSecond
    Daily
    # DurationSeconds seconds every IntervalSeconds from EpochAnchorSeconds
    FixedInterval
    # DurationSeconds seconds from EpochAnchorSeconds, once
    OneShot

# Role: a real-time schedule (data). Answers "the state at time T" by computation (Evaluate). Has no loop; it is registered with the scope's realtime_clock_component and evaluated once per second
# Placement: attach to an entity in the editor. One realtime_clock_component is needed in the scope (or the world)
# Children: place the things driven by the schedule (Kit components, countdown_component, screen displays, ability grants (GrantOnBegin off), ...) on this entity or its descendants
# Notifies:
#   - Only when the state or the cycle changes: sends schedule_state_changed_event down and fires StateChangedEvent (once on the first evaluation too). On entering Active, also sends activated_event down; on leaving Active, deactivated_event (when SendActivation is on)
#   - Every second: fires SecondEvent with a snapshot (for displays. Each subscribing component adds per-second work, so use StateChangedEvent when only the state matters)
# From outside: Evaluate (pure computation; for tests and previews), GetCurrentSnapshot, IsActive, FindClock
# Requirements / notes:
#   - Every value is computed from the clock's GetNowEpochSeconds(). Late joiners, server restarts and debug time jumps all get "the current position" (not a playback from the start signal). When the server starts in the middle of a period, the first evaluation is Active and an activated_event with ElapsedSeconds > 0 arrives
#   - Real time cannot be stopped (there is no Pause)
#   - When the time is jumped for debugging, the intermediate changes collapse into one change (the state at the destination)
#   - Keep a Daily duration under 86400 and a FixedInterval duration under the interval (otherwise always Active)
schedule_component<public> := class<final_super>(component):

    # Kind of repetition (Daily / FixedInterval / OneShot). Default Daily
    @editable:
        ToolTip := ScheduleKindToolTip
        Categories := array{ScheduleCategory}
    Kind<public>:schedule_kind = schedule_kind.Daily

    # Hour of the Daily start time (0-23; local time; the time zone is the clock's setting). Default 20
    @editable_number(int):
        ToolTip := ScheduleStartHourToolTip
        Categories := array{ScheduleCategory}
        MinValue := option{0}
        MaxValue := option{23}
    StartHour<public>:int = 20

    # Minute of the Daily start time (0-59). Default 0
    @editable_number(int):
        ToolTip := ScheduleStartMinuteToolTip
        Categories := array{ScheduleCategory}
        MinValue := option{0}
        MaxValue := option{59}
    StartMinute<public>:int = 0

    # Second of the Daily start time (0-59). Default 0
    @editable_number(int):
        ToolTip := ScheduleStartSecondToolTip
        Categories := array{ScheduleCategory}
        MinValue := option{0}
        MaxValue := option{59}
    StartSecond<public>:int = 0

    # Length of the period (Active) in seconds. Keep under 86400 for Daily and under the interval for FixedInterval. Default 600
    @editable_number(float):
        ToolTip := ScheduleDurationToolTip
        Categories := array{ScheduleCategory}
        MinValue := option{0.0}
    DurationSeconds<public>:float = 600.0

    # FixedInterval interval (seconds). 0 or less means once (same as OneShot). Default 3600
    @editable_number(float):
        ToolTip := ScheduleIntervalToolTip
        Categories := array{ScheduleCategory}
        MinValue := option{0.0}
    IntervalSeconds<public>:float = 3600.0

    # Anchor time of FixedInterval, start time of OneShot (epoch seconds). Default 0
    @editable_number(float):
        ToolTip := ScheduleEpochAnchorToolTip
        Categories := array{ScheduleCategory}
        MinValue := option{0.0}
    EpochAnchorSeconds<public>:float = 0.0

    # When on, sends activated_event to itself and its descendants on entering Active, and deactivated_event on leaving. Default on
    @editable:
        ToolTip := ScheduleSendActivationToolTip
        Categories := array{ScheduleCategory}
    SendActivation<public>:logic = true

    var<private> Clock:?realtime_clock_component = false
    # The last value delivered (false until the first evaluation)
    var<private> LastSnapshot:?schedule_snapshot = false
    # The value to deliver this tick (set by Advance, delivered by NotifySecond)
    var<private> PendingSecond:?schedule_snapshot = false

    StateChangedEventInternal<private><final>:event(schedule_snapshot) = event(schedule_snapshot){}
    SecondEventInternal<private><final>:event(schedule_snapshot) = event(schedule_snapshot){}

    # Fires with the new value only when the state (Before / Active / After) or the cycle changes. Fires once on the first evaluation too. Nothing outside those changes (Await / Subscribe; cannot be Signaled from outside)
    StateChangedEvent<public><final>:listenable(schedule_snapshot) = MakeProxyListenable(StateChangedEventInternal)

    # Fires once per second with the current value (for remaining-time displays; each subscriber adds per-second work). Arrives after the same second's StateChangedEvent (Await / Subscribe; cannot be Signaled from outside)
    SecondEvent<public><final>:listenable(schedule_snapshot) = MakeProxyListenable(SecondEventInternal)

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        TryRegister()

    OnSimulate<override>()<suspends>:void =
        if (not Clock?):
            # The clock may have started after us (added at runtime), so wait one frame and look again
            TickEvents.PrePhysics.Await()
            TryRegister()
        if (not Clock?):
            # Still none: keep looking every second until found (also picks up a clock added later by a prefab). Report once if none after 1 s
            race:
                block:
                    Found := Entity.AwaitScopedComponent(realtime_clock_component)
                    UseClock(Found)
                block:
                    Sleep(1.0)
                    Print("[schedule_component] realtime_clock_component not found in the scope (or the world). Looking every second until found (not evaluated until then)")
                    Sleep(Inf)

    OnEndSimulation<override>():void =
        if (Found := Clock?):
            Found.Unregister(Self)
        set Clock = false
        set LastSnapshot = false
        set PendingSecond = false
        (super:)OnEndSimulation()

    # The clock this schedule is registered with. Fails when not found (before OnBeginSimulation / no clock)
    FindClock<public>()<decides><transacts>:realtime_clock_component =
        Clock?

    # Time zone offset (seconds) used for computation. The clock's setting when there is one, otherwise DefaultTimeZoneOffsetSeconds
    GetTimeZoneOffsetSeconds<public>()<transacts>:int =
        if (Found := Clock?):
            Found.GetTimeZoneOffsetSeconds()
        else:
            DefaultTimeZoneOffsetSeconds

    # The last evaluated value. Fails until the first evaluation (before the clock's first tick)
    FindLastSnapshot<public>()<decides><transacts>:schedule_snapshot =
        LastSnapshot?

    # The current value. With a clock, recomputed from GetNowEpochSeconds() (removes the sub-second drift since the last evaluation). Without one, the last value, or computed from real time (no debug offset)
    GetCurrentSnapshot<public>()<transacts>:schedule_snapshot =
        if (Found := Clock?):
            Evaluate(Found.GetNowEpochSeconds())
        else if (Previous := LastSnapshot?):
            Previous
        else:
            Evaluate(GetSecondsSinceEpoch())

    # Succeeds when Active now (decided with GetCurrentSnapshot)
    IsActive<public>()<decides><transacts>:void =
        GetCurrentSnapshot().IsActive[]

    # Compute the value at time T (epoch seconds). A pure computation that changes no state (time zone from GetTimeZoneOffsetSeconds)
    Evaluate<public>(T:float)<transacts>:schedule_snapshot =
        EvaluateWithOffset(T, GetTimeZoneOffsetSeconds())

    # Compute the value at time T with the time zone offset TimeZoneOffsetSeconds. A pure computation that changes no state (for tests and previews in another time zone)
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
            # Yesterday's cycle crossed midnight and is still running
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

    # Find and remember the scope's realtime_clock_component, registering on the first find (does nothing when already remembered)
    TryRegister<private>():void =
        if (not Clock?, Found := Entity.ResolveScopedComponent(Clock, realtime_clock_component)?):
            UseClock(Found)

    # Remember Found as the clock and register with it (does nothing when already remembered)
    UseClock<private>(Found:realtime_clock_component):void =
        if (not Clock?):
            set Clock = option{Found}
            Found.Register(Self)

    # Called by the clock every second. Evaluates and notifies when the state or the cycle differs from last time (the first evaluation notifies too)
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

    # Called by the clock every second, after Advance on every schedule
    NotifySecond<internal>():void =
        if (Current := PendingSecond?):
            set PendingSecond = false
            SecondEventInternal.Signal(Current)
