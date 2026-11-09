using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { ConditionSystem }
using { SceneGraphSystem }
using { InteractSystem.TooltipKit }

# Role: satisfied once pressed (re-activating makes it unsatisfied again)
# Placement: attach to an entity in the editor
# Parent: directly under the entity of a game_transition_component or condition_all / condition_any
# Children: an entity with interact_trigger_component (anywhere among the descendants). When it cannot be a child, pick it with Trigger
# From outside: Reset puts it back to unsatisfied (the activation signal activated_event does too)
interacted_condition_component<public> := class<final_super>(condition_component):

    # The button to watch (an entity with interact_trigger_component). Descendant buttons count without being picked (default none)
    @editable:
        ToolTip := InteractedTriggerToolTip
        Categories := array{InteractCategory, InteractedTriggerCategory}
    Trigger<public>:?entity = false

    var Interacted<private>:logic = false
    var Subscription<private>:?cancelable = false

    IsSatisfied<override>()<decides><transacts>:void =
        Interacted?

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if:
            TriggerEntity := Trigger?
            TriggerComponent := TriggerEntity.GetComponent[interact_trigger_component]
        then:
            set Subscription = option{TriggerComponent.InteractedEvent.Subscribe(OnInteracted)}

    OnEndSimulation<override>():void =
        Subscription.CancelIfSet()
        set Subscription = false
        (super:)OnEndSimulation()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            SetInteracted(false)
        else if (interacted_event[SceneEvent]):
            SetInteracted(true)
        false

    # Puts it back to unsatisfied (not pressed yet)
    Reset<public>():void =
        SetInteracted(false)

    OnInteracted<private>(Agent:agent):void =
        SetInteracted(true)

    SetInteracted<private>(Value:logic):void =
        if (Interacted <> Value):
            set Interacted = Value
            NotifyChanged()
