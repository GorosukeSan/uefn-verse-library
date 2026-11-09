# AbilitySystem

The base of the mechanism that grants and revokes "abilities" per player. The abilities themselves live in each System as `ability_component` subclasses; who gets them and when is decided by a grant component (GrantKit) on the same entity or by code. The ability side knows nothing about how it is granted.

## Placement

| component | Where to place | What it does |
|---|---|---|
| an `ability_component` subclass | the ability's entity. Never placed directly (place a subclass). Any number per entity | while granted, runs the subclass's `RunFor` for that player and stops it when revoked |
| `ability_grant_players_component` (GrantKit) | the same entity as the ability | grants every ability on the same entity to every player in the scope (including late joiners). Revokes from players who leave. On an entity with an owner, grants only to the owner |
| `ability_grant_item_component` (GrantKit) | the item's entity (the same entity as `item_component`, `item_holder_component` and the ability) | grants to the item's holder (decided by `item_holder_component`) and revokes when it is dropped |
| `ability_grant_condition_component` (GrantKit) | the same entity as the ability, with one condition as a direct child | grants to every player in the scope (or the owner on an entity with an owner) while the condition holds. Revokes when it no longer holds |

Ability subclasses: `swing_ability_component` (SwingSystem), `jetpack_ability_component` (JetpackSystem), `hover_ability_component` (HoverSystem), `gravity_point_ability_component` (GravitySystem), `energy_restore_ability_component` (EnergySystem / RestoreKit).

Example: "everyone can swing while in this node. Players with the loadout can hover only while crouching"
```
Node (game_node_component)
└ Swing (swing_ability_component + ability_grant_players_component (GrantOnBegin = false))

Loadout prefab (LoadoutSystem's loadout_component.Prefab)
└ Hover (hover_ability_component + ability_grant_condition_component)
  └ Crouching (player_state_condition_component (PlayerSystem / MotionKit), State = Crouching)
```
Because it is inside the loadout, hover is granted only to the owner.
To make it an item, attach `item_component`, `item_holder_component` and `ability_grant_item_component` to the ability's entity as well.

## Settings (@editable)
- `ability_grant_players_component.GrantOnBegin : logic = true` — when on, grants from the start of the simulation (as soon as a player joins). When off, grants from the activation signal (in a game sequence, when this node is entered) until the deactivation signal.

`ability_grant_item_component` and `ability_grant_condition_component` have no settings (the holder is decided by `item_holder_component`, the condition by the `condition_component` directly under it).

## Events
- No scene_event is sent.
- `ability_component.GrantedEvent : listenable(agent)` — when granted and `RunFor` started (grant count 0 → 1).
- `ability_component.RevokedEvent : listenable(agent)` — when revoked by every granter and stopped (count reached 0, `RevokeAll`).
- Received: `ability_grant_players_component` takes `activated_event` (start granting) and `deactivated_event` (revoke from the players it granted). Not consumed. It reacts to these signals even when `GrantOnBegin` is on.
- Watched: `ability_grant_item_component` watches `item_holder_component.HolderAddedEvent` / `HolderRemovedEvent`, `ability_grant_condition_component` watches the child condition's `ChangedEvent`.

## Owner
- When the entity of `ability_grant_players_component` or `ability_grant_condition_component` is somewhere with an owner (under a player's slot, inside a loadout, etc.; `FindOwningPlayer[]` succeeds), they grant only to the owner. They do not grant to everyone in the scope and do not watch joins and leaves.
- Without an owner, they grant to everyone (including late joiners) in the `player_manager_component` of the scope (or the world) and revoke from players who leave.
- `ability_grant_item_component` does not look at the owner. It grants to the item's holder.
- The owner is looked up when granting starts (`Start`).

## Public API
```verse
ability_component<public> := class<abstract><final_super>(component):
    GrantedEvent<public><final>:listenable(agent)
    RevokedEvent<public><final>:listenable(agent)
    RunFor<protected>(Agent:agent)<suspends>:void         # implemented by the subclass. Canceled by a race when revoked
    Grant<public>(Agent:agent):void                        # increments the grant count. Starts RunFor on 0 → 1
    Revoke<public>(Agent:agent):void                       # decrements the grant count. Stops at 0. Does nothing if not granted
    RevokeAll<public>():void                               # revokes from everyone regardless of the count
    IsGranted<public>(Agent:agent)<decides><transacts>:void
    GetGrantedAgents<public>()<transacts>:[]agent          # order is unspecified

(InEntity:entity).GetAbilities<public>()<reads>:[]ability_component   # every ability attached to InEntity

# GrantKit
ability_grant_players_component<public> := class<final_super>(component):
    GrantOnBegin<public>:logic
    IsGranting<public>()<decides><transacts>:void          # succeeds while granting

ability_grant_item_component<public> := class<final_super>(component):

ability_grant_condition_component<public> := class<final_super>(component):
    IsGranting<public>()<decides><transacts>:void          # succeeds while the condition holds and it is granting
```

## Requirements, caveats and limits
- Even when several granters grant to the same player, only one `RunFor` runs. The grant count is tracked and it stops when every grant is revoked. A single `Revoke` does not stop it while other granters' grants remain.
- A grant component remembers and revokes only the players it granted itself (it never touches other granters' grants). A grant component grants every ability on its entity.
- Clean-up for `RunFor` is done with `defer` inside `RunFor` (because a revoke cancels it through a race). When `RunFor` returns, the ability ends there even if the grant continues.
- Revoking and re-granting right away stops the previous `RunFor` and starts a new one (told apart by a per-player generation number).
- `ability_grant_players_component` and `ability_grant_condition_component` need one `player_manager_component` in the scope (or the world) when there is no owner. `ability_grant_item_component` needs `item_holder_component` on the same entity. `ability_grant_condition_component` needs a condition as a direct child (combine several with `condition_all` / `condition_any`). Without these they do nothing (and nothing appears in the output log).
- At the end of the simulation (`OnEndSimulation`), abilities revoke from everyone and grant components revoke their own grants.
- The code of this System has no `⚠ Unverified` items and no `@experimental` API.

## Verifying
- Test: `ability_system_test_component` in `_Test/AbilitySystemTest/`. Place one entity with `player_manager_component`, and attach `ability_system_test_component` and `ability_test_probe_component` to a test entity (no grant component). Attach `ability_test_probe_component` and `ability_grant_players_component` (`GrantOnBegin = true`) to another entity and put that entity into `GrantedByPlayers`. With the first player who joins, it checks `Grant` / `Revoke` from code and the counting, `GrantedEvent` / `RevokedEvent`, `RevokeAll`, and that `ability_grant_players_component` grants once to each participant. The owner form and the item / condition grants are not tested. Results go to the output log as `[TEST] AbilitySystem`.
- Sample: `ability_sample_component` in `_Samples/AbilitySample/`. Attach it to an entity with one or more ability components (swing / jetpack / hover / gravity_point, etc.) (a grant component is optional; one `player_manager_component` in the scope). At start it lists the abilities and grant components on the same entity in the output log and Prints `GrantedEvent` / `RevokedEvent`. Pressing `ToggleAction` (default `NextTab`, E / RB, `MenuNavigationMapping`) toggles `Grant` / `Revoke` on yourself. With `StartOnBegin` off, it starts on the activation signal.
