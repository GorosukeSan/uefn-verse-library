using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Colors }
using { /UnrealEngine.com/Temporary/UI }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { WidgetSystem }
using { WidgetSystem.HudKit }
using { WidgetSystem.MenuKit }
using { WidgetSystem.CardKit }
using { _Test }

# Notification passed by the test
test_widget_ping_event<public> := class(scene_event):

# Role: test helper. Counts the received notifications and the close count per per-player widget handle
test_widget_counter<public> := class:
    var<private> Received:int = 0
    var<private> Hidden:int = 0

    OnReceived<public>(SceneEvent:scene_event):void =
        set Received += 1

    OnHidden<public>(Unused:tuple()):void =
        set Hidden += 1

    GetReceivedCount<public>()<transacts>:int = Received
    GetHiddenCount<public>()<transacts>:int = Hidden

# Role: test screen component. Shows an empty canvas and counts per handle
# Placement: created by the test code at runtime
test_player_widget_component<public> := class<final_super>(player_widget_component):

    var<private> Counters:[]test_widget_counter = array{}

    CreateWidget<override>(View:widget_view):widget =
        Counter := test_widget_counter{}
        View.ReceivedEvent.Subscribe(Counter.OnReceived)
        View.HiddenEvent.Subscribe(Counter.OnHidden)
        set Counters += array{Counter}
        canvas{}

    # Counts per created handle (in creation order)
    GetCounters<public>()<transacts>:[]test_widget_counter = Counters

# Role: verification of WidgetSystem
#   - shown to everyone on the activate signal (IsShown, CreateWidget count), SendToWidgets reaches ReceivedEvent, hidden on the deactivate signal with HiddenEvent once
#   - Audience = Chosen: not shown on activation, ShowFor shows it to one player, a second ShowFor for the same player still makes one, HideFor hides it
#   - Mode = Menu, one per player: showing a second menu to the same player closes the first (CloseOther)
#   - text_hud / gauge_hud / notification_hud / choice_menu appear and changing their values does not fail
# Test level: one entity with player_manager_component and one entity with this component. Start with at least one player (waits up to 10 seconds for them to join)
# Look: text, a gauge, a notification and a menu flash briefly during the test
# Result: [TEST] WidgetSystem in the output log
widget_system_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "WidgetSystem"}
        TickEvents.PrePhysics.Await()
        TestCards(Results)
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

    # Passing through widget_card's With* keeps every item other than the replaced one (checks that CopyCard was not forgotten when an item was added)
    TestCards<private>(Results:test_log):void =
        Base := widget_card{Id := "id", Title := "title", Subtitle := "sub", Description := "desc", Badge := "badge", AccentColor := color{R := 0.1, G := 0.2, B := 0.3}, Enabled := false}
        Card := Base.WithSubtitle("sub2").WithBadge("badge2").WithEnabled(true)
        Results.Check("card: Id kept", if (Card.Id = "id") then true else false)
        Results.Check("card: Title kept", if (Card.Title = "title") then true else false)
        Results.Check("card: Subtitle replaced", if (Card.Subtitle = "sub2") then true else false)
        Results.Check("card: Description kept", if (Card.Description = "desc") then true else false)
        Results.Check("card: Badge replaced", if (Card.Badge = "badge2") then true else false)
        Results.Check("card: Image kept (none)", if (Card.Image?) then false else true)
        Results.CheckFloat("card: AccentColor kept", Card.AccentColor.B, 0.3, 0.0001)
        Results.Check("card: Enabled replaced", Card.Enabled)
        Kept := Base.WithSubtitle("x")
        Results.Check("card: Enabled kept", if (Kept.Enabled?) then false else true)
        Results.Check("card: Badge kept", if (Kept.Badge = "badge") then true else false)

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
