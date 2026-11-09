using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { SceneGraphSystem }
using { PlayerSystem.TooltipKit }

# Notification that a player joined the group
# Direction: downward from the player_group_component's entity (SendDown)
# Sender: player_group_component. Receivers: its descendant parts (things that act only on members). Not consumed
player_group_joined_event<public> := class(scene_event):
    # The group that sent it
    Group<public>:player_group_component
    # The player who joined
    Agent<public>:agent

# Notification that a player left the group (chose another group, Leave, or left the game)
# Direction, sender and receivers are the same as player_group_joined_event
player_group_left_event<public> := class(scene_event):
    # The group that sent it
    Group<public>:player_group_component
    # The player who left
    Agent<public>:agent

# Role: a group of players (the set of those who chose it). When it receives an activation signal that tells who caused it (activated_by_agent_event: a selection menu's Targets, an interact, a volume entrance, etc.), it adds that player to the group
#   The place that records who chose what, for "show the HUD only to those who chose it in the menu" or "enable only the parts of the chosen genre". Showing a widget only to members is WidgetSystem's widget_show_in_group_component
#   With LeaveOthers, joining leaves the other groups under the same parent (sibling groups are one per player; choosing again cancels the previous choice)
#   On join, sends that player's activation signal (activated_by_agent_event) to Targets (things done once at selection: warp, loadout, etc.)
# Placement: attach to an entity in the editor. Mutually exclusive groups are placed as siblings under the same parent
# When: joining and leaving happen on signals and Join / Leave. The deactivation signal (deactivated_event) removes everyone (only that player if the signal tells who caused it)
# Notifies: JoinedEvent / LeftEvent (the player), player_group_joined_event / player_group_left_event (downward from this entity)
# From outside: Join / Leave / Clear / IsMember / GetMembers / GetMemberCount / GetMemberPlayerEntities
# Requirements / Notes: a player who leaves the game leaves the group (LeftEvent is delivered). Assumes few players and holds them in an array (no weak_map)
player_group_component<public> := class<final_super>(component):

    # When on, joining leaves the other groups under the same parent (player_group_components of sibling entities). Default on
    @editable:
        ToolTip := GroupLeaveOthersToolTip
        Categories := array{PlayerGroupCategory}
    LeaveOthers<public>:logic = true
    # Entities that receive the activation signal (activated_by_agent_event) of a player who joined (warp destination, loadout, etc.). Nothing is sent if empty
    @editable:
        ToolTip := GroupTargetsToolTip
        Categories := array{PlayerGroupCategory}
    Targets<public>:[]entity = array{}

    JoinedEventInternal<private><final>:event(agent) = event(agent){}
    LeftEventInternal<private><final>:event(agent) = event(agent){}

    # Delivered with the player each time someone joins the group (Await / Subscribe to it; it cannot be Signaled from outside)
    JoinedEvent<public><final>:listenable(agent) = MakeProxyListenable(JoinedEventInternal)

    # Delivered with the player each time someone leaves the group
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

    # Add Agent to the group (after leaving the sibling groups if LeaveOthers). Then send that player's activation signal to Targets
    # If already a member, no group notification is sent; only the signal to Targets is resent (e.g. warping when the same thing is chosen again each round)
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

    # Remove Agent from the group. Does nothing if not a member
    Leave<public>(Agent:agent):void =
        if (IsMember[Agent]):
            set Members = for (Member : Members, Member <> Agent) do Member
            LeftEventInternal.Signal(Agent)
            Entity.SendDown(player_group_left_event{Group := Self, Agent := Agent})

    # Remove everyone from the group
    Clear<public>():void =
        for (Member : Members):
            Leave(Member)

    # Succeeds if Agent is a member of the group
    IsMember<public>(Agent:agent)<decides><transacts>:void =
        Members.Find[Agent]

    # Members of the group (in join order)
    GetMembers<public>()<transacts>:[]agent =
        Members

    # Number of members in the group
    GetMemberCount<public>()<transacts>:int =
        Members.Length

    # Body entities of the members who currently have a character (FindPlayerEntity; in join order. Players before spawn or downed without a body are not included)
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

# The nearest player_group_component attached to InEntity or one of its ancestors. Fails if there is none
(InEntity:entity).FindAncestorGroup<public>()<decides><transacts>:player_group_component =
    InEntity.FindNearestAncestorComponent[player_group_component]
