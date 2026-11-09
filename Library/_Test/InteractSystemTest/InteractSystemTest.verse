using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { InteractSystem }
using { InteractSystem.ConditionKit }
using { InteractSystem.GateKit }
using { _Test }

# Role: verification of InteractSystem. Checks interact_gate_component's Open / Close / IsOpen, InteractedEvent and interacted_event on press, interacted_condition_component (chosen by Trigger) and Reset
# Test level:
#   - the button entity: mesh + basic_interactable_component + interact_trigger_component + interact_gate_component (OpenOnBegin off). Place it near the player
#   - one entity with this component; put the button entity into Button
# Input: when "interact" appears in the log, press the button within 15 seconds (hold until it completes). If not pressed, only that item fails
# Result: [TEST] InteractSystem in the output log
interact_system_test_component<public> := class<final_super>(component):

    # Button entity that carries interact_trigger_component and interact_gate_component
    @editable
    Button<public>:?entity = false

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "InteractSystem"}
        # wait until the gate has finished syncing with the interactable_component
        Sleep(0.5)
        if:
            ButtonEntity := Button?
            Trigger := ButtonEntity.GetComponent[interact_trigger_component]
            Gate := ButtonEntity.GetComponent[interact_gate_component]
        then:
            Run(Results, ButtonEntity, Trigger, Gate)
        else:
            Results.Fail("setup", "Button with interact_trigger_component and interact_gate_component is not set")
        if (Results.Finish[]) {}

    Run<private>(Results:test_log, ButtonEntity:entity, Trigger:interact_trigger_component, Gate:interact_gate_component)<suspends>:void =
        ConditionEntity := entity{}
        Condition := interacted_condition_component{Entity := ConditionEntity, Trigger := option{ButtonEntity}}
        ConditionEntity.AddComponents(array{Condition})
        Entity.AddEntities(array{ConditionEntity})

        Results.Check("gate closed at first (OpenOnBegin off)", if (Gate.IsOpen[]) then false else true)
        Gate.Open()
        Results.Check("gate open after Open", if (Gate.IsOpen[]) then true else false)
        Results.Check("condition not satisfied before interact", if (Condition.IsSatisfied[]) then false else true)

        Print("[TEST] InteractSystem: interact with the button within 15 seconds")
        Arrived8 := AwaitWithin(Trigger.InteractedEvent, 15.0)
        if (Arrived8?):
            Results.Pass("InteractedEvent received")
            Results.Check("interacted_condition satisfied (Trigger)", if (Condition.IsSatisfied[]) then true else false)
            Condition.Reset()
            Results.Check("Reset -> not satisfied", if (Condition.IsSatisfied[]) then false else true)
        else:
            Results.Fail("InteractedEvent", "not interacted within 15 s")

        Gate.Close()
        Results.Check("gate closed after Close", if (Gate.IsOpen[]) then false else true)
        ConditionEntity.RemoveFromParent()
