using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

# 役割：スイングでつかまれる物の目印。つかまれた（swing_attached_event）・振り出された（swing_pulled_event）・外れた（swing_detached_event）を受けて、AttachedEvent / PulledEvent / DetachedEvent で知らせ、今かかっているロープの点を覚える。Shatter で壊れる（つかんでいる全員のロープを swing_anchor_component.Break で途切れさせ、1 フレーム待ってから自分の entity を消す）
# 何をするかは同じ entity に置く TargetKit の component が決める（それぞれこの component の知らせを購読する）：
#   - 最初につかまれてから一定時間で壊れる → swing_life_component
#   - 振り出されると動き、着いたら壊れる → swing_lift_component
#   - 自分のコードから → AttachedEvent などを購読し、終わったら Shatter
# 置き方：エディターで entity に付ける（実行時に作ってもよい）。1 entity に 1 つ
# 同じ entity：当たり判定のあるメッシュ（スイングでつかめるもの）と、TargetKit の component
swing_target_component<public> := class<final_super>(component):

    var<private> Anchors:[]entity = array{}
    var<private> Attached:logic = false
    var<private> Pulled:logic = false
    var<private> Shattered:logic = false

    AttachedEventInternal<private><final>:event(agent) = event(agent){}
    PulledEventInternal<private><final>:event(agent) = event(agent){}
    DetachedEventInternal<private><final>:event(agent) = event(agent){}
    ShatteredEventInternal<private><final>:event() = event(){}

    # ロープをかけられるたびに、かけた人で届く（Await / Subscribe する。外から Signal はできない）
    AttachedEvent<public><final>:listenable(agent) = MakeProxyListenable(AttachedEventInternal)

    # この物を起点に振り出されるたびに、振り出した人で届く（地面で待っているあいだは届かない）
    PulledEvent<public><final>:listenable(agent) = MakeProxyListenable(PulledEventInternal)

    # かけられたロープが外れるたびに、外れた人で届く
    DetachedEvent<public><final>:listenable(agent) = MakeProxyListenable(DetachedEventInternal)

    # Shatter で壊れ始めたときに 1 回だけ届く（そのあと 1 フレームで entity が消える）
    ShatteredEvent<public><final>:listenable(tuple()) = MakeProxyListenable(ShatteredEventInternal)

    # 一度でもロープをかけられたなら成功する
    WasAttached<public>()<decides><transacts>:void =
        Attached?

    # 一度でも振り出されたなら成功する
    WasPulled<public>()<decides><transacts>:void =
        Pulled?

    # Shatter が呼ばれたなら成功する
    IsShattered<public>()<decides><transacts>:void =
        Shattered?

    # 今かかっているロープの本数
    GetAnchorCount<public>()<transacts>:int =
        Anchors.Length

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Event := swing_attached_event[SceneEvent]):
            set Anchors += array{Event.Anchor}
            set Attached = true
            AttachedEventInternal.Signal(Event.Agent)
        else if (Event := swing_pulled_event[SceneEvent]):
            set Pulled = true
            PulledEventInternal.Signal(Event.Agent)
        else if (Event := swing_detached_event[SceneEvent]):
            set Anchors = for (Anchor : Anchors, Anchor <> Event.Anchor):
                Anchor
            DetachedEventInternal.Signal(Event.Agent)
        false

    # 壊す：かかっているロープをすべて途切れさせ（swing_anchor_component.Break）、ShatteredEvent を送り、スイング側が Break を受け取るまで 1 フレーム待ってから entity を消す。2 回目以降は何もしない
    Shatter<public>()<suspends>:void =
        if (Shattered?):
            return
        set Shattered = true
        for (Anchor : Anchors, Marker := Anchor.GetComponent[swing_anchor_component]):
            Marker.Break()
        set Anchors = array{}
        ShatteredEventInternal.Signal()
        TickEvents.PrePhysics.Await()
        Entity.RemoveFromParent()

# InEntity に付いた swing_target_component を返す。同じ entity で同時に足された直後は見つからないことがあるので、見つからなければ 1 フレーム待って探し直す。それでも無ければ false
(InEntity:entity).AwaitSwingTarget<internal>(Tick:listenable(float))<suspends>:?swing_target_component =
    if (Target := InEntity.GetComponent[swing_target_component]):
        option{Target}
    else:
        Tick.Await()
        if (Target := InEntity.GetComponent[swing_target_component]) then option{Target} else false
