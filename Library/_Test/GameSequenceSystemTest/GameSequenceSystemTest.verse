using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { GameSequenceSystem }
using { _Test }
using { _Test.ConditionSystemTest }

# Role: remembers why a node was exited (pass Record to Subscribe of ExitedEvent)
test_exit_recorder<public> := class:

    var<private> Count:int = 0
    var<private> LastReason:?game_node_exit_reason = false

    Record<public>(Reason:game_node_exit_reason):void =
        set Count += 1
        set LastReason = option{Reason}

    GetCount<public>()<transacts>:int = Count

    # Succeeds when the last exit reason is transitioned
    WasTransitioned<public>()<decides><transacts>:void =
        LastReason? = game_node_exit_reason.Transitioned

    # Succeeds when the last exit reason is jumped
    WasJumped<public>()<decides><transacts>:void =
        LastReason? = game_node_exit_reason.Jumped

    # Succeeds when the last exit reason is stopped
    WasStopped<public>()<decides><transacts>:void =
        LastReason? = game_node_exit_reason.Stopped

# Role: remembers state changes of the sequence (pass Record to Subscribe of StateChangedEvent)
test_sequence_state_recorder<public> := class:

    var<private> Seen:[]game_sequence_state = array{}

    Record<public>(State:game_sequence_state):void =
        set Seen += array{State}

    # Succeeds when State has been received at least once
    HasSeen<public>(State:game_sequence_state)<decides><transacts>:void =
        Seen.Find[State]

