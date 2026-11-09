using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { EnergySystem }
using { HoverSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { _Test }

# Role: verification of HoverSystem. Grants / revokes hover_ability_component from code and checks that hovering by human input delivers the events and drains energy (refill at checkpoints moved to CheckpointSystem's EnergyKit, so it is checked in CheckpointSystemTest)
# Test level:
#   - one entity with player_manager_component
#   - the test entity carries only hover_system_test_component (the ability and the energy are created by the test at runtime as children)
# Human input: when "jump and hold jump in the air" appears, jump within 30 seconds, hold jump in the air for about 1 second, then release
# Result: [TEST] HoverSystem in the output log
hover_system_test_component<public> := class<final_super>(component):

    var<private> HoverSceneEventCount:int = 0

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (hover_changed_event[SceneEvent]):
            set HoverSceneEventCount += 1
        false

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "HoverSystem"}
        MaybeAgent := AwaitFirstPlayer()
        if (Agent := MaybeAgent?):
            TestHover(Results, Agent)
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

    TestHover<private>(Results:test_log, Agent:agent)<suspends>:void =
        HoverEntity := entity{}
        Hover := hover_ability_component{Entity := HoverEntity, EnergyPerSecond := 20.0}
        Energy := energy_component{Entity := HoverEntity, MaxEnergy := 100.0}
        HoverEntity.AddComponents(array{Hover, Energy})
        Entity.AddEntities(array{HoverEntity})
        defer:
            Hover.RevokeAll()
            HoverEntity.RemoveFromParent()
        TickEvents.PrePhysics.Await()

        Hover.Grant(Agent)
        Results.Check("Grant from code", if (Hover.IsGranted[Agent]) then true else false)
        Results.Check("not hovering on Grant", if (Hover.IsHovering[Agent]) then false else true)

        Results.CheckFloat("energy is full before hovering", Energy.CurrentAmount, 100.0, 0.001)

        Print("[TEST] HoverSystem: jump and hold jump in the air for about 1 second, then release (30 seconds)")
        Started := AwaitHoverChange(Hover, true, 30.0)
        Results.Check("HoverChangedEvent true (manual)", Started)
        Results.Check("IsHovering while hovering (manual)", if (Hover.IsHovering[Agent]) then true else false)
        Stopped := AwaitHoverChange(Hover, false, 30.0)
        Results.Check("HoverChangedEvent false after release (manual)", Stopped)
        Results.Check("hovering used energy (manual)", if (Energy.CurrentAmount < 100.0) then true else false)
        Results.Check("hover_changed_event sent up (manual)", if (HoverSceneEventCount >= 2) then true else false)

        Hover.Revoke(Agent)
        Results.Check("Revoke from code", if (Hover.IsGranted[Agent]) then false else true)

    # Waits up to Seconds for Hover's HoverChangedEvent to report the Active state. True when it does
    AwaitHoverChange<private>(Hover:hover_ability_component, Active:logic, Seconds:float)<suspends>:logic =
        race:
            block:
                loop:
                    Changed := Hover.HoverChangedEvent.Await()
                    if (Changed(1) = Active):
                        break
                true
            block:
                Sleep(Seconds)
                false
