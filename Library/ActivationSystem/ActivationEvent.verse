using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

# Activation signal. The receiving component starts running (starts a countdown, shows a screen, accepts input, etc.)
# Direction: from the sending entity downward (SendDown). In the game flow, when a node is entered (game_node_entered_event); also the Targets of interact_trigger_component, activate_on_begin_component, your code (SendActivated)
# Receivers: components on that entity and its descendants that wait for activation. Not consumed
activated_event<public> := class(scene_event):

# Deactivation signal. The receiving component stops and cleans up what it created while active
# Direction: from the sending entity downward (SendDown). In the game flow, when a node is left (game_node_exited_event); also your code (SendDeactivated)
# Receivers: components on that entity and its descendants that wait for activation. Not consumed
deactivated_event<public> := class(scene_event):

# Notification that an activated part has finished its job (used up, ran to the end). Receivers stop themselves
# Direction: from the finished part's entity upward (SendUp). Senders: CharacterSystem's CellKit (grant of a single-use action cell), etc.
# Receivers: ancestor components that "stop when their contents finish" (PickupSystem's pickup_effect_component ends the effect). Not consumed
activation_finished_event<public> := class(scene_event):

# Sends the activation signal (activated_event) to InEntity and its descendants. Use it to run components that wait for activation outside the game flow
(InEntity:entity).SendActivated<public>():void =
    InEntity.SendDown(activated_event{})

# Sends the deactivation signal (deactivated_event) to InEntity and its descendants
(InEntity:entity).SendDeactivated<public>():void =
    InEntity.SendDown(deactivated_event{})

# Activation signal that tells who triggered it (a subclass of activated_event, so parts waiting for activation run as usual)
# Direction and receivers are the same as activated_event. Senders: parts that know who pressed, entered or chose (interact_trigger_component, choice_menu_component, volume_activation_component, motion reactions, etc.)
# Receivers that need a player (FNDeviceSystem's device bridges, etc.) use Agent
activated_by_agent_event<public> := class(activated_event):
    # Who triggered it
    Agent<public>:agent

# Sends the activation signal triggered by Agent (activated_by_agent_event) to InEntity and its descendants
(InEntity:entity).SendActivatedBy<public>(Agent:agent):void =
    InEntity.SendDown(activated_by_agent_event{Agent := Agent})

# If SceneEvent is an activation signal that tells who triggered it, returns that agent. Otherwise fails
(SceneEvent:scene_event).FindActivatingAgent<public>()<decides><transacts>:agent =
    activated_by_agent_event[SceneEvent].Agent
