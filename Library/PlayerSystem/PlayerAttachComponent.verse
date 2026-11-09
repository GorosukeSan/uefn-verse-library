using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { ActivationSystem }
using { SceneGraphSystem }
using { PlayerSystem.TooltipKit }

# プレイヤーに付けた entity をだれに見せるか
player_attach_visibility<public> := enum:
    # 全員に見せる
    Everyone
    # 付けた本人にだけ見せる（自分にだけ出る目印など）
    OwnerOnly
    # 本人以外に見せる（頭の上の名札・アイコンなど）
    OthersOnly

# 役割：プレイヤーの体に entity（Prefab）を付けて、体と一緒に動かす。親子にはせず、この entity の子にした上で SetOrigin（entity_origin）で体を基準にする（体の entity の中身には触らない）
#   同じ人には 1 つだけ付ける（AttachTo を何度呼んでも 1 つ）。リスポーンなどで体の entity が変わったら、RefreshSeconds ごとの見回りで付け直す（体がいないあいだは隠す）
#   だれに付けるか：AttachToEveryone なら起動で全員（途中参加も）。オフなら AttachTo / DetachFrom で決める。持ち主のいる entity（キャラクターの中など）なら、全員の代わりに持ち主だけ
# 置き方：エディターで entity に付ける
# 親：起動の合図が届く場所（ActiveOnBegin なら どこでもよい）
# いつ：ActiveOnBegin なら開始から。起動の合図（activated_event）か Activate で付け始め、停止の合図（deactivated_event）か Deactivate で全員から外す
# 知らせ：付けたとき AttachedEvent（その人, 付けた entity）、外したとき DetachedEvent
# 外から：Activate / Deactivate / AttachTo / DetachFrom / DetachAll / FindAttached / IsAttachedTo
# 前提：区画（または世界）に player_manager_component が 1 つ（AttachToEveryone のとき）
# ⚠ 未検証：entity_origin で体に付けた entity が、体の向き・しゃがみに合わせて動くか
player_attach_component<public> := class<final_super>(component):

    # 付ける entity（prefab）。既定の entity のままなら何も無い entity
    @editable:
        ToolTip := AttachPrefabToolTip
        Categories := array{AttachCategory}
    Prefab<public>:concrete_subtype(entity) = entity
    # 体の原点からのずらし（センチメートル。Forward・Left・Up）。既定は真上に 200
    @editable:
        ToolTip := AttachOffsetToolTip
        Categories := array{AttachCategory}
    OffsetCm<public>:vector3 = vector3{Up := 200.0}
    # だれに見せるか。既定 Everyone
    @editable:
        ToolTip := AttachVisibilityToolTip
        Categories := array{AttachCategory}
    Visibility<public>:player_attach_visibility = player_attach_visibility.Everyone
    # オンなら、起動したら全員に付ける（途中参加の人にも）。オフなら AttachTo で決めた人だけ。既定オン
    @editable:
        ToolTip := AttachEveryoneToolTip
        Categories := array{AttachCategory}
    AttachToEveryone<public>:logic = true
    # オンならゲームの開始から付ける。既定オフ
    @editable:
        ToolTip := AttachActiveOnBeginToolTip
        Categories := array{AttachCategory}
    ActiveOnBegin<public>:logic = false
    # 体が変わっていないか（リスポーンなど）を見回る間隔（秒）。既定 1
    @editable_number(float):
        ToolTip := AttachRefreshSecondsToolTip
        Categories := array{AttachCategory}
        MinValue := option{0.1}
        MaxValue := option{10.0}
    RefreshSeconds<public>:float = 1.0

    AttachedEventInternal<private><final>:event(tuple(agent, entity)) = event(tuple(agent, entity)){}
    DetachedEventInternal<private><final>:event(agent) = event(agent){}

    # 付けたときに、（その人, 付けた entity）で届く（Await / Subscribe する。外から Signal はできない）
    AttachedEvent<public><final>:listenable(tuple(agent, entity)) = MakeProxyListenable(AttachedEventInternal)

    # 外したときに、その人で届く
    DetachedEvent<public><final>:listenable(agent) = MakeProxyListenable(DetachedEventInternal)

    var<private> Active:logic = false
    var<private> Attached:[agent]entity = map{}
    # 付けたときの体（変わったら付け直す）
    var<private> Bodies:[agent]entity = map{}
    var<private> AddedSubscription:?cancelable = false
    var<private> RemovedSubscription:?cancelable = false
    var<private> Manager:?player_manager_component = false
    StartEvent<private>:event() = event(){}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (ActiveOnBegin?):
            Activate()

    OnSimulate<override>()<suspends>:void =
        loop:
            if (not Active?):
                StartEvent.Await()
            Sleep(RefreshSeconds)
            if (Active?):
                Refresh()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Activate()
        else if (deactivated_event[SceneEvent]):
            Deactivate()
        false

    OnEndSimulation<override>():void =
        Deactivate()
        set Manager = false
        (super:)OnEndSimulation()

    # 付け始める（AttachToEveryone なら今いる全員と、これから参加する人）。もう起動していれば何もしない
    Activate<public>():void =
        if (Active?):
            return
        set Active = true
        StartEvent.Signal()
        if (OwningPlayer := Entity.FindOwningPlayer[]):
            # 持ち主のいる entity（キャラクターの中など）なら、持ち主にだけ付ける
            if (AttachToEveryone?):
                AttachTo(OwningPlayer)
        else if (Found := Entity.ResolveScopedComponent(Manager, player_manager_component)?):
            set Manager = option{Found}
            set RemovedSubscription = option{Found.PlayerRemovedEvent.Subscribe(OnPlayerRemoved)}
            if (AttachToEveryone?):
                set AddedSubscription = option{Found.PlayerAddedEvent.Subscribe(OnPlayerAdded)}
                for (Slot : Found.GetSlots()):
                    AttachTo(Slot.Player)

    # 全員から外し、付けるのをやめる。起動していなければ何もしない
    Deactivate<public>():void =
        if (not Active?):
            return
        set Active = false
        AddedSubscription.CancelIfSet()
        set AddedSubscription = false
        RemovedSubscription.CancelIfSet()
        set RemovedSubscription = false
        DetachAll()

    # Agent に付ける（もう付いていれば、その entity を返して何もしない）。起動していなければ起動する（AttachToEveryone なら全員にも付く）
    AttachTo<public>(Agent:agent):entity =
        if (not Active?):
            Activate()
        if (Existing := Attached[Agent]):
            return Existing
        Attachment := Prefab{}
        Entity.AddEntities(array{Attachment})
        if (set Attached[Agent] = Attachment) {}
        Follow(Agent, Attachment)
        AttachedEventInternal.Signal((Agent, Attachment))
        Attachment

    # Agent から外す（付いていなければ何もしない）
    DetachFrom<public>(Agent:agent):void =
        if (Attachment := Attached[Agent]):
            set Attached = Attached.RemoveKey(Agent)
            set Bodies = Bodies.RemoveKey(Agent)
            Attachment.RemoveFromParent()
            DetachedEventInternal.Signal(Agent)

    # 全員から外す
    DetachAll<public>():void =
        for (Agent -> Attachment : Attached):
            DetachFrom(Agent)

    # Agent に付けている entity。付いていなければ失敗する
    FindAttached<public>(Agent:agent)<decides><transacts>:entity =
        Attached[Agent]

    # Agent に付いていれば成功する
    IsAttachedTo<public>(Agent:agent)<decides><transacts>:void =
        Attached[Agent]

    OnPlayerAdded<private>(Player:player):void =
        if (Active?, AttachToEveryone?):
            AttachTo(Player)

    OnPlayerRemoved<private>(Player:player):void =
        DetachFrom(Player)

    # 体を基準にし、見せる相手を決める。体がいなければ隠す
    Follow<private>(Agent:agent, Attachment:entity):void =
        if (Body := Agent.FindPlayerEntity[]):
            if (set Bodies[Agent] = Body) {}
            Attachment.SetOrigin(entity_origin{Entity := Body})
            Attachment.SetLocalTransform(MakeTranslationTransform(OffsetCm))
            ApplyVisibility(Agent, Attachment)
        else:
            set Bodies = Bodies.RemoveKey(Agent)
            Attachment.SetPresentableToPlayers(option{array{}})

    # 体が変わった（リスポーン）・いなくなった・戻った人を付け直す。見せる相手も今の参加者で決め直す
    Refresh<private>():void =
        for (Agent -> Attachment : Attached):
            if (Body := Agent.FindPlayerEntity[], Previous := Bodies[Agent], Body = Previous):
                ApplyVisibility(Agent, Attachment)
            else:
                Follow(Agent, Attachment)

    ApplyVisibility<private>(Agent:agent, Attachment:entity):void =
        case (Visibility):
            player_attach_visibility.Everyone =>
                Everyone:?[]player = false
                Attachment.SetPresentableToPlayers(Everyone)
            player_attach_visibility.OwnerOnly =>
                if (Player := player[Agent]):
                    Attachment.SetPresentableToPlayers(option{array{Player}})
            player_attach_visibility.OthersOnly =>
                set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)
                if (Found := Manager?):
                    Others := for (Slot : Found.GetSlots(), Slot.Player <> Agent):
                        Slot.Player
                    Attachment.SetPresentableToPlayers(option{Others})
