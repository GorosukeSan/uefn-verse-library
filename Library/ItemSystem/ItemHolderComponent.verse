using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }
using { SceneGraphSystem }
using { ItemSystem.TooltipKit }

# だれをアイテムの「持ち手」とみなすか
item_holder_rule<public> := enum:
    # 手持ちにあるあいだ（ほかのアイテムを装備していても）、持ち主
    Owned
    # 装備しているあいだ、装備している持ち主。子に item_holder_friend_component があれば、そのアイテムを装備しているあいだも
    Equipped

# 役割：アイテムの持ち手（Rule で決める人）が付いたり外れたりするのを見張り、HolderAddedEvent / HolderRemovedEvent で知らせる。装備や inventory が変わるたびに調べ直す
# 置き方：エディターで、アイテムの entity に付ける。持ち手で動くもの（ability_grant_item_component・widget_show_item_holder_component など）は、同じ entity でこれを見る
# 同じ entity：item_component
# 子：Rule が Equipped のとき、一緒に数えるアイテムの種類ごとに item_holder_friend_component を付けた entity（任意）
item_holder_component<public> := class<final_super>(component):

    # だれを持ち手とみなすか。Owned は手持ちにあるあいだ、Equipped は装備しているあいだ。既定 Equipped
    @editable:
        ToolTip := ItemHolderRuleToolTip
        Categories := array{ItemHolderCategory}
    Rule<public>:item_holder_rule = item_holder_rule.Equipped

    # 今の持ち手。いなければ false
    var<private> Holder<public>:?agent = false

    HolderAddedEventInternal<private><final>:event(agent) = event(agent){}
    HolderRemovedEventInternal<private><final>:event(agent) = event(agent){}

    # 持ち手が付いたときに、その人で届く（Await / Subscribe する。外から Signal はできない）
    HolderAddedEvent<public><final>:listenable(agent) = MakeProxyListenable(HolderAddedEventInternal)

    # 持ち手が外れたとき（手放した・消えた・シミュレーションの終わりも）に、外れた人で届く
    HolderRemovedEvent<public><final>:listenable(agent) = MakeProxyListenable(HolderRemovedEventInternal)

    OnSimulate<override>()<suspends>:void =
        if (Item := Entity.GetComponent[item_component]):
            loop:
                UpdateHolder(Item)
                AwaitHolderCheck(Item)
                # 知らせのあと 1 フレーム待ってから調べ直す（同じフレームに続けて来た変化の取りこぼし対策）
                TickEvents.PrePhysics.Await()

    OnEndSimulation<override>():void =
        SetHolder(false)
        (super:)OnEndSimulation()

    # 今の持ち手がいれば返す。いなければ失敗する
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

# 役割：item_holder_component（Rule が Equipped）の持ち手に、一緒に数えるアイテムの種類。持ち主がこの種類のアイテムを装備しているあいだも、親のアイテムの持ち手とみなす
# 置き方：エディターで entity に付ける（見た目の無い entity）
# 親：item_holder_component を付けたアイテムの entity（直下に、種類ごとに 1 つずつ）
item_holder_friend_component<public> := class<final_super>(component):

    # 一緒に数えるアイテムの prefab の型。既定の entity のままだと、どのアイテムでも数えるので必ず選ぶ
    @editable:
        ToolTip := ItemHolderFriendItemTypeToolTip
        Categories := array{ItemHolderCategory}
    ItemType<public>:castable_concrete_subtype(entity) = entity
