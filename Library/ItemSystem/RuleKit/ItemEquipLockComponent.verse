using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }

# The reason item_equip_lock_component refused to unequip a locked item
item_unequip_locked_error<public> := class<computes>(unequip_item_error):

# Role: while locked, prevents this item from being unequipped (refuses switching / unequipping through the unequip_item_query_event the inventory asks with). Lock only while a switch would be a problem, e.g. during a charge
# Placement: attach to the item's entity (the same entity as item_component) in the editor
# From outside: call Lock / Unlock in pairs (the count is tracked; once everything is unlocked the item can be unequipped again). jetpack_ability_component locks through this during charge and launch when it is on the same entity
# Requirements: does not stop removal from the inventory (RemoveItem; the item disappearing). The lock is released when the simulation ends
item_equip_lock_component<public> := class<final_super>(component):

    var<private> LockCount:int = 0

    ChangedEventInternal<private><final>:event(logic) = event(logic){}

    # Fires with the new state (true = locked) when the lock state changes (Await / Subscribe; cannot be Signaled from outside)
    ChangedEvent<public><final>:listenable(logic) = MakeProxyListenable(ChangedEventInternal)

    # Increments the lock count by 1. Fires ChangedEvent (true) when it goes from 0 to 1
    Lock<public>():void =
        set LockCount += 1
        if (LockCount = 1):
            ChangedEventInternal.Signal(true)

    # Decrements the lock count by 1. Fires ChangedEvent (false) when it reaches 0. Does nothing when not locked
    Unlock<public>():void =
        if (LockCount > 0):
            set LockCount -= 1
            if (LockCount = 0):
                ChangedEventInternal.Signal(false)

    # Succeeds while locked (more Lock calls than Unlock calls)
    IsLocked<public>()<decides><transacts>:void =
        LockCount > 0

    OnReceive<override>(SceneEvent:scene_event):logic =
        if:
            Query := unequip_item_query_event[SceneEvent]
            Query.Item.Entity = Entity
            IsLocked[]
        then:
            Query.AddError(item_unequip_locked_error{})
        false

    OnEndSimulation<override>():void =
        if (LockCount > 0):
            set LockCount = 0
            ChangedEventInternal.Signal(false)
        (super:)OnEndSimulation()
