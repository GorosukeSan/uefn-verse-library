using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { SceneGraphSystem }

# Represents player state with tags.
# A System that holds a state attaches a tag to the player (agent; in v43 an agent is also an entity, so it can carry tags) for the duration and removes it when done.
# The tag goes on the agent, not the character's entity, so it survives before spawn, while downed and after respawn.
# Other Systems can check the state with Agent.HasPlayerTag[tag type] without knowing that System (e.g. hover does not lift someone whose "movement is controlled").
# Attach through player_tag_holder (it removes only what it attached and leaves tags of the same type attached by other parts).
# ⚠ Unverified: whether adding / removing tags on an agent and ContainsTag work in UEFN 43.00 (in the digest, agent derives from entity and entity is has_tags). Checked by PlayerSystemTest in _Test

# Base class of tags that represent player state. Create a subclass per state.
# A tag attached via a subclass is also found by the base type (Agent.HasPlayerTag[player_state_tag] means "in some state")
player_state_tag<public> := class<abstract>(tag):

# Tag attached while an ability or similar directly controls the player's movement (velocity / position).
# Other forces (gravity, hover, etc.) do not overwrite the velocity of someone carrying this.
# Example: while swinging (SwingSystem's swinging_tag is a subclass). Attach a subclass of this when you write your own movement-controlling ability
controlled_movement_tag<public> := class(player_state_tag):

# Succeeds if Agent carries a tag of TagType (or a subclass)
(Agent:agent).HasPlayerTag<public>(TagType:castable_subtype(tag))<decides><reads>:void =
    Agent.ContainsTag[TagType]

# Remembers, per player, the tag one part attached, so it can later remove only what it attached.
# If another part attached a tag of the same type to the same player, that one is left alone.
# Usage: hold Tags:player_tag_holder = player_tag_holder{}, call Tags.Add(Agent, hovering_tag{}) when entering the state,
#   Tags.Remove(Agent) when leaving, and Tags.RemoveAll() when stopping (OnEndSimulation, an ability's defer)
player_tag_holder<public> := class:
    var<private> Keys:[agent]tag_key = map{}

    # Attach Tag to Agent. Does nothing if this holder already attached a tag. Pass a freshly created Tag each call (hovering_tag{} etc.)
    Add<public>(Agent:agent, Tag:tag)<transacts>:void =
        if (not Keys[Agent]):
            if (set Keys[Agent] = Agent.AddTag(Tag)) {}

    # Remove the tag this holder attached to Agent (does nothing if none)
    Remove<public>(Agent:agent)<transacts>:void =
        if (Key := Keys[Agent]):
            if (Agent.RemoveTag[Key]) {}
            set Keys = Keys.RemoveKey(Agent)

    # Add if On, otherwise Remove
    Set<public>(Agent:agent, On:logic, Tag:tag)<transacts>:void =
        if (On?):
            Add(Agent, Tag)
        else:
            Remove(Agent)

    # Succeeds if this holder has attached a tag to Agent
    Has<public>(Agent:agent)<decides><reads>:void =
        Keys[Agent]

    # Remove every tag this holder attached
    RemoveAll<public>()<transacts>:void =
        for (Agent -> Key : Keys):
            if (Agent.RemoveTag[Key]) {}
        set Keys = map{}
