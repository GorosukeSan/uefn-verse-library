using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { SceneGraphSystem }
using { PlayerSystem.TooltipKit }

# Role: satisfied when the number of participants is MinPlayerCount or more
# Placement: attach to an entity in the editor
# Parent: directly under the entity of a game_transition_component or condition_all / condition_any
# Requirements: one player_manager_component in the scope (or world) (looked up at start and when a notification arrives, then remembered)
player_count_condition_component<public> := class<final_super>(condition_component):

    # Satisfied when at least this many players participate (1-100, default 2)
    @editable_number(int):
        ToolTip := MinPlayerCountToolTip
        Categories := array{PlayerCategory}
        MinValue := option{1}
        MaxValue := option{100}
    MinPlayerCount<public>:int = 2

    var<private> Manager:?player_manager_component = false

    IsSatisfied<override>()<decides><transacts>:void =
        # Do not look up inside the check (only read what is remembered)
        Manager?.GetPlayerCount() >= MinPlayerCount

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)

    OnReceive<override>(SceneEvent:scene_event):logic =
        set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)
        if (Found := Manager?):
            if (Added := player_added_event[SceneEvent], Added.Manager = Found):
                NotifyChanged()
            else if (Removed := player_removed_event[SceneEvent], Removed.Manager = Found):
                NotifyChanged()
        false

    OnEndSimulation<override>():void =
        set Manager = false
        (super:)OnEndSimulation()
