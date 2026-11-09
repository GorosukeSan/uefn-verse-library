using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SceneGraphSystem }
using { SwingSystem.TooltipKit }

# A set of multipliers that change the swing strength (values only; in the editor they go into swing_modifier_component). When several stack, combine them with Apply
swing_modifier<public> := struct:
    # Multiplier for the grab range (and the rope length limit when reeling out)
    RangeMultiplier<public>:float = 1.0
    # Multiplier for the pendulum speed limit
    SpeedMultiplier<public>:float = 1.0
    # Multiplier for the launch, steering and hold acceleration
    AccelerationMultiplier<public>:float = 1.0
    # Multiplier for the speed added on release
    BoostMultiplier<public>:float = 1.0
    # Multiplier for the reel-in / reel-out speed
    ReelMultiplier<public>:float = 1.0
    # Number added to the ropes that can be attached at the same time
    ExtraRopes<public>:int = 0
    # false forbids new grabs
    AllowGrab<public>:logic = true

# The combined modifiers currently applied. swing_registry_component.GetStats builds it by stacking every swing_modifier_component applied to the agent
swing_stats<public> := struct:
    # Scale applied to the grab range (and the rope length limit when reeling out)
    RangeScale<public>:float = 1.0
    # Scale applied to the pendulum speed limit
    SpeedScale<public>:float = 1.0
    # Scale applied to the launch, steering and hold acceleration
    AccelerationScale<public>:float = 1.0
    # Scale applied to the speed added on release
    BoostScale<public>:float = 1.0
    # Scale applied to the reel-in / reel-out speed
    ReelScale<public>:float = 1.0
    # Number added to the ropes that can be attached at the same time
    ExtraRopes<public>:int = 0
    # false forbids new grabs
    CanGrab<public>:logic = true

# Returns the result of stacking Modifier (multipliers are multiplied, rope counts added, grabbing allowed only when both are true). Stats itself is unchanged
(Stats:swing_stats).Apply<public>(Modifier:swing_modifier)<transacts>:swing_stats =
    swing_stats:
        RangeScale := Stats.RangeScale * Modifier.RangeMultiplier
        SpeedScale := Stats.SpeedScale * Modifier.SpeedMultiplier
        AccelerationScale := Stats.AccelerationScale * Modifier.AccelerationMultiplier
        BoostScale := Stats.BoostScale * Modifier.BoostMultiplier
        ReelScale := Stats.ReelScale * Modifier.ReelMultiplier
        ExtraRopes := Stats.ExtraRopes + Modifier.ExtraRopes
        CanGrab := if (Stats.CanGrab?, Modifier.AllowGrab?) then true else false

# The modifiers (swing_stats) applied to an agent changed
# Direction: swing_ability_component wraps it in a player_event and SendDowns it under the agent's slot, and SendUps it from the ability entity. Receivers: views such as the HUD. Not consumed
swing_stats_changed_event<public> := class(scene_event):
    # Ability that sent it
    Ability<public>:swing_ability_component
    # Agent whose modifiers changed
    Agent<public>:agent
    # Modifiers currently applied
    Stats<public>:swing_stats

# Request: apply the modifier to Agent (with an expiry)
# Direction: the sender (a power-up item, a touchable object, etc.) SendDowns / SendUps it to the entity of swing_modifier_grant_component. Receiver: that entity's swing_modifier_grant_component. Not consumed
swing_modifier_request_event<public> := class(scene_event):
    # Object that made the request
    Sender<public>:entity
    # Agent to apply the modifier to
    Agent<public>:agent

