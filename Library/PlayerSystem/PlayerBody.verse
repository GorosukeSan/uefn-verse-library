using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Characters }

# Converts between a player and its body (the character's entity).
# entity -> agent follows Epic's standard form: read the Agent of the possessable_component attached to the entity (the agent currently controlling that entity).

# The entity of Agent's body (the fort_character's entity). Fails when there is no character (before spawn, after leaving, etc.)
(Agent:agent).FindPlayerEntity<public>()<decides><transacts>:entity =
    Agent.GetFortCharacter[].GetEntity[]

# The agent currently controlling Body (the Agent of the possessable_component attached to Body). Fails when there is no possessable_component or nobody is controlling it.
# For a player's character entity this is that player. It may also be a non-player such as an NPC
(Body:entity).FindPossessingAgent<public>()<decides><transacts>:agent =
    Body.GetComponent[possessable_component].Agent?

# The player currently controlling Body. Fails when a non-player (NPC etc.) is controlling it or nobody is
(Body:entity).FindPlayer<public>()<decides><transacts>:player =
    player[Body.FindPossessingAgent[]]

# The character (fort_character) of the agent currently controlling Body. Fails when nobody is controlling it or there is no character
(Body:entity).FindFortCharacter<public>()<decides><transacts>:fort_character =
    Body.FindPossessingAgent[].GetFortCharacter[]
