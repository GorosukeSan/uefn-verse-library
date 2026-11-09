using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { SceneGraphSystem }
using { PlayerSystem.TooltipKit }

# Role: satisfied when the member count of a player group (player_group_component) is between MinMemberCount and MaxMemberCount
#   Examples: advance when the group has at least one member (Min 1), when two members have gathered (Min 2), go back when the group is empty (Min 0, Max 0)
# Placement: attach to an entity in the editor and set the group's entity in Group (if empty, the group on this entity or its ancestors)
# Parent: directly under the entity of a game_transition_component or condition_all / condition_any
# When: finds the group at start and notifies upward each time the count changes via the group's JoinedEvent / LeftEvent
# Requirements: a player_group_component on the Group entity (or on this entity or an ancestor if empty). If none is found, Prints and is never satisfied
player_group_count_condition_component<public> := class<final_super>(condition_component):

    # The group whose members are counted (an entity with player_group_component). If empty, the group on this entity or its ancestors
    @editable:
        ToolTip := GroupCountGroupToolTip
        Categories := array{PlayerGroupCategory}
    Group<public>:?entity = false
    # Satisfied when the group has at least this many members (0-100, default 1)
    @editable_number(int):
        ToolTip := GroupCountMinToolTip
        Categories := array{PlayerGroupCategory}
        MinValue := option{0}
        MaxValue := option{100}
    MinMemberCount<public>:int = 1
    # Satisfied when the group has at most this many members (0-100, default 100 = no upper limit)
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
            Print("[player_group_count_condition_component] No player_group_component found (set Group, or place one on this entity or an ancestor)")

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        set Target = false
        (super:)OnEndSimulation()

    # The group being counted. Fails before start or when none was found
    FindTargetGroup<public>()<decides><transacts>:player_group_component =
        Target?

    FindGroup<private>()<decides><transacts>:player_group_component =
        if (GroupEntity := Group?):
            GroupEntity.GetComponent[player_group_component]
        else:
            Entity.FindAncestorGroup[]

    OnMembersChanged<private>(Agent:agent):void =
        NotifyChanged()
