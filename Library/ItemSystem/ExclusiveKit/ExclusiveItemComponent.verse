using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }
using { ItemSystem.TooltipKit }

# exclusive_item_component が、すでに同じ種類を持っている人の inventory に入るのを断ったときの理由
item_exclusive_error<public> := class<computes>(add_item_error):

# 役割：ItemType（アイテムの prefab の型）のアイテムを 1 人 1 つまでにする。すでに持っている人の inventory には 2 つ目が入らない（拾えない・配られても入らない）
# 置き方：エディターで entity に付ける
# 同じ entity：item_component
# 外から：inventory に入るとき（add_item_query_event）に、持ち主のアイテム（GetAgentItems）を調べて断る
exclusive_item_component<public> := class<final_super>(component):

    # 1 人 1 つまでにするアイテムの prefab の型。ふつうはこのアイテム自身の prefab。既定の entity のままだと、どのアイテムを持っていても入らない
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

    # Inventory の持ち主（いれば）の持ち物すべて、いなければ Inventory の中（FindItems）から、自分以外の ItemType のアイテムを探す
    HasOtherItem<private>(Inventory:inventory_component)<decides><transacts>:void =
        Items := if (Agent := Inventory.Entity.FindOwnerAgent[]) then Agent.GetAgentItems() else Inventory.FindItems(item_component)
        first:
            Other : Items
            Other <> Entity
            ItemType[Other]
        do:
            Other
