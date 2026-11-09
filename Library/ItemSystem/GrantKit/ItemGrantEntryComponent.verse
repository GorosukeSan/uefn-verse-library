using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }
using { ItemSystem.TooltipKit }

# 役割：配るアイテム 1 種類（Item）と個数（Count）を表す
# 置き方：エディターで entity に付ける
# 親：item_grant_component の entity の直下
item_grant_entry_component<public> := class<final_super>(component):

    # 配るアイテムの prefab。既定の entity のままだと何も配らない
    @editable:
        ToolTip := ItemGrantEntryItemToolTip
        Categories := array{ItemGrantCategory, ItemGrantEntryCategory}
    Item<public>:concrete_subtype(entity) = entity
    # 配る個数（1〜100）。同じものはまとめられることがある。既定 1
    @editable_number(int):
        ToolTip := ItemGrantEntryCountToolTip
        Categories := array{ItemGrantCategory, ItemGrantEntryCategory}
        MinValue := option{1}
        MaxValue := option{100}
    Count<public>:int = 1

    # Inventory に Count 個入れ、入ったアイテムの entity を返す。Separate なら既にあるスタックとまとめない（あとで 1 つずつ回収できるように）
    GrantTo<internal>(Inventory:inventory_component, Separate:logic)<transacts>:[]entity =
        for (Index := 1..Count, NewItem := Item{}, Inventory.AddItemDistribute(NewItem, ?AllowMergeItems := not Separate?).GetSuccess[]):
            NewItem
