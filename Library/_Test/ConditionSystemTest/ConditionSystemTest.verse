using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { ConditionSystem.GroupKit }
using { ConditionSystem.EventKit }
using { ActivationSystem }
using { _Test }

# Test notification (the type event_received_condition_component waits for)
condition_test_ping_event<public> := class(scene_event):

# Subclass of condition_test_ping_event (checks that subclasses match too)
condition_test_ping_child_event<public> := class(condition_test_ping_event):

# Test notification of a type nobody waits for
condition_test_other_event<public> := class(scene_event):

# Role: test condition. Toggled between satisfied / unsatisfied from code with SetSatisfied (also used by tests of other Systems)
# Placement: created by the test code at runtime (may also be placed in the editor)
test_condition_component<public> := class(condition_component):

    var<private> Satisfied:logic = false

    IsSatisfied<override>()<decides><transacts>:void =
        Satisfied?

    # Set whether it is satisfied to Value. Calls NotifyChanged only when it changed
    SetSatisfied<public>(Value:logic):void =
        if (Satisfied <> Value):
            set Satisfied = Value
            NotifyChanged()

# Role: counts logic notifications such as ChangedEvent (pass Record to Subscribe)
test_logic_recorder<public> := class:

    var<private> Count:int = 0
    var<private> LastValue:logic = false

    Record<public>(Value:logic):void =
        set Count += 1
        set LastValue = Value

    GetCount<public>()<transacts>:int = Count

    GetLast<public>()<transacts>:logic = LastValue

# Creates an entity with one Component under Parent and adds it. Returns the added entity
(Parent:entity).AddTestChild<public>(Component:component):entity =
    Child := Component.Entity
    Child.AddComponents(array{Component})
    Parent.AddEntities(array{Child})
    Child

