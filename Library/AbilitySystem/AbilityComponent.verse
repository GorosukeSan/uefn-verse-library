using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

# Role: base of a per-player ability (swing, jetpack, etc.). While granted, runs the subclass's RunFor for that player and stops it when revoked (RunFor is canceled by a race; clean-up is done with defer inside RunFor)
# The ability side does not decide how it is granted. Place a grant component (ability_grant_players / ability_grant_item / ability_grant_condition, etc.) on the same entity and swap it, or call Grant / Revoke from code
# Placement: never placed directly (place a subclass). Any number per entity (a grant component on the same entity grants every ability on that entity)
# Requirements / notes: even when several granters grant to the same player, only one RunFor runs (the grant count is tracked and it stops when every grant is revoked)
ability_component<public> := class<abstract><final_super>(component):

    var<private> GrantCounts:[agent]int = map{}
    # Per-player number incremented each time RunFor starts. Used to stop the previous RunFor when revoked and re-granted right away
    var<private> Generations:[agent]int = map{}

    StopEvent<private>:event() = event(){}
    GrantedEventInternal<private><final>:event(agent) = event(agent){}
    RevokedEventInternal<private><final>:event(agent) = event(agent){}

    # Fires with the player when granted and RunFor started (Await / Subscribe; cannot be signaled from outside)
    GrantedEvent<public><final>:listenable(agent) = MakeProxyListenable(GrantedEventInternal)

    # Fires with the player when revoked by every granter and stopped
    RevokedEvent<public><final>:listenable(agent) = MakeProxyListenable(RevokedEventInternal)

    # Implemented by the subclass. Runs while granted to Agent. Canceled by a race when revoked, so it need not return (if it returns, the ability ends there even if the grant continues)
    RunFor<protected>(Agent:agent)<suspends>:void

    # Grants to Agent (increments the grant count). Starts RunFor and fires GrantedEvent when the count goes from 0 to 1
    Grant<public>(Agent:agent):void =
        Count := GetGrantCount(Agent)
        if (set GrantCounts[Agent] = Count + 1) {}
        if (Count = 0):
            Generation := (if (Current := Generations[Agent]) then Current else 0) + 1
            if (set Generations[Agent] = Generation) {}
            spawn{RunGranted(Agent, Generation)}
            GrantedEventInternal.Signal(Agent)

    # Revokes from Agent (decrements the grant count). Stops RunFor and fires RevokedEvent when the count reaches 0. Does nothing if not granted
    Revoke<public>(Agent:agent):void =
        Count := GetGrantCount(Agent)
        if (Count <= 0):
            return
        if (set GrantCounts[Agent] = Count - 1) {}
        if (Count = 1):
            StopEvent.Signal()
            RevokedEventInternal.Signal(Agent)

    # Revokes from everyone and stops, regardless of the grant count
    RevokeAll<public>():void =
        for (Agent : GetGrantedAgents()):
            if (set GrantCounts[Agent] = 0) {}
            StopEvent.Signal()
            RevokedEventInternal.Signal(Agent)

    # Succeeds if granted to Agent (RunFor is running)
    IsGranted<public>(Agent:agent)<decides><transacts>:void =
        GrantCounts[Agent] > 0

    # Players currently granted (order is unspecified)
    GetGrantedAgents<public>()<transacts>:[]agent =
        for (Agent -> Count : GrantCounts, Count > 0):
            Agent

    OnEndSimulation<override>():void =
        RevokeAll()
        (super:)OnEndSimulation()

    GetGrantCount<private>(Agent:agent)<transacts>:int =
        if (Count := GrantCounts[Agent]) then Count else 0

    RunGranted<private>(Agent:agent, Generation:int)<suspends>:void =
        race:
            RunFor(Agent)
            AwaitStop(Agent, Generation)

    # On every stop notification (someone's revoke), checks whether this player is still granted and this generation is the latest.
    # Comparing the notification's payload (who) instead would make the player woken by the first notification miss their own when RevokeAll signals several times in the same tick
    AwaitStop<private>(Agent:agent, Generation:int)<suspends>:void =
        loop:
            StopEvent.Await()
            if (not IsGranted[Agent] or not Generations[Agent] = Generation):
                return

# Returns every ability (ability_component subclass) attached to InEntity
(InEntity:entity).GetAbilities<public>()<reads>:[]ability_component =
    for (Component : InEntity.GetComponents(), Ability := ability_component[Component]):
        Ability
