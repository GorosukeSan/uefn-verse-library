# ItemSystem

A System that connects Fortnite items (entities with `item_component`) to the parts of the library. It covers watching who holds an item (the holder), finding a player's inventories, granting items, limiting items to one per player, and locking equipment. It is the foundation for granting abilities through items (AbilitySystem's `ability_grant_item_component`) and showing a screen only to the holder (WidgetSystem's `widget_show_item_holder_component`).

## Placement

| component | Where to place | What it does |
|---|---|---|
| `item_holder_component` | the item's entity (the same entity as `item_component`) | notifies when the holder (whoever `Rule` selects) is attached or removed. Re-checks whenever the equip state or the inventory changes |
| `item_holder_friend_component` | directly under the item entity carrying `item_holder_component` (an entity with no look; one per type) | while the owner has an item of this type equipped, they also count as the holder of the parent item (when the parent's `Rule` is `Equipped`) |
| `item_grant_component` (GrantKit) | wherever the activation signal arrives (for the game flow, the node's entity or a descendant) | on activation, grants the child items to every player (only to the owner when placed under one). With `RevokeOnDeactivate`, takes them back on the deactivation signal |
| `item_grant_entry_component` (GrantKit) | directly under the entity of `item_grant_component` (one per kind) | one kind of item to grant and its count |
| `exclusive_item_component` (ExclusiveKit) | the item's entity (the same entity as `item_component`) | limits items of the same type to one per player |
| `item_equip_lock_component` (RuleKit) | the item's entity (the same entity as `item_component`) | prevents unequipping while locked |

Example: "when the node is entered, give everyone one jetpack; take it back when the node is left"
```
Node (game_node_component)
└ Grant (item_grant_component, RevokeOnDeactivate on)
  └ Jetpack (item_grant_entry_component, Item = the jetpack item prefab)
```
On the item prefab side, attach `item_component` + `item_holder_component` (`Equipped`) + `exclusive_item_component` + `item_equip_lock_component`, plus the ability (`jetpack_ability_component`, etc.) + `ability_grant_item_component`.

## Settings (@editable)
- `item_holder_component.Rule : item_holder_rule = item_holder_rule.Equipped` — who counts as the holder. `Owned`: while the item is in the inventory (even while another item is equipped); `Equipped`: while it is equipped.
- `item_holder_friend_component.ItemType : castable_concrete_subtype(entity) = entity` — the prefab type of the item counted together. Left at the default entity it counts any item, so always choose one.
- `item_grant_component.PickMode : item_grant_pick_mode = item_grant_pick_mode.All` — `All` grants every child item; `Random` grants `RandomCount` items, re-picked for each recipient.
- `item_grant_component.RandomCount : int = 1` — how many to grant with `Random` (1-100). If more than the number of children, all are granted.
- `item_grant_component.Destination : item_grant_destination = item_grant_destination.Root` — `Root`: the player's root inventory (`FindRootInventory`; distributed to the place matching the kind); `WeaponHotbar`: the weapon hotbar (`FindWeaponHotbar`; where it can be held).
- `item_grant_component.RevokeOnDeactivate : logic = false` — when on, takes the granted items back on the deactivation signal (they are added without merging into existing stacks so they can be taken back).
- `item_grant_entry_component.Item : concrete_subtype(entity) = entity` — the prefab of the item to grant. Left at the default entity, nothing is granted.
- `item_grant_entry_component.Count : int = 1` — how many to grant (1-100). Identical items may be merged.
- `exclusive_item_component.ItemType : castable_concrete_subtype(entity) = entity` — the prefab type of the item limited to one per player. Usually this item's own prefab. Left at the default entity, nothing enters while any item is held.

## Events
This System sends no scene_event.
- listenable (cannot be Signaled from outside)
  - `item_holder_component.HolderAddedEvent : listenable(agent)` — fires with the agent when a holder is attached.
  - `item_holder_component.HolderRemovedEvent : listenable(agent)` — fires with the removed agent when the holder is removed (dropped, destroyed, or the end of the simulation).
  - `item_equip_lock_component.ChangedEvent : listenable(logic)` — fires with the new state (true = locked) when the lock state changes (the count crosses between 0 and 1).
- Received
  - `item_grant_component` receives `activated_event` (grants to everyone) and `deactivated_event` (takes back with `RevokeOnDeactivate`).
  - `exclusive_item_component` receives `add_item_query_event` (refuses entering the inventory of someone who already has the same type, with `item_exclusive_error`).
  - `item_equip_lock_component` receives `unequip_item_query_event` (refuses unequipping while locked, with `item_unequip_locked_error`).

## Owner
Placed under a player's slot (inside a LoadoutSystem loadout, inside a CharacterSystem character, etc.; anywhere `Entity.FindOwningPlayer[]` succeeds), it affects the owner instead of everyone.
- `item_grant_component`: on the activation signal, grants only to the owner (not to other players). When `GrantToAgent` is called from code, grants to the agent passed in.

Note that the item "holder" (`item_holder_component`) and `FindOwnerAgent` look for the first agent walking up the parents from the item's entity, which is different from the slot owner (PlayerSystem's `FindOwningPlayer`).

## Public API
```verse
# Holder
item_holder_rule<public> := enum:
    Owned
    Equipped

item_holder_component<public> := class<final_super>(component):
    Rule<public>:item_holder_rule
    var<private> Holder<public>:?agent                     # the current holder. false when there is none
    HolderAddedEvent<public><final>:listenable(agent)
    HolderRemovedEvent<public><final>:listenable(agent)
    FindHolder<public>()<decides><transacts>:agent

item_holder_friend_component<public> := class<final_super>(component):
    ItemType<public>:castable_concrete_subtype(entity)

# Inventory and item helpers
(Agent:agent).GetRootInventories<public>()<transacts>:[]inventory_component   # every non-nested inventory (order unspecified)
(Agent:agent).FindRootInventory<public>()<decides><transacts>:inventory_component   # the first root
(Agent:agent).GetAgentItems<public>()<transacts>:[]entity
(Agent:agent).GetAgentEquippedItems<public>():[]entity          # cannot be called inside <decides> / <transacts>
(Agent:agent).FindWeaponHotbar<public>()<decides><transacts>:inventory_component
(InEntity:entity).FindOwnerAgent<public>()<decides><reads>:agent # the first agent walking up the parents
(Item:item_component).FindEquippedOwner<public>()<decides><reads>:agent
(Item:item_component).AwaitHolderChange<public>()<suspends>:void # waits until the equip state or the inventory changes
(Agent:agent).AwaitAnyEquipChange<public>()<suspends>:void       # never returns without an inventory
(Item:entity).RemoveFromInventory<public>():void                 # removes from the inventory and destroys
(Item:entity).ConsumeOne<public>():void                          # decrements the stack by 1. The last one is removed and destroyed
(InEntity:entity).BeginItemAbilities<public>(Agent:agent):[]ability_effect   # uses the abilities of fort_item_ability_component
EndItemAbilities<public>(Effects:[]ability_effect):void

# GrantKit
item_grant_pick_mode<public> := enum:
    All
    Random

item_grant_destination<public> := enum:
    Root
    WeaponHotbar

item_grant_component<public> := class<final_super>(component):
    PickMode<public>:item_grant_pick_mode
    RandomCount<public>:int
    Destination<public>:item_grant_destination
    RevokeOnDeactivate<public>:logic
    GrantToAgent<public>(Agent:agent)<transacts>:void           # grants to one agent (no activation signal needed; re-picked on every call)
    RevokeAll<public>()<transacts>:void                         # takes back from everyone the items granted and remembered under RevokeOnDeactivate
    RevokeFrom<public>(Agent:agent)<transacts>:void

item_grant_entry_component<public> := class<final_super>(component):
    Item<public>:concrete_subtype(entity)
    Count<public>:int

# ExclusiveKit
item_exclusive_error<public> := class<computes>(add_item_error):

exclusive_item_component<public> := class<final_super>(component):
    ItemType<public>:castable_concrete_subtype(entity)

# RuleKit
item_unequip_locked_error<public> := class<computes>(unequip_item_error):

item_equip_lock_component<public> := class<final_super>(component):
    ChangedEvent<public><final>:listenable(logic)
    Lock<public>():void                                         # increments the count by 1
    Unlock<public>():void                                       # decrements the count by 1. At 0 the item can be unequipped again
    IsLocked<public>()<decides><transacts>:void
```

## Requirements, caveats and limits
- A player has several inventories (weapon hotbar, building, materials, ammo, ...). `FindRootInventory` returns the first root; with several roots, which one is returned is unspecified. When you need a specific inventory, pick it by type from `GetRootInventories` or use `FindWeaponHotbar`.
- `FindOwnerAgent` assumes the entity of an item inside an inventory is a descendant of its owner. It fails for items lying on the ground or not yet granted.
- `AwaitAnyEquipChange` watches only the single inventory returned by `FindRootInventory`. With several roots, equip changes in another root do not arrive.
- `item_holder_component` waits one frame after a change notification before checking again (so changes arriving back to back in the same frame are not missed).
- `item_grant_component` grants to every player of the playspace (`GetPlayers`), not of a zone. Late joiners are not granted automatically; to do so, call `GrantToAgent` on the join notification (`PlayerAddedEvent` of `player_manager_component`, etc.). Nothing happens for players without a destination, and items that did not enter (`exclusive_item_component` etc.) do not report failure either.
- `item_grant_component` can only take back items granted while `RevokeOnDeactivate` was on (items no longer held are skipped).
- Call `Lock` / `Unlock` of `item_equip_lock_component` in pairs. It does not stop removal from the inventory (`RemoveItem`; the item disappearing). The lock is released when the simulation ends. `jetpack_ability_component` (JetpackSystem) locks through it during charge and launch when it is on the same entity.

## Verifying
- Test: `item_system_test_component` in `_Test/ItemSystemTest/`. Placement:
  - one entity with `player_manager_component`
  - attach `item_system_test_component` to a test entity and choose a test item prefab in `TestItem`
  - the test item prefab carries `item_component`, `item_holder_component` (`Rule` = `Owned`) and `item_equip_lock_component`. It must be non-stackable (when `TestItem` is left at the default entity, the steps that use an item are skipped)

  Checks the counting of `item_equip_lock_component` and its `ChangedEvent`, finding inventories (`GetRootInventories` / `FindRootInventory` / `GetAgentEquippedItems`) and getting the input (InputSystem's `FindPlayerInput`), `item_grant_component` (created at runtime, then `GrantToAgent`), `item_holder_component` (`Owned`), that a locked item cannot be unequipped, and `ConsumeOne` / `RemoveFromInventory`. No human input needed. Finishes in a few seconds. The result is `[TEST] ItemSystem` in the output log.
- No sample (`_Samples/`).
