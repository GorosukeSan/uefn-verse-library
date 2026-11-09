using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { ConditionSystem }

# Role: satisfied when the countdown reaches 0 (re-activating or restarting makes it unsatisfied again)
# Placement: attach to an entity in the editor
# Parent: directly under the entity of a game_transition_component or condition_all / condition_any, and also a descendant of the countdown_component entity
countdown_finished_condition_component<public> := class<final_super>(condition_component):

    var Finished<private>:logic = false

    IsSatisfied<override>()<decides><transacts>:void =
        Finished?

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent] or countdown_remaining_changed_event[SceneEvent]):
            SetFinished(false)
        else if (countdown_finished_event[SceneEvent]):
            SetFinished(true)
        false

    SetFinished<private>(Value:logic):void =
        if (Finished <> Value):
            set Finished = Value
            NotifyChanged()
