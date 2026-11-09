using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }
using { ItemSystem.TooltipKit }

# The reason exclusive_item_component refused to enter the inventory of someone who already has the same type
item_exclusive_error<public> := class<computes>(add_item_error):

# Role: limits items of ItemType (the item's prefab type) to one per player. A second one does not enter the inventory of someone who already has one (cannot be picked up; not received when granted)
# Placement: attach to an entity in the editor
# Same entity: item_component
# From outside: when entering an inventory (add_item_query_event), inspects the owner's items (GetAgentItems) and refuses
exclusive_item_component<public> := class<final_super>(component):

    # The prefab type of the item limited to one per player. Usually this item's own prefab. Left at the default entity, nothing enters while any item is held
    @editable:
        ToolTip := ExclusiveItemTypeToolTip
        Categories := array{ExclusiveCategory}
    ItemType<public>:castable_concrete_subtype(entity) = entity

    OnReceive<override>(SceneEvent:scene_event):logic =
        if:
            Query := add_item_query_event[SceneEvent]
            Query.Item.Entity = Entity
            HasOtherItem[Query.Inventory]
        then:
            Query.AddError(item_exclusive_error{})
        false

    # Looks for an ItemType item other than this one among all items of the Inventory's owner (if any), otherwise inside the Inventory (FindItems)
    HasOtherItem<private>(Inventory:inventory_component)<decides><transacts>:void =
        Items := if (Agent := Inventory.Entity.FindOwnerAgent[]) then Agent.GetAgentItems() else Inventory.FindItems(item_component)
        first:
            Other : Items
            Other <> Entity
            ItemType[Other]
        do:
            Other
