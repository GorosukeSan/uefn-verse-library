using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { EnergySystem }
using { JetpackSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { _Test }

# Role: verification of JetpackSystem. Grants / revokes jetpack_ability_component from code (reference counting, events, gauge) and checks that charging and flying by human input changes the gauge and the energy
# Test level:
#   - one entity with player_manager_component
#   - the test entity carries only jetpack_system_test_component (the ability and the energy are created by the test at runtime as children)
# Human input: when "jump, then hold jump in the air" appears, jump within 30 seconds, hold jump in the air for about 1 second, release, and land
# Result: [TEST] JetpackSystem in the output log
jetpack_system_test_component<public> := class<final_super>(component):

    var<private> BoostSceneEventCount:int = 0

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (jetpack_boost_changed_event[SceneEvent]):
            set BoostSceneEventCount += 1
        false

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "JetpackSystem"}
        MaybeAgent := AwaitFirstPlayer()
        if (Agent := MaybeAgent?):
            TestJetpack(Results, Agent)
        else:
            Results.Fail("setup", "player_manager_component missing")
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

    TestJetpack<private>(Results:test_log, Agent:agent)<suspends>:void =
        JetpackEntity := entity{}
        Jetpack := jetpack_ability_component{Entity := JetpackEntity, BoostEnergyCost := 30.0, GlideEnergyPerSecond := 0.0}
        Energy := energy_component{Entity := JetpackEntity, MaxEnergy := 100.0}
        JetpackEntity.AddComponents(array{Jetpack, Energy})
        Entity.AddEntities(array{JetpackEntity})
        defer:
            Jetpack.RevokeAll()
            JetpackEntity.RemoveFromParent()
        TickEvents.PrePhysics.Await()

        Results.Check("not granted at start", if (Jetpack.IsGranted[Agent]) then false else true)
        Results.CheckFloat("ratio 0 while not granted", Jetpack.GetBoostRatio(Agent), 0.0, 0.001)
        Granted := spawn{AwaitWithin(Jetpack.GrantedEvent, 1.0)}
        Jetpack.Grant(Agent)
        GrantedPayload := Granted.Await()
        Results.Check("GrantedEvent", if (GrantedPayload?) then true else false)
        TickEvents.PrePhysics.Await()
        Results.CheckFloat("ratio 1 (ready) after Grant", Jetpack.GetBoostRatio(Agent), 1.0, 0.001)
        Results.Check("jetpack_boost_changed_event sent up", if (BoostSceneEventCount > 0) then true else false)
        Jetpack.Grant(Agent)
        Jetpack.Revoke(Agent)
        Results.Check("still granted after one of two Revokes", if (Jetpack.IsGranted[Agent]) then true else false)

        Print("[TEST] JetpackSystem: jump, then hold jump in the air for about 1 second, release, and land (30 seconds)")
        Started := AwaitRatio(Jetpack, 0.0, 30.0)
        Results.Check("charge starts (ratio 0) (manual)", Started)
        Landed := AwaitRatio(Jetpack, 1.0, 30.0)
        Results.Check("ready again after landing (ratio 1) (manual)", Landed)
        Results.CheckFloat("one boost used BoostEnergyCost (manual)", Energy.CurrentAmount, 70.0, 0.001)

        Revoked := spawn{AwaitWithin(Jetpack.RevokedEvent, 1.0)}
        Jetpack.Revoke(Agent)
        RevokedPayload := Revoked.Await()
        Results.Check("RevokedEvent on last Revoke", if (RevokedPayload?) then true else false)
        Results.CheckFloat("ratio 0 after Revoke", Jetpack.GetBoostRatio(Agent), 0.0, 0.001)

    # Waits up to Seconds for Jetpack's BoostRatioChangedEvent to reach Target. True when it does
    AwaitRatio<private>(Jetpack:jetpack_ability_component, Target:float, Seconds:float)<suspends>:logic =
        race:
            block:
                loop:
                    Changed := Jetpack.BoostRatioChangedEvent.Await()
                    if (Abs(Changed(1) - Target) < 0.001):
                        break
                true
            block:
                Sleep(Seconds)
                false
