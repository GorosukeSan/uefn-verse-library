# EnergySystem

A System that holds the amount of "energy" used by abilities and items. `energy_component` holds the amount and notifies upward when it is consumed or restored. There is also an ability that restores energy (RestoreKit's `energy_restore_ability_component`). To refill on a checkpoint, use CheckpointSystem's EnergyKit (`checkpoint_energy_refill_component`) (EnergySystem knows nothing about checkpoints).

## Placement

| component | Where to place | What it does |
|---|---|---|
| `energy_component` | the entity of the ability or item that uses energy, or a child of it. Place one at the root of a loadout or custom character and every part inside shares the same energy. For per-player energy, attach it at run time to the player (the agent's entity) | holds the amount (starts full with `StartFull`, otherwise at 0). Sends `energy_changed_event` upward when the amount changes |
| `energy_restore_ability_component` (RestoreKit) | the ability's entity. How it is granted is chosen by a component on the same entity (AbilitySystem / ItemSystem) | when a granted player presses `RestoreAction`, restores `RestoreAmount` to that player's energy (`FindRestoreTarget`). As an item, consumes one |

How to grant `energy_restore_ability_component`:
- As an item (while equipped; using it consumes one) → place it on the item's entity together with `item_component`, `item_holder_component` and `ability_grant_item_component`. Add `basic_stackable_component` to hold several.
- To everyone from the start (unlimited uses) → `ability_grant_players_component`. Set `CooldownSeconds` to prevent spamming.
- While a condition holds → `ability_grant_condition_component` (conditions as children).
- From code → `Grant` / `Revoke`.

Example: an ability that uses energy (jetpack and hover find it with `FindEnergyFor`) and a restore item
```
Jetpack (jetpack_ability_component + a grant component)
└ Fuel (energy_component)

Potion (item_component + item_holder_component + ability_grant_item_component + basic_stackable_component + energy_restore_ability_component)
```

## Settings (@editable)
- `energy_component.MaxEnergy : float = 100.0` — the initial maximum (1–10000). After `SetMax`, read the maximum with `GetMax`.
- `energy_component.StartFull : logic = true` — when on, starts full. When off, starts at 0 (when a checkpoint or a restore fills it before use).
- `energy_restore_ability_component.RestoreAmount : float = 100.0` — amount restored per use (0–10000).
- `energy_restore_ability_component.CooldownSeconds : float = 0.0` — seconds after a restore before the next use (0–600). 0 means usable at once.
- `energy_restore_ability_component.ConsumeItemOnUse : logic = true` — when on and placed on an item, consumes one item per restore (the last one disappears and the ability is revoked). Unused when not an item.
- `energy_restore_ability_component.RestoreAction : input_action(logic) = Character.WeaponPrimary` — the input that restores when pressed (the attack button).
- `energy_restore_ability_component.RestoreMapping : input_mapping = Character.RangedWeaponMapping` — the key mapping added while granted. Pick one that contains `RestoreAction`.
- `energy_restore_ability_component.RemoveMappingOnRevoke : logic = false` — when on, removes `RestoreMapping` when revoked (for an item, when unequipped). Turn it on only for a mapping dedicated to this ability.

## Events
- `energy_changed_event` (scene_event, SendUp): `Energy : energy_component` (ratio via `Energy.GetRatio()`), `Amount : float` (the amount after the change), `Delta : float` (difference from the last notified amount; positive when increased). From the `energy_component`'s entity upward (for an item, up to the owning player). Sent only when the amount differs from the last notified one. Sent at once for `Consume` / `Restore` / `SetAmount` / `Fill` / `SetMax`, and after physics in the same frame (`TickEvents.PostPhysics`) for `Spend[]`. Not consumed.
- `energy_restore_failed_event` (scene_event, SendUp): `Ability : energy_restore_ability_component`, `Agent : agent`. Sent from the ability's entity upward when it was used but there was nothing to restore (e.g. to show "nothing to restore" on the HUD). Not consumed.
- listenable (cannot be signaled from outside)
  - `energy_component.ChangedEvent : listenable(float)` — fires with the new amount each time it changes (same timing as `energy_changed_event`; after physics for `Spend[]`).
  - `energy_restore_ability_component.RestoredEvent : listenable(tuple(agent, energy_component))` — fires on a restore with (the user, the restored energy_component).
  - `energy_restore_ability_component.FailedEvent : listenable(agent)` — fires with the user when there was nothing to restore.

## Public API
```verse
energy_changed_event<public> := class(scene_event):
    Energy<public>:energy_component
    Amount<public>:float                                   # the amount after the change
    Delta<public>:float                                    # difference from the last notified amount (positive when increased)

energy_component<public> := class<final_super>(component):
    MaxEnergy<public>:float
    StartFull<public>:logic                                # default true. false starts at 0
    var<private> CurrentAmount<public>:float               # current amount (0 to max)
    ChangedEvent<public><final>:listenable(float)
    GetMax<public>()<reads>:float                          # MaxEnergy until SetMax is called
    IsEmpty<public>()<decides><reads>:void
    IsFull<public>()<decides><reads>:void
    HasEnough<public>(Amount:float)<decides><reads>:void   # checks whether Spend[] would succeed, without changing the amount
    GetRatio<public>()<reads>:float                        # 0.0 to 1.0. 0.0 when the max is 0
    Spend<public>(Amount:float)<decides><transacts>:void   # subtracts if enough. Fails and changes nothing if not enough or negative. Usable in an if condition. Notifies after physics
    Consume<public>(Amount:float):void                     # never fails; stops at 0 when not enough
    Restore<public>(Amount:float):void                     # the part above the max is discarded
    SetAmount<public>(Value:float):void                    # sets the amount, clamped to 0..max
    Fill<public>():void
    SetMax<public>(NewMax:float):void                      # negative becomes 0. Clamps the current amount if above

(InEntity:entity).FindEnergy<public>()<decides><transacts>:energy_component                # self or descendants. Fails if none
(InEntity:entity).FindEnergyFor<public>(Agent:agent)<decides><transacts>:energy_component  # FindEnergy, else the Agent itself
(InEntity:entity).FindEnergyAbove<public>()<decides><transacts>:energy_component           # FindEnergy, else the ancestors (nearest first)

# RestoreKit
energy_restore_failed_event<public> := class(scene_event):
    Ability<public>:energy_restore_ability_component
    Agent<public>:agent

energy_restore_ability_component<public> := class<final_super>(ability_component):
    RestoreAmount<public>:float
    CooldownSeconds<public>:float
    ConsumeItemOnUse<public>:logic
    RestoreAction<public>:input_action(logic)
    RestoreMapping<public>:input_mapping
    RemoveMappingOnRevoke<public>:logic
    RestoredEvent<public><final>:listenable(tuple(agent, energy_component))
    FailedEvent<public><final>:listenable(agent)
    TryRestoreFor<public>(Agent:agent):logic               # same as pressing the button. true if it restored
    FindRestoreTarget<public>(Agent:agent)<decides><transacts>:energy_component
```

## Requirements, caveats and limits
- The amount is clamped to 0..max (`GetMax`). Calling `SetMax` before the simulation starts does not notify; the simulation starts with the new maximum (full with `StartFull`).
- The initial amount (the max with `StartFull`, otherwise 0) is fixed at the start of the simulation, or earlier on the first call of a function that changes the amount (`Spend` / `Consume` / `Restore` / `SetAmount` / `Fill`). An amount set with `SetAmount` before the start is not overwritten at the start.
- To subtract only when there is enough, write `if (Energy.Spend[10.0]):` (fails and changes nothing when not enough). The amount changes at once, but the notification (SendUp, Signal) cannot be rolled back, so `energy_changed_event` and `ChangedEvent` are sent once after physics in the same frame (`TickEvents.PostPhysics`). If the amount is changed earlier with `Consume` etc., everything is sent together then (`Delta` is the difference from the last notified amount).
- `FindEnergy` returns the one on the entity itself, or else the first found among the descendants. With several descendants it is unspecified which one is returned, so place only one.
- `FindEnergyFor` (used by jetpack and hover) looks for an `energy_component` on the ability's entity (and its descendants) first, then on the player (the agent's entity) itself (not inside the inventory). Energy placed on the ability's entity is shared by everyone granted. When neither exists it fails and the ability runs without using energy.
- `FindEnergyAbove` (used by CharacterSystem's dash etc.) searches the ancestors nearest first when there is none on the entity itself or its descendants. Place one at the root of a loadout or custom character and every part inside uses the same energy.
- `TryRestoreFor` is not `<decides>` because the notification (SendUp, Signal) and consuming the item cannot be rolled back. To only check, use `FindRestoreTarget[]`.
- The restore target (`FindRestoreTarget`) is the `energy_component` among the inventory items (items other than this entity) that is not full and has the lowest ratio, or else the player's own `energy_component` (if not full). Fails when all are full or none exists.
- Turning on `RemoveMappingOnRevoke` with the default `RangedWeaponMapping` also disables the weapon controls.
- `energy_restore_ability_component` uses AbilitySystem, ItemSystem and InputSystem. `RunFor` starts with `AwaitPlayerInput` and waits until input is available. When granted to a non-player agent it does nothing and the output log shows `[energy_restore_ability_component] granted to a non-player agent...`.

## Verifying
- Test: `energy_system_test_component` in `_Test/EnergySystemTest/`. Place one entity with `player_manager_component` and one with only `energy_system_test_component` (the `energy_component` and the ability are created by the test as children at run time). It checks `energy_component` changes and clamping, `Spend[]` (the amount is rolled back on failure; the notification arrives once after physics), `SetAmount`, `StartFull`, `SetMax`, the notifications (`ChangedEvent` and `energy_changed_event`'s `Amount` / `Delta`), `FindEnergy` / `FindEnergyFor`, and `energy_restore_ability_component`'s `TryRestoreFor`, `FailedEvent` / `RestoredEvent` and `Grant` / `Revoke` from code. It temporarily attaches an `energy_component` to the player (the agent's entity) and removes it afterwards. At the end, when the log says "press the fire button", press the fire button within 20 seconds (otherwise only that item is `[FAIL]`). Results go to the output log as `[TEST] EnergySystem`.
- There is no sample (`_Samples/`).

## Migration notes (2026-11-08)
| Old | New |
|---|---|
| `energy_component.TryConsume(Amount):logic` | `Spend[Amount]` (`<decides><transacts>`). Write `if (Energy.Spend[X]):`. If you need a logic, `logic{Energy.Spend[X]}`. Notifies after physics in the same frame |
| `energy_changed_event{Energy}` | `energy_changed_event{Energy; Amount; Delta}` (fields added only. Readers keep working. Nobody is expected to construct it) |
| (none) | `energy_component.SetAmount(Value)`, `@editable StartFull` (default true = starts full as before) |
| `energy_restore_failed_event.Sender` | `energy_restore_failed_event.Ability` (sender field names unified across the Library; events sent from an ability use `Ability`) |
