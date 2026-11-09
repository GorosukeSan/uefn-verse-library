using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { PlayerSystem }
using { SceneGraphSystem }
using { SwingSystem }
using { SwingSystem.ModifierKit }
using { SwingSystem.TargetKit }
using { _Test }

# 役割：SwingSystem の動作確認。最初に参加したプレイヤーを使い、次を順に確かめる
#   1. 倍率の重ね方（swing_stats.Apply。人は要らない）
#   2. コードからの Grant と、待機中の状態（Agent.IsSwinging が失敗・Agent.GetSwingState が Idle、待機中の Release は何も起こさない）
#   2b. 状態のタグ：swing_anchored_tag / swing_pendulum_tag を付け外しすると、Agent.IsSwinging / Agent.GetSwingState と、基底（swinging_tag・controlled_movement_tag）での HasPlayerTag が合う（能力は使わない）
#   3. 倍率の登録：実行時に作った swing_modifier_component が registry に自分を登録し、ApplyTo / ApplyToAll / RemoveFrom で registry の GetStats が変わる。付与中のスイングに swing_stats_changed_event が届く。swing_modifier_grant_component が依頼（swing_modifier_request_event）で期限付きで掛け、期限で外す
#   4. 寿命の的：実行時に作った swing_target_component + swing_life_component が、つかまれる（swing_attached_event をテストが送る）まで壊れず、つかまれてから LifeSeconds で壊れ、かかっていた点（swing_anchor_component）を Break する
#   5. リフトの的：swing_target_component + swing_lift_component が、つかまれただけでは動かず、振り出される（swing_pulled_event）と TravelCm だけ動いてから壊れる
#   6. 人の操作（RunHumanTests が true のとき）：ログの案内に従って、レティクルをつかめる物に向けて射撃を押す。HumanTimeoutSeconds 以内に GrabbedEvent が届き、Agent.IsSwinging が成功し、Release で ReleasedEvent が届いて Idle に戻るかを確かめる（届かなければ [SKIP] を出す）
#   7. Revoke と RevokedEvent
# テストのレベル：
#   - player_manager_component を付けた entity を 1 つ、swing_registry_component を付けた entity を 1 つ（同じ区画に）
#   - テスト用の entity に swing_system_test_component と swing_ability_component を付ける（付与の component は付けない。テストがコードから Grant / Revoke する）
#   - 人の操作を確かめるなら、プレイヤーから見える位置に当たり判定のあるメッシュ（キューブなど）を置く
# 結果：出力ログの [TEST] SwingSystem
swing_system_test_component<public> := class<final_super>(component):

    # 人の操作（つかむ）を待つ時間（秒）
    @editable
    HumanTimeoutSeconds<public>:float = 30.0

    # false なら人の操作の確認を飛ばす（自動の確認だけ）
    @editable
    RunHumanTests<public>:logic = true

    StatsChangedEventInternal<private><final>:event(swing_stats) = event(swing_stats){}
    StatsChangedEvent<private><final>:listenable(swing_stats) = MakeProxyListenable(StatsChangedEventInternal)

    # 同じ entity の swing_ability_component が SendUp する swing_stats_changed_event を受ける
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

    # 的に「つかまれた」と知らせるための点を作る（スイングがつかんだ点と同じく swing_anchor_component を付ける）
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

    # 状態の入口（タグ）だけを確かめる。能力を使わず、テストが自分の holder でタグを付け外しする
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
