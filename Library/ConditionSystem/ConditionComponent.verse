using { /Verse.org/SceneGraph }
using { SceneGraphSystem }

# Notification that whether a condition is satisfied may have changed
# Direction: from the condition's entity to the root (SendUp)
# Sender: condition_component subclasses (NotifyChanged). Receivers: ancestor game_node_component (re-checks its transitions), condition_all / condition_any (consume it and resend their own notification)
condition_changed_event<public> := class(scene_event):
    # The condition that sent it
    Condition<public>:condition_component

# Role: base class of conditions. Answers whether it is satisfied and notifies upward when that changes. Subclasses write only IsSatisfied and call NotifyChanged when the result may have changed
# Placement: never placed directly (place a subclass)
# Parent: directly under the entity of a game_transition_component or condition_all / condition_any (also under an ability_grant_condition_component entity, etc.)
# Notifies: sends condition_changed_event upward and delivers the current result to ChangedEvent
condition_component<public> := class<abstract><final_super>(component):

    # Implemented by the subclass. Succeeds if currently satisfied, fails otherwise. Called many times in <transacts>, so the implementation must not change state (no side effects)
    IsSatisfied<public>()<decides><transacts>:void

    ChangedEventInternal<private><final>:event(logic) = event(logic){}

    # Delivered with the current result (true if satisfied) when the satisfied state may have changed (Await / Subscribe to it; it cannot be Signaled from outside)
    ChangedEvent<public><final>:listenable(logic) = MakeProxyListenable(ChangedEventInternal)

    # Called by the subclass when the satisfied state may have changed. Sends condition_changed_event upward and delivers the current result to ChangedEvent
    NotifyChanged<protected>():void =
        Entity.SendUp(condition_changed_event{Condition := Self})
        ChangedEventInternal.Signal(if (IsSatisfied[]) then true else false)

# Succeeds if every condition (condition_component) on the direct children of InEntity is satisfied. Succeeds if there are no condition children. Does not look at grandchildren
(InEntity:entity).AreChildConditionsSatisfied<public>()<decides><transacts>:void =
    Unsatisfied := for:
        Condition : InEntity.GetChildComponents(condition_component)
        not Condition.IsSatisfied[]
    do:
        Condition
    Unsatisfied.Length = 0

# Succeeds if at least one condition (condition_component) on the direct children of InEntity is satisfied. Fails if there are no condition children. Does not look at grandchildren
(InEntity:entity).IsAnyChildConditionSatisfied<public>()<decides><transacts>:void =
    Satisfied := for:
        Condition : InEntity.GetChildComponents(condition_component)
        Condition.IsSatisfied[]
    do:
        Condition
    Satisfied.Length > 0
