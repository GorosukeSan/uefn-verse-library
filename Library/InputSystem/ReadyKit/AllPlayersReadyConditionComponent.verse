using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { PlayerSystem }
using { SceneGraphSystem }

# Role: satisfied when there is at least one participant and everyone is "ready"
# Placement: attach to an entity in the editor
# Parent: directly under the entity of game_transition_component or condition_all / condition_any
# Requirements: one player_manager_component and one player_ready_component in the zone (or the world) (looked up at start and when a notification arrives; remembered once found)
all_players_ready_condition_component<public> := class<final_super>(condition_component):

    var<private> Manager:?player_manager_component = false
    var<private> Ready:?player_ready_component = false

    IsSatisfied<override>()<decides><transacts>:void =
        # No lookup inside the check (only what is remembered is used)
        PlayerCount := Manager?.GetPlayerCount()
        PlayerCount > 0
        Ready?.GetReadyCount() = PlayerCount

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Resolve()

    OnReceive<override>(SceneEvent:scene_event):logic =
        Resolve()
        if (Changed := player_ready_changed_event[SceneEvent], Changed.PlayerReady = Ready?):
            NotifyChanged()
        else if (Added := player_added_event[SceneEvent], Added.Manager = Manager?):
            NotifyChanged()
        else if (Removed := player_removed_event[SceneEvent], Removed.Manager = Manager?):
            NotifyChanged()
        false

    OnEndSimulation<override>():void =
        set Manager = false
        set Ready = false
        (super:)OnEndSimulation()

    # Finds player_manager_component and player_ready_component in the zone and remembers them (no lookup when already remembered). Called in OnBeginSimulation and when a notification arrives
    Resolve<private>():void =
        set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)
        set Ready = Entity.ResolveScopedComponent(Ready, player_ready_component)
