using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }

# Role: walks up the parents of InEntity one by one and returns the first agent found (usually the player holding the item). Returns InEntity itself when it is an agent
# Requirements: assumes the entity of an item inside an inventory is a descendant of its owner. Fails for items lying on the ground or not yet granted
(InEntity:entity).FindOwnerAgent<public>()<decides><reads>:agent =
    if (Agent := agent[InEntity]):
        Agent
    else:
        InEntity.GetParent[].FindOwnerAgent[]

# Role: returns the owner (FindOwnerAgent) of Item while it is equipped. Fails when it is not equipped or has no owner
(Item:item_component).FindEquippedOwner<public>()<decides><reads>:agent =
    Item.IsEquipped[]
    Item.Entity.FindOwnerAgent[]

# Role: waits until either the equip state (ChangeEquippedEvent) or the inventory (ChangeInventoryEvent) of Item changes
# Requirements: only notifies that something changed, not what. After it returns, check again with FindEquippedOwner / FindOwnerAgent.
#   item_holder_component waits one frame (TickEvents.PrePhysics) after this returns before checking again (so changes arriving back to back in the same frame are not missed)
(Item:item_component).AwaitHolderChange<public>()<suspends>:void =
    race:
        AwaitEquipChange(Item)
        AwaitInventoryChange(Item)

AwaitEquipChange<internal>(Item:item_component)<suspends>:void =
    Item.ChangeEquippedEvent.Await()

AwaitInventoryChange<internal>(Item:item_component)<suspends>:void =
    Item.ChangeInventoryEvent.Await()

# Role: waits until something is equipped or unequipped in Agent's inventory (FindRootInventory)
# Requirements: never returns (Sleep(Inf)) when no inventory is found at the time of the call. Use it inside a race and stop it from another branch.
#   Only the single inventory returned by FindRootInventory is watched (changes in inventories inside it propagate upward, so they arrive). With several roots, equip changes in another root do not arrive
(Agent:agent).AwaitAnyEquipChange<public>()<suspends>:void =
    if (Inventory := Agent.FindRootInventory[]):
        race:
            AwaitEquipItem(Inventory)
            AwaitUnequipItem(Inventory)
    else:
        Sleep(Inf)

AwaitEquipItem<internal>(Inventory:inventory_component)<suspends>:void =
    Inventory.EquipItemEvent.Await()

AwaitUnequipItem<internal>(Inventory:inventory_component)<suspends>:void =
    Inventory.UnequipItemEvent.Await()

# Role: removes the item's entity from its inventory and destroys it
# Requirements: when there is no item_component or the item is not in any inventory, it is simply RemoveFromParent'ed.
#   When the inventory refuses the removal (RemoveItem returned an error) nothing happens (it is not destroyed). Success is not reported
(Item:entity).RemoveFromInventory<public>():void =
    if:
        ItemComponent := Item.GetComponent[item_component]
        Inventory := ItemComponent.GetParentInventory[]
    then:
        Result := Inventory.RemoveItem(Item)
        if (Result.GetError[]):
            return
    Item.RemoveFromParent()

# Role: for a stacked item (stackable_component) decrements the count by 1; for the last one (or a non-stackable item) removes and destroys it with RemoveFromInventory
(Item:entity).ConsumeOne<public>():void =
    if (Stack := Item.GetComponent[stackable_component], Stack.StackSize > 1):
        Stack.SetStackSize(Stack.StackSize - 1)
    else:
        Item.RemoveFromInventory()
