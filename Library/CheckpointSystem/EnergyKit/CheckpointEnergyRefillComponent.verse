using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { AbilitySystem }
using { EnergySystem }
using { ItemSystem }
using { PlayerSystem }
using { CheckpointSystem }

# Role: every time someone steps onto any checkpoint (checkpoint_component) of the zone, fills energy (EnergySystem's energy_component) to full (Fill). What gets filled depends on where this is placed:
#   - If this entity or a descendant has an energy_component (FindEnergy; the same as the first result of FindEnergyFor used by abilities), only that one (e.g. energy placed on an ability's entity and shared by everyone granted it). If the same entity has abilities (ability_component subclasses), only when someone granted one of them steps on
#   - Otherwise, the energy of the agent who stepped on: the energy_component attached to the agent and every energy_component of their items (FindEnergy)
#   Placed under a player's slot (inside a loadout, etc.), fills only when the owner steps on
# Placement: attach, in the editor, to an entity inside the zone (the entity of game_scope_component) (anywhere in the world when there is no zone). The reached notification (checkpoint_reached_event) travels down from the zone root, so it does not arrive outside the zone or inside an inventory (an item's entity). To fill an item's energy, place it on another entity inside the zone (fills the items of the agent who stepped on)
# Same entity: the energy_component to fill (may be a child; may be absent). An ability (hover_ability_component, etc.) and its grant component. Do not place on an entity whose descendants include unrelated energy_components (e.g. the zone root), or one of those gets filled
# Notifies: when filled, RefilledEvent fires with (the agent who stepped on, the energy_component filled) (energy that was already full is not filled and does not fire)
# Requirements: the energy "consumers" (hover, jetpack, ...) know nothing about this part. It only fills on the checkpoint reached notification
checkpoint_energy_refill_component<public> := class<final_super>(component):

    RefilledEventInternal<private><final>:event(tuple(agent, energy_component)) = event(tuple(agent, energy_component)){}

    # Fires with (the agent who stepped onto the checkpoint, the energy_component filled) when energy is filled (Await / Subscribe; cannot be Signaled from outside)
    RefilledEvent<public><final>:listenable(tuple(agent, energy_component)) = MakeProxyListenable(RefilledEventInternal)

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Reached := checkpoint_reached_event[SceneEvent]):
            RefillFor(Reached.Agent)
        false

    # Fills as if Agent had stepped onto a checkpoint (to fill without going through a checkpoint). true when something was filled
    # Filling (Fill) and the notification (RefilledEvent) cannot roll back, so this cannot be <decides>
    TryRefillFor<public>(Agent:agent):logic =
        RefillFor(Agent)

    RefillFor<private>(Agent:agent):logic =
        if (AppliesTo[Agent]):
            var Refilled:logic = false
            for (Energy : GetTargets(Agent), not Energy.IsFull[]):
                Energy.Fill()
                RefilledEventInternal.Signal((Agent, Energy))
                set Refilled = true
            Refilled
        else:
            false

    # Only the owner when there is one. When the same entity has abilities, only agents granted one of them
    AppliesTo<private>(Agent:agent)<decides><transacts>:void =
        if (Owner := Entity.FindOwningPlayer[]):
            Owner = Agent
        Abilities := Entity.GetAbilities()
        if (Abilities.Length > 0):
            Granted := for (Ability : Abilities, Ability.IsGranted[Agent]):
                Ability
            Granted.Length > 0

    # What to fill (the energy_component of this entity or a descendant; otherwise the energy_components of Agent and their items)
    GetTargets<private>(Agent:agent)<transacts>:[]energy_component =
        if (Own := Entity.FindEnergy[]):
            array{Own}
        else:
            AgentEnergy := if (Energy := Agent.GetComponent[energy_component]) then array{Energy} else array{}
            ItemEnergy := for (Item : Agent.GetAgentItems(), Energy := Item.FindEnergy[]):
                Energy
            AgentEnergy + ItemEnergy
