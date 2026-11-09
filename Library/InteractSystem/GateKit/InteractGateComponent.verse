using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { InteractSystem.TooltipKit }

# Role: makes the interactable_component on the same entity pressable only while open (not pressable while closed)
# Placement: attach to an entity in the editor
# Parent: where the activation signal arrives (in a game sequence, the node's entity or a descendant. It may also be an entity chosen in interact_trigger_component's Targets)
# Same entity: interactable_component (basic_interactable_component, etc.)
# When it opens: opens on the activation signal (activated_event) and closes on the deactivation signal (deactivated_event). Open from the start of the simulation when OpenOnBegin is true. Open / Close can also be called from code
# From outside: Open / Close / IsOpen
interact_gate_component<public> := class<final_super>(component):

    # true is pressable from the start of the simulation. false waits for the activation signal (default false)
    @editable:
        ToolTip := InteractGateOpenOnBeginToolTip
        Categories := array{InteractCategory}
    OpenOnBegin<public>:logic = false

    var<private> Opened:logic = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set Opened = OpenOnBegin
        Apply()

    OnSimulate<override>()<suspends>:void =
        # Sync once more after the interactable_component on the same entity has finished OnBeginSimulation
        TickEvents.PrePhysics.Await()
        Apply()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Open()
        else if (deactivated_event[SceneEvent]):
            Close()
        false

    # Makes it pressable
    Open<public>():void =
        set Opened = true
        Apply()

    # Makes it not pressable
    Close<public>():void =
        set Opened = false
        Apply()

    # Succeeds while open (pressable)
    IsOpen<public>()<decides><transacts>:void =
        Opened?

    Apply<private>():void =
        if (Interactable := Entity.GetComponent[interactable_component]):
            if (Opened?):
                Interactable.Enable()
            else:
                Interactable.Disable()
