using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { _Test }

# Role: counts how many activate / deactivate signals it received
# Placement: created by the test code at runtime
test_activation_probe_component<public> := class<final_super>(component):

    var<private> ActivatedCount:int = 0
    var<private> DeactivatedCount:int = 0

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            set ActivatedCount += 1
        else if (deactivated_event[SceneEvent]):
            set DeactivatedCount += 1
        false

    GetActivatedCount<public>()<transacts>:int = ActivatedCount

    GetDeactivatedCount<public>()<transacts>:int = DeactivatedCount

# Role: verification of ActivationSystem. Checks that SendActivated / SendDeactivated reach descendants and that activate_on_begin_component sends the activate signal exactly once on the frame after begin
# Test level: just one entity with this component. No player needed
# Result: [TEST] ActivationSystem in the output log
activation_system_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "ActivationSystem"}
        TickEvents.PrePhysics.Await()

        # parent - child (probe). Sending from the parent reaches the child
        Parent := entity{}
        Entity.AddEntities(array{Parent})
        ChildEntity := entity{}
        Probe := test_activation_probe_component{Entity := ChildEntity}
        ChildEntity.AddComponents(array{Probe})
        Parent.AddEntities(array{ChildEntity})
        Parent.SendActivated()
        Results.CheckInt("SendActivated reaches a child", Probe.GetActivatedCount(), 1)
        Parent.SendDeactivated()
        Results.CheckInt("SendDeactivated reaches a child", Probe.GetDeactivatedCount(), 1)
        Parent.RemoveFromParent()

        # activate_on_begin_component and probe on the same entity
        BeginEntity := entity{}
        BeginProbe := test_activation_probe_component{Entity := BeginEntity}
        BeginEntity.AddComponents(array{activate_on_begin_component{Entity := BeginEntity}, BeginProbe})
        Entity.AddEntities(array{BeginEntity})
        Results.CheckInt("activate_on_begin: not yet in the same frame", BeginProbe.GetActivatedCount(), 0)
        Sleep(0.2)
        Results.CheckInt("activate_on_begin: activated once", BeginProbe.GetActivatedCount(), 1)
        BeginEntity.RemoveFromParent()
        if (Results.Finish[]) {}
