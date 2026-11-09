using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SceneGraphSystem }

# プレイヤーが参加して slot ができた知らせ
# 方向：区画全体（SendScoped。区画が無ければ世界全体）
# 送り手：player_manager_component。受け手：参加者数・slot を見る component（人数の条件など）。消費しない
# 前提：slot はこの知らせより前に作られている（受けた側で FindSlot が成功する）
player_added_event<public> := class(scene_event):
    # 送った player_manager_component
    Manager<public>:player_manager_component
    # 参加した人（player。slot を探すときは player[Agent] で戻す）
    Agent<public>:agent

# プレイヤーが退出して slot が消えた知らせ
# 方向：区画全体（SendScoped。区画が無ければ世界全体）
# 送り手：player_manager_component。受け手：参加者数・slot を見る component。消費しない
# 前提：slot はこの知らせより前に消されている（受けた側で FindSlot は失敗する）
player_removed_event<public> := class(scene_event):
    # 送った player_manager_component
    Manager<public>:player_manager_component
    # 退出した人
    Agent<public>:agent

# 役割：参加したプレイヤーごとに slot の entity を子に作り、退出で消す。参加と退出を全体へ知らせる
# 置き方：エディターで entity に付ける。区画（または世界）に 1 つ（ほかの部品から FindScopedComponent で探される）
# 知らせ：参加は player_added_event、退出は player_removed_event を区画全体へ送る。実行時に作った entity のコードは、同じタイミングで Signal される PlayerAddedEvent / PlayerRemovedEvent を Await / Subscribe できる
# 前提・注意：シミュレーション開始の時点ですでにいるプレイヤーの slot は、この component の OnBeginSimulation の中で作られ、そのときの知らせ（scene event・event とも）は、まだ購読していない相手には届かない。あとから購読するコードは、先に GetSlots で今いる人を見てから、PlayerAddedEvent を待つ
player_manager_component<public> := class<final_super>(component):

    PlayerAddedEventInternal<private><final>:event(player) = event(player){}
    PlayerRemovedEventInternal<private><final>:event(player) = event(player){}

    # 参加して slot ができたあとに、その人で届く（Await / Subscribe する。外から Signal はできない）
    PlayerAddedEvent<public><final>:listenable(player) = MakeProxyListenable(PlayerAddedEventInternal)

    # 退出して slot が消えたあとに、その人で届く（Await / Subscribe する。外から Signal はできない）
    PlayerRemovedEvent<public><final>:listenable(player) = MakeProxyListenable(PlayerRemovedEventInternal)

    var PlayerSubscription<private>:?cancelable = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set PlayerSubscription = Entity.SubscribePlayers(OnPlayerAdded, OnPlayerRemoved)

    OnEndSimulation<override>():void =
        PlayerSubscription.CancelIfSet()
        set PlayerSubscription = false
        (super:)OnEndSimulation()

    # 今いる slot の数（直下の player_slot_component の数）。参加の処理より前（OnBeginSimulation の前）は 0
    GetPlayerCount<public>()<reads>:int =
        Entity.GetChildComponents(player_slot_component).Length

    # 今いる全員の slot（直下の player_slot_component。並び順は決まっていない）。参加の処理より前は空
    GetSlots<public>()<reads>:[]player_slot_component =
        Entity.GetChildComponents(player_slot_component)

    # Player の slot を探す。slot は実行時に作られるので、その人の参加の処理より前（player_added_event / PlayerAddedEvent より前）と、退出のあとは失敗する
    FindSlot<public>(Player:player)<decides><reads>:player_slot_component =
        first:
            Slot : Entity.GetChildComponents(player_slot_component)
            Slot.Player = Player
        do:
            Slot

    OnPlayerAdded<private>(Player:player):void =
        if (FindSlot[Player]):
            return
        SlotEntity := entity{}
        SlotEntity.AddComponents(array{player_slot_component{Entity := SlotEntity, Player := Player}})
        Entity.AddEntities(array{SlotEntity})
        Entity.SendScoped(player_added_event{Manager := Self, Agent := Player})
        PlayerAddedEventInternal.Signal(Player)

    OnPlayerRemoved<private>(Player:player):void =
        if (Slot := FindSlot[Player]):
            Slot.Entity.RemoveFromParent()
            Entity.SendScoped(player_removed_event{Manager := Self, Agent := Player})
            PlayerRemovedEventInternal.Signal(Player)
