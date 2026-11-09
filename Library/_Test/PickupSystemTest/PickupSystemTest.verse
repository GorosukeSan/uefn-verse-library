using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { PickupSystem }
using { PickupSystem.StageKit }
using { _Test }

# 役割：テスト用。届いた起動・停止の合図を数える
pickup_test_probe_component<public> := class<final_super>(component):
    var<private> Activated:int = 0
    var<private> Deactivated:int = 0
    var<private> LastAgent:?agent = false

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            set Activated += 1
            if (Agent := SceneEvent.FindActivatingAgent[]):
                set LastAgent = option{Agent}
        else if (deactivated_event[SceneEvent]):
            set Deactivated += 1
        false

    GetActivated<public>()<transacts>:int = Activated
    GetDeactivated<public>()<transacts>:int = Deactivated
    FindLastAgent<public>()<decides><transacts>:agent = LastAgent?

# 役割：PickupSystem の動作確認
#   効果：GrantPickupEffectEntity で組み立てた効果が、持ち主（slot の下）・次のフレームの起動の合図（持ち主が起こした）・pickup_effect_tag・DurationSeconds で停止の合図と消えること
#   重ねがけ：同じ EffectId の Extend（1 つのまま延びる）、Stack と MaxStacks、Replace。Instant。EndPickupEffectsFor
#   オーブ：pickup_component の TryPickup（拾える状態・見た目・RespawnSeconds で戻る・RespawnSeconds 0 は戻らない・Restore・停止の合図で隠す）、RequireGroupMember
#   ステージ（StageKit）：pickup_stage_signal_component が範囲の Group の相手に起動の合図を送り、効果の終わりで元に戻す。2 つの効果が重なったら両方終わってから戻す
# テストのレベル：player_manager_component を付けた entity を 1 つと、この component を付けた entity を 1 つ（どちらも最上位）。プレイヤー 1 人で始める（参加を最大 10 秒待つ）
# 結果：出力ログの [TEST] PickupSystem。約 4 秒
pickup_system_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "PickupSystem"}
        Sleep(0.0)
        if (Manager := Entity.FindScopedComponent[player_manager_component]):
            if (Manager.GetPlayerCount() = 0):
                Arrived := AwaitWithin(Manager.PlayerAddedEvent, 10.0)
                if (not Arrived?):
                    Results.Fail("setup", "no player joined within 10 s")
            if (Slot := Manager.GetSlots()[0]):
                Agent:agent = Slot.Player
                TestLifetime(Results, Agent)
                TestStacking(Results, Agent)
                TestPickup(Results, Agent)
                TestStage(Results, Agent)
                Results.CheckInt("EndPickupEffectsFor leaves nothing", Entity.GetActivePickupEffects(Agent).Length, 0)
        else:
            Results.Fail("setup", "player_manager_component not found")
        if (Results.Finish[]) {}

    # 効果の entity（根に pickup_effect_component と数える部品）を組み立てる
    MakeEffect<private>(Duration:float, Id:string, Mode:pickup_effect_stack_mode, Stacks:int, IsInstant:logic):tuple(entity, pickup_effect_component, pickup_test_probe_component) =
        Made := entity{}
        Effect := pickup_effect_component{Entity := Made, DurationSeconds := Duration, EffectId := Id, StackMode := Mode, MaxStacks := Stacks, Instant := IsInstant}
        Probe := pickup_test_probe_component{Entity := Made}
        Made.AddComponents(array{Effect, Probe})
        (Made, Effect, Probe)

    Grant<private>(Agent:agent, Made:entity):void =
        Entity.GrantPickupEffectEntity(Agent, Made, Entity.GetGlobalTransform(), option{Entity})

    TestLifetime<private>(Results:test_log, Agent:agent)<suspends>:void =
        Parts := MakeEffect(0.6, "", pickup_effect_stack_mode.Extend, 0, false)
        Grant(Agent, Parts(0))
        Results.CheckInt("no activation in the first frame", Parts(2).GetActivated(), 0)
        Sleep(0.1)
        Results.CheckInt("activated once", Parts(2).GetActivated(), 1)
        Results.Check("activated by the owner", if (Parts(2).FindLastAgent[] = Agent) then true else false)
        Results.Check("IsActive", if (Parts(1).IsActive[]) then true else false)
        Results.Check("owner", if (Parts(1).FindOwner[] = Agent) then true else false)
        Results.Check("source", if (Parts(1).FindSource[] = Entity) then true else false)
        Results.Check("owning player (under the slot)", if (Parts(0).FindOwningPlayer[] = Agent) then true else false)
        Results.Check("pickup_effect_tag", if (Agent.HasPlayerTag[pickup_effect_tag]) then true else false)
        Results.Check("FindPickupEffect from inside", if (Parts(0).FindPickupEffect[] = Parts(1)) then true else false)
        Sleep(0.8)
        Results.CheckInt("deactivated when the time is up", Parts(2).GetDeactivated(), 1)
        Results.Check("removed from the slot", if (Parts(0).GetParent[]) then false else true)
        Results.Check("tag removed", if (Agent.HasPlayerTag[pickup_effect_tag]) then false else true)

        # Instant：次のフレームで終わる
        Instant := MakeEffect(10.0, "", pickup_effect_stack_mode.Extend, 0, true)
        Grant(Agent, Instant(0))
        Sleep(0.2)
        Results.CheckInt("instant: activated", Instant(2).GetActivated(), 1)
        Results.CheckInt("instant: deactivated", Instant(2).GetDeactivated(), 1)

    TestStacking<private>(Results:test_log, Agent:agent)<suspends>:void =
        # Extend：2 つ目は始まらず、1 つ目が延びる
        A := MakeEffect(1.0, "ext", pickup_effect_stack_mode.Extend, 0, false)
        Grant(Agent, A(0))
        Sleep(0.1)
        B := MakeEffect(1.0, "ext", pickup_effect_stack_mode.Extend, 0, false)
        Grant(Agent, B(0))
        Sleep(0.1)
        Results.CheckInt("extend: second not activated", B(2).GetActivated(), 0)
        Results.CheckFloat("extend: remaining", A(1).GetRemainingSeconds(), 1.8, 0.15)
        A(1).End()
        Results.CheckInt("End sends deactivated", A(2).GetDeactivated(), 1)

        # Stack と MaxStacks = 2：3 つ目は始まらない
        S1 := MakeEffect(5.0, "stk", pickup_effect_stack_mode.Stack, 2, false)
        S2 := MakeEffect(5.0, "stk", pickup_effect_stack_mode.Stack, 2, false)
        Grant(Agent, S1(0))
        Grant(Agent, S2(0))
        Sleep(0.1)
        S3 := MakeEffect(5.0, "stk", pickup_effect_stack_mode.Stack, 2, false)
        Grant(Agent, S3(0))
        Sleep(0.1)
        Results.CheckInt("stack: two activated", S1(2).GetActivated() + S2(2).GetActivated(), 2)
        Results.CheckInt("stack: third refused", S3(2).GetActivated(), 0)

        # Replace：前のは終わる
        R1 := MakeEffect(5.0, "rep", pickup_effect_stack_mode.Replace, 0, false)
        Grant(Agent, R1(0))
        Sleep(0.1)
        R2 := MakeEffect(5.0, "rep", pickup_effect_stack_mode.Replace, 0, false)
        Grant(Agent, R2(0))
        Sleep(0.1)
        Results.CheckInt("replace: old deactivated", R1(2).GetDeactivated(), 1)
        Results.CheckInt("replace: new activated", R2(2).GetActivated(), 1)

        Ended := Entity.EndPickupEffectsFor(Agent)
        Results.CheckInt("EndPickupEffectsFor ends the rest", Ended, 3)
        Results.CheckInt("ended effects got deactivated", S1(2).GetDeactivated() + S2(2).GetDeactivated() + R2(2).GetDeactivated(), 3)

    TestPickup<private>(Results:test_log, Agent:agent)<suspends>:void =
        Orb := entity{}
        Pickup := pickup_component{Entity := Orb, RespawnSeconds := 0.5}
        Orb.AddComponents(array{Pickup})
        Entity.AddEntities(array{Orb})
        Sleep(0.1)
        Results.Check("available after begin", if (Pickup.IsAvailable[]) then true else false)
        Results.Check("TryPickup", Pickup.TryPickup(Agent))
        Results.Check("not available after pickup", if (Pickup.IsAvailable[]) then false else true)
        Again := Pickup.TryPickup(Agent)
        Results.Check("second TryPickup fails", if (Again?) then false else true)
        Sleep(0.7)
        Results.CheckInt("effect granted (default root added)", Entity.GetActivePickupEffects(Agent).Length, 1)
        Results.Check("restored after RespawnSeconds", if (Pickup.IsAvailable[]) then true else false)
        Orb.SendDeactivated()
        Results.Check("deactivated hides", if (Pickup.IsAvailable[]) then false else true)
        Orb.SendActivated()
        Results.Check("activated restores", if (Pickup.IsAvailable[]) then true else false)
        Orb.RemoveFromParent()

        # RespawnSeconds = 0 は戻らない。RequireGroupMember は組の人だけ
        Room := entity{}
        Group := player_group_component{Entity := Room}
        Room.AddComponents(array{Group})
        Once := entity{}
        OncePickup := pickup_component{Entity := Once, RespawnSeconds := 0.0, RequireGroupMember := true}
        Once.AddComponents(array{OncePickup})
        Room.AddEntities(array{Once})
        Entity.AddEntities(array{Room})
        Sleep(0.1)
        Refused := OncePickup.TryPickup(Agent)
        Results.Check("group: non-member refused", if (Refused?) then false else true)
        Group.Join(Agent)
        Results.Check("group: member picks", OncePickup.TryPickup(Agent))
        Sleep(0.7)
        Results.Check("RespawnSeconds 0 stays hidden", if (OncePickup.IsAvailable[]) then false else true)
        OncePickup.Restore()
        Results.Check("Restore", if (OncePickup.IsAvailable[]) then true else false)
        Room.RemoveFromParent()
        Entity.EndPickupEffectsFor(Agent)

    TestStage<private>(Results:test_log, Agent:agent)<suspends>:void =
        # 相手：この entity の下（最上位の entity の中）に Group "t" の相手と、Group "other" の相手
        Target := entity{}
        TargetMark := pickup_stage_target_component{Entity := Target, Group := "t"}
        TargetProbe := pickup_test_probe_component{Entity := Target}
        Target.AddComponents(array{TargetMark, TargetProbe})
        Other := entity{}
        OtherMark := pickup_stage_target_component{Entity := Other, Group := "other"}
        OtherProbe := pickup_test_probe_component{Entity := Other}
        Other.AddComponents(array{OtherMark, OtherProbe})
        Entity.AddEntities(array{Target, Other})
        Sleep(0.1)

        First := MakeStageEffect(0.5)
        Second := MakeStageEffect(1.0)
        Grant(Agent, First(0))
        Sleep(0.1)
        Results.CheckInt("stage: target activated", TargetProbe.GetActivated(), 1)
        Results.Check("stage: activated by the picker", if (TargetProbe.FindLastAgent[] = Agent) then true else false)
        Results.CheckInt("stage: other group untouched", OtherProbe.GetActivated(), 0)
        Grant(Agent, Second(0))
        Sleep(0.1)
        Results.CheckInt("stage: second hold sends nothing new", TargetProbe.GetActivated(), 1)
        Sleep(0.5)
        Results.CheckInt("stage: still held by the second effect", TargetProbe.GetDeactivated(), 0)
        Sleep(0.6)
        Results.CheckInt("stage: reverted after both ended", TargetProbe.GetDeactivated(), 1)
        Target.RemoveFromParent()
        Other.RemoveFromParent()

    MakeStageEffect<private>(Duration:float):tuple(entity, pickup_effect_component) =
        Made := entity{}
        Effect := pickup_effect_component{Entity := Made, DurationSeconds := Duration}
        Made.AddComponents(array{Effect})
        Signal := entity{}
        Signal.AddComponents(array{pickup_stage_signal_component{Entity := Signal, Group := "t", Scope := pickup_stage_scope.SourceRoot}})
        Made.AddEntities(array{Signal})
        (Made, Effect)
