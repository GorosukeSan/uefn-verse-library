using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/UI }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { WidgetSystem }
using { WidgetSystem.HudKit }
using { WidgetSystem.MenuKit }
using { _Test }

# テストで渡す知らせ
test_widget_ping_event<public> := class(scene_event):

# 役割：テスト用。1 人分の窓口ごとに、届いた知らせと閉じた回数を数える
test_widget_counter<public> := class:
    var<private> Received:int = 0
    var<private> Hidden:int = 0

    OnReceived<public>(SceneEvent:scene_event):void =
        set Received += 1

    OnHidden<public>(Unused:tuple()):void =
        set Hidden += 1

    GetReceivedCount<public>()<transacts>:int = Received
    GetHiddenCount<public>()<transacts>:int = Hidden

# 役割：テスト用の画面表示の component。空の canvas を出し、窓口ごとに数える
# 置き方：テストのコードが実行時に作る
test_player_widget_component<public> := class<final_super>(player_widget_component):

    var<private> Counters:[]test_widget_counter = array{}

    CreateWidget<override>(View:widget_view):widget =
        Counter := test_widget_counter{}
        View.ReceivedEvent.Subscribe(Counter.OnReceived)
        View.HiddenEvent.Subscribe(Counter.OnHidden)
        set Counters += array{Counter}
        canvas{}

    # 作った窓口ごとの数（作った順）
    GetCounters<public>()<transacts>:[]test_widget_counter = Counters

