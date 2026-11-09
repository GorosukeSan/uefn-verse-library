using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { CountdownSystem.TooltipKit }

# Notification that the remaining seconds (rounded up to a whole number) changed. Arrives at the start, every second and on AddSeconds (not when it reaches 0; countdown_finished_event arrives then)
# Direction: from the countdown_component's entity downward (SendDown). With AlsoSendUp on, also upward from the parent (SendUp)
# Sender: countdown_component. Receivers: descendant countdown_finished_condition_components, screens that show the remaining seconds, etc. (with AlsoSendUp, also ancestor nodes and HUDs). Not consumed
countdown_remaining_changed_event<public> := class(scene_event):
    # The countdown that sent it
    Countdown<public>:countdown_component
    # Remaining seconds (rounded up; 1 or more)
    RemainingWholeSeconds<public>:int

# Notification that the count ended (the remaining time reached 0). Not sent when stopped by Stop or the deactivation signal
# Direction: from the countdown_component's entity downward (SendDown). With AlsoSendUp on, also upward from the parent (SendUp)
# Sender: countdown_component. Receivers: descendant countdown_finished_condition_components etc. (with AlsoSendUp, also ancestors). Not consumed
countdown_finished_event<public> := class(scene_event):
    # The countdown that sent it
    Countdown<public>:countdown_component

