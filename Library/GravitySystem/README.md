# GravitySystem

A System for gravity points. `gravity_well_component` pulls nearby players toward its center, and `gravity_point_ability_component` is an ability (an AbilitySystem `ability_component` subclass) that lets a granted player place such a point where the reticle aims.

## Placement

| component | Where to place | What it does |
|---|---|---|
| `gravity_well_component` | the entity that should have gravity (the same entity as its visual mesh). The ability may also create it at run time | every frame, pulls players within `RadiusCm` toward the center (added to their velocity) |
| `gravity_point_ability_component` | the same entity as the grant component (AbilitySystem's GrantKit). For an item, the item's entity | when a granted player presses `PlaceAction`, places a gravity point where the reticle aims and removes it after `DurationSeconds` seconds. Pressing again while placed removes it at once |

How `gravity_point_ability_component` is granted is chosen by a component on the same entity.
- As an item (while equipped) → place it together with `item_component`, `item_holder_component` and `ability_grant_item_component`. Add `exclusive_item_component` to limit it to one per player
- To everyone from the start / while active → `ability_grant_players_component` (each player can place one)
- While a condition holds → `ability_grant_condition_component` (conditions as children)
- From code → `Grant` / `Revoke`

Example: a fixed gravity point and an item that places gravity points
```
Scope (or world)
├ Player manager (player_manager_component)
├ Gravity point (gravity_well_component + mesh)
└ Gravity gun (item_component + item_holder_component + ability_grant_item_component + gravity_point_ability_component)
```

## Settings (@editable)
- `gravity_well_component.RadiusCm : float = 1500.0` — radius the pull reaches (centimeters, 100–20000). Strongest at the center, 0 at this distance.
- `gravity_well_component.StrengthCmPerSecondSquared : float = 1200.0` — pull strength at the center (centimeters per second squared, 0–10000). The speed toward the center grows by this much every second.
- `gravity_point_ability_component.WellPrefab : concrete_subtype(entity) = entity` — the prefab used as the look of a placed point. Each placement creates one and adds `gravity_well_component`. With the default entity, the point has no visual.
- `gravity_point_ability_component.DurationSeconds : float = 30.0` — time until a placed point disappears (seconds, 1–600).
- `gravity_point_ability_component.PlaceDistanceCm : float = 800.0` — how many centimeters ahead of the reticle to place it (100–10000). If something is in the way, it is placed in front of it (150 cm short of the hit).
- `gravity_point_ability_component.RadiusCm : float = 1500.0` / `StrengthCmPerSecondSquared : float = 1200.0` — the radius and strength given to the placed point (same meaning as in `gravity_well_component`).
- `gravity_point_ability_component.PlaceAction : input_action(logic) = Character.WeaponPrimary` — the input that places a point (or removes it while placed).
- `gravity_point_ability_component.PlaceMapping : input_mapping = Character.RangedWeaponMapping` — the key mapping enabled while granted. Pick one that contains `PlaceAction`.
- `gravity_point_ability_component.RemoveMappingOnRevoke : logic = false` — removes `PlaceMapping` when revoked. Turn it on only for a mapping dedicated to this ability (with `RangedWeaponMapping`, turning it on also disables the weapon controls).

## Events
- No scene_event is sent.
- `gravity_point_ability_component.PlacedEvent : listenable(tuple(agent, gravity_well_component))` — when someone places a point, with (the placer, the placed point).
- `gravity_point_ability_component.RemovedEvent : listenable(agent)` — when someone's point disappears (timed out, pressed again, `RemoveWell`, end of the simulation), with the placer.
- The grant / revoke `GrantedEvent` / `RevokedEvent` belong to `ability_component`.

## Public API
```verse
gravity_well_component<public> := class<final_super>(component):
    RadiusCm<public>:float
    StrengthCmPerSecondSquared<public>:float

gravity_point_ability_component<public> := class<final_super>(ability_component):
    WellPrefab<public>:concrete_subtype(entity)
    DurationSeconds<public>:float
    PlaceDistanceCm<public>:float
    RadiusCm<public>:float
    StrengthCmPerSecondSquared<public>:float
    PlaceAction<public>:input_action(logic)
    PlaceMapping<public>:input_mapping
    RemoveMappingOnRevoke<public>:logic
    PlacedEvent<public><final>:listenable(tuple(agent, gravity_well_component))   # (the placer, the placed point)
    RemovedEvent<public><final>:listenable(agent)
    FindWell<public>(Agent:agent)<decides><transacts>:gravity_well_component     # fails if Agent has no point
    Toggle<public>(Agent:agent):void       # same as pressing (places if none, removes if one exists). Does nothing without a character
    RemoveWell<public>(Agent:agent):void   # does nothing if none
    # Grant / Revoke / RevokeAll / IsGranted / GetGrantedAgents / GrantedEvent / RevokedEvent come from ability_component
```

## Requirements, caveats and limits
- One `player_manager_component` is needed in the scope (or the world) (the players to pull). `gravity_well_component` looks it up once at the start and remembers it (retrying every second until found).
- Players with `controlled_movement_tag` (PlayerSystem; the base of `swinging_tag`, `jetpack_boosting_tag`, etc.) are not pulled (their movement takes priority).
- Each player can place at most one point per ability. A placed point stays until its time runs out even if the ability is revoked (it is removed at the end of the simulation).
- A placed point is created as a child of the simulation's root entity, not under the ability's entity.
- If the point's visual mesh has collision, it can also be grabbed by a swing.
- Placing the grant component under a player's slot (inside a loadout, etc.) grants only to the owner (a GrantKit rule). The behavior of the ability itself does not change.
- No experimental API is used.

## Verifying
- Test: `gravity_system_test_component` in `_Test/GravitySystemTest/`. Place one entity with `player_manager_component` and attach only `gravity_system_test_component` to a test entity (the point and the ability are created by the test at run time). Start in an open area with nothing within 3 m above the player's head. It checks that the point pulls the player upward, `Grant` / `Revoke` from code, placing and removing with `Toggle`, and the timeout. When "press fire" appears, press the fire button within 30 seconds. About 5 seconds excluding the human input. Results go to the output log as `[TEST] GravitySystem`.
- Sample: `ability_sample_component` in `_Samples/AbilitySample/`. Attached together with `gravity_point_ability_component` on the same entity, `ToggleAction` (default E / RB) toggles the grant on yourself.
