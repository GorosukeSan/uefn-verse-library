using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }
using { /Fortnite.com/Itemization }

# Agent の配下にある「根」の inventory（ほかの inventory の中に入っていないもの）をすべて返す。並び順は決まっていない
# 前提・注意：Fortnite のプレイヤーには inventory が複数ある（武器のホットバー・建築・素材・弾薬など）。入れ子になっているものは、外側だけを返す。
#   探すのは Agent の配下だけ（世界全体は探さない）。持っているアイテムは、これらの FindItems でたどれる（GetAgentItems）
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

# Agent の根の inventory（GetRootInventories）の 1 つ目を返す。アイテムを配る・装備の変化を待つときの入れ先。無ければ失敗する
# 前提・注意：根が複数あるときは、どれが返るかは決まらない。特定の inventory が要るときは GetRootInventories から型で選ぶ
(Agent:agent).FindRootInventory<public>()<decides><transacts>:inventory_component =
    Agent.GetRootInventories()[0]

# Agent が持っているアイテムの entity（根の inventory とその中の inventory すべて。inventory_component.FindItems）。並び順は決まっていない
(Agent:agent).GetAgentItems<public>()<transacts>:[]entity =
    var Items:[]entity = array{}
    for (Inventory : Agent.GetRootInventories()):
        set Items += Inventory.FindItems(item_component)
    Items

# Agent が装備しているアイテムの entity（根の inventory ごとの GetEquippedItems）。並び順は決まっていない
# GetEquippedItems が巻き戻せない（no_rollback）ので、これも <decides> / <transacts> の中では呼べない。先に受けてから if で調べる
(Agent:agent).GetAgentEquippedItems<public>():[]entity =
    var Items:[]entity = array{}
    for (Inventory : Agent.GetRootInventories()):
        set Items += Inventory.GetEquippedItems()
    Items

# Agent の武器のホットバー（fort_inventory_weapon_hotbar_component）。武器を「手に持てる場所」へ確実に入れたいときの入れ先。無ければ失敗する
(Agent:agent).FindWeaponHotbar<public>()<decides><transacts>:inventory_component =
    Found := for (Hotbar : Agent.FindDescendantComponents(fort_inventory_weapon_hotbar_component)):
        Hotbar
    Found[0]
