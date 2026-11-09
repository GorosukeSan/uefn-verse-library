using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ModeSystem }
using { ModeSystem.ConditionKit }
using { ModeSystem.VoteKit }
using { PlayerSystem }
using { SceneGraphSystem }
using { _Test }

# Role: counts SelectedEvent notifications (pass Record to Subscribe)
test_mode_recorder<public> := class:

    var<private> Count:int = 0
    var<private> LastMode:?game_mode_component = false

    Record<public>(Mode:?game_mode_component):void =
        set Count += 1
        set LastMode = Mode

    GetCount<public>()<transacts>:int = Count

    GetLast<public>()<transacts>:?game_mode_component = LastMode

# Role: verification of ModeSystem. Checks candidate order by Order, accepting (Activate / Deactivate), how Select decides (AllowReselect), Clear, SelectedEvent and mode_changed_event, mode_selected_condition, and voting (mode_vote_component)
# Test level: one entity with this component (mode_select is created by the test at runtime). Do not place another mode_select_component in the scope (or the world)
#   The voting test needs player_manager_component and one player (skipped when absent)
# Result: [TEST] ModeSystem in the output log
mode_system_test_component<public> := class<final_super>(component):

    var<private> ChangedEventCount:int = 0

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (mode_changed_event[SceneEvent]):
            set ChangedEventCount += 1
        false

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "ModeSystem"}
        TickEvents.PrePhysics.Await()
        SelectEntity := entity{}
        Selector := mode_select_component{Entity := SelectEntity}
        Vote := mode_vote_component{Entity := SelectEntity}
        SelectEntity.AddComponents(array{Selector, Vote})
        Entity.AddEntities(array{SelectEntity})
        # add them in the reverse of Order
        Second := AddMode(SelectEntity, "Second", 1)
        First := AddMode(SelectEntity, "First", 0)

        ConditionEntity := entity{}
        Condition := mode_selected_condition_component{Entity := ConditionEntity, Mode := option{First.Entity}}
        ConditionEntity.AddComponents(array{Condition})
        Entity.AddEntities(array{ConditionEntity})

        Recorder := test_mode_recorder{}
        Subscription := Selector.SelectedEvent.Subscribe(Recorder.Record)

        Modes := Selector.GetModes()
        Results.CheckInt("GetModes count", Modes.Length, 2)
        Results.Check("GetModes sorted by Order", if (Modes[0] = First, Modes[1] = Second) then true else false)

        BeforeActivate := Selector.TrySelect(First)
        Results.Check("Select is ignored before Activate", if (BeforeActivate?) then false else true)
        Selector.Activate()
        Results.Check("IsActive after Activate", if (Selector.IsActive[]) then true else false)
        AfterActivate := Selector.TrySelect(First)
        Results.Check("Select after Activate", AfterActivate)
        Results.Check("IsSelected(First)", if (Selector.IsSelected[First]) then true else false)
        Results.Check("SelectedEvent with First", if (Recorder.GetLast()? = First) then true else false)
        Results.CheckInt("mode_changed_event received once", ChangedEventCount, 1)
        Results.Check("mode_selected_condition satisfied", if (Condition.IsSatisfied[]) then true else false)

        Reselected := Selector.TrySelect(Second)
        Results.Check("first wins: second Select is ignored", if (Reselected?) then false else true)
        Results.Check("still First", if (Selector.FindSelected[] = First) then true else false)

        Selector.Clear()
        Results.Check("Clear: nothing selected", if (Selector.FindSelected[]) then false else true)
        Results.Check("Clear: SelectedEvent with false", if (Recorder.GetLast()?) then false else true)
        Results.CheckInt("Clear: mode_changed_event received", ChangedEventCount, 2)
        Results.Check("Clear: condition not satisfied", if (Condition.IsSatisfied[]) then false else true)

        Selector.TrySelect(Second)
        Selector.Deactivate()
        Results.Check("Deactivate clears the selection", if (Selector.FindSelected[]) then false else true)
        Results.Check("not active after Deactivate", if (Selector.IsActive[]) then false else true)

        TestVote(Results, Selector, Vote, First, Second)

        Subscription.Cancel()
        ConditionEntity.RemoveFromParent()
        SelectEntity.RemoveFromParent()
        if (Results.Finish[]) {}

    TestVote<private>(Results:test_log, Selector:mode_select_component, Vote:mode_vote_component, First:game_mode_component, Second:game_mode_component):void =
        if (Manager := Entity.FindScopedComponent[player_manager_component], Slot := Manager.GetSlots()[0]):
            Selector.Activate()
            Accepted := Vote.TryVote(Slot.Player, Second)
            Results.Check("vote: Vote accepted", Accepted)
            if (Manager.GetPlayerCount() = 1):
                Results.Check("vote: everyone voted -> Second selected", if (Selector.FindSelected[] = Second) then true else false)
            else:
                Results.CheckInt("vote: vote count", Vote.GetVoteCount(Second), 1)
            Selector.Deactivate()
            Results.Check("vote: votes cleared with the selection", if (Vote.FindVote[Slot.Player]) then false else true)
        else:
            Print("[TEST] ModeSystem: vote test skipped (no player_manager_component or no player)")
            Results.CheckInt("vote: no votes without players", Vote.GetVoteCount(First), 0)

    AddMode<private>(Parent:entity, Title:string, Order:int):game_mode_component =
        ModeEntity := entity{}
        Mode := game_mode_component{Entity := ModeEntity, Title := Title, Order := Order}
        ModeEntity.AddComponents(array{Mode})
        Parent.AddEntities(array{ModeEntity})
        Mode
