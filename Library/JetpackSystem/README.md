# JetpackSystem

The jetpack ability (a subclass of AbilitySystem's `ability_component`). When a granted player presses jump (`BoostAction`) in the air, they charge and hover; on release they launch in the configured direction. After launching until landing, holding the button limits the fall speed. Uses energy (EnergySystem) when present.

## Placement

| component | Where to place | What it does |
|---|---|---|
| `jetpack_ability_component` | the same entity as the grant component (AbilitySystem's GrantKit). For an item, the item's entity | runs the charge, launch, glide and landing watch for each granted player. Attaches `jetpack_boosting_tag` to the player from charging until the flight ends |

How it is granted is chosen by the component placed on the same entity.
- As an item (while equipped) -> place together with `item_component`, `item_holder_component` and `ability_grant_item_component`. Put the energy on the item's entity. `exclusive_item_component` (ItemSystem's ExclusiveKit) to limit to one per player. `item_equip_lock_component` (ItemSystem's RuleKit) to prevent switching items while charging / flying
- To everyone from the start / while active -> `ability_grant_players_component` (energy on this entity is shared by everyone; attach the energy to the players for per-player energy)
- While a condition is satisfied -> `ability_grant_condition_component` (conditions as direct children)
- From code -> `Grant` / `Revoke`

Effects: when the same entity has `fort_item_ability_component`, its `ItemEquippedAbilities` are used on the player while charging, launching and gliding.

Example: a jetpack item that disappears when its energy runs out
```
Zone (or the world)
├ Players (player_manager_component)
└ Jetpack (item_component + item_holder_component + ability_grant_item_component
                 + jetpack_ability_component + energy_component + item_equip_lock_component)
```

## Settings (@editable)
Launch:
- `jetpack_ability_component.BoostSpeedCmPerSecond : float = 3000.0` — speed at the moment of launch with a x1 charge (cm/s, 0-20000).
- `jetpack_ability_component.BoostDurationSeconds : float = 0.8` — seconds from launch until the speed reaches 0 with a x1 charge (0.1-5). After that the player falls normally.
- `jetpack_ability_component.BoostEaseExponent : float = 2.0` — speed = initial speed x (1 - elapsed / duration) to this power (0-5). 0 for constant; larger values start faster.

Launch direction:
- `jetpack_ability_component.BoostPitchDegrees : float = 90.0` — vertical angle (degrees, -90 to 90). 90 straight up, 0 horizontal, -90 straight down. Not affected by the vertical view direction.
- `jetpack_ability_component.BoostYawDegrees : float = 0.0` — horizontal angle (degrees, -180 to 180). 0 is the view direction flattened; positive is right.

Charge:
- `jetpack_ability_component.MinChargeSeconds : float = 1.0` — charges up to this keep the launch distance at x1 (0-10 s).
- `jetpack_ability_component.MaxChargeSeconds : float = 3.0` — at this many seconds the distance is maximum (x `MaxChargeMultiplier`) and energy is consumed at that moment (0.1-10 s). Holding longer keeps hovering at maximum.
- `jetpack_ability_component.MaxChargeMultiplier : float = 3.0` — launch distance multiplier at full charge (1-10). For a distance of N times, the initial speed and the duration are each multiplied by sqrt(N).
- `jetpack_ability_component.ChargeLiftCm : float = 50.0` — height the position is lifted directly when charging starts (cm, 0-300).
- `jetpack_ability_component.ChargeRiseSpeedCmPerSecond : float = 50.0` — rising speed while charging (cm/s, 0-1000). No horizontal movement. 0 holds the height.

Energy:
- `jetpack_ability_component.BoostEnergyCost : float = 30.0` — amount consumed per launch (0-1000). Consumed the moment the charge reaches maximum, or the moment of release if earlier. Launching works even when short; energy goes to 0.
- `jetpack_ability_component.GlideEnergyPerSecond : float = 1.0` — amount consumed per second while gliding (0-100).
- `jetpack_ability_component.RemoveItemWhenEmpty : logic = true` — on an item, the whole item disappears when energy reaches 0 (after the flight ends if mid-flight). Not used when not an item.

Glide:
- `jetpack_ability_component.GlideMaxFallSpeedCmPerSecond : float = 300.0` — fall speed limit (cm/s, 0-5000). 0 holds the height.

Input:
- `jetpack_ability_component.BoostAction : input_action(logic) = Character.Jump` — the action pressed in the air to charge and released to launch. After a launch until landing, holding it glides.
- `jetpack_ability_component.BoostMapping : input_mapping = Character.TraversalMapping` — the key mapping added while granted (one containing `BoostAction`).
- `jetpack_ability_component.RemoveMappingOnRevoke : logic = false` — removes `BoostMapping` on revoke. Turn it on only when a mapping dedicated to this ability is chosen (on with `TraversalMapping` disables movement too).

## Events
- `jetpack_boost_changed_event` (scene_event, SendUp): `Ability : jetpack_ability_component`, `Agent : agent`, `Ratio : float` (gauge 0.0-1.0). Sent upward from the ability's entity, and the same event wrapped in a `player_event` is also SendDown under the player's slot (received by that player's views such as a HUD). Sent only when the gauge value changes (1 on grant and on landing, 0 to 1 while charging, 0 from launch until landing, 0 on revoke). Not consumed.
- `jetpack_ability_component.BoostRatioChangedEvent : listenable(tuple(agent, float))` — fires with (the agent, gauge) at the same time as `jetpack_boost_changed_event`. Cannot be Signaled from outside.
- `GrantedEvent` / `RevokedEvent : listenable(agent)` — grant / revoke (from `ability_component`).
- Received: none (input is read directly from `player_input`).

## Tags
- `jetpack_boosting_tag` (derived from `controlled_movement_tag`): attached to the player (`agent`) from the start of charging until the flight ends (while the velocity is being controlled). Removed when the flight ends or when stopped by a revoke. Not attached while gliding.
- Attached and removed through `player_tag_holder` (PlayerSystem), over the same span as the `item_equip_lock_component` lock.
- Other Systems check with `Agent.HasPlayerTag[jetpack_boosting_tag]` (or `controlled_movement_tag` to ask whether the movement is being controlled). Gravity and hover do not overwrite the velocity of a tagged player.

## Public API
```verse
jetpack_boosting_tag<public> := class(controlled_movement_tag):

jetpack_boost_changed_event<public> := class(scene_event):
    Ability<public>:jetpack_ability_component
    Agent<public>:agent
    Ratio<public>:float

jetpack_ability_component<public> := class<final_super>(ability_component):
    BoostSpeedCmPerSecond<public>:float
    BoostDurationSeconds<public>:float
    BoostEaseExponent<public>:float
    BoostPitchDegrees<public>:float
    BoostYawDegrees<public>:float
    MinChargeSeconds<public>:float
    MaxChargeSeconds<public>:float
    MaxChargeMultiplier<public>:float
    ChargeLiftCm<public>:float
    ChargeRiseSpeedCmPerSecond<public>:float
    BoostEnergyCost<public>:float
    GlideEnergyPerSecond<public>:float
    RemoveItemWhenEmpty<public>:logic
    GlideMaxFallSpeedCmPerSecond<public>:float
    BoostAction<public>:input_action(logic)
    BoostMapping<public>:input_mapping
    RemoveMappingOnRevoke<public>:logic
    BoostRatioChangedEvent<public><final>:listenable(tuple(agent, float))
    GetBoostRatio<public>(Agent:agent)<transacts>:float     # 0.0-1.0. 0.0 for agents not granted
    # Grant / Revoke / RevokeAll / IsGranted / GetGrantedAgents / GrantedEvent / RevokedEvent come from ability_component
```

## Requirements, caveats and limits
- Pressing on the ground does nothing (it is a normal jump). Once charging has started, no new charge until landing. Holding the button meanwhile glides.
- Velocity has no effect on the ground, so at the start of the charge the position is lifted directly by `ChargeLiftCm` (MovementSystem's `LiftBy`; collision is ignored).
- The velocity is set every frame (`TickEvents.PrePhysics`) with `SetLinearVelocity`. Elapsed time is measured by summing the delivered seconds.
- Energy is found with `FindEnergyFor` (the `energy_component` of this entity or a descendant, otherwise the one attached to the player (agent)). Without either, it runs without using energy. At 0, neither charging nor gliding is possible.
- The gauge becomes 1 immediately on grant. It also returns to 1 on landing (even when energy is 0).
- Sending to the slot needs a `player_manager_component` in the zone (or the world) (without one, nothing is sent to the slot). It is looked up when a granted player's run starts and remembered once found (looked up again each time until found).
- `AwaitPlayerInput` is used at the top of `RunFor` to wait until the input is available. It does not run for agents that are not players.
- The ability itself does not look at the owner. Being granted only to the owner when placed under a slot (a loadout, etc.) is the work of the grant components (`ability_grant_players_component` / `ability_grant_condition_component`) (AbilitySystem).
- Attaching tags to an agent relies on PlayerSystem's `⚠ Unverified` (`PlayerTags.verse`: whether attaching / removing tags on an agent and `ContainsTag` work in UEFN).
- The code in this folder has no `⚠ Unverified` and no `@experimental` API.

## Verifying
- Test: `jetpack_system_test_component` in `_Test/JetpackSystemTest/`. Place one entity with `player_manager_component` and attach only `jetpack_system_test_component` to a test entity (the ability and the energy are created by the test at runtime as children). After checking grant / revoke from code (counting, `GrantedEvent` / `RevokedEvent`, the gauge, and that `jetpack_boost_changed_event` arrives upward), when the log says "jump, then hold jump in the air", within 30 s jump, hold jump in the air for about a second, release and land (gauge 0 on charge, 1 on landing, energy decreased by `BoostEnergyCost`). Under a minute including the human input. The result is `[TEST] JetpackSystem` in the output log.
- Sample: `ability_sample_component` in `_Samples/AbilitySample/`. Attached to the entity carrying `jetpack_ability_component`, each player can toggle their own grant with `ToggleAction` (default E / RB). The log is `[ability_sample]`.

## Migration notes (2026-11-08)
| Old | New |
|---|---|
| `jetpack_boost_changed_event.Sender` | `jetpack_boost_changed_event.Ability` (the sender field name was unified across the Library; events sent from an ability use `Ability`. The wrapping `player_event.Sender` stays as it is) |
