using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { SceneGraphSystem }
using { SwingSystem }

# Role: while the condition (a condition_component subclass on a direct child) is satisfied, applies the modifier of the swing_modifier_component on the same entity to every player (late joiners too). Removes it when the condition stops being satisfied
# Placement: attach in the editor to the same entity as swing_modifier_component
# Children: one direct child entity carrying a condition_component subclass (combine several conditions with condition_all / condition_any)
swing_modifier_condition_component<public> := class<final_super>(component):

    var<private> Active:logic = false
    var<private> Subscription:?cancelable = false

    # Succeeds while applying (while the condition is satisfied)
    IsApplying<public>()<decides><transacts>:void =
        Active?

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Condition := Entity.FindChildComponent[condition_component]):
            set Subscription = option{Condition.ChangedEvent.Subscribe(OnConditionChanged)}
            OnConditionChanged(if (Condition.IsSatisfied[]) then true else false)

    OnEndSimulation<override>():void =
        Subscription.CancelIfSet()
        set Subscription = false
        OnConditionChanged(false)
        (super:)OnEndSimulation()

    OnConditionChanged<private>(Satisfied:logic):void =
        if (Satisfied?):
            if (not Active?, Modifier := Entity.GetComponent[swing_modifier_component]):
                set Active = true
                Modifier.ApplyToAll()
        else if (Active?):
            set Active = false
            if (Modifier := Entity.GetComponent[swing_modifier_component]):
                Modifier.RemoveFromAll()
