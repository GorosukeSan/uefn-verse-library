using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Input }
using { /Fortnite.com/Characters }
using { /UnrealEngine.com/Abilities }
using { EnergySystem }
using { ItemSystem }
using { InputSystem }
using { ItemSystem.RuleKit }
using { MovementSystem }
using { PlayerSystem }

# Role: runtime class that jetpack_ability_component creates and runs for each granted agent. Holds the charge, launch, glide and landing watch (see jetpack_ability_component for the details of the movement)
# Tags: from charging until the flight ends (while the velocity is being controlled), attaches jetpack_boosting_tag to the agent (the same span as SetLocked)
# Requirements: per-frame waits use the Tick (TickEvents.PrePhysics) passed in from the owning component. Elapsed time is measured by summing its return value (seconds since the previous frame)
jetpack_runner<internal> := class<internal>:

    Ability<internal>:jetpack_ability_component
    Agent<internal>:agent
    PlayerInput<internal>:player_input
    Tick<internal>:listenable(float)

    var Ready<private>:logic = true
    var Charging<private>:logic = false
    var Flying<private>:logic = false
    var Paid<private>:logic = false
    var Locked<private>:logic = false
    var ChargeElapsed<private>:float = 0.0
    # The jetpack_boosting_tag attached to the agent from charging until the flight ends
    BoostingTags<private>:player_tag_holder = player_tag_holder{}

    LaunchEvent<private>:event(tuple(vector3, float)) = event(tuple(vector3, float)){}
    AirborneEvent<private>:event() = event(){}

    # Runs until revoked. Returns true and ends only when energy reached 0 and the whole item should disappear (ShouldRemoveItemWhenEmpty)
    Run<internal>()<suspends>:logic =
        Ability.SetBoostRatio(Agent, 1.0)
        race:
            block:
                PlayerInput.HoldInputMapping(Ability.BoostMapping, Ability.RemoveMappingOnRevoke)
                false
            block:
                WatchLanding()
                false
            RunInput()
            RunFlights()

    # Cleanup when stopped (releases the lock)
    Cleanup<internal>():void =
        SetLocked(false)

    RunInput<private>()<suspends>:logic =
        loop:
            PlayerInput.AwaitPressed(Ability.BoostAction)
            if (Ready?):
                if (not IsEmpty[], FortCharacter := Agent.GetFortCharacter[], FortCharacter.IsInAir[]):
                    ChargeSeconds := ChargeUntilReleased()
                    PayBoost()
                    Launch(ChargeSeconds)
            else if (not IsEmpty[]):
                Emptied := GlideUntilReleased()
                if (Emptied?, not Flying?, Ability.ShouldRemoveItemWhenEmpty[]):
                    return true

    RunFlights<private>()<suspends>:logic =
        loop:
            Launched := LaunchEvent.Await()
            Fly(Launched(0), Launched(1))
            SetLocked(false)
            if (IsEmpty[], Ability.ShouldRemoveItemWhenEmpty[]):
                return true

    # From the start of charging until landing, checks for landing every frame (does nothing while on the ground)
    WatchLanding<private>()<suspends>:void =
        loop:
            AirborneEvent.Await()
            loop:
                Tick.Await()
                if (not Charging?, not Flying?, FortCharacter := Agent.GetFortCharacter[], FortCharacter.IsOnGround[]):
                    set Ready = true
                    Ability.SetBoostRatio(Agent, 1.0)
                    break

    ChargeUntilReleased<private>()<suspends>:float =
        set Ready = false
        set Charging = true
        set Paid = false
        set ChargeElapsed = 0.0
        SetLocked(true)
        AirborneEvent.Signal()
        Ability.SetBoostRatio(Agent, 0.0)
        Effects := Ability.Entity.BeginItemAbilities(Agent)
        defer:
            EndItemAbilities(Effects)
            set Charging = false
        if (FortCharacter := Agent.GetFortCharacter[]):
            FortCharacter.LiftBy(Ability.ChargeLiftCm)
        race:
            PlayerInput.AwaitReleased(Ability.BoostAction)
            ChargeEachFrame()
        ChargeElapsed

    ChargeEachFrame<private>()<suspends>:void =
        loop:
            DeltaTime := Tick.Await()
            set ChargeElapsed += DeltaTime
            if (FortCharacter := Agent.GetFortCharacter[]):
                # SetLinearVelocity is in meters per second
                FortCharacter.SetLinearVelocity(vector3{Up := Ability.ChargeRiseSpeedCmPerSecond / 100.0})
            Ability.SetBoostRatio(Agent, Min(ChargeElapsed / Ability.MaxChargeSeconds, 1.0))
            if (ChargeElapsed >= Ability.MaxChargeSeconds):
                PayBoost()

    PayBoost<private>():void =
        if (not Paid?):
            set Paid = true
            if (Energy := Ability.Entity.FindEnergyFor[Agent]):
                Energy.Consume(Ability.BoostEnergyCost)

    Launch<private>(ChargeSeconds:float):void =
        Ability.SetBoostRatio(Agent, 0.0)
        if (FortCharacter := Agent.GetFortCharacter[]):
            Direction := GetBoostDirection(FortCharacter)
            Scale := Sqrt(GetDistanceMultiplier(ChargeSeconds))
            set Flying = true
            LaunchEvent.Signal((Direction, Scale))
        else:
            SetLocked(false)

    Fly<private>(Direction:vector3, Scale:float)<suspends>:void =
        set Flying = true
        Effects := Ability.Entity.BeginItemAbilities(Agent)
        defer:
            EndItemAbilities(Effects)
            set Flying = false
        # SetLinearVelocity is in meters per second
        InitialSpeed := Ability.BoostSpeedCmPerSecond / 100.0 * Scale
        Duration := Ability.BoostDurationSeconds * Scale
        var Elapsed:float = 0.0
        loop:
            if (Elapsed >= Duration):
                break
            if (FortCharacter := Agent.GetFortCharacter[]):
                Remaining := 1.0 - Elapsed / Duration
                Speed := InitialSpeed * Pow(Remaining, Ability.BoostEaseExponent)
                FortCharacter.SetLinearVelocity(Direction * Speed)
            else:
                break
            set Elapsed += Tick.Await()

    # Until released or landed, limits the fall speed and consumes energy. true when stopped because energy reached 0
    GlideUntilReleased<private>()<suspends>:logic =
        Effects := Ability.Entity.BeginItemAbilities(Agent)
        defer:
            EndItemAbilities(Effects)
        race:
            block:
                PlayerInput.AwaitReleased(Ability.BoostAction)
                false
            GlideEachFrame()

    GlideEachFrame<private>()<suspends>:logic =
        loop:
            DeltaTime := Tick.Await()
            if (FortCharacter := Agent.GetFortCharacter[]):
                if (FortCharacter.IsOnGround[]):
                    return false
                SlowFall(FortCharacter)
                if (Energy := Ability.Entity.FindEnergyFor[Agent]):
                    Energy.Consume(Ability.GlideEnergyPerSecond * DeltaTime)
                    if (Energy.IsEmpty[]):
                        return true

    SlowFall<private>(FortCharacter:fort_character):void =
        Velocity := FortCharacter.GetLinearVelocity()
        # GetLinearVelocity / SetLinearVelocity are in meters per second
        MaxFall := Ability.GlideMaxFallSpeedCmPerSecond / 100.0
        if (Velocity.Up < -MaxFall):
            FortCharacter.SetLinearVelocity(vector3{Forward := Velocity.Forward, Left := Velocity.Left, Up := -MaxFall})

    IsEmpty<private>()<decides><transacts>:void =
        Ability.Entity.FindEnergyFor[Agent].IsEmpty[]

    SetLocked<private>(Value:logic):void =
        if (Locked = Value):
            return
        set Locked = Value
        BoostingTags.Set(Agent, Value, jetpack_boosting_tag{})
        if (Lock := Ability.Entity.GetComponent[item_equip_lock_component]):
            if (Value?):
                Lock.Lock()
            else:
                Lock.Unlock()

    GetDistanceMultiplier<private>(ChargeSeconds:float)<reads>:float =
        MinSeconds := Ability.MinChargeSeconds
        MaxSeconds := Ability.MaxChargeSeconds
        if (ChargeSeconds <= MinSeconds or MaxSeconds <= MinSeconds):
            1.0
        else:
            Progress := Min((ChargeSeconds - MinSeconds) / (MaxSeconds - MinSeconds), 1.0)
            1.0 + Progress * (Ability.MaxChargeMultiplier - 1.0)

    GetBoostDirection<private>(FortCharacter:fort_character)<transacts>:vector3 =
        View := FortCharacter.GetViewDirection()
        Flat := vector3{Forward := View.Forward, Left := View.Left}
        var Facing:vector3 = vector3{Forward := 1.0}
        if (Flat.Length() > 0.001):
            set Facing = Flat.MakeUnitVector()
        Right := vector3{Forward := Facing.Left, Left := -Facing.Forward}
        Up := vector3{Up := 1.0}
        Yaw := DegreesToRadians(Ability.BoostYawDegrees)
        Pitch := DegreesToRadians(Ability.BoostPitchDegrees)
        Horizontal := Facing * Cos(Yaw) + Right * Sin(Yaw)
        Horizontal * Cos(Pitch) + Up * Sin(Pitch)
