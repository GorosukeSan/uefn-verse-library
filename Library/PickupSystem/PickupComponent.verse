using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { VolumeSystem }
using { CharacterSystem.SurfaceKit }
using { PickupSystem.TooltipKit }

# Notification that a pickup was picked up
# Direction: from the picked-up object's entity to the root (SendUp)
# Sender: pickup_component (Pickup). Receivers: ancestor components (the map root, the game root, etc.). Not consumed
pickup_picked_event<public> := class(scene_event):
    # The picked-up object (sender)
    Pickup<public>:pickup_component
    # Agent who picked it up
    Agent<public>:agent
    # Entity of the created effect prefab. false if it could not be created (Effect is empty or there is no slot)
    Effect<public>:?entity

# Role: base class for conditions that restrict who can pick up (subclass it to write a condition in code; the only member is CanPick). pickup_component lets only agents pass every subclass on the same entity pick up
#   Example: "only players currently playing" in a game. To filter by tag, write Agent.HasPlayerTag[tag]
# Placement: attach in the editor to the same entity as pickup_component. At most one subclass per entity (the editor cannot attach two components with the same base)
pickup_filter_component<public> := class<abstract><final_super>(component):
    # Succeeds if Agent may pick up Pickup
    CanPick<public>(Pickup:pickup_component, Agent:agent)<decides><transacts>:void

