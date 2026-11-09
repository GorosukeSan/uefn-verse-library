using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { SceneGraphSystem }

# Wrapper that passes a notification between the views of the same player
# Direction: downward from the slot's entity (SendDown). Sent with player_view_set.SendToPlayer
# Receivers: the views under the same player's slot. Not consumed
player_event<public> := class(scene_event):
    # The view (component) that sent it
    Sender<public>:component
    # The notification being passed (the receiving view looks at this content)
    Event<public>:scene_event

# Wrapper that passes a notification from the component that created the view to that view
# Direction: to the entity of a view created by player_view_set (SendDown). Sent with player_view_set.SendToViews
# Receivers: that view. Not consumed
player_view_source_event<public> := class(scene_event):
    # The notification passed from the creator side (the component that holds the player_view_set)
    Event<public>:scene_event

# Interface that decides whom a player_view_set may create a view for (passed to Activate's ViewFilter)
# Implemented by: player_widget_component and other things that have a condition on whom they may be shown to
player_view_filter<public> := interface:
    # Succeeds if a view may be created for Agent
    AllowsView<public>(Agent:agent)<decides><transacts>:void

# Role: while active, creates one view (entity) per player under every player slot of the scope and removes them on deactivation. Also creates for players who join later; the views of players who leave are removed from the world together with the slot (the view's component goes through OnEndSimulation; also dropped from GetViews etc.)
# Usage: hold a player_view_set{} in a component field, call HandleActivation from OnReceive and Deactivate from OnEndSimulation (no inheritance). A view is an ordinary component created by the CreateView function
# Requirements: one player_manager_component in the scope (or world)
player_view_set<public> := class<unique>:

    var<private> Views:[]entity = array{}
    var<private> Active:logic = false
    var<private> CreateView:?type{_(:entity, :player_slot_component):component} = false
    var<private> AddedSubscription:?cancelable = false
    var<private> RemovedSubscription:?cancelable = false
    var<private> Manager:?player_manager_component = false
    var<private> Filter:?player_view_filter = false

    # Succeeds while active (from Activate to Deactivate)
    IsActive<public>()<decides><transacts>:void =
        Active?

    # Entities of the current views (only those in the world; excludes players who left and players hidden with HideFor. Order is undefined)
    GetViews<public>()<transacts>:[]entity =
        for (View : Views, View.GetSimulationEntity[]):
            View

    # Finds the player_manager_component of Owner's scope, creates a view with CreateView under every current slot and waits for later joins. Does nothing if already active
    # If Everyone is false, activates without creating for anyone (creates only for players chosen with ShowFor; not for later joins either)
    # If ViewFilter is given, creates only for players the ViewFilter allows (both for everyone and for ShowFor. Nothing is done for disallowed players)
    # If no player_manager_component is found, counts as activated but creates no views (and does not wait for joins. Prints once)
    # The view of a player who left is dropped from the remembered list on the manager's leave notification (PlayerRemovedEvent)
    Activate<public>(Owner:entity, MakeView:type{_(:entity, :player_slot_component):component}, ?Everyone:logic = true, ?ViewFilter:?player_view_filter = false):void =
        if (Active?):
            return
        set Active = true
        set CreateView = option{MakeView}
        set Filter = ViewFilter
        set Manager = Owner.ResolveScopedComponent(Manager, player_manager_component)
        if (Found := Manager?):
            set RemovedSubscription = option{Found.PlayerRemovedEvent.Subscribe(OnPlayerRemoved)}
            if (Everyone?):
                set AddedSubscription = option{Found.PlayerAddedEvent.Subscribe(OnPlayerAdded)}
                for (Slot : Found.GetSlots()):
                    Attach(Slot)
        else:
            Print("[player_view_set] No player_manager_component found in the scope (or the world). No views are created")

    # Removes every created view and stops waiting for joins. Does nothing if not active
    Deactivate<public>():void =
        if (not Active?):
            return
        set Active = false
        AddedSubscription.CancelIfSet()
        set AddedSubscription = false
        RemovedSubscription.CancelIfSet()
        set RemovedSubscription = false
        set Manager = false
        set Filter = false
        for (View : Views):
            View.RemoveFromParent()
        set Views = array{}

    # Activate if SceneEvent is an activated_event, Deactivate if it is a deactivated_event. Otherwise does nothing. Call from the component's OnReceive
    HandleActivation<public>(SceneEvent:scene_event, Owner:entity, MakeView:type{_(:entity, :player_slot_component):component}):void =
        if (activated_event[SceneEvent]):
            Activate(Owner, MakeView)
        else if (deactivated_event[SceneEvent]):
            Deactivate()

    # Returns Agent's view if there is one. Fails when not active, when Agent has not joined, or when hidden with HideFor
    FindViewFor<public>(Agent:agent)<decides><transacts>:entity =
        first:
            View : GetViews()
            Slot := View.GetParent[].GetComponent[player_slot_component]
            Slot.Player = Agent
        do:
            View

    # Removes Agent's view (stops it for that player only). While active, ShowFor can recreate it. Does nothing if there is no view
    HideFor<public>(Agent:agent):void =
        if (View := FindViewFor[Agent]):
            View.RemoveFromParent()
            set Views = GetViews()

    # If active, Agent has joined and has no view, creates one (brings back a player hidden with HideFor). Otherwise does nothing
    ShowFor<public>(Agent:agent):void =
        if:
            Active?
            not FindViewFor[Agent]
            Found := Manager?
            Player := player[Agent]
            Slot := Found.FindSlot[Player]
        then:
            Attach(Slot)

    # Sends player_view_source_event{Event := SceneEvent} to every current view entity (views receive it in OnReceive)
    SendToViews<public>(SceneEvent:scene_event):void =
        for (View : GetViews()):
            View.SendDown(player_view_source_event{Event := SceneEvent})

    OnPlayerAdded<private>(Player:player):void =
        if (Active?, Found := Manager?, Slot := Found.FindSlot[Player]):
            Attach(Slot)

    # Drop the view of a player who left from the list (the view entity has already left the world together with the slot)
    OnPlayerRemoved<private>(Player:player):void =
        set Views = for (View : Views, Slot := View.GetParent[].GetComponent[player_slot_component], Slot.Player <> Player):
            View

    Attach<private>(Slot:player_slot_component):void =
        if (MakeView := CreateView?, IsAllowed[Slot.Player]):
            ViewEntity := entity{}
            ViewEntity.AddComponents(array{MakeView(ViewEntity, Slot)})
            Slot.Entity.AddEntities(array{ViewEntity})
            set Views = GetViews() + array{ViewEntity}

    IsAllowed<private>(Agent:agent)<decides><transacts>:void =
        if (Check := Filter?, not Check.AllowsView[Agent]):
            false?

# Sends player_event{Sender := View, Event := SceneEvent} down from the slot of the same player as View (a view component under a slot). The player's other views receive it in OnReceive
# Does nothing when View is not under a slot (has no parent)
(View:component).SendToPlayer<public>(SceneEvent:scene_event):void =
    if (Slot := View.Entity.GetParent[]):
        Slot.SendDown(player_event{Sender := View, Event := SceneEvent})

# Returns the player_slot_component of the parent (slot) of View's entity. Fails for anything other than a view
(View:component).FindViewSlot<public>()<decides><transacts>:player_slot_component =
    View.Entity.GetParent[].GetComponent[player_slot_component]
