using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }

# Notification that an input action was pressed
# Direction: the whole zone (SendScoped; the whole world when there is no zone)
# Sender: player_input_component. Receivers: components that watch for presses. Not consumed (to watch only the presses of one component, Subscribe to TriggeredEvent or filter by Input)
player_input_triggered_event<public> := class(scene_event):
    # The player_input_component that sent it
    Input<public>:player_input_component
    # The agent who pressed
    Agent<public>:agent
    # The action pressed (the InputAction of the sending component)
    Action<public>:input_action(logic)
