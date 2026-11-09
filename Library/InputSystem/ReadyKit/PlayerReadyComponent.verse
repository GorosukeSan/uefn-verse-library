using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { PlayerSystem }
using { SceneGraphSystem }
using { InputSystem.InputKit }
using { InputSystem.TooltipKit }

# Role: while active, holds each player's "ready" state. Every time the InputAction of the player_input_component on the same entity is pressed, toggles the presser's ready state, sends player_ready_changed_event to the whole zone and fires ReadyChangedEvent. On deactivation everyone's ready state is cleared
# Placement: attach to an entity in the editor
# Parent: wherever the activation signal arrives (for the game flow, the node's entity or a descendant)
# Same entity: one player_input_component that notifies presses (the press action is its InputAction. With several, which one is used is unspecified, so put other inputs on another entity). Without one, pressing does not toggle (drive it only through SetReady from code)
# When: from the activation signal (activated_event) to the deactivation signal (deactivated_event). From the start of the simulation when ActiveOnBegin is true. Activate / Deactivate may also be called from code
# Notifies: sends player_ready_changed_event to the whole zone and fires ReadyChangedEvent
# Requirements: one player_manager_component in the zone (or the world)
# From outside: Activate / Deactivate / IsActive / IsReady / SetReady / ToggleReady / ResetAll / GetReadyCount / FindInput
player_ready_component<public> := class<final_super>(component):

    # When true, accepts from the start of the simulation. When false, from the activation signal (default false)
    @editable:
        ToolTip := ReadyActiveOnBeginToolTip
        Categories := array{ReadyCategory}
    ActiveOnBegin<public>:logic = false

    ReadyChangedEventInternal<private><final>:event(tuple(agent, logic)) = event(tuple(agent, logic)){}

    # Fires with (the agent, whether ready) every time someone's ready state toggles (Await / Subscribe; cannot be Signaled from outside)
    ReadyChangedEvent<public><final>:listenable(tuple(agent, logic)) = MakeProxyListenable(ReadyChangedEventInternal)

    Views<private>:player_view_set = player_view_set{}

    # The player_input_component whose presses are received (the first one found on the same entity)
    var<private> Input:?player_input_component = false
    var<private> InputSubscription:?cancelable = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        ConnectInput()
        if (ActiveOnBegin?):
            Activate()

    OnReceive<override>(SceneEvent:scene_event):logic =
        ConnectInput()
        Views.HandleActivation(SceneEvent, Entity, CreateView)
        false

    # Starts accepting (everyone starts "not ready"). Does nothing when already accepting
    Activate<public>():void =
        ConnectInput()
        Views.Activate(Entity, CreateView)

    # Stops accepting and clears everyone's ready state (no notification for those who were ready). Does nothing when not accepting
    Deactivate<public>():void =
        Views.Deactivate()

    # Succeeds while accepting
    IsActive<public>()<decides><transacts>:void =
        Views.IsActive[]

    OnEndSimulation<override>():void =
        InputSubscription.CancelIfSet()
        set InputSubscription = false
        Views.Deactivate()
        (super:)OnEndSimulation()

    # The player_input_component whose presses are received. Fails when there is none on the same entity (not found yet)
    FindInput<public>()<decides><transacts>:player_input_component =
        Input?

    # Succeeds when Agent is ready. Fails when not accepting or the agent has no view (has not joined)
    IsReady<public>(Agent:agent)<decides><transacts>:void =
        FindView[Agent].IsReady[]

    # Sets Agent's ready state to Value (notifies only when it changed). Does nothing when not accepting or the agent has no view
    SetReady<public>(Agent:agent, Value:logic):void =
        if (View := FindView[Agent]):
            View.SetReady(Value)

    # Toggles Agent's ready state (same as a press). Does nothing when not accepting or the agent has no view
    ToggleReady<public>(Agent:agent):void =
        if (View := FindView[Agent]):
            View.SetReady(if (View.IsReady[]) then false else true)

    # Cancels everyone's ready state
    ResetAll<public>():void =
        for (ViewEntity : Views.GetViews(), View := ViewEntity.GetComponent[player_ready_view_component]):
            View.SetReady(false)

    # The number of ready players (counts only the views of players present; players who left are not counted). 0 while inactive
    GetReadyCount<public>()<transacts>:int =
        Ready := for (ViewEntity : Views.GetViews(), View := ViewEntity.GetComponent[player_ready_view_component], View.IsReady[]):
            View
        Ready.Length

    # Finds the player_input_component on the same entity and subscribes to its TriggeredEvent (does nothing when already subscribed). Called at start, when a signal is received, and in Activate (so the order components are added at runtime does not matter)
    ConnectInput<private>():void =
        if (not InputSubscription?, Found := Entity.GetComponent[player_input_component]):
            set Input = option{Found}
            set InputSubscription = option{Found.TriggeredEvent.Subscribe(OnInputTriggered)}

    OnInputTriggered<private>(Agent:agent):void =
        ToggleReady(Agent)

    FindView<private>(Agent:agent)<decides><transacts>:player_ready_view_component =
        first:
            ViewEntity : Views.GetViews()
            View := ViewEntity.GetComponent[player_ready_view_component]
            View.Player = Agent
        do:
            View

    CreateView<private>(ViewEntity:entity, Slot:player_slot_component):component =
        player_ready_view_component{Entity := ViewEntity, Source := Self, Player := Slot.Player}

    NotifyReadyChanged<internal>(Player:player, Ready:logic):void =
        Entity.SendScoped(player_ready_changed_event{PlayerReady := Self, Agent := Player, Ready := Ready})
        ReadyChangedEventInternal.Signal((Player, Ready))
