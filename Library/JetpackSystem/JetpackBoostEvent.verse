using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { PlayerSystem }

# Tag attached to an agent charging or flying with the jetpack (while its velocity is being controlled). Attached and removed by jetpack_ability_component.
# Derived from controlled_movement_tag, so gravity and hover do not overwrite this agent's velocity
jetpack_boosting_tag<public> := class(controlled_movement_tag):

# Direction: upward from the entity of jetpack_ability_component (SendUp). The same event is also sent down under the agent's slot as a player_event (received by that agent's views such as a HUD)
# Receivers: a HUD showing the boost gauge, etc. Not consumed
# Sent: only when the gauge value changes (usable = 1, 0 to 1 while charging, 0 after launching until landing, 0 on revoke)
jetpack_boost_changed_event<public> := class(scene_event):
    # The jetpack ability that sent it
    Ability<public>:jetpack_ability_component
    # The agent whose gauge changed
    Agent<public>:agent
    # The gauge (0.0-1.0)
    Ratio<public>:float
