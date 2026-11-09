using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { SceneGraphSystem }
using { InteractSystem.TooltipKit }

# Notification that a press completed
# Direction: from the interact_trigger_component's entity to the root (SendUp)
# Sender: interact_trigger_component. Receivers: ancestor interacted_condition_components etc. Not consumed
interacted_event<public> := class(scene_event):
    # The trigger that sent it
    Trigger<public>:interact_trigger_component
    # The presser
    Agent<public>:agent

# Role: each time a press completes (the interactable_component's SucceededEvent), notifies the presser upward and sends the activation signal to the Targets entities (with Toggle, alternates the activation and deactivation signals on each press: switch, lever)
# Placement: attach to an entity in the editor
# Parent: a descendant of whatever wants to know about the press (for a game flow condition, under the interacted_condition_component entity). Anywhere works
# Same entity: interactable_component (basic_interactable_component, etc.). interact_gate_component to make it pressable only while active
# Notifies: sends interacted_event upward from this entity. Run-time code can Await / Subscribe InteractedEvent (press completed), StartedEvent (press started; the start of a hold; fires at the start as of v43.00) and CanceledEvent (hold canceled mid-way)
# From outside: IsOn (with Toggle, whether it is on now), SetOn (sets on / off directly and sends the signal)
interact_trigger_component<public> := class<final_super>(component):

    # Entities that receive the activation signal each time a press completes (the entity and its descendants receive it). When empty, only notifies upward
    @editable:
        ToolTip := InteractTargetsToolTip
        Categories := array{InteractCategory, InteractTargetsCategory}
    Targets<public>:[]entity = array{}

    # true alternates the activation and deactivation signals to Targets on each press (switch, lever). false sends only the activation signal (default false)
    @editable:
        ToolTip := InteractToggleToolTip
        Categories := array{InteractCategory}
    Toggle<public>:logic = false

    InteractedEventInternal<private><final>:event(agent) = event(agent){}

    # Fires with the presser each time a press completes (Await / Subscribe; cannot be signaled from outside)
    InteractedEvent<public><final>:listenable(agent) = MakeProxyListenable(InteractedEventInternal)

    StartedEventInternal<private><final>:event(agent) = event(agent){}
    CanceledEventInternal<private><final>:event(agent) = event(agent){}

    # Fires with the presser each time a press starts (for a hold, when the hold starts; with a hold time of 0, at the same time as InteractedEvent)
    StartedEvent<public><final>:listenable(agent) = MakeProxyListenable(StartedEventInternal)

    # Fires with the player each time a hold is canceled mid-way
    CanceledEvent<public><final>:listenable(agent) = MakeProxyListenable(CanceledEventInternal)

    var Subscription<private>:?cancelable = false
    var<private> On:logic = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Interactable := Entity.GetComponent[interactable_component]):
            Group := cancelable_group:
                Cancelables := array:
                    Interactable.SucceededEvent.Subscribe(OnSucceeded)
                    Interactable.StartedEvent.Subscribe(OnStarted)
                    Interactable.CanceledEvent.Subscribe(OnCanceled)
            set Subscription = option{Group}

    OnEndSimulation<override>():void =
        Subscription.CancelIfSet()
        set Subscription = false
        (super:)OnEndSimulation()

    # With Toggle, succeeds if on now (the last signal sent was activation). Fails without Toggle
    IsOn<public>()<decides><transacts>:void =
        Toggle?
        On?

    # Sets on / off to Value and sends the activation signal (on) or the deactivation signal (off) to Targets. Does nothing if unchanged
    SetOn<public>(Value:logic):void =
        if (On <> Value):
            set On = Value
            for (Target : Targets):
                if (Value?):
                    Target.SendActivated()
                else:
                    Target.SendDeactivated()

    OnSucceeded<private>(Agent:agent):void =
        Entity.SendUp(interacted_event{Trigger := Self, Agent := Agent})
        if (Toggle?):
            SetOn(if (On?) then false else true)
        else:
            for (Target : Targets):
                Target.SendActivatedBy(Agent)
        InteractedEventInternal.Signal(Agent)

    OnStarted<private>(Agent:agent):void =
        StartedEventInternal.Signal(Agent)

    OnCanceled<private>(Agent:agent):void =
        CanceledEventInternal.Signal(Agent)
