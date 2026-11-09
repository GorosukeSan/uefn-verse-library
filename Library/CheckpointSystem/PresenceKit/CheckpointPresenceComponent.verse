using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { CheckpointSystem }
using { SceneGraphSystem }

# Role: aggregates the "stepped on / left" of every checkpoint_component in the zone and answers who is standing on which checkpoint and which one they reached last. It only remembers the checkpoint_reached_event / checkpoint_left_event the checkpoints send to the whole zone; it never searches itself (checkpoints spawned at runtime are counted too)
# Placement: attach, in the editor, to any entity inside the zone (the entity of game_scope_component) (anywhere in the world when there is no zone). One per zone
# Notifies: ReachedEvent when someone steps on, LeftEvent when someone leaves (both fire with the checkpoint's scene event itself)
# Requirements: players already standing before this was placed are not counted (counting starts at simulation start). When standing on overlapping checkpoints at the same time, all of them are remembered (leaving one of them still counts as standing on the rest)
checkpoint_presence_component<public> := class<final_super>(component):

    ReachedEventInternal<private><final>:event(checkpoint_reached_event) = event(checkpoint_reached_event){}

    # Fires with the notification (Agent and Checkpoint) when someone steps onto any checkpoint of the zone (Await / Subscribe; cannot be Signaled from outside)
    ReachedEvent<public><final>:listenable(checkpoint_reached_event) = MakeProxyListenable(ReachedEventInternal)

    LeftEventInternal<private><final>:event(checkpoint_left_event) = event(checkpoint_left_event){}

    # Fires with the notification when someone leaves any checkpoint of the zone (leaves the game, or the checkpoint disappears) (Await / Subscribe; cannot be Signaled from outside)
    LeftEvent<public><final>:listenable(checkpoint_left_event) = MakeProxyListenable(LeftEventInternal)

    # Per agent, the checkpoints currently stood on (in the order reached; the last is the newest)
    var Standing<private>:[agent][]checkpoint_component = map{}
    var LastReached<private>:[agent]checkpoint_component = map{}

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Reached := checkpoint_reached_event[SceneEvent]):
            # A checkpoint stepped onto again moves to the end (the same one is not counted twice)
            Others := WithoutCheckpoint(GetStanding(Reached.Agent), Reached.Checkpoint)
            if (set Standing[Reached.Agent] = Others + array{Reached.Checkpoint}) {}
            if (set LastReached[Reached.Agent] = Reached.Checkpoint) {}
            ReachedEventInternal.Signal(Reached)
        else if (Left := checkpoint_left_event[SceneEvent]):
            Rest := WithoutCheckpoint(GetStanding(Left.Agent), Left.Checkpoint)
            if (Rest.Length > 0):
                if (set Standing[Left.Agent] = Rest) {}
            else:
                set Standing = Standing.RemoveKey(Left.Agent)
            LeftEventInternal.Signal(Left)
        false

    # Succeeds when Agent is standing on any checkpoint of the zone
    IsOnAnyCheckpoint<public>(Agent:agent)<decides><reads>:void =
        FindStandingCheckpoint[Agent]

    # The checkpoint Agent is standing on now (with overlaps, the last reached among those still stood on). Fails when not standing
    FindStandingCheckpoint<public>(Agent:agent)<decides><reads>:checkpoint_component =
        OnTop := for (Checkpoint : Standing[Agent], Checkpoint.IsStanding[Agent]):
            Checkpoint
        OnTop[OnTop.Length - 1]

    # The checkpoint Agent reached last (remembered after leaving it and after that checkpoint disappears. Use for respawn points, etc.). Fails when none was ever reached
    FindLastReached<public>(Agent:agent)<decides><reads>:checkpoint_component =
        LastReached[Agent]

    # Forgets the remembered "last reached checkpoint" of everyone (restarting the game, etc.)
    ForgetLastReached<public>():void =
        set LastReached = map{}

    GetStanding<private>(Agent:agent)<transacts>:[]checkpoint_component =
        if (List := Standing[Agent]) then List else array{}

    WithoutCheckpoint<private>(List:[]checkpoint_component, Checkpoint:checkpoint_component)<transacts>:[]checkpoint_component =
        for (Other : List, Other <> Checkpoint):
            Other
