using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Random }
using { /Fortnite.com/Playspaces }
using { /UnrealEngine.com/Itemization }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { ItemSystem.TooltipKit }

# What item_grant_component grants from its child items (item_grant_entry_component)
item_grant_pick_mode<public> := enum:
    # Grant every child item
    All
    # Grant RandomCount of the child items, re-picked for each recipient
    Random

# Which inventory item_grant_component puts the items into
item_grant_destination<public> := enum:
    # The player's root inventory (FindRootInventory). Items are distributed to the place matching their kind
    Root
    # The weapon hotbar (FindWeaponHotbar). Reliably lands somewhere it can be held
    WeaponHotbar

# Role: when activated, grants the child items selected by PickMode to every player (only to the owner when the entity has one)
# Placement: attach to an entity in the editor
# Parent: wherever the activation signal arrives (for the game flow, the node's entity or a descendant)
# Children: one entity with item_grant_entry_component each, directly under it
# When: grants to everyone on the activation signal (activated_event). With RevokeOnDeactivate, takes the granted items back on the deactivation signal (deactivated_event) (granted items are added without merging into existing stacks)
# From outside: to grant to a single player call GrantToAgent (no activation signal needed). Late joiners are not granted automatically; to do so, call GrantToAgent on the join notification (PlayerAddedEvent of player_manager_component, etc.)
item_grant_component<public> := class<final_super>(component):

    # What to grant from the child items. All: everything; Random: RandomCount items re-picked per player. Default All
    @editable:
        ToolTip := ItemGrantPickModeToolTip
        Categories := array{ItemGrantCategory, ItemGrantPickCategory}
    PickMode<public>:item_grant_pick_mode = item_grant_pick_mode.All
    # How many to grant when PickMode is Random (1-100). If more than the number of children, all are granted. Default 1
    @editable_number(int):
        ToolTip := ItemGrantRandomCountToolTip
        Categories := array{ItemGrantCategory, ItemGrantPickCategory}
        MinValue := option{1}
        MaxValue := option{100}
    RandomCount<public>:int = 1
    # The inventory to put items into. Root: the inventory (to the place matching the kind); WeaponHotbar: the weapon hotbar. Default Root
    @editable:
        ToolTip := ItemGrantDestinationToolTip
        Categories := array{ItemGrantCategory}
    Destination<public>:item_grant_destination = item_grant_destination.Root
    # When true, takes the granted items back on the deactivation signal (they are added without merging into existing stacks so they can be taken back). Default false
    @editable:
        ToolTip := ItemGrantRevokeOnDeactivateToolTip
        Categories := array{ItemGrantCategory}
    RevokeOnDeactivate<public>:logic = false

    var<private> Granted:[agent][]entity = map{}

    # Grants the child items to a single Agent with the same selection as on activation (re-picked on every call; with Random, each call may give different items).
    # Does nothing when Agent's inventory (FindRootInventory) is not found. Items that did not enter (exclusive_item_component etc.) do not report failure either
    GrantToAgent<public>(Agent:agent)<transacts>:void =
        if (Inventory := FindDestination[Agent]):
            for (Entry : PickEntries()):
                Items := Entry.GrantTo(Inventory, RevokeOnDeactivate)
                if (RevokeOnDeactivate?):
                    Previous := if (Known := Granted[Agent]) then Known else array{}
                    if (set Granted[Agent] = Previous + Items) {}

    # Takes back from everyone the items this component granted and remembered under RevokeOnDeactivate (items no longer held are skipped)
    RevokeAll<public>()<transacts>:void =
        for (Agent -> Items : Granted):
            RevokeItems(Items)
        set Granted = map{}

    # Takes back the items this component granted to Agent and remembered under RevokeOnDeactivate
    RevokeFrom<public>(Agent:agent)<transacts>:void =
        if (Items := Granted[Agent]):
            RevokeItems(Items)
            set Granted = Granted.RemoveKey(Agent)

    RevokeItems<private>(Items:[]entity)<transacts>:void =
        for (Item : Items, Holder := Item.GetComponent[item_component], Inventory := Holder.GetParentInventory[]):
            Inventory.RemoveItem(Item)

    FindDestination<private>(Agent:agent)<decides><transacts>:inventory_component =
        case (Destination):
            item_grant_destination.WeaponHotbar => Agent.FindWeaponHotbar[]
            item_grant_destination.Root => Agent.FindRootInventory[]

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            GrantToAll()
        else if (deactivated_event[SceneEvent], RevokeOnDeactivate?):
            RevokeAll()
        false

    GrantToAll<private>()<transacts>:void =
        if (OwningPlayer := Entity.FindOwningPlayer[]):
            # An entity with an owner (inside a character, etc.): grant only to the owner
            GrantToAgent(OwningPlayer)
        else if (Playspace := Entity.GetPlayspaceForEntity[]):
            for (Player : Playspace.GetPlayers()):
                GrantToAgent(Player)

    PickEntries<private>()<transacts>:[]item_grant_entry_component =
        Entries := Entity.GetChildComponents(item_grant_entry_component)
        case (PickMode):
            item_grant_pick_mode.All => Entries
            item_grant_pick_mode.Random =>
                Shuffled := Shuffle(Entries)
                if (Picked := Shuffled.Slice[0, Min(RandomCount, Shuffled.Length)]) then Picked else array{}
