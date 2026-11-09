using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { PlayerSystem }
using { WidgetSystem }
using { WidgetSystem.TooltipKit }

# Role: shows every player_widget_component on the same entity only to people in a player group (player_group_component). Shows on joining the group and hides on leaving
#   E.g. "show that genre's HUD only to people who chose it in a menu". Nothing is shown while the widget is not activated yet (when it activates, only the group's people see it)
#   Placed together with another widget_show_*_component (a volume, etc.), only people who satisfy both see it (a group member entering the volume)
# Placement: in the editor, attach to the same entity as the widget
# Same entity: a player_widget_component subclass. With Audience = Everyone, everyone in the group sees it; with Chosen, the group members among the people another part called ShowFor on
# Requirements: if Group is empty, the player_group_component of this entity or an ancestor is used. With neither, nobody sees it
widget_show_in_group_component<public> := class<final_super>(widget_audience_filter_component):

    # The group (an entity with player_group_component). Empty means the group of this entity or an ancestor
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
            Print("[widget_show_in_group_component] No group (player_group_component) found. Nothing will be shown to anyone")

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
