using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { SceneGraphSystem }
using { PlayerSystem.TooltipKit }

# 人が組に入った知らせ
# 方向：player_group_component の entity から下へ（SendDown）
# 送り手：player_group_component。受け手：その子孫の部品（組に入った人にだけ何かをするもの）。消費しない
player_group_joined_event<public> := class(scene_event):
    # 送った組
    Group<public>:player_group_component
    # 入った人
    Agent<public>:agent

# 人が組から出た知らせ（ほかの組を選んだ・Leave・退出）
# 方向・送り手・受け手は player_group_joined_event と同じ
player_group_left_event<public> := class(scene_event):
    # 送った組
    Group<public>:player_group_component
    # 出た人
    Agent<public>:agent

# 役割：プレイヤーの組（選んだ人の集まり）。だれが起こしたか分かる起動の合図（activated_by_agent_event。選択メニューの Targets・インタラクト・ボリュームの入り口など）を受けたら、その人を組に入れる
#   「メニューで選んだ人にだけ HUD を出す」「選んだジャンルの部品だけ効かせる」ときの、だれが選んだかの置き場。widget を組の人にだけ出すのは WidgetSystem の widget_show_in_group_component
#   LeaveOthers なら、組に入るとき、同じ親の下のほかの組から出る（兄弟の組どうしは 1 人 1 つ。選び直しで前の選びが外れる）
#   入ったら Targets へ、その人の起動の合図（activated_by_agent_event）を送る（ワープ・ロードアウトなど、選んだときに 1 回すること）
# 置き方：エディターで entity に付ける。排他にする組は、同じ親の下に兄弟として並べる
# いつ：組に入る・出るのは合図と Join / Leave。停止の合図（deactivated_event）で全員が出る（だれが起こしたか分かる停止の合図なら、その人だけ）
# 知らせ：JoinedEvent / LeftEvent（その人）、player_group_joined_event / player_group_left_event（この entity から下へ）
# 外から：Join / Leave / Clear / IsMember / GetMembers / GetMemberCount / GetMemberPlayerEntities
# 前提・注意：ゲームから抜けた人は組から出る（LeftEvent が届く）。人数は少ない前提で、配列で持つ（weak_map は使わない）
player_group_component<public> := class<final_super>(component):

    # オンなら、組に入るとき、同じ親の下のほかの組（兄弟の entity の player_group_component）から出る。既定オン
    @editable:
        ToolTip := GroupLeaveOthersToolTip
        Categories := array{PlayerGroupCategory}
    LeaveOthers<public>:logic = true
    # 組に入った人の起動の合図（activated_by_agent_event）を送る entity（ワープ先・ロードアウトなど）。空なら送らない
    @editable:
        ToolTip := GroupTargetsToolTip
        Categories := array{PlayerGroupCategory}
    Targets<public>:[]entity = array{}

    JoinedEventInternal<private><final>:event(agent) = event(agent){}
    LeftEventInternal<private><final>:event(agent) = event(agent){}

    # 人が組に入るたびに、その人で届く（Await / Subscribe する。外から Signal はできない）
    JoinedEvent<public><final>:listenable(agent) = MakeProxyListenable(JoinedEventInternal)

    # 人が組から出るたびに、その人で届く
    LeftEvent<public><final>:listenable(agent) = MakeProxyListenable(LeftEventInternal)

    var<private> Members:[]agent = array{}
    var<private> PlayerSubscription:?cancelable = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set PlayerSubscription = Entity.SubscribePlayers(OnPlayerAdded, OnPlayerRemoved)

    OnEndSimulation<override>():void =
        PlayerSubscription.CancelIfSet()
        set PlayerSubscription = false
        set Members = array{}
        (super:)OnEndSimulation()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent], Agent := SceneEvent.FindActivatingAgent[]):
            Join(Agent)
        else if (deactivated_event[SceneEvent]):
            if (Agent := SceneEvent.FindActivatingAgent[]):
                Leave(Agent)
            else:
                Clear()
        false

    # Agent を組に入れる（LeaveOthers なら兄弟の組から出してから）。そのあと Targets へその人の起動の合図を送る
    # もう入っていれば、組の知らせは出さず、Targets への合図だけ送り直す（ラウンドごとに同じものを選び直したときのワープなど）
    Join<public>(Agent:agent):void =
        if (IsMember[Agent]):
            SendToTargets(Agent)
            return
        if (LeaveOthers?):
            for (Other : GetSiblingGroups()):
                Other.Leave(Agent)
        set Members += array{Agent}
        JoinedEventInternal.Signal(Agent)
        Entity.SendDown(player_group_joined_event{Group := Self, Agent := Agent})
        SendToTargets(Agent)

    # Agent を組から出す。入っていなければ何もしない
    Leave<public>(Agent:agent):void =
        if (IsMember[Agent]):
            set Members = for (Member : Members, Member <> Agent) do Member
            LeftEventInternal.Signal(Agent)
            Entity.SendDown(player_group_left_event{Group := Self, Agent := Agent})

    # 全員を組から出す
    Clear<public>():void =
        for (Member : Members):
            Leave(Member)

    # Agent が組に入っているなら成功する
    IsMember<public>(Agent:agent)<decides><transacts>:void =
        Members.Find[Agent]

    # 組に入っている人（入った順）
    GetMembers<public>()<transacts>:[]agent =
        Members

    # 組に入っている人の数
    GetMemberCount<public>()<transacts>:int =
        Members.Length

    # 組に入っている人のうち、今キャラクターがいる人の体の entity（FindPlayerEntity。入った順。スポーン前・倒れて体が無い人は含まない）
    GetMemberPlayerEntities<public>()<transacts>:[]entity =
        for (Member : Members, Body := Member.FindPlayerEntity[]):
            Body

    SendToTargets<private>(Agent:agent):void =
        for (Target : Targets):
            Target.SendActivatedBy(Agent)

    OnPlayerAdded<private>(Player:player):void = {}

    OnPlayerRemoved<private>(Player:player):void =
        Leave(Player)

    GetSiblingGroups<private>()<transacts>:[]player_group_component =
        if (Parent := Entity.GetParent[]):
            for (Sibling : Parent.GetEntities(), Sibling <> Entity, Group := Sibling.GetComponent[player_group_component]):
                Group
        else:
            array{}

# InEntity かその祖先に付いている、いちばん近い player_group_component。無ければ失敗する
(InEntity:entity).FindAncestorGroup<public>()<decides><transacts>:player_group_component =
    InEntity.FindNearestAncestorComponent[player_group_component]
