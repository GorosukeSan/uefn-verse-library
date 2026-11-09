using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Random }
using { /Fortnite.com/Playspaces }
using { /UnrealEngine.com/Itemization }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { ItemSystem.TooltipKit }

# item_grant_component が、子のアイテム（item_grant_entry_component）から何を配るか
item_grant_pick_mode<public> := enum:
    # 子のアイテムをすべて配る
    All
    # 子のアイテムから RandomCount 個を、配る人ごとに選び直して配る
    Random

# item_grant_component が、アイテムをどの inventory に入れるか
item_grant_destination<public> := enum:
    # プレイヤーの根の inventory（FindRootInventory）。種類に合った場所へ振り分けられる
    Root
    # 武器のホットバー（FindWeaponHotbar）。手に持てる場所へ確実に入れる
    WeaponHotbar

# 役割：起動したとき、子のアイテムから PickMode で選んだものを全プレイヤーに配る（持ち主のいる entity なら持ち主にだけ）
# 置き方：エディターで entity に付ける
# 親：起動の合図が届く場所（ゲームの流れなら、ノードの entity かその子孫）
# 子：item_grant_entry_component を付けた entity を、直下に 1 つずつ
# いつ：起動の合図（activated_event）で全員に配る。RevokeOnDeactivate なら、停止の合図（deactivated_event）で配った物を回収する（配った物は既にあるスタックとまとめずに入れる）
# 外から：1 人だけに配るときは GrantToAgent を呼ぶ（起動の合図は要らない）。途中参加の人には自動では配らないので、配りたいときは参加の知らせ（player_manager_component の PlayerAddedEvent など）を受けて GrantToAgent を呼ぶ
item_grant_component<public> := class<final_super>(component):

    # 子のアイテムから何を配るか。All はすべて、Random は RandomCount 個を人ごとに選び直す。既定 All
    @editable:
        ToolTip := ItemGrantPickModeToolTip
        Categories := array{ItemGrantCategory, ItemGrantPickCategory}
    PickMode<public>:item_grant_pick_mode = item_grant_pick_mode.All
    # PickMode が Random のときに配る数（1〜100）。子の数より多ければ全部配る。既定 1
    @editable_number(int):
        ToolTip := ItemGrantRandomCountToolTip
        Categories := array{ItemGrantCategory, ItemGrantPickCategory}
        MinValue := option{1}
        MaxValue := option{100}
    RandomCount<public>:int = 1
    # 入れる inventory。Root は持ち物（種類に合った場所へ）、WeaponHotbar は武器のホットバー。既定 Root
    @editable:
        ToolTip := ItemGrantDestinationToolTip
        Categories := array{ItemGrantCategory}
    Destination<public>:item_grant_destination = item_grant_destination.Root
    # true なら停止の合図で配った物を回収する（回収できるよう、既にあるスタックとまとめずに入れる）。既定 false
    @editable:
        ToolTip := ItemGrantRevokeOnDeactivateToolTip
        Categories := array{ItemGrantCategory}
    RevokeOnDeactivate<public>:logic = false

    var<private> Granted:[agent][]entity = map{}

    # Agent 1 人に、起動したときと同じ選び方で子のアイテムを配る（呼ぶたびに選び直す。Random なら呼ぶたびに違うものになりうる）。
    # Agent の inventory（FindRootInventory）が見つからないときは何もしない。exclusive_item_component などで入らなかったアイテムも、失敗は返さない
    GrantToAgent<public>(Agent:agent)<transacts>:void =
        if (Inventory := FindDestination[Agent]):
            for (Entry : PickEntries()):
                Items := Entry.GrantTo(Inventory, RevokeOnDeactivate)
                if (RevokeOnDeactivate?):
                    Previous := if (Known := Granted[Agent]) then Known else array{}
                    if (set Granted[Agent] = Previous + Items) {}

    # このcomponent が RevokeOnDeactivate で配って覚えている物を、全員から回収する（もう持っていない物は飛ばす）
    RevokeAll<public>()<transacts>:void =
        for (Agent -> Items : Granted):
            RevokeItems(Items)
        set Granted = map{}

    # このcomponent が RevokeOnDeactivate で Agent に配って覚えている物を回収する
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
            # 持ち主のいる entity（キャラクターの中など）なら、持ち主にだけ配る
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
