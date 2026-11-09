using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SceneGraphSystem }

# Role: helper that lets a component find "the schedule_component on its own entity or an ancestor" and receive state changes (and every second, when needed). Not inherited; held as one field (ScheduleSystem Kits, FNDeviceSystem, your components)
# Usage: Attach(Entity, OnChanged, OnSecond) in OnBeginSimulation, Detach in OnEndSimulation. When the schedule has already been evaluated, OnChanged is called once inside Attach (a Kit added at runtime also starts from the current state)
# Requirements: follows one schedule only (the nearest when nested). When OnSecond is passed it is called every second (use only for displays)
schedule_follower<public> := class<unique>:

    var<private> Schedule:?schedule_component = false
    var<private> Subscriptions:[]cancelable = array{}

    # The schedule found. Fails before Attach or when none was found
    FindSchedule<public>()<decides><transacts>:schedule_component =
        Schedule?

    # Find a schedule_component on the Owner entity, or else on an ancestor, and subscribe. Does nothing when not found (returns false)
    Attach<public>(Owner:entity, OnChanged:type{_(:schedule_snapshot):void}, OnSecond:?type{_(:schedule_snapshot):void}):logic =
        Detach()
        # The schedule on itself or the nearest ancestor (the engine's FindAncestorComponents has no defined order, so it is not used)
        if (Found := Owner.FindNearestAncestorComponent[schedule_component]):
            set Schedule = option{Found}
            # Passing the function argument straight to Subscribe gives V3502 in UEFN, so wrap it in a method
            set Subscriptions = array{Found.StateChangedEvent.Subscribe(schedule_callback_relay{Callback := OnChanged}.Invoke)}
            if (Second := OnSecond?):
                set Subscriptions += array{Found.SecondEvent.Subscribe(schedule_callback_relay{Callback := Second}.Invoke)}
            if (Snapshot := Found.FindLastSnapshot[]):
                OnChanged(Snapshot)
            true
        else:
            false

    # Stop subscribing
    Detach<public>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        set Schedule = false

# Wrapper for passing a function to a listenable's Subscribe (passing a function received as an argument directly gives V3502 in the UEFN build)
schedule_callback_relay<internal> := class<internal>:
    Callback<internal>:type{_(:schedule_snapshot):void}

    Invoke<internal>(Snapshot:schedule_snapshot):void =
        Callback(Snapshot)