# Role: verification of GameSequenceSystem. Checks the first node chosen by Order, transitions (with 2 conditions it does not advance until both are satisfied), Finished, Restart, JumpTo, Stop, exit reasons, a StartOnActivate sequence (a sequence placed under a node starts when the node is entered and stops when it is exited), and Stop -> Start on the same frame (stop, then start again; the child sequence when the parent re-enters the same node)
# Test level: just one entity with this component (sequence, nodes, transitions and conditions are created by the test at runtime). No player needed
# Sequence built:
#   sequence (StartOnRoundStart / StartOnBegin off)
#   ├ B (Order 1) - end (no Target) - 2 conditions
#   ├ A (Order 0) - to B - 1 condition
#   └ C (Order 5) - no transition (entered only by JumpTo)
#     └ inner (StartOnActivate; StartOnRoundStart off) - D (Order 0)
# Result: [TEST] GameSequenceSystem in the output log
game_sequence_system_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "GameSequenceSystem"}
        TickEvents.PrePhysics.Await()
        SequenceEntity := entity{}
        Sequence := game_sequence_component{Entity := SequenceEntity, StartOnRoundStart := false, StartOnBegin := false}
        SequenceEntity.AddComponents(array{Sequence})
        Entity.AddEntities(array{SequenceEntity})

        # Add B first so that insertion order is not what makes it first
        B := AddNode(SequenceEntity, 1)
        A := AddNode(SequenceEntity, 0)
        C := AddNode(SequenceEntity, 5)
        AToB := AddTransition(A, option{B.Entity})
        CondAB := AddCondition(AToB)
        BEnd := AddTransition(B, false)
        CondEnd1 := AddCondition(BEnd)
        CondEnd2 := AddCondition(BEnd)
        InnerEntity := entity{}
        Inner := game_sequence_component{Entity := InnerEntity, StartOnRoundStart := false, StartOnActivate := true}
        InnerEntity.AddComponents(array{Inner})
        C.Entity.AddEntities(array{InnerEntity})
        D := AddNode(InnerEntity, 0)

        AExits := test_exit_recorder{}
        AExitSubscription := A.ExitedEvent.Subscribe(AExits.Record)

        Results.Check("first node is the lowest Order (not child order)", if (Sequence.FindFirstNode[] = A) then true else false)
        Results.Check("idle before Start", if (Sequence.State = game_sequence_state.Idle) then true else false)
        Results.Check("StartOnActivate: inner sequence idle before C is entered", if (Inner.State = game_sequence_state.Idle) then true else false)

        Sequence.Start()
        Sleep(0.2)
        Results.Check("running after Start", if (Sequence.IsRunning[]) then true else false)
        Results.Check("current node is A", if (Sequence.CurrentNode? = A) then true else false)
        Results.Check("A is active", if (A.IsActive[]) then true else false)

        CondAB.SetSatisfied(true)
        Sleep(0.2)
        Results.Check("moved to B when A's condition is satisfied", if (Sequence.CurrentNode? = B) then true else false)
        Results.Check("A exited with transitioned", if (AExits.WasTransitioned[]) then true else false)
        Results.Check("A is not active", if (A.IsActive[]) then false else true)

        CondEnd1.SetSatisfied(true)
        Sleep(0.2)
        Results.Check("two conditions: one is not enough", if (Sequence.CurrentNode? = B) then true else false)
        CondEnd2.SetSatisfied(true)
        Sleep(0.2)
        Results.Check("two conditions: both -> Finished", if (Sequence.State = game_sequence_state.Finished) then true else false)
        Results.Check("no current node after Finished", if (Sequence.CurrentNode?) then false else true)

        # Reset the conditions before restarting (otherwise A goes straight to B and B straight to the end)
        CondAB.SetSatisfied(false)
        CondEnd1.SetSatisfied(false)
        Sequence.Restart()
        Sleep(0.2)
        Results.Check("Restart starts again from A", if (Sequence.CurrentNode? = A) then true else false)

        Sequence.JumpTo(C)
        Sleep(0.2)
        Results.Check("JumpTo moves to C", if (Sequence.CurrentNode? = C) then true else false)
        Results.Check("A exited with jumped", if (AExits.WasJumped[]) then true else false)
        Results.Check("StartOnActivate: inner sequence starts when C is entered", if (Inner.CurrentNode? = D) then true else false)

        Sequence.Stop()
        Sleep(0.2)
        Results.Check("Stop -> Stopped", if (Sequence.State = game_sequence_state.Stopped) then true else false)
        Results.Check("C is not active after Stop", if (C.IsActive[]) then false else true)
        Results.Check("StartOnActivate: inner sequence stops when C is exited", if (Inner.State = game_sequence_state.Stopped) then true else false)
        Results.Check("StartOnActivate: D is not active after C is exited", if (D.IsActive[]) then false else true)

        Sequence.JumpTo(B)
        Sleep(0.2)
        Results.Check("JumpTo while stopped starts at B", if (Sequence.CurrentNode? = B) then true else false)

        # Stop -> Start on the same frame: not dropped; stops, then starts again at the first node (A)
        States := test_sequence_state_recorder{}
        StateSubscription := Sequence.StateChangedEvent.Subscribe(States.Record)
        Sequence.Stop()
        Sequence.Start()
        Sleep(0.2)
        Results.Check("Stop then Start in the same frame: running again", if (Sequence.IsRunning[]) then true else false)
        Results.Check("Stop then Start in the same frame: starts again from A", if (Sequence.CurrentNode? = A) then true else false)
        Results.Check("Stop then Start in the same frame: went through Stopped", if (States.HasSeen[game_sequence_state.Stopped]) then true else false)
        StateSubscription.Cancel()

        # Nesting: when the parent re-enters the same node (C), the child sequence receives the deactivate and activate signals on the same frame in a row. It does not stay stopped; the child advances from D
        Sequence.JumpTo(C)
        Sleep(0.2)
        Sequence.JumpTo(C)
        Sleep(0.2)
        Results.Check("re-enter the same node: inner sequence is running", if (Inner.IsRunning[]) then true else false)
        Results.Check("re-enter the same node: inner sequence is at D", if (Inner.CurrentNode? = D) then true else false)
        Sequence.Stop()

        AExitSubscription.Cancel()
        SequenceEntity.RemoveFromParent()
        if (Results.Finish[]) {}

    AddNode<private>(Parent:entity, Order:int):game_node_component =
        NodeEntity := entity{}
        Node := game_node_component{Entity := NodeEntity, Order := Order}
        NodeEntity.AddComponents(array{Node})
        Parent.AddEntities(array{NodeEntity})
        Node

    AddTransition<private>(Node:game_node_component, Target:?entity):entity =
        Node.Entity.AddTestChild(game_transition_component{Entity := entity{}, Target := Target})

    AddCondition<private>(TransitionEntity:entity):test_condition_component =
        Condition := test_condition_component{Entity := entity{}}
        TransitionEntity.AddTestChild(Condition)
        Condition