# Role: counts DurationSeconds seconds and notifies the descendants each time the remaining seconds (whole number) change and when the count ends
# Placement: attach to an entity in the editor. Also usable outside the game flow
# When it starts: when StartOnActivated is true, restarts from the beginning on the activation signal (activated_event) (even while counting) and stops on the deactivation signal (deactivated_event) (in a game sequence, from entering the node to leaving it). When StartOnBegin is true, starts at the start of the simulation. Both may be false, with Start / Restart / Stop called from code
# Children: things that use the remaining seconds (countdown_finished_condition, etc.) go on this entity or its descendants
# Notifies: sends countdown_remaining_changed_event / countdown_finished_event downward (also upward with AlsoSendUp) and fires RemainingChangedEvent / FinishedEvent
# From outside: Start / Restart / Stop / Pause / Resume / AddSeconds. Query the current state with IsRunning / IsPaused / GetRemainingSeconds (fraction) / GetRemainingWholeSeconds (rounded up)
# Requirements / notes: the remaining time is "end time minus the current simulation time" (not counted by frames or accumulated waits, so it does not drift). It does not decrease while paused
countdown_component<public> := class<final_super>(component):

    # Seconds to count (0.1-3600 seconds, fractions allowed). The count ends at 0. Default 5.0 (for a different length this once, Restart(?Seconds := ...))
    @editable_number(float):
        ToolTip := CountdownDurationToolTip
        Categories := array{CountdownCategory}
        MinValue := option{0.1}
        MaxValue := option{3600.0}
    DurationSeconds<public>:float = 5.0

    # true restarts from the beginning on the activation signal (even while counting) and stops on the deactivation signal. false ignores the signals. Default true
    @editable:
        ToolTip := CountdownStartOnActivatedToolTip
        Categories := array{CountdownCategory}
    StartOnActivated<public>:logic = true

    # true starts counting at the start of the simulation (when the game flow is not used). Default false
    @editable:
        ToolTip := CountdownStartOnBeginToolTip
        Categories := array{CountdownCategory}
    StartOnBegin<public>:logic = false

    # true sends the notifications (countdown_remaining_changed_event / countdown_finished_event) upward from the parent to the ancestors (SendUp) in addition to the descendants (SendDown) (for a HUD outside the node or ancestor parts). Its own entity receives them only once, through SendDown. Default false
    @editable:
        ToolTip := CountdownAlsoSendUpToolTip
        Categories := array{CountdownCategory}
    AlsoSendUp<public>:logic = false

    var<private> Running:logic = false
    var<private> Paused:logic = false
    # Simulation time (seconds) at which the count ends, while counting (not paused)
    var<private> EndTimeSeconds:float = 0.0
    # Remaining time (seconds) while paused
    var<private> PausedRemainingSeconds:float = 0.0
    # Last notified remaining seconds (rounded up). -1 if nothing was notified yet
    var<private> LastNotifiedSeconds:int = -1

    RemainingChangedEventInternal<private><final>:event(int) = event(int){}

    # Fires with the value each time the remaining seconds (rounded up) change (at the start, every second, on AddSeconds) (Await / Subscribe; cannot be signaled from outside)
    RemainingChangedEvent<public><final>:listenable(int) = MakeProxyListenable(RemainingChangedEventInternal)

    FinishedEventInternal<private><final>:event() = event(){}

    # Fires when the count ends (not when stopped by Stop or the deactivation signal) (Await / Subscribe; cannot be signaled from outside)
    FinishedEvent<public><final>:listenable(tuple()) = MakeProxyListenable(FinishedEventInternal)

    # Tells the counting loop that the state changed (started, stopped, paused, resumed, adjusted)
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
                # Wait until the remaining seconds (rounded up) next change. Recompute if the state changes meanwhile
                Remaining := GetRemainingSeconds()
                Whole := CeilWholeSeconds(Remaining)
                WaitSeconds := Max(Remaining - (Whole - 1) * 1.0, 0.0)
                race:
                    Sleep(WaitSeconds)
                    WakeEvent.Await()
            else:
                WakeEvent.Await()

    # Starts counting from DurationSeconds if not counting. Does nothing while counting (including paused) (use Restart to restart)
    Start<public>():void =
        if (not Running?):
            Restart()

    # Restarts from the beginning (even while counting, paused or after the end). With Seconds, counts that many seconds this once (fractions allowed; 0 or less ends on the spot); otherwise DurationSeconds. Notifies the remaining seconds at the start
    Restart<public>(?Seconds:?float = false):void =
        Duration := if (Override := Seconds?) then Override else DurationSeconds
        set Running = true
        set Paused = false
        set EndTimeSeconds = GetSimulationElapsedTime() + Duration
        set LastNotifiedSeconds = -1
        Refresh()
        WakeEvent.Signal()

    # Stops counting (FinishedEvent does not fire). Does nothing if not counting
    Stop<public>():void =
        if (not Running?):
            return
        set Running = false
        set Paused = false
        WakeEvent.Signal()

    # Succeeds while counting (not paused). Fails before the start, after a stop, after the end and while paused
    IsRunning<public>()<decides><transacts>:void =
        Running?
        not Paused?

    # Succeeds while counting and paused
    IsPaused<public>()<decides><transacts>:void =
        Running?
        Paused?

    # Pauses while counting (the remaining time stays as it is). Does nothing if not counting or already paused
    Pause<public>():void =
        if (not Running? or Paused?):
            return
        set PausedRemainingSeconds = Max(EndTimeSeconds - GetSimulationElapsedTime(), 0.0)
        set Paused = true
        WakeEvent.Signal()

    # If paused, resumes from the remaining time at the pause. Does nothing if not paused
    Resume<public>():void =
        if (not Running? or not Paused?):
            return
        set EndTimeSeconds = GetSimulationElapsedTime() + PausedRemainingSeconds
        set Paused = false
        Refresh()
        WakeEvent.Signal()

    # While counting (including paused), adds DeltaSeconds seconds to the remaining time (subtracts when negative). At 0 or less the count ends on the spot (on resume if paused). Notifies if the remaining seconds changed. Does nothing if not counting
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

    # Remaining seconds (fraction). 0.0 if not counting or after the end. While paused, the remaining time at the pause
    GetRemainingSeconds<public>()<transacts>:float =
        if (not Running?):
            0.0
        else if (Paused?):
            PausedRemainingSeconds
        else:
            Max(EndTimeSeconds - GetSimulationElapsedTime(), 0.0)

    # Remaining seconds rounded up to a whole number (the value shown on screen; same as RemainingChangedEvent). 0 if not counting or after the end
    GetRemainingWholeSeconds<public>()<transacts>:int =
        CeilWholeSeconds(GetRemainingSeconds())

    # Ends the count if the remaining time is 0; otherwise notifies only when the remaining seconds (rounded up) changed
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

    # Sends to itself and the descendants. With AlsoSendUp, also from the parent to the ancestors (upward from the parent so that its own entity does not receive it twice)
    Send<private>(SceneEvent:scene_event):void =
        Entity.SendDown(SceneEvent)
        if (AlsoSendUp?, Parent := Entity.GetParent[]):
            Parent.SendUp(SceneEvent)

# Rounds seconds (fraction) up to a whole number. Values that are nearly whole (error under 0.001 seconds) become that whole number. 0 or less becomes 0
CeilWholeSeconds<internal>(TimeSeconds:float)<transacts>:int =
    if (TimeSeconds <= 0.001):
        0
    else if (Whole := Ceil[TimeSeconds - 0.001]):
        Whole
    else:
        0
