using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Game }
using { ActivationSystem.TooltipKit }

# Signal that a round started (a subclass of activated_event, so parts waiting for activation start on it)
# Direction: from the Targets of activate_on_round_component (its entity when empty) downward (SendDown)
# Sender: activate_on_round_component. Receivers: parts waiting for activation (those that need the round number take this type). Not consumed
round_started_event<public> := class(activated_event):
    # Number of the round that started (from 1)
    RoundNumber<public>:int

# Signal that a round ended (a subclass of deactivated_event, so parts waiting for activation stop and clean up on it)
# Direction, sender and receivers are the same as round_started_event
round_ended_event<public> := class(deactivated_event):
    # Number of the round that ended (from 1)
    RoundNumber<public>:int

# Role: a helper (run-time class) that receives the start and end of Fortnite rounds (fort_round_manager). A component holds one in a field and calls Start in OnBeginSimulation and Stop in OnEndSimulation (no inheritance)
#   OnStarted runs each time a round starts and is canceled when the round ends (you can write work that lasts only for the round as is). If a round is already in progress, it runs right away inside Start
#   OnEnded is called each time a round ends
# Requirements / notes: without a fort_round_manager (not available from the simulation entity), Start returns false and calls nothing
round_watcher<public> := class<unique>:

    var<private> Manager:?fort_round_manager = false
    var<private> Subscriptions:[]cancelable = array{}
    var<private> InRound:logic = false
    # Number of the last round that ended (to decide whether this round has ended without relying on subscription order)
    var<private> EndedRound:int = 0

    # Subscribes to the round manager of Owner's simulation. false if not available
    Start<public>(Owner:entity, OnStarted:type{_()<suspends>:void}, OnEnded:type{_():void}):logic =
        Stop()
        if (Found := Owner.GetFortRoundManager[]):
            set Manager = option{Found}
            # Passing a function argument straight to Subscribe gives V3502 in UEFN, so wrap it in a method
            Relay := round_callback_relay{Watcher := Self, Started := OnStarted, Ended := OnEnded}
            set Subscriptions = array:
                Found.SubscribeRoundStarted(Relay.InvokeStarted)
                Found.SubscribeRoundEnded(Relay.InvokeEnded)
            true
        else:
            false

    # Stops subscribing
    Stop<public>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        set Manager = false
        set InRound = false
        set EndedRound = 0

    # Succeeds during a round (from its start to its end).
    #   Also decides from the round manager's RoundNumber (which increases before the start callback), so that it succeeds even when another part's callback for the same round start is called first
    IsInRound<public>()<decides><transacts>:void =
        if (InRound?):
        else:
            Found := Manager?
            Found.RoundNumber > 0
            Found.RoundNumber > EndedRound

    # Number of the current (last started) round. 0 before the first round and back to 0 when the game ends. 0 without a round manager
    GetRoundNumber<public>()<transacts>:int =
        if (Found := Manager?) then Found.RoundNumber else 0

    SetInRound<internal>(Value:logic):void =
        set InRound = Value
        if (not Value?, Found := Manager?):
            set EndedRound = Found.RoundNumber

# Wrapper used by round_watcher to pass the given functions to a listenable
round_callback_relay<internal> := class<internal>:
    Watcher<internal>:round_watcher
    Started<internal>:type{_()<suspends>:void}
    Ended<internal>:type{_():void}

    InvokeStarted<internal>()<suspends>:void =
        Watcher.SetInRound(true)
        Started()

    InvokeEnded<internal>():void =
        Watcher.SetInRound(false)
        Ended()

# Role: when a Fortnite round starts, sends the activation signal (round_started_event) to Targets, and the deactivation signal (round_ended_event) when it ends. Runs signal-driven parts (countdowns, spawners, screens, menus, volumes, loadouts, etc.) only during the round and restarts them every round
#   FirstRound / LastRound limit which rounds send (0 means no limit). Use it to start on "the start of the game (round)" instead of the start of the simulation (turn off the parts' ActiveOnBegin / StartOnBegin)
# Placement: attach to an entity in the editor. When Targets is empty, sends to this entity and its descendants
# Notifies: round_started_event / round_ended_event (with RoundNumber), RoundStartedEvent / RoundEndedEvent (the round number)
# From outside: IsInRound / GetRoundNumber
# Requirements / notes: does nothing without a fort_round_manager (reported in the output log)
activate_on_round_component<public> := class<final_super>(component):

    # Entities to signal (the entity and its descendants receive it). When empty, sends to this entity and its descendants
    @editable:
        ToolTip := RoundTargetsToolTip
        Categories := array{ActivationCategory}
    Targets<public>:[]entity = array{}
    # Send from this round number (from 1; 0 means from the first). Default 0
    @editable_number(int):
        ToolTip := RoundFirstToolTip
        Categories := array{ActivationCategory}
        MinValue := option{0}
        MaxValue := option{100}
    FirstRound<public>:int = 0
    # Send up to this round number (0 means to the last). Default 0
    @editable_number(int):
        ToolTip := RoundLastToolTip
        Categories := array{ActivationCategory}
        MinValue := option{0}
        MaxValue := option{100}
    LastRound<public>:int = 0

    RoundStartedEventInternal<private><final>:event(int) = event(int){}
    RoundEndedEventInternal<private><final>:event(int) = event(int){}

    # Fires with the round number each time a signaled round starts (Await / Subscribe; cannot be signaled from outside)
    RoundStartedEvent<public><final>:listenable(int) = MakeProxyListenable(RoundStartedEventInternal)

    # Fires with the round number each time a signaled round ends
    RoundEndedEvent<public><final>:listenable(int) = MakeProxyListenable(RoundEndedEventInternal)

    Watcher<private>:round_watcher = round_watcher{}
    var<private> SentRound:int = 0

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Started := Watcher.Start(Entity, OnRoundStarted, OnRoundEnded)
        if (not Started?):
            Print("[activate_on_round_component] fort_round_manager not found (cannot send round signals)")

    OnEndSimulation<override>():void =
        Watcher.Stop()
        (super:)OnEndSimulation()

    # Succeeds during a round
    IsInRound<public>()<decides><transacts>:void =
        Watcher.IsInRound[]

    # Number of the current (last started) round (0 before the first)
    GetRoundNumber<public>()<transacts>:int =
        Watcher.GetRoundNumber()

    OnRoundStarted<private>()<suspends>:void =
        Number := Watcher.GetRoundNumber()
        if (IsTargetRound[Number]):
            set SentRound = Number
            for (Receiver : GetReceivers()):
                Receiver.SendDown(round_started_event{RoundNumber := Number})
            RoundStartedEventInternal.Signal(Number)

    OnRoundEnded<private>():void =
        # Stop only when a signaled round ends (nothing at the end of a round that was not signaled)
        if (SentRound > 0):
            Number := SentRound
            set SentRound = 0
            for (Receiver : GetReceivers()):
                Receiver.SendDown(round_ended_event{RoundNumber := Number})
            RoundEndedEventInternal.Signal(Number)

    IsTargetRound<private>(Number:int)<decides><transacts>:void =
        FirstRound <= 0 or Number >= FirstRound
        LastRound <= 0 or Number <= LastRound

    GetReceivers<private>()<transacts>:[]entity =
        if (Targets.Length > 0) then Targets else array{Entity}
