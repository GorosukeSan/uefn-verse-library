using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { PlayerSystem }
using { WidgetSystem }
using { WidgetSystem.TooltipKit }

# 役割：同じ entity の player_widget_component（すべて）を、プレイヤーの組（player_group_component）に入っている人にだけ出す。組に入ったら出し、出たら消す
#   「メニューで選んだ人にだけ、そのジャンルの HUD を出す」など。widget がまだ起動していなければ出さない（起動したときに組の人にだけ出る）
#   ほかの widget_show_*_component（ボリュームなど）と一緒に置くと、両方を満たす人にだけ出る（組に入った人がボリュームに入ったら出る）
# 置き方：エディターで、widget と同じ entity に付ける
# 同じ entity：player_widget_component の派生。Audience が Everyone なら組の全員に、Chosen ならほかの部品が ShowFor した人のうち組の人に出る
# 前提・注意：Group が空なら、この entity かその祖先の player_group_component を使う。どちらも無ければ、だれにも出さない
widget_show_in_group_component<public> := class<final_super>(widget_audience_filter_component):

    # 組（player_group_component を付けた entity）。空なら、この entity かその祖先の組
    @editable:
        ToolTip := ShowInGroupToolTip
        Categories := array{PlayerWidgetCategory}
    Group<public>:?entity = false

    var<private> Found:?player_group_component = false
    var<private> Subscriptions:[]cancelable = array{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (GroupComponent := FindGroup[]):
            set Found = option{GroupComponent}
            set Subscriptions = array:
                GroupComponent.JoinedEvent.Subscribe(OnJoined)
                GroupComponent.LeftEvent.Subscribe(OnLeft)
        else:
            Print("[widget_show_in_group_component] 組（player_group_component）が見つかりません。だれにも出しません")

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        set Found = false
        (super:)OnEndSimulation()

    AllowsWidgetFor<override>(Agent:agent)<decides><transacts>:void =
        Found?.IsMember[Agent]

    OnJoined<private>(Agent:agent):void =
        for (Widget : Entity.GetPlayerWidgets(), Widget.IsShown[], Widget.Audience = player_widget_audience.Everyone):
            Widget.ShowFor(Agent)

    OnLeft<private>(Agent:agent):void =
        for (Widget : Entity.GetPlayerWidgets()):
            Widget.HideFor(Agent)

    FindGroup<private>()<decides><transacts>:player_group_component =
        if (Target := Group?) then Target.GetComponent[player_group_component] else Entity.FindAncestorGroup[]
