using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { PlayerSystem }
using { PlayerSystem.ConditionKit }
using { SceneGraphSystem }
using { _Test }
using { _Test.ConditionSystemTest }

# 役割：テスト用の view。player_view_set が slot の下に作る（中身は持たない）
# 置き方：テストのコードが実行時に作る
test_player_view_component<public> := class<final_super>(component):

    Slot<public>:player_slot_component

# テスト用の状態タグ（派生で付けて基底で探せるかを見る）
test_moving_tag<public> := class(controlled_movement_tag):

# 役割：PlayerSystem の動作確認。player_manager_component の slot（GetPlayerCount / GetSlots / FindSlot）、player_count_condition、player_view_set（Activate / Deactivate / GetViews / FindViewSlot）、SubscribePlayers、プレイヤーのタグ（player_tag_holder / HasPlayerTag）、組（player_group_component の Join / Leave / GetMemberCount / FindAncestorGroup）と組の人数の条件（player_group_count_condition_component）を確かめる。テスト中に参加・退出があれば、その知らせ（player_added_event / PlayerAddedEvent など）もログに出す
# テストのレベル：player_manager_component を付けた entity を 1 つと、この component を付けた entity を 1 つ。プレイヤー 1 人以上で始める（参加を最大 10 秒待つ）
# 結果：出力ログの [TEST] PlayerSystem
player_system_test_component<public> := class<final_super>(component):

    var<private> AddedEventCount:int = 0
    var<private> SubscribedCount:int = 0

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Added := player_added_event[SceneEvent]):
            set AddedEventCount += 1
            Print("[TEST] PlayerSystem: player_added_event (slots {Added.Manager.GetPlayerCount()})")
        else if (Removed := player_removed_event[SceneEvent]):
            Print("[TEST] PlayerSystem: player_removed_event (slots {Removed.Manager.GetPlayerCount()})")
        false

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "PlayerSystem"}
        TickEvents.PrePhysics.Await()
        if (Manager := Entity.FindScopedComponent[player_manager_component]):
            if (Manager.GetPlayerCount() = 0):
                Arrived9 := AwaitWithin(Manager.PlayerAddedEvent, 10.0)
                if (not Arrived9?):
                    Results.Fail("setup", "no player joined within 10 s")
            TestManager(Results, Manager)
            TestCondition(Results, Manager)
            TestViewSet(Results, Manager)
            TestSubscribePlayers(Results, Manager)
            TestPlayerTags(Results, Manager)
            TestGroup(Results, Manager)
        else:
            Results.Fail("setup", "player_manager_component not found")
        if (Results.Finish[]) {}

    TestManager<private>(Results:test_log, Manager:player_manager_component):void =
        Count := Manager.GetPlayerCount()
        Results.Check("at least one slot", if (Count > 0) then true else false)
        Results.CheckInt("GetSlots matches GetPlayerCount", Manager.GetSlots().Length, Count)
        if (Slot := Manager.GetSlots()[0]):
            Results.Check("FindSlot finds the slot of its player", if (Manager.FindSlot[Slot.Player] = Slot) then true else false)

    TestCondition<private>(Results:test_log, Manager:player_manager_component):void =
        ConditionEntity := entity{}
        Reached := player_count_condition_component{Entity := ConditionEntity, MinPlayerCount := 1}
        TooMany := player_count_condition_component{Entity := ConditionEntity, MinPlayerCount := 100}
        ConditionEntity.AddComponents(array{Reached, TooMany})
        Entity.AddEntities(array{ConditionEntity})
        Results.Check("player_count_condition (min 1) satisfied", if (Reached.IsSatisfied[]) then true else false)
        Results.Check("player_count_condition (min 100) not satisfied", if (TooMany.IsSatisfied[]) then false else true)
        ConditionEntity.RemoveFromParent()

    TestViewSet<private>(Results:test_log, Manager:player_manager_component):void =
        Views := player_view_set{}
        Results.Check("view set inactive at first", if (Views.IsActive[]) then false else true)
        Views.Activate(Entity, MakeView)
        Results.Check("view set active", if (Views.IsActive[]) then true else false)
        Results.CheckInt("one view per player", Views.GetViews().Length, Manager.GetPlayerCount())
        for (ViewEntity : Views.GetViews(), View := ViewEntity.GetComponent[test_player_view_component]):
            Results.Check("view is under its slot", if (View.FindViewSlot[] = View.Slot) then true else false)
        Views.Deactivate()
        Results.CheckInt("no views after Deactivate", Views.GetViews().Length, 0)

    TestSubscribePlayers<private>(Results:test_log, Manager:player_manager_component):void =
        set SubscribedCount = 0
        MaybeSubscription := Entity.SubscribePlayers(OnSubscribedAdded, OnSubscribedRemoved)
        if (Subscription := MaybeSubscription?):
            Results.CheckInt("SubscribePlayers calls OnAdded for current players", SubscribedCount, Manager.GetPlayerCount())
            Subscription.Cancel()
        else:
            Results.Fail("SubscribePlayers", "no playspace")

    MakeView<private>(ViewEntity:entity, Slot:player_slot_component):component =
        test_player_view_component{Entity := ViewEntity, Slot := Slot}

    OnSubscribedAdded<private>(Player:player):void =
        set SubscribedCount += 1

    OnSubscribedRemoved<private>(Player:player):void = {}

    TestPlayerTags<private>(Results:test_log, Manager:player_manager_component):void =
        if (Slot := Manager.GetSlots()[0]):
            Agent := Slot.Player
            First := player_tag_holder{}
            Second := player_tag_holder{}
            Results.Check("no state tag at first", if (Agent.HasPlayerTag[test_moving_tag]) then false else true)
            First.Add(Agent, test_moving_tag{})
            Results.Check("HasPlayerTag finds the added tag", if (Agent.HasPlayerTag[test_moving_tag]) then true else false)
            Results.Check("found by base type controlled_movement_tag", if (Agent.HasPlayerTag[controlled_movement_tag]) then true else false)
            Results.Check("found by base type player_state_tag", if (Agent.HasPlayerTag[player_state_tag]) then true else false)
            Results.Check("holder Has", if (First.Has[Agent]) then true else false)
            Second.Add(Agent, test_moving_tag{})
            First.Remove(Agent)
            Results.Check("another holder's tag stays after Remove", if (Agent.HasPlayerTag[test_moving_tag]) then true else false)
            Second.RemoveAll()
            Results.Check("no tag after both removed", if (Agent.HasPlayerTag[test_moving_tag]) then false else true)
            First.Set(Agent, true, test_moving_tag{})
            First.Set(Agent, false, test_moving_tag{})
            Results.Check("Set(false) clears", if (Agent.HasPlayerTag[test_moving_tag]) then false else true)

    # 組（Group）と、その子の条件 2 つ（1 人以上・だれもいない）を実行時に作る
    TestGroup<private>(Results:test_log, Manager:player_manager_component):void =
        if (Slot := Manager.GetSlots()[0]):
            Agent := Slot.Player
            GroupEntity := entity{}
            Group := player_group_component{Entity := GroupEntity}
            GroupEntity.AddComponents(array{Group})
            Entity.AddEntities(array{GroupEntity})
            # 子に置いた条件は Group を空のままにして、祖先の組（FindAncestorGroup）を数える
            ConditionEntity := entity{}
            Someone := player_group_count_condition_component{Entity := ConditionEntity, MinMemberCount := 1}
            Nobody := player_group_count_condition_component{Entity := ConditionEntity, MinMemberCount := 0, MaxMemberCount := 0}
            ConditionEntity.AddComponents(array{Someone, Nobody})
            GroupEntity.AddEntities(array{ConditionEntity})
            Recorder := test_logic_recorder{}
            Subscription := Someone.ChangedEvent.Subscribe(Recorder.Record)
            Results.Check("FindAncestorGroup from a child", if (ConditionEntity.FindAncestorGroup[] = Group) then true else false)
            Results.Check("group count condition finds the ancestor group", if (Someone.FindTargetGroup[] = Group) then true else false)
            Results.CheckInt("group empty at first", Group.GetMemberCount(), 0)
            Results.Check("group count (min 1) not satisfied when empty", if (Someone.IsSatisfied[]) then false else true)
            Results.Check("group count (max 0) satisfied when empty", if (Nobody.IsSatisfied[]) then true else false)
            Group.Join(Agent)
            Results.CheckInt("GetMemberCount after Join", Group.GetMemberCount(), 1)
            Results.Check("IsMember after Join", if (Group.IsMember[Agent]) then true else false)
            Results.Check("group count (min 1) satisfied after Join", if (Someone.IsSatisfied[]) then true else false)
            Results.Check("group count (max 0) not satisfied after Join", if (Nobody.IsSatisfied[]) then false else true)
            Results.CheckInt("group count ChangedEvent on Join", Recorder.GetCount(), 1)
            Results.CheckInt("GetMemberPlayerEntities has the body (player spawned)", Group.GetMemberPlayerEntities().Length, 1)
            Group.Leave(Agent)
            Results.CheckInt("GetMemberCount after Leave", Group.GetMemberCount(), 0)
            Results.Check("group count (min 1) not satisfied after Leave", if (Someone.IsSatisfied[]) then false else true)
            Results.CheckInt("group count ChangedEvent on Leave", Recorder.GetCount(), 2)
            Subscription.Cancel()
            GroupEntity.RemoveFromParent()
