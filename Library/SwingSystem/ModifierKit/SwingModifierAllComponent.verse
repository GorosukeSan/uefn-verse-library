using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { SwingSystem }
using { SwingSystem.TooltipKit }

# Role: applies the modifier of the swing_modifier_component on the same entity to every player (late joiners too) (a restricted mode, a stage where everyone gets stronger, etc.)
# When: from the start of the simulation if ApplyOnBegin is true. Otherwise from the activate signal (activated_event) to the deactivate signal (deactivated_event)
# Placement: attach in the editor to the same entity as swing_modifier_component
# Parent: if you use the activate signal, somewhere it is delivered (for a game sequence, the node entity or a descendant)
swing_modifier_all_component<public> := class<final_super>(component):

    # true applies to everyone from the start. false (default) applies from the activate signal to the deactivate signal
    @editable:
        ToolTip := SwingModifierApplyOnBeginToolTip
        Categories := array{SwingCategory, SwingModifierCategory}
    ApplyOnBegin<public>:logic = false

    var<private> Active:logic = false

    # Succeeds while applying
    IsApplying<public>()<decides><transacts>:void =
        Active?

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (ApplyOnBegin?):
            Start()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Start()
        else if (deactivated_event[SceneEvent]):
            Stop()
        false

    OnEndSimulation<override>():void =
        Stop()
        (super:)OnEndSimulation()

    Start<private>():void =
        if (not Active?, Modifier := Entity.GetComponent[swing_modifier_component]):
            set Active = true
            Modifier.ApplyToAll()

    Stop<private>():void =
        if (Active?):
            set Active = false
            if (Modifier := Entity.GetComponent[swing_modifier_component]):
                Modifier.RemoveFromAll()
