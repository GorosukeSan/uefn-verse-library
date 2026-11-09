using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { SceneGraphSystem }
using { PlayerSystem.TooltipKit }

# 役割：プレイヤーの組（player_group_component）の人数が MinMemberCount 以上・MaxMemberCount 以下なら満たす
#   例：組の人が 1 人以上いれば進む（Min 1）、組の人が 2 人そろったら（Min 2）、組の人がいなくなったら戻る（Min 0・Max 0）
# 置き方：エディターで entity に付け、Group に組の entity を入れる（空なら、この entity かその祖先の組）
# 親：game_transition_component か condition_all / condition_any の entity の直下
# いつ：開始時に組を探し、組の JoinedEvent / LeftEvent で人数が変わるたびに上へ知らせる
# 前提：Group の entity（空ならこの entity か祖先）に player_group_component。見つからなければ Print し、満たさない
player_group_count_condition_component<public> := class<final_super>(condition_component):

    # 人数を数える組（player_group_component を付けた entity）。空なら、この entity かその祖先の組
    @editable:
        ToolTip := GroupCountGroupToolTip
        Categories := array{PlayerGroupCategory}
    Group<public>:?entity = false
    # 組の人数がこの数以上なら満たす（0〜100、既定 1）
    @editable_number(int):
        ToolTip := GroupCountMinToolTip
        Categories := array{PlayerGroupCategory}
        MinValue := option{0}
        MaxValue := option{100}
    MinMemberCount<public>:int = 1
    # 組の人数がこの数以下なら満たす（0〜100、既定 100 = 上限なし）
    @editable_number(int):
        ToolTip := GroupCountMaxToolTip
        Categories := array{PlayerGroupCategory}
        MinValue := option{0}
        MaxValue := option{100}
    MaxMemberCount<public>:int = 100

    var<private> Target:?player_group_component = false
    var<private> Subscriptions:[]cancelable = array{}

    IsSatisfied<override>()<decides><transacts>:void =
        Count := Target?.GetMemberCount()
        Count >= MinMemberCount
        Count <= MaxMemberCount

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := FindGroup[]):
            set Target = option{Found}
            set Subscriptions = array:
                Found.JoinedEvent.Subscribe(OnMembersChanged)
                Found.LeftEvent.Subscribe(OnMembersChanged)
        else:
            Print("[player_group_count_condition_component] player_group_component が見つかりません（Group か、この entity・祖先に置いてください）")

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        set Target = false
        (super:)OnEndSimulation()

    # 数えている組。開始前・見つからなかったときは失敗する
    FindTargetGroup<public>()<decides><transacts>:player_group_component =
        Target?

    FindGroup<private>()<decides><transacts>:player_group_component =
        if (GroupEntity := Group?):
            GroupEntity.GetComponent[player_group_component]
        else:
            Entity.FindAncestorGroup[]

    OnMembersChanged<private>(Agent:agent):void =
        NotifyChanged()
