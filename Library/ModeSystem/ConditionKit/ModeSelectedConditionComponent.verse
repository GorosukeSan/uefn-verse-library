using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { ModeSystem }
using { SceneGraphSystem }
using { ModeSystem.TooltipKit }

# Role: satisfied when the mode on the Mode entity is selected
# Placement: attach to an entity in the editor
# Parent: directly under the entity of a game_transition_component or condition_all / condition_any
# Requirements: one mode_select_component in the scope (or the world) (looked up at start and when a notification arrives, and remembered once found)
mode_selected_condition_component<public> := class<final_super>(condition_component):

    # Satisfied when this mode (an entity with game_mode_component) is selected. Never satisfied when empty. Default empty
    @editable:
        ToolTip := ModeSelectedModeToolTip
        Categories := array{ModeCategory}
    Mode<public>:?entity = false

    var<private> Selector:?mode_select_component = false

    IsSatisfied<override>()<decides><transacts>:void =
        # No lookup inside the check (only reads what is remembered)
        Expected := Mode?
        Selected := Selector?.FindSelected[]
        Selected.Entity = Expected

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set Selector = Entity.ResolveScopedComponent(Selector, mode_select_component)

    OnReceive<override>(SceneEvent:scene_event):logic =
        set Selector = Entity.ResolveScopedComponent(Selector, mode_select_component)
        if (Changed := mode_changed_event[SceneEvent], Changed.Selector = Selector?):
            NotifyChanged()
        false

    OnEndSimulation<override>():void =
        set Selector = false
        (super:)OnEndSimulation()
