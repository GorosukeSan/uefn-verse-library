using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SceneGraphSystem }

# Role: satisfied when every child condition is satisfied (satisfied if there are no children)
# Placement: attach to an entity in the editor
# Parent: directly under the entity of a game_transition_component or condition_all / condition_any
# Children: entities carrying a condition (a condition_component subclass), one each, directly below (order does not matter)
# Notifies: when a condition_changed_event arrives from a descendant condition, consumes it, resends its own condition_changed_event upward and delivers to ChangedEvent as well
condition_all_component<public> := class<final_super>(condition_component):

    IsSatisfied<override>()<decides><transacts>:void =
        Entity.AreChildConditionsSatisfied[]

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Changed := condition_changed_event[SceneEvent], Changed.Condition <> Self):
            NotifyChanged()
            true
        else:
            false