# 役割：WidgetSystem の動作確認
#   - 起動の合図で全員に出る（IsShown・CreateWidget の回数）、SendToWidgets が ReceivedEvent に届く、停止の合図で消えて HiddenEvent が 1 回届く
#   - Audience = Chosen：起動しても出ない、ShowFor で 1 人に出る、同じ人に 2 回 ShowFor しても 1 枚、HideFor で消える
#   - Mode = Menu の 1 人 1 枚：同じ人に 2 つ目のメニューを出すと、1 つ目が閉じる（CloseOther）
#   - text_hud / gauge_hud / notification_hud / choice_menu が出て、値を変えても失敗しない
# テストのレベル：player_manager_component を付けた entity を 1 つと、この component を付けた entity を 1 つ。プレイヤー 1 人以上で始める（参加を最大 10 秒待つ）
# 見た目：テストの途中で、文字・ゲージ・通知・メニューが一瞬出る
# 結果：出力ログの [TEST] WidgetSystem
widget_system_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "WidgetSystem"}
        TickEvents.PrePhysics.Await()
        if (Manager := Entity.FindScopedComponent[player_manager_component]):
            if (Manager.GetPlayerCount() = 0):
                Arrived := AwaitWithin(Manager.PlayerAddedEvent, 10.0)
                if (not Arrived?):
                    Results.Fail("setup", "no player joined within 10 s")
            TestEveryone(Results, Manager)
            if (Slot := Manager.GetSlots()[0]):
                TestChosen(Results, Slot.Player)
                TestMenuConflict(Results, Slot.Player)
                TestKits(Results, Slot.Player)
        else:
            Results.Fail("setup", "player_manager_component not found")
        if (Results.Finish[]) {}

    TestEveryone<private>(Results:test_log, Manager:player_manager_component):void =
        WidgetEntity := entity{}
        Widgets := test_player_widget_component{Entity := WidgetEntity}
        WidgetEntity.AddComponents(array{Widgets})
        Entity.AddEntities(array{WidgetEntity})
        PlayerCount := Manager.GetPlayerCount()

        Results.Check("not shown before activation", if (Widgets.IsShown[]) then false else true)
        WidgetEntity.SendActivated()
        Results.Check("shown after activated_event", if (Widgets.IsShown[]) then true else false)
        Results.CheckInt("one widget per player", Widgets.GetCounters().Length, PlayerCount)

        Widgets.SendToWidgets(test_widget_ping_event{})
        for (Counter : Widgets.GetCounters()):
            Results.CheckInt("SendToWidgets reaches ReceivedEvent", Counter.GetReceivedCount(), 1)

        WidgetEntity.SendDeactivated()
        Results.Check("not shown after deactivated_event", if (Widgets.IsShown[]) then false else true)
        for (Counter : Widgets.GetCounters()):
            Results.CheckInt("HiddenEvent once", Counter.GetHiddenCount(), 1)
        WidgetEntity.RemoveFromParent()

    TestChosen<private>(Results:test_log, Agent:agent):void =
        WidgetEntity := entity{}
        Widgets := test_player_widget_component{Entity := WidgetEntity, Audience := player_widget_audience.Chosen}
        WidgetEntity.AddComponents(array{Widgets})
        Entity.AddEntities(array{WidgetEntity})
        WidgetEntity.SendActivated()
        Results.CheckInt("Chosen: nobody on activation", Widgets.GetCounters().Length, 0)
        Widgets.ShowFor(Agent)
        Results.Check("Chosen: ShowFor shows", if (Widgets.IsShownFor[Agent]) then true else false)
        Widgets.ShowFor(Agent)
        Results.CheckInt("Chosen: second ShowFor does not duplicate", Widgets.GetCounters().Length, 1)
        Results.Check("FindView returns the view", if (View := Widgets.FindView[Agent], View.Player = Agent) then true else false)
        Widgets.HideFor(Agent)
        Results.Check("Chosen: HideFor hides", if (Widgets.IsShownFor[Agent]) then false else true)
        WidgetEntity.RemoveFromParent()

    TestMenuConflict<private>(Results:test_log, Agent:agent):void =
        FirstEntity := entity{}
        First := test_player_widget_component{Entity := FirstEntity, Mode := player_widget_mode.Menu, Audience := player_widget_audience.Chosen}
        FirstEntity.AddComponents(array{First})
        SecondEntity := entity{}
        Second := test_player_widget_component{Entity := SecondEntity, Mode := player_widget_mode.Menu, Audience := player_widget_audience.Chosen}
        SecondEntity.AddComponents(array{Second})
        Entity.AddEntities(array{FirstEntity, SecondEntity})
        First.ShowFor(Agent)
        Second.ShowFor(Agent)
        Results.Check("menu: second menu shown", if (Second.IsShownFor[Agent]) then true else false)
        Results.Check("menu: first menu closed (one menu per player)", if (First.IsShownFor[Agent]) then false else true)
        Second.HideFor(Agent)
        FirstEntity.RemoveFromParent()
        SecondEntity.RemoveFromParent()

    TestKits<private>(Results:test_log, Agent:agent):void =
        KitEntity := entity{}
        Text := text_hud_component{Entity := KitEntity, Text := "test"}
        Gauge := gauge_hud_component{Entity := KitEntity}
        Notice := notification_hud_component{Entity := KitEntity}
        Menu := choice_menu_component{Entity := KitEntity, Options := array{"A", "B"}, Audience := player_widget_audience.Chosen}
        KitEntity.AddComponents(array{Text, Gauge, Notice, Menu})
        Entity.AddEntities(array{KitEntity})
        KitEntity.SendActivated()
        Results.Check("text_hud shown", if (Text.IsShownFor[Agent]) then true else false)
        Text.SetTextFor(Agent, StringToMessage("changed"))
        Gauge.SetRatioFor(Agent, 0.25)
        Results.CheckFloat("gauge ratio", Gauge.GetRatioFor(Agent), 0.25, 0.001)
        Results.Check("notification_hud shown (ActiveOnBegin)", if (Notice.IsShownFor[Agent]) then true else false)
        Notice.Notify(Agent, StringToMessage("hello"))
        Menu.OpenFor(Agent)
        Results.Check("choice_menu opened", if (Menu.IsShownFor[Agent]) then true else false)
        Menu.HideFor(Agent)
        KitEntity.RemoveFromParent()
