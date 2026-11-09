using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { LoadoutSystem.TooltipKit }

# ロードアウトを付けた・外した知らせ
# 方向：区画全体（SendScoped。区画が無ければ世界全体）
# 送り手：loadout_component（Loadout）。受け手：ロードアウトの選択を数える部品、利用者の component。消費しない
loadout_changed_event<public> := class(scene_event):
    # 送った部品
    Loadout<public>:loadout_component
    # 付けた・外した人
    Agent<public>:agent
    # true なら付けた、false なら外した
    Applied<public>:logic

# 役割：プレイヤー 1 人分のロードアウト（能力・エネルギー・HUD・付ける物・動きへの反応などの部品を入れたプレハブ）を、人ごとに作ってその人の slot の下に置く。外すと消す
#   プレハブの中の部品は持ち主（その人）だけに効く（能力の付与・widget・player_attach_component・item_grant_component・hud_hide_component が FindOwningPlayer で持ち主に絞る）。コードを書かずに、部品の組み合わせでプレイヤーの能力・見た目・HUD をまとめて付けられる（CharacterSystem の独自ロードアウトもプレハブに入れて付ける）
#   作った次のフレームで、ロードアウトの entity とその子孫へ起動の合図（activated_event）を送る（起動を待つ部品が動き出す）。外すときは停止の合図を送ってから消す
#   同じ人には 1 つだけ作る（ApplyTo を何度呼んでも 1 つ）。Group が空でなければ、同じ Group のほかのロードアウトをその人から外してから付ける（職業・クラスの切り替え）
# 置き方：エディターで entity に付ける（区画の中ならどこでも）
# いつ：ApplyToEveryone なら起動で全員（途中参加も）。オフなら ApplyTo / RemoveFrom で決める（choice_menu_component の Targets や、ボリュームの入り口などから）
#   起動：ActiveOnBegin なら開始から、そうでなければ起動の合図（activated_event）か Activate から。停止の合図（deactivated_event）か Deactivate で全員から外す
#   ApplyToEveryone がオフのとき、だれが起こしたかの分かる起動の合図（activated_by_agent_event。ボリュームの入り口・インタラクト・選択メニューの Targets など）が届いたら、その人に付ける（コードなしで「入った人・押した人に付ける」ができる）
# 知らせ：付けた・外したとき loadout_changed_event を区画全体へ、AppliedEvent / RemovedEvent に届ける
# 外から：Activate / Deactivate / ApplyTo / RemoveFrom / RemoveFromAll / IsAppliedTo / FindInstance / GetAppliedAgents
# 前提：区画（または世界）に player_manager_component が 1 つ（slot の下に置くため）
loadout_component<public> := class<final_super>(component):

    # 1 人分のロードアウトのプレハブ。中に能力・エネルギー・HUD などの部品を入れておく
    @editable:
        ToolTip := LoadoutPrefabToolTip
        Categories := array{LoadoutCategory}
    Prefab<public>:concrete_subtype(entity) = entity
    # オンなら、起動したら全員に付ける（途中参加の人にも）。既定オン
    @editable:
        ToolTip := LoadoutEveryoneToolTip
        Categories := array{LoadoutCategory}
    ApplyToEveryone<public>:logic = true
    # オンなら、ゲームの開始から付ける。既定オフ
    @editable:
        ToolTip := LoadoutActiveOnBeginToolTip
        Categories := array{LoadoutCategory}
    ActiveOnBegin<public>:logic = false
    # 入れ替えのグループ。空でなければ、同じグループのほかのロードアウトをその人から外してから付ける（1 人 1 つの職業など）。既定は空
    @editable:
        ToolTip := LoadoutGroupToolTip
        Categories := array{LoadoutCategory}
    Group<public>:string = ""

    AppliedEventInternal<private><final>:event(tuple(agent, entity)) = event(tuple(agent, entity)){}
    RemovedEventInternal<private><final>:event(agent) = event(agent){}

    # 付けたときに、（その人, ロードアウトの entity）で届く（Await / Subscribe する。外から Signal はできない）
    AppliedEvent<public><final>:listenable(tuple(agent, entity)) = MakeProxyListenable(AppliedEventInternal)

    # 外したときに、その人で届く
    RemovedEvent<public><final>:listenable(agent) = MakeProxyListenable(RemovedEventInternal)

    var<private> Active:logic = false
    var<private> Instances:[agent]entity = map{}
    var<private> Manager:?player_manager_component = false
    var<private> Subscriptions:[]cancelable = array{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (ActiveOnBegin?):
            Activate()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            # 全員に付けない設定で、だれが起こしたかの分かる合図（ボリュームに入った人・ボタンを押した人など）なら、その人に付ける
            if (not ApplyToEveryone?, Agent := SceneEvent.FindActivatingAgent[]):
                ApplyTo(Agent)
            else:
                Activate()
        else if (deactivated_event[SceneEvent]):
            Deactivate()
        false

    OnEndSimulation<override>():void =
        Deactivate()
        (super:)OnEndSimulation()

    # 付け始める（ApplyToEveryone なら今いる全員と、これから参加する人）。もう起動していれば何もしない
    Activate<public>():void =
        if (Active?):
            return
        set Active = true
        set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)
        if (Found := Manager?):
            set Subscriptions = array{Found.PlayerRemovedEvent.Subscribe(OnPlayerRemoved)}
            if (ApplyToEveryone?):
                set Subscriptions += array{Found.PlayerAddedEvent.Subscribe(OnPlayerAdded)}
                for (Slot : Found.GetSlots()):
                    ApplyTo(Slot.Player)
        else:
            Print("[loadout_component] player_manager_component が見つからないので、ロードアウトを付けられません")

    # 全員から外し、付けるのをやめる。起動していなければ何もしない
    Deactivate<public>():void =
        if (not Active?):
            return
        set Active = false
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        RemoveFromAll()
        set Manager = false

    # Agent にロードアウトを付ける（もう付いていれば何もしない）。起動していなければ起動する。Group が同じほかのロードアウトは外す。付けられなかった（参加していない）ときは false
    ApplyTo<public>(Agent:agent):logic =
        if (not Active?):
            Activate()
        if (Instances[Agent]):
            return true
        if (Player := player[Agent], Found := Manager?, Slot := Found.FindSlot[Player]):
            RemoveSameGroup(Slot, Agent)
            Instance := Prefab{}
            Instance.AddComponents(array{loadout_instance_component{Entity := Instance, Source := Self, Player := Player}})
            Slot.Entity.AddEntities(array{Instance})
            if (set Instances[Agent] = Instance) {}
            Entity.SendScoped(loadout_changed_event{Loadout := Self, Agent := Agent, Applied := true})
            AppliedEventInternal.Signal((Agent, Instance))
            return true
        false

    # Agent からロードアウトを外す（停止の合図を送ってから消す）。付いていなければ何もしない
    RemoveFrom<public>(Agent:agent):void =
        if (Instance := Instances[Agent]):
            set Instances = Instances.RemoveKey(Agent)
            Instance.SendDeactivated()
            Instance.RemoveFromParent()
            Entity.SendScoped(loadout_changed_event{Loadout := Self, Agent := Agent, Applied := false})
            RemovedEventInternal.Signal(Agent)

    # 全員から外す
    RemoveFromAll<public>():void =
        for (Agent -> Instance : Instances):
            RemoveFrom(Agent)

    # Agent に付いていれば成功する
    IsAppliedTo<public>(Agent:agent)<decides><transacts>:void =
        Instances[Agent]

    # Agent に付けたロードアウトの entity。付いていなければ失敗する
    FindInstance<public>(Agent:agent)<decides><transacts>:entity =
        Instances[Agent]

    # 今ロードアウトが付いている人（並び順は決まっていない）
    GetAppliedAgents<public>()<transacts>:[]agent =
        for (Agent -> Instance : Instances):
            Agent

    OnPlayerAdded<private>(Player:player):void =
        if (Active?, ApplyToEveryone?):
            ApplyTo(Player)

    OnPlayerRemoved<private>(Player:player):void =
        RemoveFrom(Player)

    # 同じ人の slot の下にある、同じ Group のほかのロードアウトを外す
    RemoveSameGroup<private>(Slot:player_slot_component, Agent:agent):void =
        if (Group <> ""):
            for (Child : Slot.Entity.GetEntities(), Other := Child.GetComponent[loadout_instance_component], Other.Source <> Self, Other.Source.Group = Group):
                Other.Source.RemoveFrom(Agent)

# 役割：ロードアウト（loadout_component が作ったプレハブ）の根に付く印。だれのロードアウトか・どの loadout_component が作ったかを持ち、作った次のフレームで起動の合図を配下へ送る
# 置き方：実行時に loadout_component が付ける（エディターでは置かない）
loadout_instance_component<public> := class<final_super><internal>(component):
    # 作った loadout_component
    Source<public>:loadout_component
    # 持ち主
    Player<public>:player

    OnSimulate<override>()<suspends>:void =
        # 同じプレハブの部品がみな OnBeginSimulation を終えてから届くように、1 フレーム待つ
        TickEvents.PrePhysics.Await()
        Entity.SendActivated()

# InEntity か、その祖先のロードアウト（loadout_instance_component）。ロードアウトの中でなければ失敗する
(InEntity:entity).FindLoadoutInstance<public>()<decides><transacts>:loadout_instance_component =
    var Current:entity = InEntity
    var Found:?loadout_instance_component = false
    loop:
        if (Instance := Current.GetComponent[loadout_instance_component]):
            set Found = option{Instance}
            break
        if (Parent := Current.GetParent[]):
            set Current = Parent
        else:
            break
    Found?
