using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { ConditionSystem.TooltipKit }

# Default of event_received_condition_component.EventType. A scene_event nobody ever sends, so the condition is not satisfied until an EventType is chosen
no_scene_event<public> := class(scene_event):

# Role: once activated (after receiving the activation signal activated_event; from the start if no signal comes), becomes satisfied when a scene_event of EventType (or a subclass) reaches this entity. Returns to unsatisfied on the activation signal or Reset
#   Use it to advance on a game-side notification ("when a card is played", "when an enemy is defeated") without writing a condition subclass
# Placement: attach to an entity in the editor and choose the type in EventType. From code, create it with event_received_condition_component{Entity := E, EventType := my_event}
# Parent: directly under the entity of a game_transition_component or condition_all / condition_any
# When: only looks at scene_events that reach this entity (SendDown from an ancestor, SendScoped to the whole scope, SendGlobal to the whole world, SendUp from a descendant). Events SendUp'd on another branch do not reach it
# Notifies: sends condition_changed_event upward when it becomes satisfied and when it returns (NotifyChanged). Does not consume the received scene_event
# From outside: Reset (return to unsatisfied), FindReceivedEvent (the scene_event received when it became satisfied; read its Agent etc.)
# ⚠ Unverified: whether an @editable of subtype(scene_event) lets you pick a type in the UEFN editor (scene_event is an interface; subtype(component) is confirmed to work), and whether narrowing by a type value (EventType[SceneEvent]) works in UEFN (it works in the standalone type check and in the new VM)
event_received_condition_component<public> := class<final_super>(condition_component):

    # Type of the scene_event to wait for (subclasses match too). Never satisfied while left at the default no_scene_event
    @editable:
        ToolTip := EventTypeToolTip
        Categories := array{EventConditionCategory}
    EventType<public>:subtype(scene_event) = no_scene_event

    var<private> Received:?scene_event = false

    IsSatisfied<override>()<decides><transacts>:void =
        Received?

    OnReceive<override>(SceneEvent:scene_event):logic =
        # Reset on the activation signal before checking the type (if EventType is activated_event, activation satisfies it directly)
        if (activated_event[SceneEvent]):
            Reset()
        if (EventType[SceneEvent], not Received?):
            set Received = option{SceneEvent}
            NotifyChanged()
        false

    OnEndSimulation<override>():void =
        set Received = false
        (super:)OnEndSimulation()

    # Return to the unsatisfied state (nothing received yet). Does nothing if not satisfied
    Reset<public>():void =
        if (Received?):
            set Received = false
            NotifyChanged()

    # The scene_event received when it became satisfied (the first matching one since activation). Fails if nothing has been received yet
    FindReceivedEvent<public>()<decides><transacts>:scene_event =
        Received?
