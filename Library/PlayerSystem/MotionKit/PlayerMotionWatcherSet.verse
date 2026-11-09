using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SceneGraphSystem }

# Role: the set of watched players used by the parts (runtime class). If Owner is an owned entity, watches the one owner; otherwise everyone in the scope (including later joins), and Updates every player_motion_watcher every frame (Tick)
player_motion_watcher_set<internal> := class<internal>:

    var<private> Watchers:[agent]player_motion_watcher = map{}
    var<private> Notify:?type{_(:agent, :player_motion):void} = false
    var<private> Subscriptions:[]cancelable = array{}

    # Start watching. Motions are passed to Notify. Tick is the owning component's TickEvents.PrePhysics
    Start<internal>(Owner:entity, InNotify:type{_(:agent, :player_motion):void}, Tick:listenable(float)):void =
        Stop()
        set Notify = option{InNotify}
        set Subscriptions = array{Tick.Subscribe(OnTick)}
        if (OwningPlayer := Owner.FindOwningPlayer[]):
            Add(OwningPlayer)
        else if (Manager := Owner.FindScopedComponent[player_manager_component]):
            set Subscriptions += array:
                Manager.PlayerAddedEvent.Subscribe(OnAdded)
                Manager.PlayerRemovedEvent.Subscribe(OnRemoved)
            for (Slot : Manager.GetSlots()):
                Add(Slot.Player)

    # Stop watching
    Stop<internal>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        for (Agent -> Watcher : Watchers):
            Watcher.Stop()
        set Watchers = map{}
        set Notify = false

    # The watched players (order is undefined)
    GetAgents<internal>()<transacts>:[]agent =
        for (Agent -> Watcher : Watchers):
            Agent

    # Succeeds if Agent is in State. Fails if Agent is not watched or has no character
    IsInState<internal>(Agent:agent, State:player_motion_state)<decides><transacts>:void =
        Watchers[Agent].IsInState[State]

    Add<private>(Agent:agent):void =
        if (not Watchers[Agent], Callback := Notify?):
            Watcher := player_motion_watcher{Agent := Agent, Notify := Callback}
            if (set Watchers[Agent] = Watcher) {}
            Watcher.Update()

    OnAdded<private>(Player:player):void =
        Add(Player)

    OnRemoved<private>(Player:player):void =
        if (Watcher := Watchers[Player]):
            Watcher.Stop()
            set Watchers = Watchers.RemoveKey(Player)

    OnTick<private>(DeltaTime:float):void =
        for (Agent -> Watcher : Watchers):
            Watcher.Update()
