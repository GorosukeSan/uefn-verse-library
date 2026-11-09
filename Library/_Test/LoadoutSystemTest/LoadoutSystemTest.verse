using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { LoadoutSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { _Test }

# Role: verification of LoadoutSystem. Checks that ApplyTo creates a loadout under the slot (with an owner), that a second ApplyTo does not add another, that other loadouts of the same Group are removed, and that RemoveFrom removes it
# Test level: one entity with player_manager_component and one entity with this component. Start with at least one player (waits up to 10 seconds for them to join)
# Result: [TEST] LoadoutSystem in the output log
loadout_system_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "LoadoutSystem"}
        TickEvents.PrePhysics.Await()
        if (Manager := Entity.FindScopedComponent[player_manager_component]):
            if (Manager.GetPlayerCount() = 0):
                Arrived := AwaitWithin(Manager.PlayerAddedEvent, 10.0)
                if (not Arrived?):
                    Results.Fail("setup", "no player joined within 10 s")
            if (Slot := Manager.GetSlots()[0]):
                Run(Results, Slot.Player)
        else:
            Results.Fail("setup", "player_manager_component not found")
        if (Results.Finish[]) {}

    Run<private>(Results:test_log, Agent:agent):void =
        # Only one component of a type per entity, so each loadout gets its own entity
        Holder := entity{}
        FirstEntity := entity{}
        SecondEntity := entity{}
        First := loadout_component{Entity := FirstEntity, ApplyToEveryone := false, Group := "class"}
        Second := loadout_component{Entity := SecondEntity, ApplyToEveryone := false, Group := "class"}
        FirstEntity.AddComponents(array{First})
        SecondEntity.AddComponents(array{Second})
        Holder.AddEntities(array{FirstEntity, SecondEntity})
        Entity.AddEntities(array{Holder})

        Applied := First.ApplyTo(Agent)
        Results.Check("ApplyTo succeeds", Applied)
        Results.Check("IsAppliedTo", if (First.IsAppliedTo[Agent]) then true else false)
        if (Instance := First.FindInstance[Agent]):
            Results.Check("instance owner is the player", if (Owner := Instance.FindOwningPlayer[], Owner = Agent) then true else false)
            Results.Check("instance has loadout_instance_component", if (Instance.FindLoadoutInstance[].Source = First) then true else false)
        else:
            Results.Fail("FindInstance", "no instance")
        First.ApplyTo(Agent)
        Results.CheckInt("second ApplyTo does not duplicate", First.GetAppliedAgents().Length, 1)

        Second.ApplyTo(Agent)
        Results.Check("same group: second applied", if (Second.IsAppliedTo[Agent]) then true else false)
        Results.Check("same group: first removed", if (First.IsAppliedTo[Agent]) then false else true)

        Second.RemoveFrom(Agent)
        Results.Check("RemoveFrom removes", if (Second.IsAppliedTo[Agent]) then false else true)
        Holder.RemoveFromParent()
