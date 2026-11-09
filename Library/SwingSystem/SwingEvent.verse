using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { PlayerSystem }

# Swing state. Idle = no rope attached, Anchored = waiting on the ground with only a rope attached, Swinging = swinging as a pendulum
swing_state<public> := enum:
    Idle
    Anchored
    Swinging

# Tag on an agent who is swinging (rope attached: waiting on the ground or swinging). This tag (and IsSwinging / GetSwingState below, which read it) is the only entry point for checking the swing state
# What is actually attached is a subclass: swing_anchored_tag (waiting on the ground) or swing_pendulum_tag (swinging). Both are found as swinging_tag. swing_ability_component adds and removes them (never attach directly)
# A controlled_movement_tag subclass, so gravity (GravitySystem) and hover (HoverSystem) do not overwrite this agent's velocity
swinging_tag<public> := class(controlled_movement_tag):

# Tag on an agent waiting on the ground with only a rope attached (swing_state.Anchored). swinging_tag subclass
swing_anchored_tag<public> := class(swinging_tag):

# Tag on an agent swinging as a pendulum (swing_state.Swinging). swinging_tag subclass
swing_pendulum_tag<public> := class(swinging_tag):

# Succeeds if Agent is swinging (rope attached: waiting on the ground or swinging). Looks at swinging_tag (does not search the ability or the scope registry)
(Agent:agent).IsSwinging<public>()<decides><reads>:void =
    Agent.HasPlayerTag[swinging_tag]

# Agent's swing state. Read from the tags (swing_pendulum_tag = Swinging, any other swinging_tag = Anchored, none = Idle)
(Agent:agent).GetSwingState<public>()<reads>:swing_state =
    if (Agent.HasPlayerTag[swing_pendulum_tag]):
        swing_state.Swinging
    else if (Agent.HasPlayerTag[swinging_tag]):
        swing_state.Anchored
    else:
        swing_state.Idle

# Makes the tag to attach for State (false for Idle)
MakeSwingStateTag<internal>(State:swing_state)<transacts>:?swinging_tag =
    case (State):
        swing_state.Anchored => option{swing_anchored_tag{}}
        swing_state.Swinging => option{swing_pendulum_tag{}}
        _ => false

# While idle, whether the object beyond the reticle can be grabbed changed (HUD reticle color etc.)
# Direction: swing_ability_component wraps it in a player_event and SendDowns it under the agent's slot, and SendUps it from the ability entity. Receivers: views such as the HUD. Not consumed
swing_target_changed_event<public> := class(scene_event):
    # Ability that sent it
    Ability<public>:swing_ability_component
    # Agent looking through the reticle
    Agent<public>:agent
    # true if grabbable
    CanGrab<public>:logic

# The swing state (swing_state) changed. The same content also reaches swing_ability_component.StateChangedEvent (to query the current state use Agent.GetSwingState())
# Direction: same as swing_target_changed_event (SendDown under the slot as player_event + SendUp from the ability entity). Not consumed
swing_state_changed_event<public> := class(scene_event):
    # Ability that sent it
    Ability<public>:swing_ability_component
    # Agent whose state changed
    Agent<public>:agent
    # New state
    State<public>:swing_state

# One rope attached (grabbed). Anchor is the entity of the grabbed point (with swing_anchor_component). Also reaches swing_ability_component.GrabbedEvent
# Direction: same as swing_target_changed_event. Not consumed
swing_grabbed_event<public> := class(scene_event):
    # Ability that sent it
    Ability<public>:swing_ability_component
    # Agent who attached the rope
    Agent<public>:agent
    # Entity of the grabbed point (with swing_anchor_component)
    Anchor<public>:entity

# All ropes removed and released (released by the player, the point broke, or Release forced it). Also reaches swing_ability_component.ReleasedEvent
# Direction: same as swing_target_changed_event. Not consumed
swing_released_event<public> := class(scene_event):
    # Ability that sent it
    Ability<public>:swing_ability_component
    # Agent who released
    Agent<public>:agent

# While on the ground, the reticle started / stopped (Holder := false) pointing at a player (Holder) whose rope is attached to you. For the "pull the rope" hint
# Direction: same as swing_target_changed_event. Not consumed
swing_reel_hint_event<public> := class(scene_event):
    # Ability that sent it
    Ability<public>:swing_ability_component
    # Agent who sees the hint
    Agent<public>:agent
    # Player who can be pulled. false when no longer in view
    Holder<public>:?agent

# Only one of several attached ropes detached (the point broke, got too far away, or the grabbed object disappeared). Also reaches swing_ability_component.RopeDetachedEvent
# Direction: same as swing_target_changed_event. Not consumed
swing_rope_detached_event<public> := class(scene_event):
    # Ability that sent it
    Ability<public>:swing_ability_component
    # Agent who attached the rope
    Agent<public>:agent
    # Entity of the grabbed point (with swing_anchor_component)
    Anchor<public>:entity

# Tells the grabbed object (the entity hit by the reticle sphere) that a rope was attached to it
# Direction: swing_runner SendDowns it to the hit entity. Receivers: that entity's swing_target_component (and looks on its descendants etc.). Not consumed
swing_attached_event<public> := class(scene_event):
    # Ability that sent it
    Ability<public>:swing_ability_component
    # Agent who attached the rope
    Agent<public>:agent
    # Entity of the grabbed point (with swing_anchor_component)
    Anchor<public>:entity

# Tells the grabbed object that a swing was launched from that point (the pendulum started). Arrives on every launch
# Direction: same as swing_attached_event. Not consumed
swing_pulled_event<public> := class(scene_event):
    # Ability that sent it
    Ability<public>:swing_ability_component
    # Agent who attached the rope
    Agent<public>:agent
    # Entity of the grabbed point (with swing_anchor_component)
    Anchor<public>:entity

# Tells the grabbed object that the rope at that point detached
# Direction: same as swing_attached_event. Not consumed
swing_detached_event<public> := class(scene_event):
    # Ability that sent it
    Ability<public>:swing_ability_component
    # Agent who attached the rope
    Agent<public>:agent
    # Entity of the grabbed point (with swing_anchor_component)
    Anchor<public>:entity
