using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem.TooltipKit }

# Role: enables on the activation signal (activated_event) and disables on the deactivation signal (deactivated_event) (reversed with Invert). Toggles every component with an enabled state (enableable: meshes, lights, interactables, particles, etc.)
#   Connects the activation signal to looks and controls, like "show the door when the node is entered" or "turn on the light when the button is pressed"
# Placement: attach to an entity in the editor, where the signal arrives (the entity of the part to activate, or a descendant)
# Same entity: the meshes etc. to toggle (when Targets is empty)
# When: with ApplyOnBegin, applies the "deactivated" state at start. After that, on every signal
# From outside: toggle directly with SetEnabled. Read the current state (whether the activation signal was received) with IsOn
# Requirements / notes: does not toggle this component itself. Does not look at the descendants of the Targets entities; toggles only the components attached to those entities
enable_on_activation_component<public> := class<final_super>(component):

    # The entities to enable / disable. When empty, toggles the components attached to this entity (those with an enabled state). Default empty
    @editable:
        ToolTip := EnableTargetsToolTip
        Categories := array{ActivationCategory}
    Targets<public>:[]entity = array{}

    # true reverses it (disable on activation, enable on deactivation). Default false
    @editable:
        ToolTip := EnableInvertToolTip
        Categories := array{ActivationCategory}
    Invert<public>:logic = false

    # true applies the "deactivated" state at the start of the simulation (e.g. keep hidden until activated). Default true
    @editable:
        ToolTip := EnableApplyOnBeginToolTip
        Categories := array{ActivationCategory}
    ApplyOnBegin<public>:logic = true

    var<private> On:logic = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (ApplyOnBegin?):
            Apply(false)

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Apply(true)
        else if (deactivated_event[SceneEvent]):
            Apply(false)
        false

    # Puts it in the activated state (Active = true) or the deactivated state (false). With Invert, enabled / disabled are reversed
    Apply<public>(Active:logic):void =
        set On = Active
        Enabled := if (Invert?) then (if (Active?) then false else true) else Active
        SetEnabled(Enabled)

    # Enables the components of Targets (this entity when empty) if Enabled, otherwise disables them (does not change this component's IsOn state)
    SetEnabled<public>(Enabled:logic):void =
        Receivers := if (Targets.Length > 0) then Targets else array{Entity}
        for (Receiver : Receivers, Component : Receiver.GetComponents(), Component <> Self, Target := enableable[Component]):
            if (Enabled?):
                Target.Enable()
            else:
                Target.Disable()

    # Succeeds if the last signal received was activation (Apply(true))
    IsOn<public>()<decides><transacts>:void =
        On?
