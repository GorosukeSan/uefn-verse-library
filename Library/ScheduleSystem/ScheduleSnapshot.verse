using { /Verse.org/SceneGraph }

# State of a schedule
schedule_state<public> := enum:
    # Waiting for the next start (for repeating schedules, also after the previous cycle ended)
    Before
    # During the period
    Active
    # Ended (one-shot only; repeating schedules never reach it)
    After

# A schedule's "value at time T". Everything is computed from T and nothing is stored (late joiners and server restarts get the same value)
# Created once per second and delivered through StateChangedEvent / SecondEvent / schedule_state_changed_event
schedule_snapshot<public> := struct:
    # The time used for computation (epoch seconds, including the debug offset)
    NowSeconds<public>:float = 0.0
    # State
    State<public>:schedule_state = schedule_state.Before
    # Cycle number. For Daily, the "local day number"; for FixedInterval, the count with the first cycle as 0; for OneShot, 0. In Before the upcoming cycle, in Active the current cycle, in After the last cycle
    CycleIndex<public>:int = 0
    # Start time of cycle CycleIndex (epoch seconds)
    CycleStartSeconds<public>:float = 0.0
    # Seconds since the current cycle started. 0 unless Active
    ElapsedSeconds<public>:float = 0.0
    # Seconds until the current cycle ends. 0 unless Active
    SecondsToEnd<public>:float = 0.0
    # Seconds until the next start. In Before, until cycle CycleIndex starts; in Active, until the next cycle starts (when repeating); 0 when there is none
    SecondsToStart<public>:float = 0.0
    # Whether SecondsToStart is meaningful (there is a next start). false in a one-shot's Active / After
    HasNextStart<public>:logic = false

# Succeeds when Snapshot is Active
(Snapshot:schedule_snapshot).IsActive<public>()<decides><computes>:void =
    Snapshot.State = schedule_state.Active

# Succeeds when the two snapshots have "the same state and the same cycle" (used to decide whether to raise StateChangedEvent)
(Snapshot:schedule_snapshot).IsSameStateAndCycle<public>(Other:schedule_snapshot)<decides><computes>:void =
    Snapshot.State = Other.State
    Snapshot.CycleIndex = Other.CycleIndex

# Which "remaining" value to use for display
schedule_remaining_kind<public> := enum:
    # Remaining until the next start (during Active, until the next cycle; 0 when there is none)
    UntilStart
    # During Active, remaining until the current cycle ends; otherwise, until the next start (a board that "counts down to the start, then counts down to the end once started")
    UntilEnd

# Remaining seconds chosen by Kind (fraction; 0.0 when there is none)
(Snapshot:schedule_snapshot).GetRemainingSeconds<public>(Kind:schedule_remaining_kind)<computes>:float =
    case (Kind):
        schedule_remaining_kind.UntilStart =>
            if (Snapshot.HasNextStart?) then Snapshot.SecondsToStart else 0.0
        schedule_remaining_kind.UntilEnd =>
            if (Snapshot.State = schedule_state.Active):
                Snapshot.SecondsToEnd
            else if (Snapshot.HasNextStart?):
                Snapshot.SecondsToStart
            else:
                0.0

# Notification that a schedule's state or cycle changed (arrives once on the first evaluation too; Previous is false)
# Direction: down from the schedule_component entity (SendDown)
# Sender: schedule_component. Receivers: that entity and its descendants (schedule_active_condition, your components). Not consumed
# Requirements: on entering / leaving Active, activated_event / deactivated_event are also sent down right after this notification
schedule_state_changed_event<public> := class(scene_event):
    # The schedule that sent it
    Schedule<public>:schedule_component
    # The previous value (false on the first evaluation)
    Previous<public>:?schedule_snapshot
    # The current value
    Current<public>:schedule_snapshot