# Role: verification of ConditionSystem. Checks combinations and nesting of condition_all / condition_any, how ChangedEvent arrives, AreChildConditionsSatisfied / IsAnyChildConditionSatisfied, and event_received_condition_component (EventKit)
# Test level: just one entity with this component (the condition entities are created by the test at runtime). No player needed
# Result: [TEST] ConditionSystem in the output log
condition_system_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "ConditionSystem"}
        # create them after every component in the same tree has started running
        TickEvents.PrePhysics.Await()
        TestAll(Results)
        TestAny(Results)
        TestNested(Results)
        TestEmpty(Results)
        TestEventReceived(Results)
        if (Results.Finish[]) {}

    TestAll<private>(Results:test_log):void =
        AllEntity := Entity.AddTestChild(condition_all_component{Entity := entity{}})
        A := test_condition_component{Entity := entity{}}
        B := test_condition_component{Entity := entity{}}
        AllEntity.AddTestChild(A)
        AllEntity.AddTestChild(B)
        if (All := AllEntity.GetComponent[condition_all_component]):
            Recorder := test_logic_recorder{}
            Subscription := All.ChangedEvent.Subscribe(Recorder.Record)
            Results.Check("all: none satisfied -> not satisfied", if (All.IsSatisfied[]) then false else true)
            A.SetSatisfied(true)
            Results.Check("all: one of two -> not satisfied", if (All.IsSatisfied[]) then false else true)
            Results.CheckInt("all: ChangedEvent after child change", Recorder.GetCount(), 1)
            B.SetSatisfied(true)
            Results.Check("all: both -> satisfied", if (All.IsSatisfied[]) then true else false)
            Results.Check("all: ChangedEvent carries true", Recorder.GetLast())
            A.SetSatisfied(false)
            Results.Check("all: back to not satisfied", if (All.IsSatisfied[]) then false else true)
            Results.CheckInt("all: ChangedEvent count", Recorder.GetCount(), 3)
            Subscription.Cancel()
        else:
            Results.Fail("all: setup", "condition_all_component not found")
        AllEntity.RemoveFromParent()

    TestAny<private>(Results:test_log):void =
        AnyEntity := Entity.AddTestChild(condition_any_component{Entity := entity{}})
        A := test_condition_component{Entity := entity{}}
        B := test_condition_component{Entity := entity{}}
        AnyEntity.AddTestChild(A)
        AnyEntity.AddTestChild(B)
        if (Any := AnyEntity.GetComponent[condition_any_component]):
            Results.Check("any: none -> not satisfied", if (Any.IsSatisfied[]) then false else true)
            B.SetSatisfied(true)
            Results.Check("any: second child only -> satisfied (order does not matter)", if (Any.IsSatisfied[]) then true else false)
            A.SetSatisfied(true)
            B.SetSatisfied(false)
            Results.Check("any: first child only -> satisfied", if (Any.IsSatisfied[]) then true else false)
        else:
            Results.Fail("any: setup", "condition_any_component not found")
        AnyEntity.RemoveFromParent()

    TestNested<private>(Results:test_log):void =
        # all ─┬ X
        #      └ any ─┬ Y
        #             └ Z
        AllEntity := Entity.AddTestChild(condition_all_component{Entity := entity{}})
        X := test_condition_component{Entity := entity{}}
        AllEntity.AddTestChild(X)
        AnyEntity := AllEntity.AddTestChild(condition_any_component{Entity := entity{}})
        Y := test_condition_component{Entity := entity{}}
        Z := test_condition_component{Entity := entity{}}
        AnyEntity.AddTestChild(Y)
        AnyEntity.AddTestChild(Z)
        if (All := AllEntity.GetComponent[condition_all_component]):
            Recorder := test_logic_recorder{}
            Subscription := All.ChangedEvent.Subscribe(Recorder.Record)
            X.SetSatisfied(true)
            Results.Check("nested: X only -> not satisfied", if (All.IsSatisfied[]) then false else true)
            Z.SetSatisfied(true)
            Results.Check("nested: X and Z -> satisfied", if (All.IsSatisfied[]) then true else false)
            Results.Check("nested: grandchild change reaches outer ChangedEvent", Recorder.GetLast())
            Results.CheckInt("nested: one ChangedEvent per change", Recorder.GetCount(), 2)
            Subscription.Cancel()
        else:
            Results.Fail("nested: setup", "condition_all_component not found")
        AllEntity.RemoveFromParent()

    TestEmpty<private>(Results:test_log):void =
        Empty := entity{}
        Entity.AddEntities(array{Empty})
        Results.Check("empty: AreChildConditionsSatisfied succeeds", if (Empty.AreChildConditionsSatisfied[]) then true else false)
        Results.Check("empty: IsAnyChildConditionSatisfied fails", if (Empty.IsAnyChildConditionSatisfied[]) then false else true)
        Empty.RemoveFromParent()

    TestEventReceived<private>(Results:test_log):void =
        Waiting := event_received_condition_component{Entity := entity{}, EventType := condition_test_ping_event}
        Unset := event_received_condition_component{Entity := entity{}}
        WaitingEntity := Entity.AddTestChild(Waiting)
        UnsetEntity := Entity.AddTestChild(Unset)
        Recorder := test_logic_recorder{}
        Subscription := Waiting.ChangedEvent.Subscribe(Recorder.Record)
        Results.Check("event: not satisfied at first", if (Waiting.IsSatisfied[]) then false else true)
        WaitingEntity.SendDown(condition_test_other_event{})
        Results.Check("event: other type does not satisfy", if (Waiting.IsSatisfied[]) then false else true)
        Ping := condition_test_ping_event{}
        WaitingEntity.SendDown(Ping)
        Results.Check("event: EventType satisfies", if (Waiting.IsSatisfied[]) then true else false)
        Results.Check("event: FindReceivedEvent returns the received event", if (Received := Waiting.FindReceivedEvent[], condition_test_ping_event[Received]) then true else false)
        Results.CheckInt("event: ChangedEvent once", Recorder.GetCount(), 1)
        WaitingEntity.SendDown(condition_test_ping_event{})
        Results.CheckInt("event: second event does not notify again", Recorder.GetCount(), 1)
        WaitingEntity.SendDown(activated_event{})
        Results.Check("event: activated_event resets", if (Waiting.IsSatisfied[]) then false else true)
        WaitingEntity.SendDown(condition_test_ping_child_event{})
        Results.Check("event: derived type satisfies", if (Waiting.IsSatisfied[]) then true else false)
        Waiting.Reset()
        Results.Check("event: Reset", if (Waiting.IsSatisfied[]) then false else true)
        UnsetEntity.SendDown(condition_test_ping_event{})
        Results.Check("event: default EventType (no_scene_event) never satisfies", if (Unset.IsSatisfied[]) then false else true)
        Subscription.Cancel()
        WaitingEntity.RemoveFromParent()
        UnsetEntity.RemoveFromParent()
