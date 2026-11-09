using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

# Role: marker for an object that swings can grab. Receives grabbed (swing_attached_event) / launched (swing_pulled_event) / released (swing_detached_event), notifies through AttachedEvent / PulledEvent / DetachedEvent, and remembers the rope points currently attached. Shatter breaks it (cuts every holder's rope with swing_anchor_component.Break, waits one frame, then removes its own entity)
# What happens is decided by the TargetKit components placed on the same entity (each subscribes to this component's notifications):
#   - breaks a fixed time after the first grab -> swing_life_component
#   - moves when launched from and breaks on arrival -> swing_lift_component
#   - from your own code -> subscribe to AttachedEvent etc. and call Shatter when done
# Placement: attach to an entity in the editor (may also be created at runtime). One per entity
# Same entity: a mesh with collision (what the swing grabs) and the TargetKit components
swing_target_component<public> := class<final_super>(component):

    var<private> Anchors:[]entity = array{}
    var<private> Attached:logic = false
    var<private> Pulled:logic = false
    var<private> Shattered:logic = false

    AttachedEventInternal<private><final>:event(agent) = event(agent){}
    PulledEventInternal<private><final>:event(agent) = event(agent){}
    DetachedEventInternal<private><final>:event(agent) = event(agent){}
    ShatteredEventInternal<private><final>:event() = event(){}

    # Fires with the agent each time a rope is attached (Await / Subscribe it; it cannot be Signaled from outside)
    AttachedEvent<public><final>:listenable(agent) = MakeProxyListenable(AttachedEventInternal)

    # Fires with the agent each time a swing is launched from this object (not while waiting on the ground)
    PulledEvent<public><final>:listenable(agent) = MakeProxyListenable(PulledEventInternal)

    # Fires with the agent each time an attached rope is released
    DetachedEvent<public><final>:listenable(agent) = MakeProxyListenable(DetachedEventInternal)

    # Fires once when Shatter starts breaking it (the entity disappears one frame later)
    ShatteredEvent<public><final>:listenable(tuple()) = MakeProxyListenable(ShatteredEventInternal)

    # Succeeds if a rope has ever been attached
    WasAttached<public>()<decides><transacts>:void =
        Attached?

    # Succeeds if a swing has ever been launched from it
    WasPulled<public>()<decides><transacts>:void =
        Pulled?

    # Succeeds if Shatter has been called
    IsShattered<public>()<decides><transacts>:void =
        Shattered?

    # Number of ropes currently attached
    GetAnchorCount<public>()<transacts>:int =
        Anchors.Length

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Event := swing_attached_event[SceneEvent]):
            set Anchors += array{Event.Anchor}
            set Attached = true
            AttachedEventInternal.Signal(Event.Agent)
        else if (Event := swing_pulled_event[SceneEvent]):
            set Pulled = true
            PulledEventInternal.Signal(Event.Agent)
        else if (Event := swing_detached_event[SceneEvent]):
            set Anchors = for (Anchor : Anchors, Anchor <> Event.Anchor):
                Anchor
            DetachedEventInternal.Signal(Event.Agent)
        false

    # Break: cuts every attached rope (swing_anchor_component.Break), sends ShatteredEvent, waits one frame so the swing side receives Break, then removes the entity. Does nothing from the second call on
    Shatter<public>()<suspends>:void =
        if (Shattered?):
            return
        set Shattered = true
        for (Anchor : Anchors, Marker := Anchor.GetComponent[swing_anchor_component]):
            Marker.Break()
        set Anchors = array{}
        ShatteredEventInternal.Signal()
        TickEvents.PrePhysics.Await()
        Entity.RemoveFromParent()

# Returns the swing_target_component attached to InEntity. Right after being added together on the same entity it may not be found yet, so if missing, waits one frame and looks again. false if still missing
(InEntity:entity).AwaitSwingTarget<internal>(Tick:listenable(float))<suspends>:?swing_target_component =
    if (Target := InEntity.GetComponent[swing_target_component]):
        option{Target}
    else:
        Tick.Await()
        if (Target := InEntity.GetComponent[swing_target_component]) then option{Target} else false