# Role: the modifier that changes the swing strength (the values). This component does not decide who it applies to
# Who and when is chosen by the ModifierKit components placed on the same entity:
#   - everyone while activated -> swing_modifier_all_component
#   - agents who received a request (swing_modifier_request_event), with an expiry -> swing_modifier_grant_component
#   - everyone while a condition is satisfied -> swing_modifier_condition_component (condition on a child)
#   - from code -> ApplyTo / RemoveFrom / ApplyToAll / RemoveFromAll
# Placement: attach to an entity in the editor (may also be created at runtime). At most one per entity
# Notifies: ChangedEvent when the targets change. Registers itself with the scope's swing_registry_component and notifies it on every change (the swing side rebuilds its modifier from that; it does not search every time)
# Requirements: one swing_registry_component in the scope (or the world) (without it modifiers have no effect)
swing_modifier_component<public> := class<final_super>(component):

    # Multiplier for the grab range (and the rope length limit when reeling out) (default 1 = unchanged)
    @editable_number(float):
        ToolTip := SwingModifierRangeToolTip
        Categories := array{SwingCategory, SwingModifierCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    RangeMultiplier<public>:float = 1.0
    # Multiplier for the pendulum speed limit (and the hold limit) (default 1 = unchanged)
    @editable_number(float):
        ToolTip := SwingModifierSpeedToolTip
        Categories := array{SwingCategory, SwingModifierCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    SpeedMultiplier<public>:float = 1.0
    # Multiplier for the launch momentum, the steering acceleration toward the look direction and the hold acceleration (default 1 = unchanged)
    @editable_number(float):
        ToolTip := SwingModifierAccelerationToolTip
        Categories := array{SwingCategory, SwingModifierCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    AccelerationMultiplier<public>:float = 1.0
    # Multiplier for the speed added on release (default 1 = unchanged)
    @editable_number(float):
        ToolTip := SwingModifierBoostToolTip
        Categories := array{SwingCategory, SwingModifierCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    BoostMultiplier<public>:float = 1.0
    # Multiplier for the reel-in / reel-out speed (default 1 = unchanged)
    @editable_number(float):
        ToolTip := SwingModifierReelToolTip
        Categories := array{SwingCategory, SwingModifierCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    ReelMultiplier<public>:float = 1.0
    # Number added to the ropes that can be attached at the same time (negative subtracts; never below 1; default 0)
    @editable_number(int):
        ToolTip := SwingModifierExtraRopesToolTip
        Categories := array{SwingCategory, SwingModifierCategory}
        MinValue := option{-4}
        MaxValue := option{4}
    ExtraRopes<public>:int = 0
    # false forbids new grabs (ropes already attached are kept; default true)
    @editable:
        ToolTip := SwingModifierAllowGrabToolTip
        Categories := array{SwingCategory, SwingModifierCategory}
    AllowGrab<public>:logic = true

    var<private> AllCount:int = 0
    var<private> AgentCounts:[agent]int = map{}
    var<private> Registry:?swing_registry_component = false

    ChangedEventInternal<private><final>:event() = event(){}

    # Fires when the targets change (Await / Subscribe it; it cannot be Signaled from outside)
    ChangedEvent<public><final>:listenable(tuple()) = MakeProxyListenable(ChangedEventInternal)

    # This component's modifier (the set of values)
    GetModifier<public>()<transacts>:swing_modifier =
        swing_modifier:
            RangeMultiplier := RangeMultiplier
            SpeedMultiplier := SpeedMultiplier
            AccelerationMultiplier := AccelerationMultiplier
            BoostMultiplier := BoostMultiplier
            ReelMultiplier := ReelMultiplier
            ExtraRopes := ExtraRopes
            AllowGrab := AllowGrab

    # Succeeds if applied to Agent (either applied to everyone or applied to that agent)
    IsAppliedTo<public>(Agent:agent)<decides><transacts>:void =
        AllCount > 0 or AgentCounts[Agent] > 0

    # Apply to everyone (increments a count. Calling RemoveFromAll the same number of times removes it. Does not touch other sources)
    ApplyToAll<public>():void =
        set AllCount += 1
        if (AllCount = 1):
            NotifyChanged()

    # Undo one ApplyToAll. At 0 it is removed from everyone (agents applied with ApplyTo keep it)
    RemoveFromAll<public>():void =
        if (AllCount > 0):
            set AllCount -= 1
            if (AllCount = 0):
                NotifyChanged()

    # Apply to Agent (increments a count. Calling RemoveFrom the same number of times removes it)
    ApplyTo<public>(Agent:agent):void =
        Count := GetAgentCount(Agent)
        if (set AgentCounts[Agent] = Count + 1) {}
        if (Count = 0):
            NotifyChanged()

    # Undo one ApplyTo. Does nothing if not applied
    RemoveFrom<public>(Agent:agent):void =
        Count := GetAgentCount(Agent)
        if (Count > 0):
            if (set AgentCounts[Agent] = Count - 1) {}
            if (Count = 1):
                NotifyChanged()

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Register()

    OnEndSimulation<override>():void =
        set AllCount = 0
        set AgentCounts = map{}
        if (Current := Registry?):
            Current.RemoveModifier(Self)
        set Registry = false
        (super:)OnEndSimulation()

    GetAgentCount<private>(Agent:agent)<transacts>:int =
        if (Count := AgentCounts[Agent]) then Count else 0

    # Looks up the scope's registry once and registers (if not found, tries again on the next change)
    Register<private>():void =
        if (not Registry?, Found := Entity.ResolveScopedComponent(Registry, swing_registry_component)?):
            set Registry = option{Found}
            Found.AddModifier(Self)

    NotifyChanged<private>():void =
        Register()
        ChangedEventInternal.Signal()
        if (Current := Registry?):
            Current.NotifyModifiersChanged()
