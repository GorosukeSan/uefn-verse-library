using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { ActivationSystem }
using { MovementSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { VolumeSystem }
using { VolumeSystem.ActivationKit }
using { VolumeSystem.ConditionKit }
using { _Test }

# 役割：テスト用。起動・停止の合図を数える
test_activation_probe_component<public> := class<final_super>(component):
    var<private> Activated:int = 0
    var<private> Deactivated:int = 0

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            set Activated += 1
        else if (deactivated_event[SceneEvent]):
            set Deactivated += 1
        false

    GetActivatedCount<public>()<transacts>:int = Activated
    GetDeactivatedCount<public>()<transacts>:int = Deactivated

# 役割：VolumeSystem の動作確認。プレイヤーの位置にボリュームを作って「入った」（PlayerEnteredEvent・IsInside・in_volume_tag）、
#   player_in_volume_condition_component が満たされること、volume_activation_component が子へ起動の合図を送ることを見る。
#   そのあとボリュームを遠くへ動かして「出た」（PlayerExitedEvent・タグが外れる・停止の合図）を見る
# テストのレベル：player_manager_component を付けた entity を 1 つと、この component を付けた entity を 1 つ。プレイヤー 1 人で始める（地面に立っていること）
# 結果：出力ログの [TEST] VolumeSystem
volume_system_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "VolumeSystem"}
        TickEvents.PrePhysics.Await()
        if:
            Manager := Entity.FindScopedComponent[player_manager_component]
            Slot := Manager.GetSlots()[0]
            Character := Slot.Player.GetFortCharacter[]
            Position := Character.FindGlobalTranslation[]
        then:
            Run(Results, Slot.Player, Position)
        else:
            Results.Fail("setup", "no player_manager_component or no player character")
        if (Results.Finish[]) {}

    Run<private>(Results:test_log, Agent:agent, Position:vector3)<suspends>:void =
        # 構成：根（条件 + 起動の Kit）─ ボリューム、根 ─ 合図を受ける子
        Root := entity{}
        Condition := player_in_volume_condition_component{Entity := Root, MinPlayers := 1}
        Activation := volume_activation_component{Entity := Root}
        Root.AddComponents(array{Condition, Activation})
        VolumeEntity := entity{}
        # 底面を足元より下にして、キャラクターの位置が入る大きさにする
        VolumeEntity.SetGlobalTransform(MakeTranslationTransform(Position - vector3{Up := 200.0}))
        Volume := player_volume_component{Entity := VolumeEntity, WidthCm := 600.0, DepthCm := 600.0, HeightCm := 600.0, PollIntervalSeconds := 0.1}
        VolumeEntity.AddComponents(array{Volume})
        ProbeEntity := entity{}
        Probe := test_activation_probe_component{Entity := ProbeEntity}
        ProbeEntity.AddComponents(array{Probe})
        Root.AddEntities(array{VolumeEntity, ProbeEntity})
        Entity.AddEntities(array{Root})

        Results.Check("Contains: own position", if (Volume.Contains[Position]) then true else false)
        Results.Check("Contains: far away is outside", if (Volume.Contains[Position + vector3{Forward := 5000.0}]) then false else true)

        MaybeEntered := AwaitWithin(Volume.PlayerEnteredEvent, 2.0)
        if (Entered := MaybeEntered?):
            Results.Check("PlayerEnteredEvent is the player", if (Entered = Agent) then true else false)
        else if (Volume.IsInside[Agent]):
            Results.Pass("entered before the first await (already inside)")
        else:
            Results.Fail("PlayerEnteredEvent", "not entered within 2 s")
        Results.Check("IsInside", if (Volume.IsInside[Agent]) then true else false)
        Results.CheckInt("GetInsideCount", Volume.GetInsideCount(), 1)
        Results.Check("in_volume_tag on the player", if (Agent.HasPlayerTag[in_volume_tag]) then true else false)
        Results.Check("player_in_volume_condition satisfied", if (Condition.IsSatisfied[]) then true else false)
        Results.Check("volume_activation occupied", if (Activation.IsOccupied[]) then true else false)
        Results.CheckInt("child got activated_event", Probe.GetActivatedCount(), 1)

        # 遠くへ動かして出す
        VolumeEntity.SetGlobalTransform(MakeTranslationTransform(Position + vector3{Forward := 10000.0}))
        Arrived11 := AwaitWithin(Volume.PlayerExitedEvent, 2.0)
        if (Arrived11?):
            Results.Pass("PlayerExitedEvent after moving the volume away")
        else:
            Results.Fail("PlayerExitedEvent", "not exited within 2 s")
        Results.Check("not inside", if (Volume.IsInside[Agent]) then false else true)
        Results.Check("in_volume_tag removed", if (Agent.HasPlayerTag[in_volume_tag]) then false else true)
        Results.Check("condition not satisfied", if (Condition.IsSatisfied[]) then false else true)
        Results.CheckInt("child got deactivated_event", Probe.GetDeactivatedCount(), 1)
        Results.Check("volume still active after the last one left (not stopped by its own deactivated_event)", if (Volume.IsActive[]) then true else false)

        # Deactivate で止まる
        Volume.Deactivate()
        Results.Check("Deactivate -> not active", if (Volume.IsActive[]) then false else true)
        Root.RemoveFromParent()
