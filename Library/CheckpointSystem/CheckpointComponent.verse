using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { MovementSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { CheckpointSystem.TooltipKit }

# Notification that someone stepped onto a checkpoint. Direction: the whole zone (SendScoped: SendDown from the zone root; the whole world when there is no zone)
# Sender: checkpoint_component (Checkpoint). When Agent steps onto the top face (same timing as ReachedEvent; whether it is the first time does not matter)
# Receivers: checkpoint_presence_component, components counting arrivals, etc. Not consumed
checkpoint_reached_event<public> := class(scene_event):
    # The checkpoint stepped onto (the sender of the notification)
    Checkpoint<public>:checkpoint_component
    # The agent who stepped on
    Agent<public>:agent

# Notification that someone left a checkpoint. Direction: the whole zone (SendScoped: SendDown from the zone root; the whole world when there is no zone)
# Sender: checkpoint_component (Checkpoint). When Agent leaves the top face, leaves the game, or the checkpoint is removed from the world (same timing as LeftEvent)
# Receivers: checkpoint_presence_component, etc. Not consumed
checkpoint_left_event<public> := class(scene_event):
    # The checkpoint left (the sender of the notification)
    Checkpoint<public>:checkpoint_component
    # The agent who left (including players who left the game)
    Agent<public>:agent

# Tag attached to an agent standing on a checkpoint. Attached and removed by checkpoint_component (other Systems check with Agent.HasPlayerTag[on_checkpoint_tag])
on_checkpoint_tag<public> := class(player_state_tag):

# Role: a platform you can pass through from below and stand on, but cannot drop down from. Treated as a box centered on this entity's position, WidthCm wide, DepthCm deep and ThicknessCm thick (centimeters). Every frame, looks at every player in the zone and moves anyone moving upward from right below the box (within ApproachCm) onto the top face (looks like passing through a solid mesh; Verse cannot change collision per player). Also checks every frame whether they stand on the top face and notifies stepping on / leaving
#   The checkpoints of one zone are watched together in one place (the internal checkpoint_tracker). Player positions are read once per player per frame and compared with every checkpoint (not read once per checkpoint)
# Placement: attach to an entity in the editor (checkpoint_factory_component may also attach it at runtime)
# Same entity: a mesh with collision (sized WidthCm x DepthCm x ThicknessCm)
# When: from simulation start until it stops. All checkpoints of the zone are checked together in the TickEvents.PrePhysics of one of them
# Notifies: checkpoint_reached_event and ReachedEvent when stepped onto; checkpoint_left_event and LeftEvent when left. For players who leave the game and for players standing on it when it stops (is removed from the world), sends the left notification and clears the standing state
# Tags: while standing, attaches on_checkpoint_tag to the agent
# From outside: ask with IsStanding whether someone is standing on it (to ask where in the zone people are standing, use checkpoint_presence_component of PresenceKit)
# Requirements: one player_manager_component in the zone (game_scope_component; the world when there is none). The first one found is remembered (looked up every second until found)
checkpoint_component<public> := class<final_super>(component):

    ReachedEventInternal<private><final>:event(agent) = event(agent){}

    # Fires with the agent when they step onto the top (same timing as checkpoint_reached_event. Await / Subscribe; cannot be Signaled from outside)
    ReachedEvent<public><final>:listenable(agent) = MakeProxyListenable(ReachedEventInternal)

    LeftEventInternal<private><final>:event(agent) = event(agent){}

    # Fires with the agent when they leave the top, when a standing player leaves the game, or when this stops (same timing as checkpoint_left_event. Await / Subscribe; cannot be Signaled from outside)
    LeftEvent<public><final>:listenable(agent) = MakeProxyListenable(LeftEventInternal)

    # Width of the platform along Forward (centimeters). Match the mesh size. Default 750
    @editable_number(float):
        ToolTip := CheckpointWidthToolTip
        Categories := array{CheckpointCategory}
        MinValue := option{50.0}
        MaxValue := option{10000.0}
    WidthCm<public>:float = 750.0
    # Width of the platform along Left (centimeters). Match the mesh size. Default 750
    @editable_number(float):
        ToolTip := CheckpointDepthToolTip
        Categories := array{CheckpointCategory}
        MinValue := option{50.0}
        MaxValue := option{10000.0}
    DepthCm<public>:float = 750.0
    # Thickness of the platform (centimeters). Match the mesh size. Default 250
    @editable_number(float):
        ToolTip := CheckpointThicknessToolTip
        Categories := array{CheckpointCategory}
        MinValue := option{10.0}
        MaxValue := option{2000.0}
    ThicknessCm<public>:float = 250.0
    # Players moving upward from within this distance (centimeters) right below the platform are passed onto the top face. Default 300
    @editable_number(float):
        ToolTip := CheckpointApproachToolTip
        Categories := array{CheckpointCategory}
        MinValue := option{50.0}
        MaxValue := option{1000.0}
    ApproachCm<public>:float = 300.0

    EdgeMarginCm<private>:float = 40.0
    LandOffsetCm<private>:float = 100.0
    StandHeightCm<private>:float = 250.0

    var Standing<private>:[agent]logic = map{}
    var StandingTags<private>:player_tag_holder = player_tag_holder{}
    var Tracker<private>:?checkpoint_tracker = false
    var Tracking<private>:logic = false
    var DriveSubscription<private>:?cancelable = false
    var FrameCenter<private>:vector3 = vector3{}

    # Succeeds when Agent is standing on this platform. The result of the per-frame check, so up to one frame late. Fails for agents not yet checked, who left, or who left the game, and after this stops
    IsStanding<public>(Agent:agent)<decides><reads>:void =
        Standing[Agent]?

    # The agents currently standing on this platform
    GetStandingAgents<public>()<reads>:[]agent =
        for (Agent -> Value : Standing, Value?):
            Agent

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Shared := FindSharedTracker()
        set Tracker = option{Shared}
        set Tracking = true
        Shared.Register(Self)

    OnEndSimulation<override>():void =
        set Tracking = false
        if (Shared := Tracker?):
            Shared.Unregister(Self)
        set Tracker = false
        StopDriving()
        for (Agent -> Value : Standing, Value?):
            SetStanding(Agent, false)
        set Standing = map{}
        StandingTags.RemoveAll()
        (super:)OnEndSimulation()

    # The checkpoint_tracker used by a checkpoint that started earlier in the same zone (the world when there is no zone). Creates a new one when there is none
    # With nested zones, only checkpoints whose nearest zone is the same are used (so another zone's player_manager_component is not watched)
    FindSharedTracker<private>():checkpoint_tracker =
        MaybeRoot:?entity = if (Scope := Entity.FindScopeEntity[]) then option{Scope} else if (World := Entity.GetSimulationEntity[]) then option{World} else false
        if (Root := MaybeRoot?, Found := FindTrackerUnder[Root]):
            Found
        else:
            checkpoint_tracker{}

    FindTrackerUnder<private>(Root:entity)<decides><transacts>:checkpoint_tracker =
        first (Other : Root.FindDescendantComponents(checkpoint_component), Other <> Self, Shared := Other.Tracker?, IsInSameScope[Other]):
            Shared

    IsInSameScope<private>(Other:checkpoint_component)<decides><transacts>:void =
        if (Mine := Entity.FindScopeEntity[]):
            Theirs := Other.Entity.FindScopeEntity[]
            Mine = Theirs
        else:
            not Other.Entity.FindScopeEntity[]

    # Called by checkpoint_tracker: starts calling the checkpoint_tracker's Tick every frame from this checkpoint's TickEvents.PrePhysics
    StartDriving<internal>():void =
        if (not DriveSubscription?):
            set DriveSubscription = option{TickEvents.PrePhysics.Subscribe(OnDriverTick)}

    # Called by checkpoint_tracker: stops calling Tick
    StopDriving<internal>():void =
        DriveSubscription.CancelIfSet()
        set DriveSubscription = false

    OnDriverTick<private>(DeltaTime:float):void =
        if (Shared := Tracker?):
            Shared.Tick()

    # Called by checkpoint_tracker: reads the platform's position for this frame (not re-read per player)
    PrepareFrame<internal>():void =
        set FrameCenter = Entity.GetGlobalTranslation()

    # Called by checkpoint_tracker: checks Agent (at Position). true when moved from right below onto the top face (the caller re-reads the position)
    CheckAt<internal>(Agent:agent, FortCharacter:fort_character, Position:vector3):logic =
        var Moved:logic = false
        if (Tracking?):
            Center := FrameCenter
            Bottom := Center.Up - ThicknessCm / 2.0
            Top := Center.Up + ThicknessCm / 2.0
            if (IsAbove[Position, Center, EdgeMarginCm]):
                if (Position.Up < Bottom, Position.Up > Bottom - ApproachCm, FortCharacter.GetLinearVelocity().Up > 0.0):
                    set Moved = PassThrough(FortCharacter, Position, Top)
                UpdateStanding(Agent, FortCharacter, Position, Top)
            else:
                SetStanding(Agent, false)
        Moved

    # Called by checkpoint_tracker: clears the standing state of a player who left the game (sends the left notification if they were standing)
    ForgetAgent<internal>(Agent:agent):void =
        SetStanding(Agent, false)

    IsAbove<private>(Position:vector3, Center:vector3, MarginCm:float)<decides><reads>:void =
        Abs(Position.Forward - Center.Forward) <= WidthCm / 2.0 + MarginCm
        Abs(Position.Left - Center.Left) <= DepthCm / 2.0 + MarginCm

    PassThrough<private>(FortCharacter:fort_character, Position:vector3, Top:float):logic =
        if (CharacterEntity := FortCharacter.GetEntity[]):
            Current := CharacterEntity.GetGlobalTransform()
            Lifted := vector3{Forward := Position.Forward, Left := Position.Left, Up := Top + LandOffsetCm}
            CharacterEntity.SetGlobalTransform(Current.WithTranslation(Lifted))
            true
        else:
            false

    UpdateStanding<private>(Agent:agent, FortCharacter:fort_character, Position:vector3, Top:float):void =
        if (Position.Up >= Top, Position.Up <= Top + StandHeightCm, FortCharacter.IsOnGround[]):
            SetStanding(Agent, true)
        else:
            SetStanding(Agent, false)

    SetStanding<private>(Agent:agent, Value:logic):void =
        Was := logic{Standing[Agent]?}
        if (Was <> Value):
            if (set Standing[Agent] = Value) {}
            StandingTags.Set(Agent, Value, on_checkpoint_tag{})
            if (Value?):
                Entity.SendScoped(checkpoint_reached_event{Checkpoint := Self, Agent := Agent})
                ReachedEventInternal.Signal(Agent)
            else:
                Entity.SendScoped(checkpoint_left_event{Checkpoint := Self, Agent := Agent})
                LeftEventInternal.Signal(Agent)
