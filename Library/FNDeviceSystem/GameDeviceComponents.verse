using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Devices }
using { ActivationSystem }
using { FNDeviceSystem.TooltipKit }

# Parts that do, from the activation signal, the game-progress things only devices can do (ending the game, class and team, score).
# Each part, on the activation signal, operates its device on the Recipients (the agent who caused the signal / the owner / everyone).

# Role: on the activation signal, Activates the end game device for the Recipients (ends with a win or a loss; the win / loss setting is on the device)
# Placement: attach to an entity in the editor (wherever the signal arrives: the goal volume, the last node of the game flow, ...)
device_end_game_component<public> := class<final_super>(component):

    # The end game device that ends the game
    @editable:
        ToolTip := DeviceEndGameToolTip
        Categories := array{FNDeviceCategory}
    EndGame<public>:?end_game_device = false
    # Whom to end the game for. Default Activator (the agent who caused the signal)
    @editable:
        ToolTip := DeviceRecipientsToolTip
        Categories := array{FNDeviceCategory}
    Recipients<public>:device_target_agents = device_target_agents.Activator

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent], Device := EndGame?):
            for (Agent : GetDeviceTargets(Entity, SceneEvent, Recipients)):
                Device.Activate(Agent)
        false

# How class and team are changed
device_class_change<public> := enum:
    # Class only
    Class
    # Team only
    Team
    # Team and class
    TeamAndClass

# Role: on the activation signal, uses the class and team selector device on the Recipients (changes class / team; which class / team is set on the device)
#   Placed inside a loadout (LoadoutSystem), the owner's class also changes when the loadout is attached (the loadout receives the activation signal the frame after it is attached. Recipients = Owner)
# Placement: attach to an entity in the editor
device_class_component<public> := class<final_super>(component):

    # The class and team selector device to use
    @editable:
        ToolTip := DeviceClassSelectorToolTip
        Categories := array{FNDeviceCategory}
    Selector<public>:?class_and_team_selector_device = false
    # What to change. Default Class
    @editable:
        ToolTip := DeviceClassChangeToolTip
        Categories := array{FNDeviceCategory}
    Change<public>:device_class_change = device_class_change.Class
    # Whom to change. Default Owner (the owner; the agent who caused the signal when there is none)
    @editable:
        ToolTip := DeviceRecipientsToolTip
        Categories := array{FNDeviceCategory}
    Recipients<public>:device_target_agents = device_target_agents.Owner

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent], Device := Selector?):
            for (Agent : GetDeviceTargets(Entity, SceneEvent, Recipients)):
                case (Change):
                    device_class_change.Class => Device.ChangeClass(Agent)
                    device_class_change.Team => Device.ChangeTeam(Agent)
                    device_class_change.TeamAndClass => Device.ChangeTeamAndClass(Agent)
        false

# How the score is changed
device_score_change<public> := enum:
    # Award points as configured on the score manager (Activate)
    Award
    # One step up (Increment)
    Increment
    # One step down (Decrement)
    Decrement

# Role: on the activation signal, uses the score manager device on the Recipients (award / increment / decrement; the points are set on the device)
# Placement: attach to an entity in the editor (coins, goals, reactions to eliminations, ...)
device_score_component<public> := class<final_super>(component):

    # The score manager device to use
    @editable:
        ToolTip := DeviceScoreManagerToolTip
        Categories := array{FNDeviceCategory}
    ScoreManager<public>:?score_manager_device = false
    # How to change it. Default Award
    @editable:
        ToolTip := DeviceScoreChangeToolTip
        Categories := array{FNDeviceCategory}
    Change<public>:device_score_change = device_score_change.Award
    # Whose score to change. Default Activator
    @editable:
        ToolTip := DeviceRecipientsToolTip
        Categories := array{FNDeviceCategory}
    Recipients<public>:device_target_agents = device_target_agents.Activator

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent], Device := ScoreManager?):
            for (Agent : GetDeviceTargets(Entity, SceneEvent, Recipients)):
                case (Change):
                    device_score_change.Award => Device.Activate(Agent)
                    device_score_change.Increment => Device.Increment(Agent)
                    device_score_change.Decrement => Device.Decrement(Agent)
        false
