using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }
using { ItemSystem }
using { InputSystem }
using { ItemSystem.GrantKit }
using { ItemSystem.RuleKit }
using { PlayerSystem }
using { SceneGraphSystem }
using { _Test }

# Role: verification of ItemSystem. Checks finding the player's inventory (GetRootInventories / FindRootInventory / GetAgentItems), getting the input (FindPlayerInput),
#   the reference counting of item_equip_lock_component, item_grant_component (created at runtime, GrantToAgent), item_holder_component (Rule = Owned), ConsumeOne / RemoveFromInventory, and that equipment cannot be removed while locked
# Test level:
#   - one entity with player_manager_component
#   - attach item_system_test_component to the test entity and choose the test item prefab in TestItem
#   - test item prefab: carries item_component, item_holder_component (Rule = Owned) and item_equip_lock_component. Not stackable
#     (if TestItem is left as the default entity, the checks that use the item are skipped)
# Human input: none
# Result: [TEST] ItemSystem in the output log
item_system_test_component<public> := class<final_super>(component):

    # Test item prefab (with item_component, item_holder_component (Owned) and item_equip_lock_component; not stackable)
    @editable
    TestItem<public>:concrete_subtype(entity) = entity

    var<private> LockChangedCount:int = 0

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "ItemSystem"}
        TestLockCount(Results)
        MaybeAgent := AwaitFirstPlayer()
        if (Agent := MaybeAgent?):
            TestAgentQueries(Results, Agent)
            TestGrantAndHolder(Results, Agent)
        else:
            Results.Fail("setup", "player_manager_component missing")
        if (Results.Finish[]) {}

    AwaitFirstPlayer<private>()<suspends>:?agent =
        if (Manager := Entity.FindScopedComponent[player_manager_component]):
            if (Slot := Manager.GetSlots()[0]):
                option{Slot.Player}
            else:
                Player := Manager.PlayerAddedEvent.Await()
                option{Player}
        else:
            false

    OnLockChanged<private>(Locked:logic):void =
        set LockChangedCount += 1

    TestLockCount<private>(Results:test_log):void =
        Lock := item_equip_lock_component{Entity := entity{}}
        Subscription := Lock.ChangedEvent.Subscribe(OnLockChanged)
        Results.Check("lock: unlocked at start", if (Lock.IsLocked[]) then false else true)
        Lock.Lock()
        Lock.Lock()
        Results.Check("lock: locked", if (Lock.IsLocked[]) then true else false)
        Lock.Unlock()
        Results.Check("lock: still locked after one of two Unlocks", if (Lock.IsLocked[]) then true else false)
        Lock.Unlock()
        Results.Check("lock: unlocked after both", if (Lock.IsLocked[]) then false else true)
        Lock.Unlock()
        Results.CheckInt("lock: ChangedEvent only on 0<->1 (extra Unlock ignored)", LockChangedCount, 2)
        Subscription.Cancel()

    TestAgentQueries<private>(Results:test_log, Agent:agent):void =
        Roots := Agent.GetRootInventories()
        Results.Check("GetRootInventories finds at least one", if (Roots.Length > 0) then true else false)
        Results.Check("FindRootInventory succeeds", if (Agent.FindRootInventory[]) then true else false)
        Results.Check("FindPlayerInput succeeds for a player", if (Agent.FindPlayerInput[]) then true else false)
        Equipped := Agent.GetAgentEquippedItems()
        Results.Check("GetAgentEquippedItems is a subset of GetAgentItems", AllIn(Equipped, Agent.GetAgentItems()))

    AllIn<private>(Items:[]entity, All:[]entity)<transacts>:logic =
        for (Item : Items, not All.Find[Item]):
            return false
        true

    TestGrantAndHolder<private>(Results:test_log, Agent:agent)<suspends>:void =
        if (Probe := TestItem{}, not Probe.GetComponent[item_component]):
            Print("[TEST] ItemSystem: TestItem has no item_component, skipping item tests")
            return
        GrantEntity := entity{}
        Grant := item_grant_component{Entity := GrantEntity, PickMode := item_grant_pick_mode.Random, RandomCount := 1}
        EntryEntity := entity{}
        EntryEntity.AddComponents(array{item_grant_entry_component{Entity := EntryEntity, Item := TestItem, Count := 2}})
        GrantEntity.AddComponents(array{Grant})
        GrantEntity.AddEntities(array{EntryEntity})
        Entity.AddEntities(array{GrantEntity})
        defer:
            GrantEntity.RemoveFromParent()
        TickEvents.PrePhysics.Await()

        Before := Agent.GetAgentItems()
        Grant.GrantToAgent(Agent)
        TickEvents.PrePhysics.Await()
        After := Agent.GetAgentItems()
        NewItems := for (Item : After, not Before.Find[Item]) do Item
        Results.CheckInt("GrantToAgent adds Count items (Random, RandomCount 1)", NewItems.Length, 2)
        if (First := NewItems[0], Holder := First.GetComponent[item_holder_component]):
            if (not Holder.FindHolder[]):
                AwaitWithin(Holder.HolderAddedEvent, 1.0)
            Results.Check("item_holder_component (Owned) holder is the owner", if (Holder.FindHolder[] = Agent) then true else false)
            TestLock(Results, First)
            Removed := spawn{AwaitWithin(Holder.HolderRemovedEvent, 1.0)}
            First.ConsumeOne()
            RemovedPayload := Removed.Await()
            Results.Check("ConsumeOne removes a single item (HolderRemovedEvent)", if (RemovedPayload?) then true else false)
        else:
            Results.Fail("item_holder_component", "granted item has no item_holder_component")
        for (Item : NewItems):
            if (Item.GetParent[]):
                Item.RemoveFromInventory()
        TickEvents.PrePhysics.Await()
        Left := for (Item : Agent.GetAgentItems(), NewItems.Find[Item]) do Item
        Results.CheckInt("RemoveFromInventory removes the rest", Left.Length, 0)

    TestLock<private>(Results:test_log, Item:entity):void =
        if (ItemComponent := Item.GetComponent[item_component], Lock := Item.GetComponent[item_equip_lock_component]):
            EquipResult := ItemComponent.Equip()
            if (EquipResult.GetError[]):
                Results.Fail("lock: equip the test item", "Equip failed")
                return
            Lock.Lock()
            LockedResult := ItemComponent.Unequip()
            Results.Check("lock: Unequip refused while locked", if (LockedResult.GetError[]) then true else false)
            Lock.Unlock()
            UnlockedResult := ItemComponent.Unequip()
            Results.Check("lock: Unequip allowed after Unlock", if (UnlockedResult.GetError[]) then false else true)
        else:
            Results.Fail("lock", "test item has no item_equip_lock_component")
