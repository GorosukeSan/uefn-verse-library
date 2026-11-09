# LoadoutSystem

A System that builds a prefab bundling one player's parts (a loadout) per player and places it under that player's slot. The parts inside affect only the owner, so abilities, energy, HUD, attachments, a custom character and so on can be attached to a player as a bundle, with no code.

## Placement

| component | Where | What it does |
|---|---|---|
| `loadout_component` | an entity (anywhere inside the scope) | On activation, creates `Prefab` per player and places it under that player's slot. On removal, sends the deactivate signal and then deletes it |
| `loadout_instance_component` | not placed (attached at runtime to the root of the loadout created by `loadout_component`) | Holds whose loadout it is and which `loadout_component` created it; on the frame after creation, sends the activate signal to the loadout entity and its descendants |

Example: "give everyone a custom character (CharacterSystem) that walks and jumps, and play a sound on landing"
```
Loadout (loadout_component, Prefab = the prefab below, ActiveOnBegin = true)

Prefab
└ Body (character_motor_component + character_walk_component + character_jump_component + character_owner_stasis_component)
  ├ Look (mesh)
  └ Landing (character_action_trigger_component, Action = Landed)
    └ Sound (device_audio_component (FNDeviceSystem))
```
The contents of the prefab become a separate entity per player, each affecting only its owner. Abilities (an ability subclass + `ability_grant_players_component`), an `energy_component` or widgets can go in the same prefab as well.

## Settings (@editable)
- `loadout_component.Prefab : concrete_subtype(entity) = entity` — prefab of one player's loadout.
- `loadout_component.ApplyToEveryone : logic = true` — when on, applied on activation to everyone present and to everyone who joins later. When off, only to the players chosen with `ApplyTo`.
- `loadout_component.ActiveOnBegin : logic = false` — when on, activates when the simulation begins. When off, from the activate signal (`activated_event`) or `Activate`.
- `loadout_component.Group : string = ""` — exclusive group. When not empty, other loadouts of the same `Group` are removed from the player before applying (one job per player, etc.).

## Events
- `loadout_changed_event` (scene_event, SendScoped): `Loadout : loadout_component` (the sender), `Agent : agent`, `Applied : logic` (true when applied, false when removed). To the whole scope (the whole world when there is no scope). Sent by `loadout_component`. Not consumed.
- `loadout_component.AppliedEvent : listenable(tuple(agent, entity))` — fires with (the agent, the loadout entity) when applied.
- `loadout_component.RemovedEvent : listenable(agent)` — fires with the agent when removed.
- Sent: to the loadout entity and its descendants, `activated_event` on the frame after creation (from `loadout_instance_component`), and `deactivated_event` on removal (before deletion).
- Received: `loadout_component` handles `activated_event` (`Activate`) and `deactivated_event` (`Deactivate`; removes from everyone). Neither is consumed. Even when the activate signal knows who triggered it (`activated_by_agent_event`), it is not applied to that agent (it only activates; applying is done by `ApplyToEveryone` or `ApplyTo`).

## Owner
- The loadout is created as a child of the player's slot (the entity of `player_slot_component`) under `player_manager_component`, so `FindOwningPlayer[]` succeeds for the parts inside and they affect only the owner. Parts that narrow to the owner: ability grants (`ability_grant_players_component` / `ability_grant_condition_component`), widgets (`player_widget_component`), `player_attach_component`, `item_grant_component`, `hud_hide_component`, the MotionKit parts (PlayerSystem), custom characters (CharacterSystem), and `device_target_agents.Owner` of FNDeviceSystem.
- The loadout is not created under the entity of `loadout_component`. Its position is under the slot entity, so parts that need a location move themselves (e.g. `SpawnAtOwner` of a custom character).
- `Entity.FindLoadoutInstance[]` lets a part find its own loadout (`Source` / `Player`).
- One `loadout_component` creates only one instance per player (calling `ApplyTo` repeatedly still gives one).

## Public API
```verse
loadout_changed_event<public> := class(scene_event):
    Character<public>:loadout_component
    Agent<public>:agent
    Applied<public>:logic

loadout_component<public> := class<final_super>(component):
    Prefab<public>:concrete_subtype(entity)
    ApplyToEveryone<public>:logic
    ActiveOnBegin<public>:logic
    Group<public>:string
    AppliedEvent<public><final>:listenable(tuple(agent, entity))
    RemovedEvent<public><final>:listenable(agent)
    Activate<public>():void                                    # Start applying (everyone and late joiners with ApplyToEveryone). No-op when active
    Deactivate<public>():void                                  # Remove from everyone and stop applying
    ApplyTo<public>(Agent:agent):logic                         # Activates first when not active. Removes others of the same Group. false when not joined
    RemoveFrom<public>(Agent:agent):void                       # Sends the deactivate signal, then deletes
    RemoveFromAll<public>():void
    IsAppliedTo<public>(Agent:agent)<decides><transacts>:void
    FindInstance<public>(Agent:agent)<decides><transacts>:entity
    GetAppliedAgents<public>()<transacts>:[]agent              # Order unspecified

loadout_instance_component<public> := class<final_super><internal>(component):
    Source<public>:loadout_component
    Player<public>:player

(InEntity:entity).FindLoadoutInstance<public>()<decides><transacts>:loadout_instance_component   # InEntity or an ancestor. Fails outside a loadout
```

## Requirements, caveats and limits
- One `player_manager_component` is needed in the scope (or the world). When it is not found, nothing is applied and a message goes to the output log.
- The activate signal is sent on the frame after creation (so that every part of the prefab has finished `OnBeginSimulation` before it arrives). Parts inside the loadout that wait for activation (grants with `GrantOnBegin` off, countdowns, `enable_on_activation_component`, ...) start here. Reaction parts (the `Targets` of `character_action_trigger_component` or `player_motion_trigger_component`) receive this signal too, so a sound and the like may play once right after applying.
- The loadout of a player who leaves is removed. At the end of the simulation it is removed from everyone as well.
- When an activate signal arrives while `ApplyToEveryone` is off, it only activates (applies to nobody). To apply per player from a menu or a volume, call `ApplyTo` from code.
- This System's code has no `⚠ Unverified` items and no `@experimental` API.

## Verifying
- Test: `loadout_system_test_component` in `_Test/LoadoutSystemTest/`. Place one entity with `player_manager_component` and one entity with this component, and start with at least one player (waits up to 10 s for a player to join). Checks that `ApplyTo` creates the loadout under the slot with that player as owner, that `loadout_instance_component` is attached, that a second `ApplyTo` does not add another, that other loadouts of the same `Group` are removed, and that `RemoveFrom` deletes it. Finishes quickly. Results go to the output log as `[TEST] LoadoutSystem`.
- Sample: there is no sample using `loadout_component` in `_Samples/`. `_Samples/Platformer2DSampleExperimentalKit/` creates a custom character under the slot from code without a loadout (the owner is decided the same way).