# Role: a pickup (orb). Creates the effect prefab (Effect) for the agent who touches it and gives it to them (a prefab with PickupSystem's pickup_effect_component on the root; created under that agent's slot, owner = the picker)
#   On pickup, hides the look (meshes on this entity and its descendants) and brings it back after RespawnSeconds (0 means it does not return; Restore or the activate signal brings it back)
#   How touching is detected (any of these; both may be present):
#     Custom character (CharacterSystem): touched (Touched) the character_surface_component (SurfaceKit) on the same entity
#     Fortnite character: entered the player_volume_component (VolumeSystem) on the same entity
#     Code: TryPickup(Agent)
#   Who can pick up: with RequireGroupMember, only members of the nearest ancestor player_group_component (PlayerSystem) group (e.g. players currently playing the map). pickup_filter_component subclasses on the same entity can filter too
# Placement: attach in the editor to the pickup entity (the look mesh and the parts that detect touching go on the same entity). Give the mesh no collision
#   To replace the look: change this entity's mesh, or put a look prefab in Visual (created as a child of this entity at start)
# When: from the start (from the activate signal if ActiveOnBegin is off). The activate signal restores it (makes it available), the deactivate signal hides it (unavailable)
# Notifies: PickedEvent (the picker), RestoredEvent, pickup_picked_event (SendUp)
# From outside: TryPickup / Restore / Hide / IsAvailable / CanPick
# Requirements: one player_manager_component in the scope or the world (to create the effect under the agent's slot)
pickup_component<public> := class<final_super>(component):

    # Prefab of the effect given to the picker (pickup_effect_component on the root). Leaving the default entity gives an empty effect with the default duration (10 s)
    @editable:
        ToolTip := PickupEffectToolTip
        Categories := array{PickupCategory}
    Effect<public>:concrete_subtype(entity) = entity
    # Seconds until it returns after being picked up. 0 means it does not return (one time only; Restore, the activate signal or a game reset brings it back). Default 10
    @editable_number(float):
        ToolTip := PickupRespawnToolTip
        Categories := array{PickupCategory}
        MinValue := option{0.0}
        MaxValue := option{3600.0}
    RespawnSeconds<public>:float = 10.0
    # Look prefab. Created as a child of this entity at start and removed together on pickup (instead of or in addition to this entity's mesh). Leaving the default entity adds nothing
    @editable:
        ToolTip := PickupVisualToolTip
        Categories := array{PickupCategory}
    Visual<public>:concrete_subtype(entity) = entity
    # When on, only members of the nearest ancestor player_group_component's group can pick it up (nobody if there is no group). Default off
    @editable:
        ToolTip := PickupRequireGroupToolTip
        Categories := array{PickupCategory}
    RequireGroupMember<public>:logic = false
    # When on, it can be picked up from the start. When off, it stays hidden until the activate signal (e.g. an orb revealed by a stage signal). Default on
    @editable:
        ToolTip := PickupActiveOnBeginToolTip
        Categories := array{PickupCategory}
    ActiveOnBegin<public>:logic = true
    # Display name (for the output log and your HUD; not used by the effect itself). Default empty
    @editable:
        ToolTip := PickupDisplayNameToolTip
        Categories := array{PickupCategory}
    DisplayName<public>:string = ""

    PickedEventInternal<private><final>:event(agent) = event(agent){}
    RestoredEventInternal<private><final>:event(tuple()) = event(tuple()){}

    # Fires with the picker each time it is picked up (Await / Subscribe it; it cannot be Signaled from outside)
    PickedEvent<public><final>:listenable(agent) = MakeProxyListenable(PickedEventInternal)

    # Fires each time it becomes available again (returned after the timer, Restore, the activate signal)
    RestoredEvent<public><final>:listenable(tuple()) = MakeProxyListenable(RestoredEventInternal)

    var<private> Available:logic = false
    # Counter that invalidates stale "restore" waits
    var<private> Generation:int = 0
    var<private> VisualEntity:?entity = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        VisualType:concrete_subtype(entity) = Visual
        Made := VisualType{}
        Entity.AddEntities(array{Made})
        Made.SetGlobalTransform(Entity.GetGlobalTransform())
        set VisualEntity = option{Made}

    OnSimulate<override>()<suspends>:void =
        # Sync the look once the mesh and the touch volume on the same entity are in place
        Sleep(0.0)
        if (ActiveOnBegin?):
            Restore()
        else:
            Hide()

    OnEndSimulation<override>():void =
        set Generation += 1
        set Available = false
        if (Made := VisualEntity?):
            Made.RemoveFromParent()
        set VisualEntity = false
        (super:)OnEndSimulation()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Contact := character_surface_contact_event[SceneEvent]):
            if (Contact.Surface.Entity = Entity, Contact.Contact = character_surface_contact.Touched, Agent := Contact.Agent?):
                TryPickup(Agent)
        else if (Entered := player_volume_entered_event[SceneEvent]):
            if (Entered.Volume.Entity = Entity):
                TryPickup(Entered.Agent)
        else if (activated_event[SceneEvent]):
            Restore()
        else if (deactivated_event[SceneEvent]):
            Hide()
        false

    # Let Agent pick it up: if available and Agent may pick up, gives the effect, hides the look and restores after RespawnSeconds. true if picked up
    TryPickup<public>(Agent:agent):logic =
        if (not Available?):
            return false
        if (not CanPick[Agent]):
            return false
        set Available = false
        Show(false)
        MaybeEffect := Entity.GrantPickupEffect(Agent, Effect, Entity.GetGlobalTransform(), option{Entity})
        PickedEventInternal.Signal(Agent)
        Entity.SendUp(pickup_picked_event{Pickup := Self, Agent := Agent, Effect := MaybeEffect})
        set Generation += 1
        if (RespawnSeconds > 0.0):
            spawn{RestoreAfter(Generation)}
        true

    # Make it available again right away (shows the look). Cancels any pending restore
    Restore<public>():void =
        set Generation += 1
        set Available = true
        Show(true)
        RestoredEventInternal.Signal(())

    # Hide it and make it unavailable (until Restore or the activate signal). Cancels any pending restore
    Hide<public>():void =
        set Generation += 1
        set Available = false
        Show(false)

    # Succeeds if it can be picked up now
    IsAvailable<public>()<decides><transacts>:void =
        Available?

    # Succeeds if Agent may pick up (the RequireGroupMember group and every pickup_filter_component subclass on the same entity)
    CanPick<public>(Agent:agent)<decides><transacts>:void =
        if (RequireGroupMember?):
            Entity.FindAncestorGroup[].IsMember[Agent]
        Refused := for (Each : Entity.GetComponents(), Filter := pickup_filter_component[Each], not Filter.CanPick[Self, Agent]):
            Filter
        Refused.Length = 0

    RestoreAfter<private>(MyGeneration:int)<suspends>:void =
        Sleep(RespawnSeconds)
        if (MyGeneration = Generation):
            Restore()

    # Shows / hides the meshes on this entity and its descendants. Also toggles the touch volume (character_surface_component)
    Show<private>(Visible:logic):void =
        for (Mesh : Entity.FindDescendantComponents(mesh_component)):
            ShowMesh(Mesh, Visible)
        for (Each : Entity.GetComponents(), Mesh := mesh_component[Each]):
            ShowMesh(Mesh, Visible)
        if (Surface := Entity.GetComponent[character_surface_component]):
            Surface.SetActive(Visible)

    ShowMesh<private>(Mesh:mesh_component, Visible:logic):void =
        if (Visible?):
            Mesh.Enable()
        else:
            Mesh.Disable()
