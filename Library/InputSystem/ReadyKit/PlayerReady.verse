using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { PlayerSystem }
using { SceneGraphSystem }

# Direction: the whole zone (SendScoped; the whole world when there is no zone)
# Sender: player_ready_component (its view). Receivers: all_players_ready_condition_component, etc. Not consumed
player_ready_changed_event<public> := class(scene_event):
    # The player_ready_component that sent it
    PlayerReady<public>:player_ready_component
    # The agent who toggled
    Agent<public>:agent
    # true when ready after the toggle
    Ready<public>:logic

# Tag attached to a "ready" agent. Attached and removed by player_ready_component (its view) (other Systems check with Agent.HasPlayerTag[player_ready_tag])
player_ready_tag<public> := class(player_state_tag):

# Role: holds one player's "ready" state (the toggle on press is called by player_ready_component)
# Placement: created at runtime by player_ready_component (not placed in the editor)
# Tags: while ready, attaches player_ready_tag to the agent (removed when the view disappears = accepting stops, or the player leaves)
# When: when the view stops (OnEndSimulation; deactivation, HideFor, or leaving, which removes the whole slot) it goes back to "not ready" (no notification is sent)
player_ready_view_component<public> := class<final_super>(component):

    # The player_ready_component that created this view
    Source<public>:player_ready_component
    # The player this view handles
    Player<public>:player

    var<private> Ready:logic = false
    var<private> ReadyTags:player_tag_holder = player_tag_holder{}

    # Succeeds while "ready"
    IsReady<public>()<decides><reads>:void =
        Ready?

    # Sets ready (cancels when Value is false). Notifies only when it changed
    SetReady<public>(Value:logic):void =
        if (Ready = Value):
            return
        set Ready = Value
        ReadyTags.Set(Player, Value, player_ready_tag{})
        Source.NotifyReadyChanged(Player, Value)

    OnEndSimulation<override>():void =
        # When the view stops (leaving, etc.), reset the ready state too (so a stopped view does not stay in the count)
        set Ready = false
        ReadyTags.RemoveAll()
        (super:)OnEndSimulation()
