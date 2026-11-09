using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { ActivationSystem }
using { SceneGraphSystem }
using { PlayerSystem.TooltipKit }

# Whom an entity attached to a player is shown to
player_attach_visibility<public> := enum:
    # Shown to everyone
    Everyone
    # Shown only to the player it is attached to (a marker only you can see, etc.)
    OwnerOnly
    # Shown to everyone except that player (a name tag or icon above the head, etc.)
    OthersOnly

# Role: attaches an entity (Prefab) to a player's body and moves it with the body. Not parented to the body: it is made a child of this entity and based on the body with SetOrigin (entity_origin) (the body entity's contents are not touched)
#   Only one per player (calling AttachTo repeatedly still gives one). When the body entity changes (respawn etc.), the patrol every RefreshSeconds reattaches it (hidden while there is no body)
#   Whom to attach to: with AttachToEveryone, everyone on activation (including later joins). When off, decided by AttachTo / DetachFrom. On an owned entity (inside a character etc.), only the owner instead of everyone
# Placement: attach to an entity in the editor
# Parent: wherever the activation signal reaches (anywhere if ActiveOnBegin)
# When: from the start if ActiveOnBegin. Starts attaching on the activation signal (activated_event) or Activate, detaches from everyone on the deactivation signal (deactivated_event) or Deactivate
# Notifies: AttachedEvent (the player, the attached entity) on attach, DetachedEvent on detach
# From outside: Activate / Deactivate / AttachTo / DetachFrom / DetachAll / FindAttached / IsAttachedTo
# Requirements: one player_manager_component in the scope (or world) (when AttachToEveryone)
# ⚠ Unverified: whether an entity attached to the body with entity_origin follows the body's facing and crouching
player_attach_component<public> := class<final_super>(component):

    # The entity (prefab) to attach. Left at the default entity, it is an empty entity
    @editable:
        ToolTip := AttachPrefabToolTip
        Categories := array{AttachCategory}
    Prefab<public>:concrete_subtype(entity) = entity
    # Offset from the body's origin (centimeters; Forward, Left, Up). Default is 200 straight up
    @editable:
        ToolTip := AttachOffsetToolTip
        Categories := array{AttachCategory}
    OffsetCm<public>:vector3 = vector3{Up := 200.0}
    # Whom it is shown to. Default Everyone
    @editable:
        ToolTip := AttachVisibilityToolTip
        Categories := array{AttachCategory}
    Visibility<public>:player_attach_visibility = player_attach_visibility.Everyone
    # When on, attaches to everyone on activation (including later joins). When off, only to players chosen with AttachTo. Default on
    @editable:
        ToolTip := AttachEveryoneToolTip
        Categories := array{AttachCategory}
    AttachToEveryone<public>:logic = true
    # When on, attaches from the start of the game. Default off
    @editable:
        ToolTip := AttachActiveOnBeginToolTip
        Categories := array{AttachCategory}
    ActiveOnBegin<public>:logic = false
    # Interval (seconds) of the patrol that checks whether the body changed (respawn etc.). Default 1
    @editable_number(float):
        ToolTip := AttachRefreshSecondsToolTip
        Categories := array{AttachCategory}
        MinValue := option{0.1}
        MaxValue := option{10.0}
    RefreshSeconds<public>:float = 1.0

    AttachedEventInternal<private><final>:event(tuple(agent, entity)) = event(tuple(agent, entity)){}
    DetachedEventInternal<private><final>:event(agent) = event(agent){}

    # Delivered with (the player, the attached entity) on attach (Await / Subscribe to it; it cannot be Signaled from outside)
    AttachedEvent<public><final>:listenable(tuple(agent, entity)) = MakeProxyListenable(AttachedEventInternal)

    # Delivered with the player on detach
    DetachedEvent<public><final>:listenable(agent) = MakeProxyListenable(DetachedEventInternal)

    var<private> Active:logic = false
    var<private> Attached:[agent]entity = map{}
    # The body at attach time (reattach when it changes)
    var<private> Bodies:[agent]entity = map{}
    var<private> AddedSubscription:?cancelable = false
    var<private> RemovedSubscription:?cancelable = false
    var<private> Manager:?player_manager_component = false
    StartEvent<private>:event() = event(){}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (ActiveOnBegin?):
            Activate()

    OnSimulate<override>()<suspends>:void =
        loop:
            if (not Active?):
                StartEvent.Await()
            Sleep(RefreshSeconds)
            if (Active?):
                Refresh()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Activate()
        else if (deactivated_event[SceneEvent]):
            Deactivate()
        false

    OnEndSimulation<override>():void =
        Deactivate()
        set Manager = false
        (super:)OnEndSimulation()

    # Start attaching (with AttachToEveryone: everyone present now and everyone who joins later). Does nothing if already active
    Activate<public>():void =
        if (Active?):
            return
        set Active = true
        StartEvent.Signal()
        if (OwningPlayer := Entity.FindOwningPlayer[]):
            # On an owned entity (inside a character etc.), attach only to the owner
            if (AttachToEveryone?):
                AttachTo(OwningPlayer)
        else if (Found := Entity.ResolveScopedComponent(Manager, player_manager_component)?):
            set Manager = option{Found}
            set RemovedSubscription = option{Found.PlayerRemovedEvent.Subscribe(OnPlayerRemoved)}
            if (AttachToEveryone?):
                set AddedSubscription = option{Found.PlayerAddedEvent.Subscribe(OnPlayerAdded)}
                for (Slot : Found.GetSlots()):
                    AttachTo(Slot.Player)

    # Detach from everyone and stop attaching. Does nothing if not active
    Deactivate<public>():void =
        if (not Active?):
            return
        set Active = false
        AddedSubscription.CancelIfSet()
        set AddedSubscription = false
        RemovedSubscription.CancelIfSet()
        set RemovedSubscription = false
        DetachAll()

    # Attach to Agent (if already attached, returns that entity and does nothing). Activates if not active (with AttachToEveryone, everyone gets attached too)
    AttachTo<public>(Agent:agent):entity =
        if (not Active?):
            Activate()
        if (Existing := Attached[Agent]):
            return Existing
        Attachment := Prefab{}
        Entity.AddEntities(array{Attachment})
        if (set Attached[Agent] = Attachment) {}
        Follow(Agent, Attachment)
        AttachedEventInternal.Signal((Agent, Attachment))
        Attachment

    # Detach from Agent (does nothing if not attached)
    DetachFrom<public>(Agent:agent):void =
        if (Attachment := Attached[Agent]):
            set Attached = Attached.RemoveKey(Agent)
            set Bodies = Bodies.RemoveKey(Agent)
            Attachment.RemoveFromParent()
            DetachedEventInternal.Signal(Agent)

    # Detach from everyone
    DetachAll<public>():void =
        for (Agent -> Attachment : Attached):
            DetachFrom(Agent)

    # The entity attached to Agent. Fails if not attached
    FindAttached<public>(Agent:agent)<decides><transacts>:entity =
        Attached[Agent]

    # Succeeds if attached to Agent
    IsAttachedTo<public>(Agent:agent)<decides><transacts>:void =
        Attached[Agent]

    OnPlayerAdded<private>(Player:player):void =
        if (Active?, AttachToEveryone?):
            AttachTo(Player)

    OnPlayerRemoved<private>(Player:player):void =
        DetachFrom(Player)

    # Base on the body and decide whom to show to. Hide if there is no body
    Follow<private>(Agent:agent, Attachment:entity):void =
        if (Body := Agent.FindPlayerEntity[]):
            if (set Bodies[Agent] = Body) {}
            Attachment.SetOrigin(entity_origin{Entity := Body})
            Attachment.SetLocalTransform(MakeTranslationTransform(OffsetCm))
            ApplyVisibility(Agent, Attachment)
        else:
            set Bodies = Bodies.RemoveKey(Agent)
            Attachment.SetPresentableToPlayers(option{array{}})

    # Reattach for players whose body changed (respawn), disappeared or came back. Also redecide whom to show to from the current participants
    Refresh<private>():void =
        for (Agent -> Attachment : Attached):
            if (Body := Agent.FindPlayerEntity[], Previous := Bodies[Agent], Body = Previous):
                ApplyVisibility(Agent, Attachment)
            else:
                Follow(Agent, Attachment)

    ApplyVisibility<private>(Agent:agent, Attachment:entity):void =
        case (Visibility):
            player_attach_visibility.Everyone =>
                Everyone:?[]player = false
                Attachment.SetPresentableToPlayers(Everyone)
            player_attach_visibility.OwnerOnly =>
                if (Player := player[Agent]):
                    Attachment.SetPresentableToPlayers(option{array{Player}})
            player_attach_visibility.OthersOnly =>
                set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)
                if (Found := Manager?):
                    Others := for (Slot : Found.GetSlots(), Slot.Player <> Agent):
                        Slot.Player
                    Attachment.SetPresentableToPlayers(option{Others})
