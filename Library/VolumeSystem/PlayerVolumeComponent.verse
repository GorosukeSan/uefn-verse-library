using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { ActivationSystem }
using { MovementSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { VolumeSystem.TooltipKit }

# Shape of the volume
player_volume_shape<public> := enum:
    # Box (width x depth x height)
    Box
    # Upright cylinder (diameter = width; depth is unused)
    Cylinder

# Notification that a player entered the volume
# Direction: from the player_volume_component's entity to the root (SendUp)
# Sender: player_volume_component (Volume). Receivers: components on the same entity and ancestors (VolumeSystem Kits, your components). Not consumed
# Receivers tell "which volume" apart with Volume (for only the volume on your own entity, Entered.Volume.Entity = Entity)
player_volume_entered_event<public> := class(scene_event):
    # The volume that sent it
    Volume<public>:player_volume_component
    # The player who entered
    Agent<public>:agent

# Notification that a player left the volume (left, character gone, left the game, or the volume stopped)
# Direction, sender and receivers are the same as player_volume_entered_event
player_volume_exited_event<public> := class(scene_event):
    # The volume that sent it
    Volume<public>:player_volume_component
    # The player who left
    Agent<public>:agent

# Role: detects players entering and leaving a box or cylinder volume anchored at this entity's position and notifies about it. It holds no behavior (conditions, activation, effects); other components on the same entity or an ancestor receive the notification and decide (no inheritance)
#   Detection: while active, every PollIntervalSeconds seconds, (1) entities overlapping this entity's mesh are queried with FindOverlapHits and the player is taken from the possessable_component's Agent (⚠ unverified), (2) players not found that way have their character position compared with the volume (confirmed in UEFN). Either hit means inside
#   Volume: the center of the bottom face is this entity's position. Width WidthCm (forward/back) x depth DepthCm (left/right) x height HeightCm, multiplied by this entity's Scale. Rotation is ignored. HeightMarginCm of margin above and below (a character's position is the middle of its body, so make it larger for a thin floor-like volume)
# Placement: attach to an entity in the editor (no mesh is needed if you do not want a visual)
# Same entity / parent: components that receive the notification (ConditionKit's player_in_volume_condition_component, ActivationKit's volume_activation_component, your components)
# When: from the start if ActiveOnBegin. Starts on the activation signal (activated_event) and stops on the deactivation signal (deactivated_event). Activate / Deactivate can also be called from code
# Notifies: sends player_volume_entered_event / player_volume_exited_event upward only when something changed, and fires PlayerEnteredEvent / PlayerExitedEvent. When stopping, sends "exited" for everyone inside and then empties
# Tags: attaches in_volume_tag to the player (agent) while inside (does not say which volume)
# From outside: GetAgentsInside / GetInsideCount / IsInside / AwaitLeft / IsActive
# Requirements: one player_manager_component in the scope (or the world); remembered once found
player_volume_component<public> := class<final_super>(component):

    # Shape of the volume. Box is a box, Cylinder is an upright cylinder with diameter WidthCm (default Box)
    @editable:
        ToolTip := VolumeShapeToolTip
        Categories := array{VolumeCategory}
    Shape<public>:player_volume_shape = player_volume_shape.Box
    # Width of the volume (forward/back, cm). Multiplied by the entity's Scale. The diameter for a cylinder (default 100.0)
    @editable_number(float):
        ToolTip := VolumeWidthToolTip
        Categories := array{VolumeCategory}
        MinValue := option{1.0}
    WidthCm<public>:float = 100.0
    # Depth of the volume (left/right, cm). Multiplied by the entity's Scale. Unused for a cylinder (default 100.0)
    @editable_number(float):
        ToolTip := VolumeDepthToolTip
        Categories := array{VolumeCategory}
        MinValue := option{1.0}
    DepthCm<public>:float = 100.0
    # Height of the volume (cm). The bottom face is at the entity's position. Multiplied by the entity's Scale (default 100.0)
    @editable_number(float):
        ToolTip := VolumeHeightToolTip
        Categories := array{VolumeCategory}
        MinValue := option{1.0}
    HeightCm<public>:float = 100.0
    # Extra margin added above and below the volume (cm). Use about 300 for a thin floor-like volume (default 100.0)
    @editable_number(float):
        ToolTip := VolumeHeightMarginToolTip
        Categories := array{VolumeCategory}
        MinValue := option{0.0}
        MaxValue := option{2000.0}
    HeightMarginCm<public>:float = 100.0
    # Interval between checks (seconds). Shorter notices sooner but costs more (default 0.25)
    @editable_number(float):
        ToolTip := VolumePollIntervalToolTip
        Categories := array{VolumeCategory}
        MinValue := option{0.05}
        MaxValue := option{10.0}
    PollIntervalSeconds<public>:float = 0.25
    # true checks from the start of the simulation. false waits for the activation signal (default true)
    @editable:
        ToolTip := VolumeActiveOnBeginToolTip
        Categories := array{VolumeCategory}
    ActiveOnBegin<public>:logic = true

    PlayerEnteredEventInternal<private><final>:event(agent) = event(agent){}
    PlayerExitedEventInternal<private><final>:event(agent) = event(agent){}

    # Fires with the player each time someone enters (Await / Subscribe; cannot be signaled from outside)
    PlayerEnteredEvent<public><final>:listenable(agent) = MakeProxyListenable(PlayerEnteredEventInternal)

    # Fires with the player each time someone leaves (also for everyone inside when the volume stops)
    PlayerExitedEvent<public><final>:listenable(agent) = MakeProxyListenable(PlayerExitedEventInternal)

    var<private> Inside:[agent]logic = map{}
    var<private> InsideTags:player_tag_holder = player_tag_holder{}
    var<private> Active:logic = false
    var<private> Manager:?player_manager_component = false
    StopEvent<private>:event() = event(){}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (ActiveOnBegin?):
            Activate()

    OnSimulate<override>()<suspends>:void =
        loop:
            if (not Active?):
                StartEvent.Await()
            race:
                StopEvent.Await()
                PollWhileActive()

    StartEvent<private>:event() = event(){}

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Activate()
        else if (deactivated_event[SceneEvent]):
            Deactivate()
        false

    OnEndSimulation<override>():void =
        set Active = false
        LeaveAll()
        (super:)OnEndSimulation()

    # Starts checking. Does nothing if already checking
    Activate<public>():void =
        if (not Active?):
            set Active = true
            StartEvent.Signal()

    # Stops checking, sends "exited" for everyone inside and empties. Does nothing if already stopped
    Deactivate<public>():void =
        if (Active?):
            set Active = false
            StopEvent.Signal()
            LeaveAll()

    # Succeeds while checking
    IsActive<public>()<decides><transacts>:void =
        Active?

    # Players inside now (order is unspecified)
    GetAgentsInside<public>()<transacts>:[]agent =
        for (Agent -> Value : Inside, Value?):
            Agent

    # Number of players inside now
    GetInsideCount<public>()<transacts>:int =
        GetAgentsInside().Length

    # Succeeds if Agent is inside now
    IsInside<public>(Agent:agent)<decides><transacts>:void =
        Inside[Agent]?

    # Waits until Agent leaves (returns at once if not inside now)
    AwaitLeft<public>(Agent:agent)<suspends>:void =
        if (IsInside[Agent]):
            loop:
                Left := PlayerExitedEvent.Await()
                if (Left = Agent):
                    break

    # Succeeds if Position (world position, cm) is inside the volume. The volume follows this entity's current position and scale
    Contains<public>(Position:vector3)<decides><transacts>:void =
        Transform := Entity.GetGlobalTransform()
        Base := Transform.Translation
        HalfWidth := WidthCm * Transform.Scale.Forward / 2.0
        HalfDepth := DepthCm * Transform.Scale.Left / 2.0
        Height := HeightCm * Transform.Scale.Up
        Forward := Position.Forward - Base.Forward
        Left := Position.Left - Base.Left
        Position.Up >= Base.Up - HeightMarginCm
        Position.Up <= Base.Up + Height + HeightMarginCm
        if (Shape = player_volume_shape.Cylinder):
            Forward * Forward + Left * Left <= HalfWidth * HalfWidth
        else:
            Abs(Forward) <= HalfWidth
            Abs(Left) <= HalfDepth

    PollWhileActive<private>()<suspends>:void =
        loop:
            Poll()
            Sleep(PollIntervalSeconds)

    Poll<private>():void =
        # Find and remember the scope's player_manager_component (no lookup once remembered)
        set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)
        if (Found := Manager?):
            Overlapping := FindOverlappingAgents()
            for (Slot : Found.GetSlots()):
                Agent := Slot.Player
                if (Overlapping.Find[Agent]):
                    Enter(Agent)
                else if (Character := Agent.GetFortCharacter[], Character.IsActive[], Position := Character.FindGlobalTranslation[], Contains[Position]):
                    Enter(Agent)
                else:
                    Leave(Agent)
            # Remove players who left the game (no slot any more)
            for (Agent -> Value : Inside, Value?, Player := player[Agent], not Found.FindSlot[Player]):
                Leave(Agent)

    # Agents (possessable_component's Agent) controlling the entities currently overlapping this entity's mesh (one that reports overlaps). Empty without a mesh
    # ⚠ Unverified: whether a player's character entity appears in the overlap results and an agent can be read from possessable_component. Even if not, the position check finds them
    FindOverlappingAgents<private>()<transacts>:[]agent =
        for (Hit : Entity.FindOverlapHits(), Agent := Hit.TargetComponent.Entity.FindPossessingAgent[]):
            Agent

    Enter<private>(Agent:agent):void =
        if (not IsInside[Agent]):
            if (set Inside[Agent] = true) {}
            InsideTags.Set(Agent, true, in_volume_tag{})
            Entity.SendUp(player_volume_entered_event{Volume := Self, Agent := Agent})
            PlayerEnteredEventInternal.Signal(Agent)

    Leave<private>(Agent:agent):void =
        if (IsInside[Agent]):
            if (set Inside[Agent] = false) {}
            InsideTags.Remove(Agent)
            Entity.SendUp(player_volume_exited_event{Volume := Self, Agent := Agent})
            PlayerExitedEventInternal.Signal(Agent)

    LeaveAll<private>():void =
        for (Agent : GetAgentsInside()):
            Leave(Agent)
        set Inside = map{}
        InsideTags.RemoveAll()

# Tag attached to a player (agent) who is inside any player_volume_component (other Systems check with Agent.HasPlayerTag[in_volume_tag])
in_volume_tag<public> := class(player_state_tag):
