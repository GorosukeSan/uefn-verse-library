using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Fortnite.com/Input }
using { /UnrealEngine.com/Itemization }
using { AbilitySystem }
using { ItemSystem }
using { InputSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { JetpackSystem.TooltipKit }

# Role: the jetpack ability. When a granted agent presses BoostAction (default Jump) in the air, charging starts (pressing on the ground does nothing; it is a normal jump); on release they launch in the direction of BoostPitchDegrees / BoostYawDegrees
#   Charge: lifts by ChargeLiftCm, then every frame sets the velocity to "horizontal 0, up ChargeRiseSpeedCmPerSecond" to hover. After MaxChargeSeconds they can keep hovering at maximum
#   Launch: for BoostDurationSeconds, sets the speed every frame to BoostSpeedCmPerSecond x (1 - elapsed / duration)^BoostEaseExponent. Distance is x1 up to MinChargeSeconds and x MaxChargeMultiplier at MaxChargeSeconds (both the initial speed and the duration are multiplied by the square root of the multiplier)
#   Glide: once charging has started, no new charge until landing; holding the button in the air meanwhile limits the fall speed to GlideMaxFallSpeedCmPerSecond
#   With energy (FindEnergyFor: the energy_component of this entity or a child, otherwise the one attached to the player), consumes BoostEnergyCost the moment the charge reaches maximum (or the moment of release if earlier) and GlideEnergyPerSecond per second while gliding (launching works even when short; energy goes to 0).
#   At 0, neither charging nor gliding is possible. When this entity is an item and RemoveItemWhenEmpty is on, the item disappears when energy reaches 0 (after the flight ends if mid-flight)
# How it is granted is chosen by the component placed on the same entity:
#   - As an item (while equipped) -> place on the item's entity together with item_component, item_holder_component and ability_grant_item_component. Put the energy on the item's entity.
#     exclusive_item_component to limit to one per player. item_equip_lock_component to prevent switching items while charging / flying (locked when present)
#   - To everyone from the start / while active -> ability_grant_players_component (energy on this entity is shared by everyone; attach it to the players for per-player energy)
#   - While a condition is satisfied -> ability_grant_condition_component (conditions as children)
#   - From code -> Grant / Revoke
# Effects: when this entity has fort_item_ability_component, its ItemEquippedAbilities are used on the agent while charging, launching and gliding
# Notifies: BoostRatioChangedEvent and jetpack_boost_changed_event (upward and down under the agent's slot) when the boost gauge changes
# Requirements: to send to the slot, a player_manager_component in the zone (or the world) (not sent without one)
jetpack_ability_component<public> := class<final_super>(ability_component):

    # Speed at the moment of launch with a x1 charge (centimeters per second. Default 3000)
    @editable_number(float):
        ToolTip := JetpackBoostSpeedToolTip
        Categories := array{JetpackCategory, JetpackLaunchCategory}
        MinValue := option{0.0}
        MaxValue := option{20000.0}
    BoostSpeedCmPerSecond<public>:float = 3000.0
    # Seconds from launch until the speed reaches 0 with a x1 charge (default 0.8)
    @editable_number(float):
        ToolTip := JetpackBoostDurationToolTip
        Categories := array{JetpackCategory, JetpackLaunchCategory}
        MinValue := option{0.1}
        MaxValue := option{5.0}
    BoostDurationSeconds<public>:float = 0.8
    # Easing of the launch (speed = initial speed x (1 - elapsed / duration) to this power. 0 for constant, default 2)
    @editable_number(float):
        ToolTip := JetpackBoostEaseExponentToolTip
        Categories := array{JetpackCategory, JetpackLaunchCategory}
        MinValue := option{0.0}
        MaxValue := option{5.0}
    BoostEaseExponent<public>:float = 2.0
    # Vertical angle of the launch direction (degrees. 90 straight up, 0 horizontal, -90 straight down. Default 90)
    @editable_number(float):
        ToolTip := JetpackBoostPitchToolTip
        Categories := array{JetpackCategory, JetpackDirectionCategory}
        MinValue := option{-90.0}
        MaxValue := option{90.0}
    BoostPitchDegrees<public>:float = 90.0
    # Horizontal angle of the launch direction (degrees. 0 is straight ahead, positive is right. Default 0)
    @editable_number(float):
        ToolTip := JetpackBoostYawToolTip
        Categories := array{JetpackCategory, JetpackDirectionCategory}
        MinValue := option{-180.0}
        MaxValue := option{180.0}
    BoostYawDegrees<public>:float = 0.0
    # Charges up to this many seconds keep the launch distance at x1 (default 1)
    @editable_number(float):
        ToolTip := JetpackMinChargeSecondsToolTip
        Categories := array{JetpackCategory, JetpackChargeCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    MinChargeSeconds<public>:float = 1.0
    # Charging up to this many seconds gives the maximum distance (x MaxChargeMultiplier) and consumes energy (default 3)
    @editable_number(float):
        ToolTip := JetpackMaxChargeSecondsToolTip
        Categories := array{JetpackCategory, JetpackChargeCategory}
        MinValue := option{0.1}
        MaxValue := option{10.0}
    MaxChargeSeconds<public>:float = 3.0
    # Launch distance multiplier at full charge (default 3)
    @editable_number(float):
        ToolTip := JetpackMaxChargeMultiplierToolTip
        Categories := array{JetpackCategory, JetpackChargeCategory}
        MinValue := option{1.0}
        MaxValue := option{10.0}
    MaxChargeMultiplier<public>:float = 3.0
    # Height the position is lifted directly when charging starts (centimeters. Default 50)
    @editable_number(float):
        ToolTip := JetpackChargeLiftToolTip
        Categories := array{JetpackCategory, JetpackChargeCategory}
        MinValue := option{0.0}
        MaxValue := option{300.0}
    ChargeLiftCm<public>:float = 50.0
    # Rising speed while charging (centimeters per second. Default 50). 0 holds the height
    @editable_number(float):
        ToolTip := JetpackChargeRiseSpeedToolTip
        Categories := array{JetpackCategory, JetpackChargeCategory}
        MinValue := option{0.0}
        MaxValue := option{1000.0}
    ChargeRiseSpeedCmPerSecond<public>:float = 50.0
    # Energy consumed per launch (default 30). Launching works even when short; energy goes to 0
    @editable_number(float):
        ToolTip := JetpackBoostEnergyCostToolTip
        Categories := array{JetpackCategory, JetpackEnergyCategory}
        MinValue := option{0.0}
        MaxValue := option{1000.0}
    BoostEnergyCost<public>:float = 30.0
    # Energy consumed per second while gliding (default 1)
    @editable_number(float):
        ToolTip := JetpackGlideEnergyPerSecondToolTip
        Categories := array{JetpackCategory, JetpackEnergyCategory}
        MinValue := option{0.0}
        MaxValue := option{100.0}
    GlideEnergyPerSecond<public>:float = 1.0
    # When true (default), on an item the whole item disappears when energy reaches 0
    @editable:
        ToolTip := JetpackRemoveItemWhenEmptyToolTip
        Categories := array{JetpackCategory, JetpackEnergyCategory}
    RemoveItemWhenEmpty<public>:logic = true
    # Fall speed limit while gliding (centimeters per second. Default 300). 0 holds the height
    @editable_number(float):
        ToolTip := JetpackGlideMaxFallSpeedToolTip
        Categories := array{JetpackCategory, JetpackGlideCategory}
        MinValue := option{0.0}
        MaxValue := option{5000.0}
    GlideMaxFallSpeedCmPerSecond<public>:float = 300.0
    # The action pressed in the air to charge and released to launch. Default Jump
    @editable:
        ToolTip := JetpackBoostActionToolTip
        Categories := array{JetpackCategory, JetpackInputCategory}
    BoostAction<public>:input_action(logic) = Character.Jump
    # The key mapping enabled while granted. One containing BoostAction. Default TraversalMapping
    @editable:
        ToolTip := JetpackBoostMappingToolTip
        Categories := array{JetpackCategory, JetpackInputCategory}
    BoostMapping<public>:input_mapping = Character.TraversalMapping
    # When true, removes BoostMapping on revoke (only for a mapping dedicated to this ability. Default false)
    @editable:
        ToolTip := JetpackRemoveMappingToolTip
        Categories := array{JetpackCategory, JetpackInputCategory}
    RemoveMappingOnRevoke<public>:logic = false

    BoostRatioChangedEventInternal<private><final>:event(tuple(agent, float)) = event(tuple(agent, float)){}

    # Fires with (the agent, gauge 0.0-1.0) when someone's boost gauge changes (Await / Subscribe; cannot be Signaled from outside). Usable = 1, 0 to 1 while charging, 0 after launching until landing, 0 on revoke
    BoostRatioChangedEvent<public><final>:listenable(tuple(agent, float)) = MakeProxyListenable(BoostRatioChangedEventInternal)

    var Ratios<private>:[agent]float = map{}
    var Manager<private>:?player_manager_component = false

    # Agent's boost gauge (0.0-1.0). 0.0 for agents not granted
    GetBoostRatio<public>(Agent:agent)<transacts>:float =
        if (Ratio := Ratios[Agent]) then Ratio else 0.0

    RunFor<override>(Agent:agent)<suspends>:void =
        MaybeInput := Agent.AwaitPlayerInput()
        if (PlayerInput := MaybeInput?):
            CacheManager()
            Runner := jetpack_runner:
                Ability := Self
                Agent := Agent
                PlayerInput := PlayerInput
                Tick := TickEvents.PrePhysics
            Emptied := RunUntilEmpty(Runner)
            if (Emptied?):
                Entity.RemoveFromInventory()

    RunUntilEmpty<private>(Runner:jetpack_runner)<suspends>:logic =
        defer:
            Runner.Cleanup()
            SetBoostRatio(Runner.Agent, 0.0)
        Runner.Run()

    # Succeeds when the whole item should disappear when energy reaches 0 (RemoveItemWhenEmpty and this entity is an item)
    ShouldRemoveItemWhenEmpty<internal>()<decides><transacts>:void =
        RemoveItemWhenEmpty?
        Entity.GetComponent[item_component]

    SetBoostRatio<internal>(Agent:agent, Ratio:float):void =
        if (Ratios[Agent] = Ratio):
            return
        if (set Ratios[Agent] = Ratio) {}
        BoostRatioChangedEventInternal.Signal((Agent, Ratio))
        Changed := jetpack_boost_changed_event{Ability := Self, Agent := Agent, Ratio := Ratio}
        Entity.SendUp(Changed)
        if (Player := player[Agent], Found := Manager?, Slot := Found.FindSlot[Player]):
            Slot.Entity.SendDown(player_event{Sender := Self, Event := Changed})

    # Finds and remembers the player_manager_component used to send to the slot (no lookup when already remembered. Looked up at every RunFor start until found)
    CacheManager<private>():void =
        set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)
