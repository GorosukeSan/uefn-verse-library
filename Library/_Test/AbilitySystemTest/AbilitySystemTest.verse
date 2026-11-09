using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { AbilitySystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { _Test }

# Role: test ability. Counts how many agents are running while it is granted
# Placement: same entity as ability_system_test_component (the test finds it itself)
ability_test_probe_component<public> := class<final_super>(ability_component):

    var<private> Running:int = 0
    var<private> Started:int = 0

    # Number of agents whose RunFor is running now
    GetRunningCount<public>()<transacts>:int = Running

    # Number of times RunFor has started (cumulative)
    GetStartedCount<public>()<transacts>:int = Started

    RunFor<override>(Agent:agent)<suspends>:void =
        set Running += 1
        set Started += 1
        defer:
            set Running -= 1
        Sleep(Inf)

# Role: verification of AbilitySystem. Uses the first player that joined and checks Grant / Revoke from code and the reference counting, the events, and the grant component
# Test level:
#   - one entity with player_manager_component
#   - the test entity carries ability_system_test_component and ability_test_probe_component (no grant component)
#   - another entity carries ability_test_probe_component and ability_grant_players_component (GrantOnBegin = true); put that entity into GrantedByPlayers
# Result: [TEST] AbilitySystem in the output log
ability_system_test_component<public> := class<final_super>(component):

    # Entity that carries ability_grant_players_component (GrantOnBegin) and ability_test_probe_component
    @editable
    GrantedByPlayers<public>:?entity = false

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "AbilitySystem"}
        MaybeAgent := AwaitFirstPlayer()
        if (Probe := Entity.GetComponent[ability_test_probe_component], Agent := MaybeAgent?):
            TestCodeGrant(Results, Probe, Agent)
            TestGrantPlayers(Results, Agent)
        else:
            Results.Fail("setup", "ability_test_probe_component or player_manager_component missing")
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

    TestCodeGrant<private>(Results:test_log, Probe:ability_test_probe_component, Agent:agent)<suspends>:void =
        Results.Check("not granted at start", if (Probe.IsGranted[Agent]) then false else true)
        Granted := spawn{AwaitWithin(Probe.GrantedEvent, 1.0)}
        Probe.Grant(Agent)
        GotGranted := Granted.Await()
        Results.Check("GrantedEvent on first Grant", if (GotGranted?) then true else false)
        TickEvents.PrePhysics.Await()
        Results.CheckInt("RunFor started once", Probe.GetRunningCount(), 1)
        Probe.Grant(Agent)
        TickEvents.PrePhysics.Await()
        Results.CheckInt("second Grant does not start again", Probe.GetStartedCount(), 1)
        Probe.Revoke(Agent)
        TickEvents.PrePhysics.Await()
        Results.Check("still granted after one Revoke (count 2 -> 1)", if (Probe.IsGranted[Agent]) then true else false)
        Revoked := spawn{AwaitWithin(Probe.RevokedEvent, 1.0)}
        Probe.Revoke(Agent)
        GotRevoked := Revoked.Await()
        Results.Check("RevokedEvent on last Revoke", if (GotRevoked?) then true else false)
        TickEvents.PrePhysics.Await()
        Results.CheckInt("RunFor stopped", Probe.GetRunningCount(), 0)
        Probe.Revoke(Agent)
        Results.Check("extra Revoke is ignored", if (Probe.IsGranted[Agent]) then false else true)
        Probe.Grant(Agent)
        Probe.Grant(Agent)
        Probe.RevokeAll()
        TickEvents.PrePhysics.Await()
        Results.CheckInt("RevokeAll stops regardless of count", Probe.GetRunningCount(), 0)

    TestGrantPlayers<private>(Results:test_log, Agent:agent)<suspends>:void =
        if (Target := GrantedByPlayers?, Probe := Target.GetComponent[ability_test_probe_component]):
            TickEvents.PrePhysics.Await()
            Results.Check("ability_grant_players grants to joined player", if (Probe.IsGranted[Agent]) then true else false)
            Results.CheckInt("ability_grant_players runs once per player", Probe.GetRunningCount(), Probe.GetGrantedAgents().Length)
        else:
            Results.Fail("ability_grant_players", "GrantedByPlayers not set or has no ability_test_probe_component")
