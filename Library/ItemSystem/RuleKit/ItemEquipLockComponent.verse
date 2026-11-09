using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }

# item_equip_lock_component が、ロック中のアイテムの装備を外すのを断ったときの理由
item_unequip_locked_error<public> := class<computes>(unequip_item_error):

# 役割：ロックしているあいだ、このアイテムの装備を外させない（持ち替え・外す操作を、inventory が問い合わせる unequip_item_query_event で断る）。チャージ中など、途中で持ち替えられると困るあいだだけロックする
# 置き方：エディターで、アイテムの entity（item_component と同じ entity）に付ける
# 外から：Lock / Unlock を対で呼ぶ（回数を数え、すべて Unlock したら外せるようになる）。jetpack_ability_component はこれが同じ entity にあれば、チャージと飛び出しのあいだロックする
# 前提・注意：inventory から取り除く（RemoveItem・アイテムが消える）のは止めない。シミュレーションが終わるとロックは解ける
item_equip_lock_component<public> := class<final_super>(component):

    var<private> LockCount:int = 0

    ChangedEventInternal<private><final>:event(logic) = event(logic){}

    # ロックの状態が変わったときに、新しい状態（true = ロック中）で届く（Await / Subscribe する。外から Signal はできない）
    ChangedEvent<public><final>:listenable(logic) = MakeProxyListenable(ChangedEventInternal)

    # ロックの回数を 1 増やす。0 から 1 になったときに ChangedEvent（true）を届ける
    Lock<public>():void =
        set LockCount += 1
        if (LockCount = 1):
            ChangedEventInternal.Signal(true)

    # ロックの回数を 1 減らす。0 になったときに ChangedEvent（false）を届ける。ロックしていなければ何もしない
    Unlock<public>():void =
        if (LockCount > 0):
            set LockCount -= 1
            if (LockCount = 0):
                ChangedEventInternal.Signal(false)

    # ロックしている（Lock の回数が Unlock より多い）なら成功する
    IsLocked<public>()<decides><transacts>:void =
        LockCount > 0

    OnReceive<override>(SceneEvent:scene_event):logic =
        if:
            Query := unequip_item_query_event[SceneEvent]
            Query.Item.Entity = Entity
            IsLocked[]
        then:
            Query.AddError(item_unequip_locked_error{})
        false

    OnEndSimulation<override>():void =
        if (LockCount > 0):
            set LockCount = 0
            ChangedEventInternal.Signal(false)
        (super:)OnEndSimulation()
