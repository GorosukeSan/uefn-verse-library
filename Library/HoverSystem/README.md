# HoverSystem

The hover ability (a subclass of AbilitySystem's `ability_component`). While a granted person holds `HoverAction` (default Jump) in the air, their fall speed is capped so they float. If there is energy (EnergySystem) it is used. This ability does not restore energy: to refill when stepping on a checkpoint, place CheckpointSystem's EnergyKit (`checkpoint_energy_refill_component`) alongside; to restore by using something, place EnergySystem's RestoreKit alongside (HoverSystem does not depend on CheckpointSystem).

## Setup (placement)

| component | Where to place | What it does |
|---|---|---|
| `hover_ability_component` | The same entity as the grant component (AbilitySystem's GrantKit). For an item, the item's entity | While a granted person holds `HoverAction` in the air, caps their fall speed at `MaxFallSpeedCmPerSecond`. Attaches `hovering_tag` to the person while hovering |

How it is granted is chosen by the component placed on the same entity.
- To everyone from the start / while activated -> `ability_grant_players_component` (energy placed on this entity is shared by everyone; attach it to the player to have one per person)
- As an item (while equipped) -> place together with `item_component`, `item_holder_component` and `ability_grant_item_component` (energy on the item's entity)
- While a condition holds -> `ability_grant_condition_component` (conditions as children)
- From code -> `Grant` / `Revoke`

Example: "everyone can hover, and energy refills at checkpoints"
```
Area (or world)
├ Player management (player_manager_component)
├ Platform (checkpoint_component + mesh) ...
└ Hover (hover_ability_component + ability_grant_players_component + energy_component + checkpoint_energy_refill_component)
```
`checkpoint_energy_refill_component` (CheckpointSystem/EnergyKit) refills the `energy_component` on its entity or a child each time a granted person steps on a checkpoint. When the energy lives on an item or a player, place only `checkpoint_energy_refill_component` on a separate entity inside the area (it refills the energy of the person who stepped on and of their items).

## Settings (@editable)
- `hover_ability_component.MaxFallSpeedCmPerSecond : float = 100.0` — fall speed cap while hovering (centimeters per second, 0–3000). 0 holds the current height.
- `hover_ability_component.EnergyPerSecond : float = 20.0` — energy used per second while hovering (0–1000). Without energy, hovering consumes nothing.
- `hover_ability_component.HoverAction : input_action(logic) = Character.Jump` — input held in the air to hover.
- `hover_ability_component.HoverMapping : input_mapping = Character.TraversalMapping` — key mapping enabled while granted. Choose one that contains `HoverAction`.
- `hover_ability_component.RemoveMappingOnRevoke : logic = false` — removes `HoverMapping` on revoke. Turn it on only for a mapping dedicated to this ability (turning it on with `TraversalMapping` also disables the movement inputs).

## Events
- `hover_changed_event` (scene_event, SendUp): `Ability : hover_ability_component`, `Agent : agent`, `Active : logic` (true = started, false = stopped). Sent from the ability's entity to its ancestors when `hover_ability_component` starts or stops hovering (for an item, up to the owning player). Not consumed.
- `hover_ability_component.HoverChangedEvent : listenable(tuple(agent, logic))` — delivered as (the person, true = started / false = stopped) when someone starts or stops hovering.
- The `GrantedEvent` / `RevokedEvent` for grant and revoke belong to `ability_component`.
- Received: it receives no scene_event.

## Tags
- `hovering_tag` (subclass of `player_state_tag`): attached to the person (agent) while hovering (in the air with the fall speed capped). Removed when the input is released, on landing, when energy reaches 0, or on revoke. Attaching and removing go through `player_tag_holder`, so a `hovering_tag` attached by another part is not removed.
- Other Systems check with `Agent.HasPlayerTag[hovering_tag]`.
- A person with `controlled_movement_tag` (the base of `swinging_tag`, `jetpack_boosting_tag`, etc.) does not hover.

## Public API
```verse
hovering_tag<public> := class(player_state_tag):

hover_changed_event<public> := class(scene_event):
    Ability<public>:hover_ability_component
    Agent<public>:agent
    Active<public>:logic

hover_ability_component<public> := class<final_super>(ability_component):
    MaxFallSpeedCmPerSecond<public>:float
    EnergyPerSecond<public>:float
    HoverAction<public>:input_action(logic)
    HoverMapping<public>:input_mapping
    RemoveMappingOnRevoke<public>:logic
    HoverChangedEvent<public><final>:listenable(tuple(agent, logic))   # (the person, true = started / false = stopped)
    IsHovering<public>(Agent:agent)<decides><transacts>:void          # succeeds if the fall speed is being capped now
    # Grant / Revoke / RevokeAll / IsGranted / GetGrantedAgents / GrantedEvent / RevokedEvent come from ability_component
```

## Requirements, caveats and limits
- The area (or world) needs a `player_manager_component` (used by the grant component).
- `RunFor` starts with `AwaitPlayerInput` and waits until input can be read. Granting to an agent that is not a player does nothing and prints `[hover_ability_component] Granted to an agent that is not a player...` in the output log.
- Energy is looked up with `FindEnergyFor` (EnergySystem: an `energy_component` on this entity or a descendant, otherwise one attached to the player (agent)). Hovering is impossible at 0, but the item is not lost.
- It does not restore energy. To refill at checkpoints use CheckpointSystem's EnergyKit (`checkpoint_energy_refill_component`); to restore by using something use EnergySystem's RestoreKit (`energy_restore_ability_component`).
- Attaching tags to an agent is marked in PlayerSystem's `PlayerTags.verse` as "⚠ Unverified: whether attaching / removing tags on an agent and ContainsTag work in UEFN" (check with `_Test/PlayerSystemTest`).
- Placing the grant component under a player's slot (inside a loadout, etc.) grants only to the owner (a GrantKit rule). The behavior of this ability itself does not change.
- No experimental APIs are used.

## Verifying
- Test: `hover_system_test_component` in `_Test/HoverSystemTest/`. Place one entity with `player_manager_component` and attach only `hover_system_test_component` to a test entity (the test creates the ability and energy as children at runtime). It checks `Grant` / `Revoke` from code, the hover notifications, `IsHovering` and the energy drain (refill at checkpoints is checked in `_Test/CheckpointSystemTest`). When "jump and hold jump in the air" appears, jump within 30 seconds, hold jump in the air for about 1 second, then release. Results are in the output log under `[TEST] HoverSystem`.
- Sample: `ability_sample_component` in `_Samples/AbilitySample/`. Attach it to the entity with `hover_ability_component`, and `ToggleAction` (default E / RB) toggles the grant to yourself.

## Migration notes (2026-11-08)
| Old | New |
|---|---|
| `hover_ability_component.RefillOnCheckpoint : logic = true` (subscribed to the area's `checkpoint_presence_component` and refilled the energy) | Removed. Add `checkpoint_energy_refill_component` (CheckpointSystem/EnergyKit) to the hover entity. It refills the `energy_component` on that entity or a child when a granted person steps on (same as before). When the energy lives on an item or a player, place it on a separate entity inside the area. Levels that changed `RefillOnCheckpoint` in the editor lose that value |
| `hover_changed_event.Sender` | `hover_changed_event.Ability` (the sender field name was unified across the Library: events sent from an ability use `Ability`) |
