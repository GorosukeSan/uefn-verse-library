using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SceneGraphSystem }

# Decides "whose is it" from the entity tree.
# An entity placed under a player's slot (the entity of a player_slot_component) belongs to that player (it has an owner).
# CharacterSystem characters, player_view_set views and so on are created under the slot, so the parts inside them affect only the owner (ability granting, widgets, attachments, item-giving parts etc. use this to narrow their target to the owner).

# The player (owner) of the slot of InEntity or one of its ancestors. Fails if not under a slot
(InEntity:entity).FindOwningPlayer<public>()<decides><transacts>:player =
    InEntity.FindOwningSlot[].Player

# The first player_slot_component found on InEntity or its ancestors. Fails if there is none
(InEntity:entity).FindOwningSlot<public>()<decides><transacts>:player_slot_component =
    InEntity.FindNearestAncestorComponent[player_slot_component]
