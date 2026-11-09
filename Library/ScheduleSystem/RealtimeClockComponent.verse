using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Verse }
using { ScheduleSystem.TooltipKit }

# Role: a real-time (epoch seconds) clock. One per scope (or world). Evaluates all registered schedules (schedule_component) together, once right after each whole-second boundary, and delivers the results. This is the only component with a loop (there is no loop per schedule)
# Placement: attach to an entity in the editor. One per scope (under game_scope_component) or world (schedule_component finds it with FindScopedComponent)
# Notifies: SecondEvent (once per second, with the time used for evaluation). The schedules' state notifications are delivered before SecondEvent within the same tick
# From outside: GetNowEpochSeconds / GetTimeZoneOffsetSeconds / GetDayIndex / GetSecondsOfDay. To shift time for debugging, SetDebugOffsetSeconds / JumpTo (in one place only. On a published island, disable at your discretion)
# Requirements / notes:
#   - GetSecondsSinceEpoch returns the same value within one transaction (all schedules share the same time within a tick)
#   - Real time cannot be stopped (for things that need pausing, use simulation-time Systems such as CountdownSystem)
#   - GetNowEpochSeconds never goes backward even if the OS clock does (it keeps the previous value). Going back with the debug offset is separate and allowed
#   - No per-frame work. Wakes once per second and computes once per schedule
realtime_clock_component<public> := class<final_super>(component):

    # Offset between local time and UTC (seconds). Default 32400 (Japan Standard Time, +9 hours). Daylight saving time is not considered
    @editable_number(int):
        ToolTip := ClockTimeZoneOffsetToolTip
        Categories := array{ScheduleClockCategory}
        MinValue := option{-50400}
        MaxValue := option{50400}
    TimeZoneOffsetSeconds<public>:int = DefaultTimeZoneOffsetSeconds

    # How long after the whole-second boundary to wake (seconds). Too small may drift by 1 second. Default 0.02
    @editable_number(float):
        ToolTip := ClockWakeMarginToolTip
        Categories := array{ScheduleClockCategory}
        MinValue := option{0.0}
        MaxValue := option{0.5}
    WakeMarginSeconds<public>:float = 0.02

    # Seconds the time is shifted for debugging (0.0 means real time)
    var<private> DebugOffsetSeconds<public>:float = 0.0
    # The last value returned by the OS clock (kept in case it goes backward)
    var<private> LastRawSeconds:float = 0.0
    # The last whole second evaluated (so the same second is not evaluated twice). -1 until then
    var<private> LastTickedSecond:int = -1
    var<private> Schedules:[]schedule_component = array{}

    SecondEventInternal<private><final>:event(float) = event(float){}

    # Fires once per second, right after the whole-second boundary, with the time used for evaluation (GetNowEpochSeconds). Arrives after the registered schedules' notifications of the same tick (Await / Subscribe; cannot be Signaled from outside)
    SecondEvent<public><final>:listenable(float) = MakeProxyListenable(SecondEventInternal)

    # Tells the loop to re-evaluate (the time was moved for debugging)
    WakeEvent<private>:event() = event(){}

    OnEndSimulation<override>():void =
        set Schedules = array{}
        (super:)OnEndSimulation()

    OnSimulate<override>()<suspends>:void =
        # First evaluation after every component in the tree has finished OnBeginSimulation (the schedules have registered)
        TickEvents.PrePhysics.Await()
        loop:
            T := GetNowEpochSeconds()
            Second := FloorToInt(T)
            if (Second <> LastTickedSecond):
                set LastTickedSecond = Second
                Tick(T)
            # Wake a little after the next whole-second boundary (Sleep is frame-based, so it may wake late but is assumed never to wake early. If it wakes early, the check above skips evaluation and waits again)
            WaitSeconds := Max((Second + 1) * 1.0 - T + WakeMarginSeconds, 0.0)
            race:
                Sleep(WaitSeconds)
                WakeEvent.Await()

    # The current time (epoch seconds + debug offset). The same value within one transaction. Keeps the previous value if the OS clock goes backward
    GetNowEpochSeconds<public>()<transacts>:float =
        Raw := GetSecondsSinceEpoch()
        Clamped := if (Raw > LastRawSeconds) then Raw else LastRawSeconds
        set LastRawSeconds = Clamped
        Clamped + DebugOffsetSeconds

    # This clock's time zone offset (seconds)
    GetTimeZoneOffsetSeconds<public>()<computes>:int =
        TimeZoneOffsetSeconds

    # The "day number" of EpochSeconds in this clock's time zone (changes at local midnight)
    GetDayIndex<public>(EpochSeconds:float)<transacts>:int =
        ScheduleSystem.GetDayIndex(EpochSeconds, TimeZoneOffsetSeconds)

    # Seconds since local midnight of EpochSeconds in this clock's time zone
    GetSecondsOfDay<public>(EpochSeconds:float)<transacts>:float =
        ScheduleSystem.GetSecondsOfDay(EpochSeconds, TimeZoneOffsetSeconds)

    # Shift the time by OffsetSeconds seconds (for debugging; negative goes to the past). Re-evaluates all schedules immediately (the intermediate changes are not replayed; only the current state is delivered, as a "jump")
    SetDebugOffsetSeconds<public>(OffsetSeconds:float):void =
        set DebugOffsetSeconds = OffsetSeconds
        set LastTickedSecond = -1
        WakeEvent.Signal()

    # Shift so that the current time becomes EpochSeconds (for debugging). Re-evaluates immediately, like SetDebugOffsetSeconds
    JumpTo<public>(EpochSeconds:float):void =
        SetDebugOffsetSeconds(EpochSeconds - (GetNowEpochSeconds() - DebugOffsetSeconds))

    # The registered schedules (in registration order)
    GetSchedules<public>()<transacts>:[]schedule_component =
        Schedules

    # Register a schedule (called by schedule_component in OnBeginSimulation). Evaluated from the next whole second. Does nothing when already registered
    Register<internal>(Schedule:schedule_component):void =
        for (Existing : Schedules, Existing = Schedule):
            return
        set Schedules += array{Schedule}

    # Unregister (called by schedule_component in OnEndSimulation)
    Unregister<internal>(Schedule:schedule_component):void =
        set Schedules = for (Existing : Schedules, Existing <> Schedule):
            Existing

    # Once per second. Delivers every schedule's state change, then every schedule's SecondEvent, and finally its own SecondEvent
    Tick<private>(T:float):void =
        Current := Schedules
        for (Schedule : Current):
            Schedule.Advance(T)
        for (Schedule : Current):
            Schedule.NotifySecond()
        SecondEventInternal.Signal(T)
