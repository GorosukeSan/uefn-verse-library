using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }

# 役割：InEntity から親を 1 つずつたどり、最初に見つかった agent（ふつうはアイテムを持っているプレイヤー）を返す。InEntity 自身が agent ならそれを返す
# 前提・注意：inventory に入っているアイテムの entity は持ち主の子孫になる前提。地面に落ちている・まだ配られていないアイテムでは失敗する
(InEntity:entity).FindOwnerAgent<public>()<decides><reads>:agent =
    if (Agent := agent[InEntity]):
        Agent
    else:
        InEntity.GetParent[].FindOwnerAgent[]

# 役割：Item が装備されているとき、その持ち主（FindOwnerAgent）を返す。装備されていない・持ち主がいないと失敗する
(Item:item_component).FindEquippedOwner<public>()<decides><reads>:agent =
    Item.IsEquipped[]
    Item.Entity.FindOwnerAgent[]

# 役割：Item の装備（ChangeEquippedEvent）か inventory（ChangeInventoryEvent）のどちらかが変わるまで待つ
# 前提・注意：変わったことだけを知らせ、何が変わったかは返さない。戻ったあとに FindEquippedOwner / FindOwnerAgent で調べ直す。
#   item_holder_component は、これが戻ったあと 1 フレーム（TickEvents.PrePhysics）待ってから調べ直す（同じフレームに続けて来た変化の取りこぼし対策）
(Item:item_component).AwaitHolderChange<public>()<suspends>:void =
    race:
        AwaitEquipChange(Item)
        AwaitInventoryChange(Item)

AwaitEquipChange<internal>(Item:item_component)<suspends>:void =
    Item.ChangeEquippedEvent.Await()

AwaitInventoryChange<internal>(Item:item_component)<suspends>:void =
    Item.ChangeInventoryEvent.Await()

# 役割：Agent の inventory（FindRootInventory）で、何かが装備される・外されるまで待つ
# 前提・注意：呼んだ時点で inventory が見つからないと、ずっと戻らない（Sleep(Inf)）。race の中で使い、ほかの枝で止める。
#   見る inventory は FindRootInventory が返す 1 つだけ（その中の inventory の変化は上へ伝わるので届く）。根が複数あると、別の根での装備の変化は届かない
(Agent:agent).AwaitAnyEquipChange<public>()<suspends>:void =
    if (Inventory := Agent.FindRootInventory[]):
        race:
            AwaitEquipItem(Inventory)
            AwaitUnequipItem(Inventory)
    else:
        Sleep(Inf)

AwaitEquipItem<internal>(Inventory:inventory_component)<suspends>:void =
    Inventory.EquipItemEvent.Await()

AwaitUnequipItem<internal>(Inventory:inventory_component)<suspends>:void =
    Inventory.UnequipItemEvent.Await()

# 役割：アイテムの entity を inventory から外して消す
# 前提・注意：item_component が無い・どの inventory にも入っていないときは、そのまま RemoveFromParent する。
#   inventory が外すのを断った（RemoveItem がエラーを返した）ときは何もしない（消さない）。成功したかは返さない
(Item:entity).RemoveFromInventory<public>():void =
    if:
        ItemComponent := Item.GetComponent[item_component]
        Inventory := ItemComponent.GetParentInventory[]
    then:
        Result := Inventory.RemoveItem(Item)
        if (Result.GetError[]):
            return
    Item.RemoveFromParent()

# 役割：重ねて持っているアイテム（stackable_component）なら数を 1 減らし、最後の 1 つ（または重ねられないアイテム）なら RemoveFromInventory で外して消す
(Item:entity).ConsumeOne<public>():void =
    if (Stack := Item.GetComponent[stackable_component], Stack.StackSize > 1):
        Stack.SetStackSize(Stack.StackSize - 1)
    else:
        Item.RemoveFromInventory()
