using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }
using { SceneGraphSystem }
using { ItemSystem.TooltipKit }

# Who counts as the "holder" of the item
item_holder_rule<public> := enum:
    # The owner, while the item is in their inventory (even while another item is equipped)
    Owned
    # The owner, while the item is equipped. With item_holder_friend_component children, also while one of those items is equipped
    Equipped

# Role: watches the item's holder (whoever Rule selects) being attached or removed and notifies through HolderAddedEvent / HolderRemovedEvent. Re-checks whenever the equip state or the inventory changes
# Placement: attach to the item's entity in the editor. Parts driven by the holder (ability_grant_item_component, widget_show_item_holder_component, ...) look for this on the same entity
# Same entity: item_component
# Children: when Rule is Equipped, one entity with item_holder_friend_component per item type to count together (optional)
item_holder_component<public> := class<final_super>(component):

    # Who counts as the holder. Owned: while in the inventory; Equipped: while equipped. Default Equipped
    @editable:
        ToolTip := ItemHolderRuleToolTip
        Categories := array{ItemHolderCategory}
    Rule<public>:item_holder_rule = item_holder_rule.Equipped

    # The current holder. false when there is none
    var<private> Holder<public>:?agent = false

    HolderAddedEventInternal<private><final>:event(agent) = event(agent){}
    HolderRemovedEventInternal<private><final>:event(agent) = event(agent){}

    # Fires with the agent when a holder is attached (Await / Subscribe; cannot be Signaled from outside)
    HolderAddedEvent<public><final>:listenable(agent) = MakeProxyListenable(HolderAddedEventInternal)

    # Fires with the removed agent when the holder is removed (dropped, destroyed, or the end of the simulation)
    HolderRemovedEvent<public><final>:listenable(agent) = MakeProxyListenable(HolderRemovedEventInternal)

    OnSimulate<override>()<suspends>:void =
        if (Item := Entity.GetComponent[item_component]):
            loop:
                UpdateHolder(Item)
                AwaitHolderCheck(Item)
                # Wait one frame after the notification before checking again (so changes arriving back to back in the same frame are not missed)
                TickEvents.PrePhysics.Await()

    OnEndSimulation<override>():void =
        SetHolder(false)
        (super:)OnEndSimulation()

    # Returns the current holder if there is one. Fails otherwise
    FindHolder<public>()<decides><transacts>:agent =
        Holder?

    AwaitHolderCheck<private>(Item:item_component)<suspends>:void =
        if (Rule = item_holder_rule.Equipped, Entity.GetChildComponents(item_holder_friend_component).Length > 0, Agent := Item.Entity.FindOwnerAgent[]):
            race:
                Item.AwaitHolderChange()
                Agent.AwaitAnyEquipChange()
        else:
            Item.AwaitHolderChange()

    ComputeHolder<private>(Item:item_component)<decides><transacts>:agent =
        Agent := Item.Entity.FindOwnerAgent[]
        case (Rule):
            item_holder_rule.Owned => Agent
            item_holder_rule.Equipped =>
                Item.IsEquipped[] or HoldsFriendItem[Agent]
                Agent

    HoldsFriendItem<private>(Agent:agent)<decides><transacts>:void =
        Friends := Entity.GetChildComponents(item_holder_friend_component)
        Friends.Length > 0
        Inventory := Agent.FindRootInventory[]
        first:
            Other : Inventory.FindItems(item_component)
            Other.GetComponent[item_component].IsEquipped[]
            Friend : Friends
            Friend.ItemType[Other]
        do:
            Other

    UpdateHolder<private>(Item:item_component):void =
        if (Agent := ComputeHolder[Item]):
            SetHolder(option{Agent})
        else:
            SetHolder(false)

    SetHolder<private>(NewHolder:?agent):void =
        if (Current := Holder?, Next := NewHolder?, Current = Next):
            return
        if (Current := Holder?):
            set Holder = false
            HolderRemovedEventInternal.Signal(Current)
        if (Next := NewHolder?):
            set Holder = NewHolder
            HolderAddedEventInternal.Signal(Next)

# Role: an item type counted together for the holder of item_holder_component (Rule = Equipped). While the owner has an item of this type equipped, they also count as the holder of the parent item
# Placement: attach to an entity in the editor (an entity with no look)
# Parent: the item entity carrying item_holder_component (directly under it, one per type)
item_holder_friend_component<public> := class<final_super>(component):

    # The prefab type of the item counted together. Left at the default entity it counts any item, so always choose one
    @editable:
        ToolTip := ItemHolderFriendItemTypeToolTip
        Categories := array{ItemHolderCategory}
    ItemType<public>:castable_concrete_subtype(entity) = entity
