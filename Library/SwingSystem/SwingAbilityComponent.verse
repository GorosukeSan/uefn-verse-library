using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Fortnite.com/Input }
using { /UnrealEngine.com/Abilities }
using { AbilitySystem }
using { InputSystem }
using { ItemSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { SwingSystem.TooltipKit }

# Role: the swing ability. Runs a swing_runner for each agent it is granted to (the movement details are in the swing_runner description). Grabbing uses GrabAction (default: fire)
# How it is granted is chosen by the component placed on the same entity:
#   - everyone from the start / while activated -> ability_grant_players_component
#   - as an item (while equipped) -> place on the item entity together with item_component, item_holder_component and ability_grant_item_component
#   - while a condition is satisfied -> ability_grant_condition_component (condition on a child)
#   - from code -> Grant / Revoke
# Notifies: the swing_runner notifications (swing_target_changed_event, swing_grabbed_event, swing_rope_detached_event, swing_released_event, swing_state_changed_event, swing_reel_hint_event, swing_stats_changed_event) are sent under the agent's slot as player_event (received by that agent's HUD and other views) and also sent up from this entity. From code, subscribe to StateChangedEvent / GrabbedEvent / RopeDetachedEvent / ReleasedEvent
# From outside: Release(Agent) forces a release. Read the current state from the tags, not the ability (Agent.IsSwinging[] / Agent.GetSwingState(); SwingEvent.verse)
# Tags: while grabbing, the agent gets swing_anchored_tag when waiting on the ground or swing_pendulum_tag when swinging (both swinging_tag <- controlled_movement_tag subclasses). Other Systems can check with Agent.HasPlayerTag[swinging_tag]
# Effects: if this entity has a fort_item_ability_component, its ItemEquippedAbilities are used on the agent while swinging
# Requirements: a player_manager_component (to send to the slot) and a swing_registry_component (for rope pulling and modifiers; optional) in the scope (or the world). Both are looked up once and remembered
# Settings: listed directly on this component (to share the same settings among several abilities, make the ability entity a prefab). Lengths in cm, speeds in cm/s, accelerations in cm/s^2, times in seconds
swing_ability_component<public> := class<final_super>(ability_component):

    # Input that attaches a rope to the object beyond the reticle and grabs it. Pressing it again while grabbing reels in. Default WeaponPrimary
    @editable:
        ToolTip := SwingGrabActionToolTip
        Categories := array{SwingCategory, SwingInputCategory}
    GrabAction<public>:input_action(logic) = Character.WeaponPrimary
    # Input mapping that contains GrabAction. Default RangedWeaponMapping (kept, not removed)
    @editable:
        ToolTip := SwingGrabMappingToolTip
        Categories := array{SwingCategory, SwingInputCategory}
    GrabMapping<public>:input_mapping = Character.RangedWeaponMapping
    # Input that accelerates while held after grabbing and releases the rope when let go. Launches while waiting on the ground. Default Jump
    @editable:
        ToolTip := SwingReleaseActionToolTip
        Categories := array{SwingCategory, SwingInputCategory}
    ReleaseAction<public>:input_action(logic) = Character.Jump
    # Input mapping that contains ReleaseAction. Default TraversalMapping (kept, not removed)
    @editable:
        ToolTip := SwingReleaseMappingToolTip
        Categories := array{SwingCategory, SwingInputCategory}
    ReleaseMapping<public>:input_mapping = Character.TraversalMapping
    # Input that reels out while held during a grab. Releases the rope while waiting on the ground. Default WeaponSecondary
    @editable:
        ToolTip := SwingReelOutActionToolTip
        Categories := array{SwingCategory, SwingInputCategory}
    ReelOutAction<public>:input_action(logic) = Character.WeaponSecondary
    # Input mapping that contains ReelOutAction. Default RangedWeaponMapping (kept, not removed)
    @editable:
        ToolTip := SwingReelOutMappingToolTip
        Categories := array{SwingCategory, SwingInputCategory}
    ReelOutMapping<public>:input_mapping = Character.RangedWeaponMapping

    # Grab range (centimeters; default 4000). Also the rope length limit when reeling out
    @editable_number(float):
        ToolTip := SwingMaxRangeToolTip
        Categories := array{SwingCategory, SwingGrabCategory}
        MinValue := option{100.0}
        MaxValue := option{20000.0}
    MaxRangeCm<public>:float = 4000.0
    # Radius of the grab test sphere (centimeters; default 50). 0 uses a point test
    @editable_number(float):
        ToolTip := SwingGrabRadiusToolTip
        Categories := array{SwingCategory, SwingGrabCategory}
        MinValue := option{0.0}
        MaxValue := option{500.0}
    GrabRadiusCm<public>:float = 50.0
    # Time the last point found can still be grabbed after the reticle leaves it (seconds; default 0.5)
    @editable_number(float):
        ToolTip := SwingGrabGraceSecondsToolTip
        Categories := array{SwingCategory, SwingGrabCategory}
        MinValue := option{0.0}
        MaxValue := option{3.0}
    GrabGraceSeconds<public>:float = 0.5
    # A press made while grabbing is used for a grab right after release if the release follows within this time (seconds; default 0.3)
    @editable_number(float):
        ToolTip := SwingGrabBufferSecondsToolTip
        Categories := array{SwingCategory, SwingGrabCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    GrabBufferSeconds<public>:float = 0.3
    # Height the body is lifted by moving its position directly before launching from the ground (centimeters; default 20)
    @editable_number(float):
        ToolTip := SwingGrabLiftHeightToolTip
        Categories := array{SwingCategory, SwingGrabCategory}
        MinValue := option{0.0}
        MaxValue := option{300.0}
    GrabLiftHeightCm<public>:float = 20.0
    # Speed added in the direction of motion at the moment of launch (centimeters per second; default 300)
    @editable_number(float):
        ToolTip := SwingGrabKickSpeedToolTip
        Categories := array{SwingCategory, SwingGrabCategory}
        MinValue := option{0.0}
        MaxValue := option{3000.0}
    GrabKickSpeedCmPerSecond<public>:float = 300.0
    # Multiplier for the launch momentum when grabbing on the ground and jumping (relative to grabbing in the air; default 2)
    @editable_number(float):
        ToolTip := SwingGroundLaunchMultiplierToolTip
        Categories := array{SwingCategory, SwingGrabCategory}
        MinValue := option{1.0}
        MaxValue := option{10.0}
    GroundLaunchMultiplier<public>:float = 2.0
    # Time after launch during which touching the ground does not count as landing (seconds; default 1)
    @editable_number(float):
        ToolTip := SwingLandingGraceSecondsToolTip
        Categories := array{SwingCategory, SwingGrabCategory}
        MinValue := option{0.0}
        MaxValue := option{5.0}
    LandingGraceSeconds<public>:float = 1.0
    # Shortest length the rope can be reeled in to (centimeters; default 200)
    @editable_number(float):
        ToolTip := SwingMinRopeLengthToolTip
        Categories := array{SwingCategory, SwingRopeCategory}
        MinValue := option{50.0}
        MaxValue := option{5000.0}
    MinRopeLengthCm<public>:float = 200.0
    # How fast the rope length changes when reeling in / out by input (centimeters per second; default 500)
    @editable_number(float):
        ToolTip := SwingReelSpeedToolTip
        Categories := array{SwingCategory, SwingRopeCategory}
        MinValue := option{0.0}
        MaxValue := option{5000.0}
    ReelSpeedCmPerSecond<public>:float = 500.0
    # Fraction of the excess beyond the rope length pulled back per second (default 5; larger is stiffer)
    @editable_number(float):
        ToolTip := SwingRopeCorrectionRateToolTip
        Categories := array{SwingCategory, SwingRopeCategory}
        MinValue := option{0.0}
        MaxValue := option{50.0}
    RopeCorrectionRate<public>:float = 5.0
    # Time after the pendulum starts during which the rope reels in automatically (seconds; default 1). 0 disables it
    @editable_number(float):
        ToolTip := SwingAutoReelSecondsToolTip
        Categories := array{SwingCategory, SwingRopeCategory}
        MinValue := option{0.0}
        MaxValue := option{5.0}
    AutoReelSeconds<public>:float = 1.0
    # How far the rope reels in automatically, as a ratio of its length at launch (default 0.67; 1 disables it)
    @editable_number(float):
        ToolTip := SwingAutoReelRatioToolTip
        Categories := array{SwingCategory, SwingRopeCategory}
        MinValue := option{0.1}
        MaxValue := option{1.0}
    AutoReelRatio<public>:float = 0.67
    # Upper limit of the speed at which the excess is pulled back (centimeters per second; default 1000)
    @editable_number(float):
        ToolTip := SwingMaxRopeCorrectionSpeedToolTip
        Categories := array{SwingCategory, SwingRopeCategory}
        MinValue := option{0.0}
        MaxValue := option{5000.0}
    MaxRopeCorrectionSpeedCmPerSecond<public>:float = 1000.0
    # Speed added in the direction of motion on release (centimeters per second; default 600)
    @editable_number(float):
        ToolTip := SwingReleaseBoostToolTip
        Categories := array{SwingCategory, SwingReleaseCategory}
        MinValue := option{0.0}
        MaxValue := option{5000.0}
    ReleaseBoostCmPerSecond<public>:float = 600.0
    # Acceleration while ReleaseAction is held during a swing (centimeters per second squared; default 1000)
    @editable_number(float):
        ToolTip := SwingHoldAccelerationToolTip
        Categories := array{SwingCategory, SwingBoostCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    HoldAccelerationCmPerSecondSquared<public>:float = 1000.0
    # Upper limit of the speed while accelerating with hold (centimeters per second; default 4500)
    @editable_number(float):
        ToolTip := SwingMaxHoldSpeedToolTip
        Categories := array{SwingCategory, SwingBoostCategory}
        MinValue := option{100.0}
        MaxValue := option{15000.0}
    MaxHoldSpeedCmPerSecond<public>:float = 4500.0
    # Total speed added over SwingEaseSeconds after launch (centimeters per second; default 400)
    @editable_number(float):
        ToolTip := SwingStartSpeedToolTip
        Categories := array{SwingCategory, SwingPendulumCategory}
        MinValue := option{0.0}
        MaxValue := option{5000.0}
    SwingStartSpeedCmPerSecond<public>:float = 400.0
    # Time until the start speed has been fully added (seconds; default 0.3)
    @editable_number(float):
        ToolTip := SwingEaseSecondsToolTip
        Categories := array{SwingCategory, SwingPendulumCategory}
        MinValue := option{0.05}
        MaxValue := option{3.0}
    SwingEaseSeconds<public>:float = 0.3
    # Gravity used by the pendulum calculation (centimeters per second squared; default 980)
    @editable_number(float):
        ToolTip := SwingGravityToolTip
        Categories := array{SwingCategory, SwingPendulumCategory}
        MinValue := option{0.0}
        MaxValue := option{6000.0}
    SwingGravityCmPerSecondSquared<public>:float = 980.0
    # Acceleration added toward the look direction while grabbing (centimeters per second squared; default 300)
    @editable_number(float):
        ToolTip := SwingSteerAccelerationToolTip
        Categories := array{SwingCategory, SwingPendulumCategory}
        MinValue := option{0.0}
        MaxValue := option{5000.0}
    SwingSteerAccelerationCmPerSecondSquared<public>:float = 300.0
    # Air drag of the pendulum (this fraction of the speed is lost per second; default 0.15)
    @editable_number(float):
        ToolTip := SwingDragToolTip
        Categories := array{SwingCategory, SwingPendulumCategory}
        MinValue := option{0.0}
        MaxValue := option{5.0}
    SwingDrag<public>:float = 0.15
    # Upper limit of the pendulum speed (centimeters per second; default 2500)
    @editable_number(float):
        ToolTip := SwingMaxSpeedToolTip
        Categories := array{SwingCategory, SwingPendulumCategory}
        MinValue := option{100.0}
        MaxValue := option{10000.0}
    MaxSwingSpeedCmPerSecond<public>:float = 2500.0
    # Number of ropes that can be attached at the same time (default 1). 2 or more lets you attach to another point while swinging
    @editable_number(int):
        ToolTip := SwingMaxRopesToolTip
        Categories := array{SwingCategory, SwingMultiCategory}
        MinValue := option{1}
        MaxValue := option{5}
    MaxRopes<public>:int = 1
    # Multiplier for how strongly you are pulled back while your rope is attached to another player (default 0.5)
    @editable_number(float):
        ToolTip := SwingPullerCorrectionRatioToolTip
        Categories := array{SwingCategory, SwingPullCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PullerCorrectionRatio<public>:float = 0.5
    # Speed at which a player pulled by a rope pull is dragged toward you (centimeters per second; default 800)
    @editable_number(float):
        ToolTip := SwingReelPullSpeedToolTip
        Categories := array{SwingCategory, SwingPullCategory}
        MinValue := option{0.0}
        MaxValue := option{6000.0}
    ReelPullSpeedCmPerSecond<public>:float = 800.0
    # Distance a rope pull drags the other player (centimeters; default 1000)
    @editable_number(float):
        ToolTip := SwingReelPullLengthToolTip
        Categories := array{SwingCategory, SwingPullCategory}
        MinValue := option{0.0}
        MaxValue := option{20000.0}
    ReelPullLengthCm<public>:float = 1000.0
    # While waiting on the ground with a rope attached to another player, follow once they are this many times MaxRangeCm away (default 0.25)
    @editable_number(float):
        ToolTip := SwingFollowDistanceRatioToolTip
        Categories := array{SwingCategory, SwingPullCategory}
        MinValue := option{0.05}
        MaxValue := option{1.0}
    FollowDistanceRatio<public>:float = 0.25

    StateChangedEventInternal<private><final>:event(tuple(agent, swing_state)) = event(tuple(agent, swing_state)){}
    GrabbedEventInternal<private><final>:event(tuple(agent, entity)) = event(tuple(agent, entity)){}
    RopeDetachedEventInternal<private><final>:event(tuple(agent, entity)) = event(tuple(agent, entity)){}
    ReleasedEventInternal<private><final>:event(agent) = event(agent){}

    # Fires with (agent, new state) each time someone's swing state (idle / waiting on the ground / pendulum) changes (Await / Subscribe it; it cannot be Signaled from outside)
    StateChangedEvent<public><final>:listenable(tuple(agent, swing_state)) = MakeProxyListenable(StateChangedEventInternal)

    # Fires with (agent, entity of the grabbed point) each time one rope is attached
    GrabbedEvent<public><final>:listenable(tuple(agent, entity)) = MakeProxyListenable(GrabbedEventInternal)

    # Fires with (agent, entity of the detached point) each time only one of several ropes detaches
    RopeDetachedEvent<public><final>:listenable(tuple(agent, entity)) = MakeProxyListenable(RopeDetachedEventInternal)

    # Fires with the agent when all ropes are removed and released (released by the player, the point broke, or Release)
    ReleasedEvent<public><final>:listenable(agent) = MakeProxyListenable(ReleasedEventInternal)

    var<private> Runners:[agent]swing_runner = map{}
    var<private> Effects:[agent][]ability_effect = map{}
    var<private> Registry:?swing_registry_component = false
    var<private> PlayerManager:?player_manager_component = false
    # Tags attached to swinging agents (swing_anchored_tag / swing_pendulum_tag)
    var<private> SwingingTags:player_tag_holder = player_tag_holder{}

    # If Agent is grabbing (waiting on the ground or swinging), forces a release. No boost (ReleaseBoost) is added. Does nothing if not grabbing or not granted
    Release<public>(Agent:agent):void =
        if (Runner := Runners[Agent]):
            Runner.ForceRelease()

    RunFor<override>(Agent:agent)<suspends>:void =
        MaybeInput := Agent.AwaitPlayerInput()
        if (PlayerInput := MaybeInput?):
            Runner := swing_runner:
                Ability := Self
                Notify := OnSwingEvent
                Tick := TickEvents.PrePhysics
                Registry := FindRegistry()
                Agent := Agent
                PlayerInput := PlayerInput
            if (set Runners[Agent] = Runner) {}
            defer:
                ForgetRunner(Agent, Runner)
                EndEffects(Agent)
                SwingingTags.Remove(Agent)
            Runner.Run()
        else if (not player[Agent]):
            Print("[swing_ability_component] Granted to a non-player agent. No input can be read, so it does nothing")

    # Looks up the scope's swing_registry_component and remembers it (no search once remembered). false if not found
    FindRegistry<private>()<transacts>:?swing_registry_component =
        set Registry = Entity.ResolveScopedComponent(Registry, swing_registry_component)
        Registry

    # Looks up the scope's player_manager_component and remembers it (no search once remembered). false if not found
    FindPlayerManager<private>()<transacts>:?player_manager_component =
        set PlayerManager = Entity.ResolveScopedComponent(PlayerManager, player_manager_component)
        PlayerManager

    ForgetRunner<private>(Agent:agent, Runner:swing_runner):void =
        if (Current := Runners[Agent], Current = Runner):
            set Runners = Runners.RemoveKey(Agent)

    OnSwingEvent<private>(Agent:agent, SceneEvent:scene_event):void =
        if (Changed := swing_state_changed_event[SceneEvent]):
            EndEffects(Agent)
            if (Changed.State = swing_state.Swinging):
                Started := Entity.BeginItemAbilities(Agent)
                if (set Effects[Agent] = Started) {}
            UpdateStateTag(Agent, Changed.State)
            StateChangedEventInternal.Signal((Agent, Changed.State))
        else if (Grabbed := swing_grabbed_event[SceneEvent]):
            GrabbedEventInternal.Signal((Agent, Grabbed.Anchor))
        else if (Detached := swing_rope_detached_event[SceneEvent]):
            RopeDetachedEventInternal.Signal((Agent, Detached.Anchor))
        else if (swing_released_event[SceneEvent]):
            ReleasedEventInternal.Signal(Agent)
        SendToSlot(Agent, SceneEvent)
        Entity.SendUp(SceneEvent)

    # Swaps the tag to match the state (removes it for Idle)
    UpdateStateTag<private>(Agent:agent, State:swing_state):void =
        SwingingTags.Remove(Agent)
        if (Tag := MakeSwingStateTag(State)?):
            SwingingTags.Add(Agent, Tag)

    SendToSlot<private>(Agent:agent, SceneEvent:scene_event):void =
        # Look up and remember outside the if (a set inside the condition would be rolled back, losing the lookup, when there is no slot)
        MaybeManager := FindPlayerManager()
        if:
            Player := player[Agent]
            Manager := MaybeManager?
            Slot := Manager.FindSlot[Player]
        then:
            Slot.Entity.SendDown(player_event{Sender := Self, Event := SceneEvent})

    EndEffects<private>(Agent:agent):void =
        if (Current := Effects[Agent]):
            EndItemAbilities(Current)
            if (set Effects[Agent] = array{}) {}
