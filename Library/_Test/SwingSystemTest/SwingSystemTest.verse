using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { PlayerSystem }
using { SceneGraphSystem }
using { SwingSystem }
using { SwingSystem.ModifierKit }
using { SwingSystem.TargetKit }
using { _Test }

# Role: verification of SwingSystem. Uses the first player that joined and checks, in order:
#   1. Stacking of multipliers (swing_stats.Apply; no player needed)
#   2. Grant from code and the idle state (Agent.IsSwinging fails, Agent.GetSwingState is Idle, Release while idle does nothing)
#   2b. State tags: attaching / removing swing_anchored_tag / swing_pendulum_tag keeps Agent.IsSwinging / Agent.GetSwingState consistent with HasPlayerTag on the bases (swinging_tag, controlled_movement_tag) (without the ability)
#   3. Modifier registration: a swing_modifier_component created at runtime registers itself with the registry; ApplyTo / ApplyToAll / RemoveFrom change the registry's GetStats. A granted swing receives swing_stats_changed_event. swing_modifier_grant_component applies on request (swing_modifier_request_event) with a time limit and removes it when it expires
#   4. Lifetime target: swing_target_component + swing_life_component created at runtime does not break until grabbed (the test sends swing_attached_event), breaks LifeSeconds after being grabbed, and Breaks the attached anchor (swing_anchor_component)
#   5. Lift target: swing_target_component + swing_lift_component does not move when merely grabbed; when pulled (swing_pulled_event) it moves TravelCm and then breaks
#   6. Human input (when RunHumanTests is true): follow the log and press fire with the reticle on a grabbable object. Checks that GrabbedEvent arrives within HumanTimeoutSeconds, Agent.IsSwinging succeeds, and Release delivers ReleasedEvent and returns to Idle (prints [SKIP] if it does not arrive)
#   7. Revoke and RevokedEvent
# Test level:
#   - one entity with player_manager_component and one entity with swing_registry_component (in the same scope)
#   - the test entity carries swing_system_test_component and swing_ability_component (no grant component; the test Grants / Revokes from code)
#   - to check human input, place a mesh with collision (e.g. a cube) where the player can see it
# Result: [TEST] SwingSystem in the output log
swing_system_test_component<public> := class<final_super>(component):

    # Seconds to wait for human input (grabbing)
    @editable
    HumanTimeoutSeconds<public>:float = 30.0

    # When false, skips the human-input checks (automatic checks only)
    @editable
    RunHumanTests<public>:logic = true

    StatsChangedEventInternal<private><final>:event(swing_stats) = event(swing_stats){}
    StatsChangedEvent<private><final>:listenable(swing_stats) = MakeProxyListenable(StatsChangedEventInternal)

    # Receives the swing_stats_changed_event that the swing_ability_component on the same entity SendUps
    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Changed := swing_stats_changed_event[SceneEvent]):
            StatsChangedEventInternal.Signal(Changed.Stats)
        false

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "SwingSystem"}
        TestStackingMath(Results)
        MaybeAgent := AwaitFirstPlayer()
        if:
            Ability := Entity.GetComponent[swing_ability_component]
            Registry := Entity.FindScopedComponent[swing_registry_component]
            Agent := MaybeAgent?
        then:
            TestGrant(Results, Ability, Agent)
            TestStateTags(Results, Agent)
            TestModifiers(Results, Registry, Agent)
            TestLifeTarget(Results, Ability, Agent)
            TestLiftTarget(Results, Ability, Agent)
            if (RunHumanTests?):
                TestHumanGrab(Results, Ability, Agent)
            TestRevoke(Results, Ability, Agent)
        else:
            Results.Fail("setup", "swing_ability_component (same entity), swing_registry_component or player_manager_component missing")
        if (Results.Finish[]) {}

    AwaitFirstPlayer<private>()<suspends>:?agent =
        if (Manager := Entity.FindScopedComponent[player_manager_component]):
            if (Slot := Manager.GetSlots()[0]):
                option{Slot.Player}
            else:
                Player := Manager.PlayerAddedEvent.Await()
                option{Player}
        else:
            false

    TestStackingMath<private>(Results:test_log):void =
        A := swing_modifier{RangeMultiplier := 2.0, SpeedMultiplier := 1.5, ExtraRopes := 1}
        B := swing_modifier{RangeMultiplier := 0.5, AccelerationMultiplier := 3.0, ExtraRopes := 2, AllowGrab := false}
        Base := swing_stats{}
        Identity := Base.Apply(swing_modifier{})
        Results.CheckFloat("identity modifier keeps RangeScale", Identity.RangeScale, 1.0, 0.0001)
        Results.Check("identity modifier keeps CanGrab", Identity.CanGrab)
        AB := Base.Apply(A).Apply(B)
        BA := Base.Apply(B).Apply(A)
        Results.CheckFloat("multipliers multiply (range 2 x 0.5)", AB.RangeScale, 1.0, 0.0001)
        Results.CheckFloat("speed 1.5 x 1", AB.SpeedScale, 1.5, 0.0001)
        Results.CheckFloat("acceleration 1 x 3", AB.AccelerationScale, 3.0, 0.0001)
        Results.CheckInt("extra ropes add (1 + 2)", AB.ExtraRopes, 3)
        Results.Check("AllowGrab false wins", if (AB.CanGrab?) then false else true)
        Results.CheckFloat("order does not matter (speed)", BA.SpeedScale, AB.SpeedScale, 0.0001)
        Results.CheckInt("order does not matter (ropes)", BA.ExtraRopes, AB.ExtraRopes)

    TestGrant<private>(Results:test_log, Ability:swing_ability_component, Agent:agent)<suspends>:void =
        Results.Check("not granted at start", if (Ability.IsGranted[Agent]) then false else true)
        Results.Check("state: not swinging before grant", if (Agent.IsSwinging[]) then false else true)
        Granted := spawn{AwaitWithin(Ability.GrantedEvent, 1.0)}
        Ability.Grant(Agent)
        GrantedResult := Granted.Await()
        Results.Check("GrantedEvent on Grant", if (GrantedResult?) then true else false)
        TickEvents.PrePhysics.Await()
        Results.Check("granted", if (Ability.IsGranted[Agent]) then true else false)
        Results.Check("state: IsSwinging fails while idle", if (Agent.IsSwinging[]) then false else true)
        Results.Check("state: GetSwingState is Idle", if (Agent.GetSwingState() = swing_state.Idle) then true else false)
        Released := spawn{AwaitWithin(Ability.ReleasedEvent, 0.5)}
        Ability.Release(Agent)
        ReleasedResult := Released.Await()
        Results.Check("Release while idle does nothing", if (ReleasedResult?) then false else true)

    TestModifiers<private>(Results:test_log, Registry:swing_registry_component, Agent:agent)<suspends>:void =
        Holder := entity{}
        Modifier := swing_modifier_component{Entity := Holder, RangeMultiplier := 2.0, ExtraRopes := 1}
        Grant := swing_modifier_grant_component{Entity := Holder, DurationSeconds := 0.5}
        Holder.AddComponents(array{Modifier, Grant})
        Entity.AddEntities(array{Holder})
        TickEvents.PrePhysics.Await()
        Results.CheckFloat("modifier not applied yet", Registry.GetStats(Agent).RangeScale, 1.0, 0.0001)
        Changed := spawn{AwaitWithin(Modifier.ChangedEvent, 0.5)}
        RunnerStats := spawn{AwaitWithin(StatsChangedEvent, 1.0)}
        Modifier.ApplyTo(Agent)
        ChangedResult := Changed.Await()
        Results.Check("ChangedEvent on ApplyTo", if (ChangedResult?) then true else false)
        Results.CheckFloat("ApplyTo: registry stats range x2", Registry.GetStats(Agent).RangeScale, 2.0, 0.0001)
        Results.CheckInt("ApplyTo: registry stats extra ropes +1", Registry.GetStats(Agent).ExtraRopes, 1)
        RunnerStatsResult := RunnerStats.Await()
        if (Stats := RunnerStatsResult?):
            Results.CheckFloat("granted swing re-reads stats on change (swing_stats_changed_event)", Stats.RangeScale, 2.0, 0.0001)
        else:
            Results.Fail("granted swing re-reads stats on change", "no swing_stats_changed_event within 1 s")
        Modifier.ApplyToAll()
        Modifier.RemoveFrom(Agent)
        Results.CheckFloat("ApplyToAll still applies after RemoveFrom", Registry.GetStats(Agent).RangeScale, 2.0, 0.0001)
        Modifier.RemoveFromAll()
        Results.CheckFloat("RemoveFromAll: back to 1", Registry.GetStats(Agent).RangeScale, 1.0, 0.0001)
        Holder.SendDown(swing_modifier_request_event{Sender := Entity, Agent := Agent})
        Results.Check("grant scope: applied on request", if (Grant.IsApplyingTo[Agent]) then true else false)
        Results.CheckFloat("grant scope: stats x2 on request", Registry.GetStats(Agent).RangeScale, 2.0, 0.0001)
        Sleep(1.0)
        Results.Check("grant scope: expired after DurationSeconds", if (Grant.IsApplyingTo[Agent]) then false else true)
        Results.CheckFloat("grant scope: stats back to 1 after expiry", Registry.GetStats(Agent).RangeScale, 1.0, 0.0001)
        Holder.RemoveFromParent()
        TickEvents.PrePhysics.Await()
        Results.CheckFloat("removed modifier unregisters", Registry.GetStats(Agent).RangeScale, 1.0, 0.0001)

    # Creates an anchor to tell the target "grabbed" (carries swing_anchor_component like the anchor a swing grabs)
    MakeAnchor<private>():tuple(entity, swing_anchor_component) =
        Anchor := entity{}
        Marker := swing_anchor_component{Entity := Anchor}
        Anchor.AddComponents(array{Marker})
        Entity.AddEntities(array{Anchor})
        (Anchor, Marker)

    TestLifeTarget<private>(Results:test_log, Ability:swing_ability_component, Agent:agent)<suspends>:void =
        Cube := entity{}
        Target := swing_target_component{Entity := Cube}
        Life := swing_life_component{Entity := Cube, LifeSeconds := 1.0, BlinkCount := 2, BlinkSeconds := 0.4}
        Cube.AddComponents(array{Target, Life})
        Entity.AddEntities(array{Cube})
        AnchorPair := MakeAnchor()
        Early := AwaitWithin(Target.ShatteredEvent, 1.5)
        Results.Check("life: not shattered before being grabbed", if (Early?) then false else true)
        Cube.SendDown(swing_attached_event{Ability := Ability, Agent := Agent, Anchor := AnchorPair(0)})
        Results.Check("life: WasAttached after swing_attached_event", if (Target.WasAttached[]) then true else false)
        Results.CheckInt("life: one anchor tracked", Target.GetAnchorCount(), 1)
        StartTime := GetSimulationElapsedTime()
        Shattered := AwaitWithin(Target.ShatteredEvent, 3.0)
        if (Shattered?):
            Results.CheckFloat("life: shatters LifeSeconds after grab", GetSimulationElapsedTime() - StartTime, 1.0, 0.3)
            Results.Check("life: anchor broken on shatter", AnchorPair(1).Broken)
            TickEvents.PrePhysics.Await()
            TickEvents.PrePhysics.Await()
            Results.Check("life: entity removed after shatter", if (Cube.GetParent[]) then false else true)
        else:
            Results.Fail("life: shatters", "no ShatteredEvent within 3 s")
        AnchorPair(0).RemoveFromParent()

    TestLiftTarget<private>(Results:test_log, Ability:swing_ability_component, Agent:agent)<suspends>:void =
        Cube := entity{}
        Target := swing_target_component{Entity := Cube}
        Lift := swing_lift_component{Entity := Cube, TravelCm := vector3{Up := 200.0}, SpeedCmPerSecond := 400.0}
        Cube.AddComponents(array{Target, Lift})
        Entity.AddEntities(array{Cube})
        AnchorPair := MakeAnchor()
        TickEvents.PrePhysics.Await()
        Start := Cube.GetGlobalTranslation()
        Cube.SendDown(swing_attached_event{Ability := Ability, Agent := Agent, Anchor := AnchorPair(0)})
        Early := AwaitWithin(Target.ShatteredEvent, 0.7)
        Results.Check("lift: not moving while only grabbed", if (Early?) then false else true)
        Results.CheckFloat("lift: still at start while only grabbed", Distance(Cube.GetGlobalTranslation(), Start), 0.0, 1.0)
        Shattered := spawn{AwaitWithin(Target.ShatteredEvent, 2.0)}
        Cube.SendDown(swing_pulled_event{Ability := Ability, Agent := Agent, Anchor := AnchorPair(0)})
        ShatteredResult := Shattered.Await()
        if (ShatteredResult?):
            Results.CheckFloat("lift: moved TravelCm before shatter", Distance(Cube.GetGlobalTranslation(), Start), 200.0, 5.0)
            Results.Check("lift: anchor broken on shatter", AnchorPair(1).Broken)
        else:
            Results.Fail("lift: shatters after travel", "no ShatteredEvent within 2 s (200 cm at 400 cm/s = 0.5 s)")
        AnchorPair(0).RemoveFromParent()

    # Checks only the state entry points (tags). Does not use the ability; the test attaches / removes the tags on its own holder
    TestStateTags<private>(Results:test_log, Agent:agent):void =
        StateTags := player_tag_holder{}
        StateTags.Add(Agent, swing_anchored_tag{})
        Results.Check("tags: anchored -> IsSwinging", if (Agent.IsSwinging[]) then true else false)
        Results.Check("tags: anchored -> GetSwingState is Anchored", if (Agent.GetSwingState() = swing_state.Anchored) then true else false)
        Results.Check("tags: anchored is found as swinging_tag", if (Agent.HasPlayerTag[swinging_tag]) then true else false)
        StateTags.Remove(Agent)
        StateTags.Add(Agent, swing_pendulum_tag{})
        Results.Check("tags: pendulum -> GetSwingState is Swinging", if (Agent.GetSwingState() = swing_state.Swinging) then true else false)
        Results.Check("tags: pendulum is found as controlled_movement_tag", if (Agent.HasPlayerTag[controlled_movement_tag]) then true else false)
        StateTags.Remove(Agent)
        Results.Check("tags: removed -> not swinging", if (Agent.IsSwinging[]) then false else true)
        Results.Check("tags: removed -> GetSwingState is Idle", if (Agent.GetSwingState() = swing_state.Idle) then true else false)

    TestHumanGrab<private>(Results:test_log, Ability:swing_ability_component, Agent:agent)<suspends>:void =
        Print("[TEST] SwingSystem: (human) aim the reticle at a mesh within {Ability.MaxRangeCm} cm and press fire within {HumanTimeoutSeconds} s")
        Grabbed := AwaitWithin(Ability.GrabbedEvent, HumanTimeoutSeconds)
        if (Payload := Grabbed?):
            Results.Check("human: GrabbedEvent carries the agent", if (Payload(0) = Agent) then true else false)
            TickEvents.PrePhysics.Await()
            Results.Check("human: IsSwinging while grabbing", if (Agent.IsSwinging[]) then true else false)
            Results.Check("human: GetSwingState is not Idle while grabbing", if (Agent.GetSwingState() <> swing_state.Idle) then true else false)
            Released := spawn{AwaitWithin(Ability.ReleasedEvent, 1.0)}
            Ability.Release(Agent)
            ReleasedResult := Released.Await()
            Results.Check("human: ReleasedEvent after Release", if (ReleasedResult?) then true else false)
            TickEvents.PrePhysics.Await()
            Results.Check("human: not swinging after Release", if (Agent.IsSwinging[]) then false else true)
            Results.Check("human: GetSwingState is Idle after Release", if (Agent.GetSwingState() = swing_state.Idle) then true else false)
        else:
            Print("[SKIP] SwingSystem: human grab (no GrabbedEvent within {HumanTimeoutSeconds} s)")

    TestRevoke<private>(Results:test_log, Ability:swing_ability_component, Agent:agent)<suspends>:void =
        Revoked := spawn{AwaitWithin(Ability.RevokedEvent, 1.0)}
        Ability.Revoke(Agent)
        RevokedResult := Revoked.Await()
        Results.Check("RevokedEvent on Revoke", if (RevokedResult?) then true else false)
        TickEvents.PrePhysics.Await()
        Results.Check("not granted after Revoke", if (Ability.IsGranted[Agent]) then false else true)
        Results.Check("state: Idle after Revoke (tag removed)", if (Agent.GetSwingState() = swing_state.Idle) then true else false)
