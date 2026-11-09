using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }
using { ItemSystem.TooltipKit }

# Role: represents one kind of item to grant (Item) and its count (Count)
# Placement: attach to an entity in the editor
# Parent: directly under the entity of item_grant_component
item_grant_entry_component<public> := class<final_super>(component):

    # The prefab of the item to grant. Left at the default entity, nothing is granted
    @editable:
        ToolTip := ItemGrantEntryItemToolTip
        Categories := array{ItemGrantCategory, ItemGrantEntryCategory}
    Item<public>:concrete_subtype(entity) = entity
    # How many to grant (1-100). Identical items may be merged. Default 1
    @editable_number(int):
        ToolTip := ItemGrantEntryCountToolTip
        Categories := array{ItemGrantCategory, ItemGrantEntryCategory}
        MinValue := option{1}
        MaxValue := option{100}
    Count<public>:int = 1

    # Puts Count items into Inventory and returns the entities that entered. With Separate they are not merged into existing stacks (so they can be taken back one by one later)
    GrantTo<internal>(Inventory:inventory_component, Separate:logic)<transacts>:[]entity =
        for (Index := 1..Count, NewItem := Item{}, Inventory.AddItemDistribute(NewItem, ?AllowMergeItems := not Separate?).GetSuccess[]):
            NewItem
