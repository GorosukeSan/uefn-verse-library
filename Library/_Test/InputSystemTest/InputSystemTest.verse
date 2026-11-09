using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { InputSystem.InputKit }
using { InputSystem.ReadyKit }
using { PlayerSystem }
using { SceneGraphSystem }
using { _Test }

# 役割：ReadyChangedEvent の知らせを数える（Subscribe に Record を渡す）
test_ready_recorder<public> := class:

    var<private> Count:int = 0
    var<private> LastReady:logic = false

    Record<public>(Payload:tuple(agent, logic)):void =
        set Count += 1
        set LastReady = Payload(1)

    GetCount<public>()<transacts>:int = Count

    GetLast<public>()<transacts>:logic = LastReady

# 役割：InputSystem の動作確認。player_ready_component をコードから動かし（Activate / FindInput / SetReady / ToggleReady / IsReady / GetReadyCount / ResetAll / Deactivate）、ReadyChangedEvent・player_ready_changed_event・all_players_ready_condition を確かめる。slot が世界から外れたとき（退出の代わり）に、その人の準備 OK が数に残らないことも確かめる。最後に E キー（ゲームパッドは RB）を押してもらい、player_input_component の TriggeredEvent と、押して（同じ entity の player_input_component の InputAction で）準備 OK が切り替わることを確かめる
# テストのレベル：player_manager_component を付けた entity を 1 つと、この component を付けた entity を 1 つ（入力と準備の component はテストが実行時に作る）。区画（または世界）にほかの player_ready_component を置かない。プレイヤー 1 人で始める（参加を最大 10 秒待つ）
# 操作：ログに「press E」と出たら 10 秒以内に E キー（ゲームパッドは RB）を押す。押さなければその項目だけ失敗になる
# 結果：出力ログの [TEST] InputSystem
input_system_test_component<public> := class<final_super>(component):

    var<private> ReadyEventCount:int = 0

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (player_ready_changed_event[SceneEvent]):
            set ReadyEventCount += 1
        false

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "InputSystem"}
        TickEvents.PrePhysics.Await()
        if (Manager := Entity.FindScopedComponent[player_manager_component]):
            if (Manager.GetPlayerCount() = 0):
                Arrived6 := AwaitWithin(Manager.PlayerAddedEvent, 10.0)
                if (not Arrived6?):
                    Results.Fail("setup", "no player joined within 10 s")
            if (Slot := Manager.GetSlots()[0]):
                Run(Results, Manager, Slot.Player)
        else:
            Results.Fail("setup", "player_manager_component not found")
        if (Results.Finish[]) {}

    Run<private>(Results:test_log, Manager:player_manager_component, Player:player)<suspends>:void =
        InputEntity := entity{}
        Input := player_input_component{Entity := InputEntity}
        Ready := player_ready_component{Entity := InputEntity}
        Condition := all_players_ready_condition_component{Entity := InputEntity}
        InputEntity.AddComponents(array{Input, Ready, Condition})
        Entity.AddEntities(array{InputEntity})
        Recorder := test_ready_recorder{}
        Subscription := Ready.ReadyChangedEvent.Subscribe(Recorder.Record)

        Results.Check("ready: not active at first", if (Ready.IsActive[]) then false else true)
        Ready.SetReady(Player, true)
        Results.Check("ready: SetReady ignored while inactive", if (Ready.IsReady[Player]) then false else true)

        Ready.Activate()
        Results.Check("ready: active after Activate", if (Ready.IsActive[]) then true else false)
        Results.Check("ready: FindInput finds the player_input_component on the same entity", if (Ready.FindInput[] = Input) then true else false)
        Results.Check("ready: not ready at first", if (Ready.IsReady[Player]) then false else true)
        Ready.SetReady(Player, true)
        Results.Check("ready: IsReady after SetReady", if (Ready.IsReady[Player]) then true else false)
        Results.CheckInt("ready: GetReadyCount", Ready.GetReadyCount(), 1)
        Results.CheckInt("ready: ReadyChangedEvent once", Recorder.GetCount(), 1)
        Results.Check("ready: ReadyChangedEvent carries true", Recorder.GetLast())
        Results.CheckInt("ready: player_ready_changed_event received", ReadyEventCount, 1)
        Ready.SetReady(Player, true)
        Results.CheckInt("ready: no event when unchanged", Recorder.GetCount(), 1)
        if (Manager.GetPlayerCount() = 1):
            Results.Check("ready: all_players_ready satisfied", if (Condition.IsSatisfied[]) then true else false)
        Ready.ToggleReady(Player)
        Results.Check("ready: ToggleReady turns it off", if (Ready.IsReady[Player]) then false else true)
        Ready.ToggleReady(Player)
        Results.Check("ready: ToggleReady turns it on again", if (Ready.IsReady[Player]) then true else false)
        Ready.ResetAll()
        Results.CheckInt("ready: ResetAll -> 0", Ready.GetReadyCount(), 0)
        Results.Check("ready: all_players_ready not satisfied after ResetAll", if (Condition.IsSatisfied[]) then false else true)
        TestLeave(Results, Manager, Ready, Player)

        # 押して確かめる
        Input.Activate()
        Results.Check("input: active after Activate", if (Input.IsActive[]) then true else false)
        Print("[TEST] InputSystem: press E (gamepad RB) within 10 seconds")
        MaybePressed := AwaitWithin(Input.TriggeredEvent, 10.0)
        if (Pressed := MaybePressed?):
            Results.Check("input: TriggeredEvent by the player", if (Pressed = Player) then true else false)
            Results.Check("input: pressing toggles ready", if (Ready.IsReady[Player]) then true else false)
        else:
            Results.Fail("input: TriggeredEvent", "not pressed within 10 s")
        Input.Deactivate()
        Results.Check("input: not active after Deactivate", if (Input.IsActive[]) then false else true)

        Ready.Deactivate()
        Results.Check("ready: not active after Deactivate", if (Ready.IsActive[]) then false else true)
        Results.CheckInt("ready: count 0 after Deactivate", Ready.GetReadyCount(), 0)
        Subscription.Cancel()
        InputEntity.RemoveFromParent()

    # 退出の代わりに、その人の slot を manager の下から外す（退出のときと同じく、slot の下の view が世界から外れて OnEndSimulation を通る）。
    # 外れた view は数えず、準備 OK も戻る。slot を戻すと view も戻り、準備 OK でないところから数え直す
    # ⚠ 本物の退出（manager の PlayerRemovedEvent で view の一覧から除く）は、プレイヤー 1 人では確かめられない（2 人以上で 1 人が抜けて確かめる）
    TestLeave<private>(Results:test_log, Manager:player_manager_component, Ready:player_ready_component, Player:player):void =
        Ready.SetReady(Player, true)
        if (Slot := Manager.FindSlot[Player]):
            SlotEntity := Slot.Entity
            SlotEntity.RemoveFromParent()
            Results.CheckInt("leave: a view outside the world is not counted", Ready.GetReadyCount(), 0)
            Results.Check("leave: IsReady fails while the slot is out", if (Ready.IsReady[Player]) then false else true)
            Results.Check("leave: player_ready_tag removed when the view stops", if (Player.HasPlayerTag[player_ready_tag]) then false else true)
            Manager.Entity.AddEntities(array{SlotEntity})
            Results.Check("leave: ready is reset when the view stops", if (Ready.IsReady[Player]) then false else true)
            Ready.SetReady(Player, true)
            Results.CheckInt("leave: the view is counted again after the slot is back", Ready.GetReadyCount(), 1)
            Ready.ResetAll()
        else:
            Results.Fail("leave: setup", "slot not found")
