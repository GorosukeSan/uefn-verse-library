using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }
using { /Fortnite.com/Itemization }

# Returns every "root" inventory under Agent (one that is not inside another inventory). The order is unspecified
# Requirements: a Fortnite player has several inventories (weapon hotbar, building, materials, ammo, ...). For nested ones only the outer one is returned.
#   Only the descendants of Agent are searched (not the whole world). The items held can be reached through FindItems on these (GetAgentItems)
(Agent:agent).GetRootInventories<public>()<transacts>:[]inventory_component =
    All := for (Inventory : Agent.FindDescendantComponents(inventory_component)):
        Inventory
    for (Inventory : All, not IsNested[Inventory, All]):
        Inventory

IsNested<internal>(Inventory:inventory_component, All:[]inventory_component)<decides><transacts>:void =
    first:
        Outer : All
        Outer <> Inventory
        Inner : Outer.FindInventories()
        Inner = Inventory
    do:
        Outer

# Returns the first of Agent's root inventories (GetRootInventories). The destination when granting items or awaiting equip changes. Fails when there is none
# Requirements: with several roots, which one is returned is unspecified. When you need a specific inventory, pick it by type from GetRootInventories
(Agent:agent).FindRootInventory<public>()<decides><transacts>:inventory_component =
    Agent.GetRootInventories()[0]

# The entities of the items Agent holds (the root inventories and every inventory inside them; inventory_component.FindItems). The order is unspecified
(Agent:agent).GetAgentItems<public>()<transacts>:[]entity =
    var Items:[]entity = array{}
    for (Inventory : Agent.GetRootInventories()):
        set Items += Inventory.FindItems(item_component)
    Items

# The entities of the items Agent has equipped (GetEquippedItems of each root inventory). The order is unspecified
# GetEquippedItems cannot roll back (no_rollback), so this cannot be called inside <decides> / <transacts> either. Take the result first, then inspect it in an if
(Agent:agent).GetAgentEquippedItems<public>():[]entity =
    var Items:[]entity = array{}
    for (Inventory : Agent.GetRootInventories()):
        set Items += Inventory.GetEquippedItems()
    Items

# Agent's weapon hotbar (fort_inventory_weapon_hotbar_component). The destination when a weapon must reliably land somewhere it can be held. Fails when there is none
(Agent:agent).FindWeaponHotbar<public>()<decides><transacts>:inventory_component =
    Found := for (Hotbar : Agent.FindDescendantComponents(fort_inventory_weapon_hotbar_component)):
        Hotbar
    Found[0]
