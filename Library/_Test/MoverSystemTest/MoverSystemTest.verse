using { /Verse.org/SceneGraph }
using { /Verse.org/SceneGraph/KeyframedMovement }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { MoverSystem }
using { MoverSystem.RouteKit }
using { SceneGraphSystem }
using { _Test }

# 役割：祖先で受けた mover の scene_event を数える（AlsoSendUp の確認用。テストが実行時に親の entity に付ける）
test_mover_event_counter<public> := class<final_super>(component):

    var<private> ReachedCount:int = 0
    var<private> FinishedCount:int = 0

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (mover_target_reached_event[SceneEvent]):
            set ReachedCount += 1
        else if (mover_finished_event[SceneEvent]):
            set FinishedCount += 1
        false

    GetReachedCount<public>()<transacts>:int = ReachedCount

    GetFinishedCount<public>()<transacts>:int = FinishedCount

# 役割：MoverSystem の動作確認。道のりの回り方（Loop / PingPong / Once の番号の順）、目印の Order での並び、Keyframe の mover が地点に予定の時間で着くこと（速さと距離から。時間は GetSimulationElapsedTime の差）、Pause で止まり Play で続きから動くこと、SetSpeed が途中から効くこと、終わりの知らせ、Physics の mover が行き先に着くこと、道のりの Reset、Restart（最初の位置へ戻ってやり直す・今の位置から別の行き先へ）、AlsoSendUp で祖先に知らせが届くことを確かめる
# テストのレベル：このテストの component を、まわり 10 メートルに何も無い空中の entity に付けるだけ（動かす entity はテストが自分の子に作る。見た目は無い）
# 結果：出力ログの [TEST] MoverSystem
mover_system_test_component<public> := class<final_super>(component):

    SpeedCmPerSecond<private>:float = 300.0
    TimeToleranceSeconds<private>:float = 0.3
    PositionToleranceCm<private>:float = 20.0

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "MoverSystem"}
        TestRouteOrder(Results)
        TestWaypointOrder(Results)
        TickEvents.PrePhysics.Await()
        TestKeyframeMover(Results)
        TestPhysicsMover(Results)
        TestRestart(Results)
        if (Results.Finish[]) {}

    TestRouteOrder<private>(Results:test_log):void =
        Points := array{vector3{Forward := 100.0}, vector3{Forward := 200.0}, vector3{Forward := 300.0}}
        Results.Check("Loop order 0,1,2,0", CheckOrder(mover_path_mode.Loop, Points, array{0, 1, 2, 0}))
        Results.Check("PingPong order 0,1,2,1,0,1", CheckOrder(mover_path_mode.PingPong, Points, array{0, 1, 2, 1, 0, 1}))
        Results.Check("Once order 0,1,2 then ends", CheckOrder(mover_path_mode.Once, Points, array{0, 1, 2, -1}))
        IncludeStart := mover_path_route_component{Entity := entity{}, Mode := mover_path_mode.Once, IncludeStart := true, Points := Points}
        First := IncludeStart.NextTarget(vector3{}, vector3{})
        Results.Check("IncludeStart: first target is point 1 (start is point 0)", if (Target := First?, Target.Index = 1) then true else false)
        Results.CheckInt("IncludeStart: start is added to the resolved points", IncludeStart.GetResolvedPoints().Length, 4)
        Resettable := mover_path_route_component{Entity := entity{}, Mode := mover_path_mode.Once, IncludeStart := false, Points := Points}
        Resettable.NextTarget(vector3{}, vector3{})
        Resettable.NextTarget(vector3{}, vector3{})
        Resettable.NextTarget(vector3{}, vector3{})
        Ended := Resettable.NextTarget(vector3{}, vector3{})
        Resettable.Reset()
        Again := Resettable.NextTarget(vector3{}, vector3{})
        Results.Check("Reset: Once route ends, then starts again from point 0", if (not Ended?, Target := Again?, Target.Index = 0) then true else false)

    CheckOrder<private>(Mode:mover_path_mode, Points:[]vector3, Expected:[]int):logic =
        Route := mover_path_route_component{Entity := entity{}, Mode := Mode, IncludeStart := false, Points := Points}
        var Ok:logic = true
        for (Want : Expected):
            Next := Route.NextTarget(vector3{}, vector3{})
            Got := if (Target := Next?) then Target.Index else -1
            if (Got <> Want):
                set Ok = false
        Ok

    TestWaypointOrder<private>(Results:test_log):void =
        Root := entity{}
        Route := mover_path_route_component{Entity := Root}
        Root.AddComponents(array{Route})
        for (Order : array{3, 1, 2}):
            Child := entity{}
            Child.AddComponents(array{mover_waypoint_component{Entity := Child, Order := Order}})
            Root.AddEntities(array{Child})
        Orders := for (Waypoint : Route.GetWaypoints()):
            Waypoint.Order
        Results.Check("waypoints are sorted by Order, not child order", if (Orders.Length = 3, Orders[0] = 1, Orders[1] = 2, Orders[2] = 3) then true else false)

    TestKeyframeMover<private>(Results:test_log)<suspends>:void =
        Start := Entity.GetGlobalTranslation() + vector3{Up := 300.0}
        P1 := Start + vector3{Forward := 300.0}
        P2 := P1 + vector3{Left := 300.0}
        MoverEntity := entity{}
        Route := mover_path_route_component{Entity := MoverEntity, Mode := mover_path_mode.Once, IncludeStart := true, Points := array{P1, P2}}
        Mover := mover_component{Entity := MoverEntity, Motion := mover_motion.Keyframe, SpeedCmPerSecond := SpeedCmPerSecond, StartOnBegin := false}
        MoverEntity.AddComponents(array{Route, Mover})
        Entity.AddEntities(array{MoverEntity})
        MoverEntity.SetGlobalTransform(MakeTranslationTransform(Start))
        TickEvents.PrePhysics.Await()
        TickEvents.PrePhysics.Await()
        Results.Check("not moving before Play (StartOnBegin = false)", if (Mover.IsMoving[]) then false else true)
        Finished := spawn{AwaitWithin(Mover.FinishedEvent, 10.0)}
        StartTime := GetSimulationElapsedTime()
        Mover.Play()
        Awaited2 := AwaitWithin(Mover.TargetReachedEvent, 3.0)
        if (First := Awaited2?):
            Results.CheckInt("first reached target is point 1", First.Index, 1)
            Results.CheckFloat("reached point 1 in distance / speed seconds", GetSimulationElapsedTime() - StartTime, 300.0 / SpeedCmPerSecond, TimeToleranceSeconds)
            Results.CheckFloat("position at point 1", Distance(MoverEntity.GetGlobalTranslation(), P1), 0.0, PositionToleranceCm)
            Results.Check("keyframed_movement_component was added", if (MoverEntity.GetComponent[keyframed_movement_component]) then true else false)
        else:
            Results.Fail("first reached target is point 1", "TargetReachedEvent did not come within 3 s")
        WaitSeconds(0.3)
        Mover.Pause()
        Results.Check("Pause stops IsMoving", if (Mover.IsMoving[]) then false else true)
        Paused := MoverEntity.GetGlobalTranslation()
        WaitSeconds(0.5)
        Results.CheckFloat("does not move while paused", Distance(MoverEntity.GetGlobalTranslation(), Paused), 0.0, 2.0)
        Left := Distance(Paused, P2)
        Mover.SetSpeed(SpeedCmPerSecond * 2.0)
        Results.CheckFloat("GetSpeedCmPerSecond after SetSpeed", Mover.GetSpeedCmPerSecond(), SpeedCmPerSecond * 2.0, 0.01)
        ResumeTime := GetSimulationElapsedTime()
        Mover.Play()
        Awaited3 := AwaitWithin(Mover.TargetReachedEvent, 3.0)
        if (Second := Awaited3?):
            Results.CheckInt("second reached target is point 2", Second.Index, 2)
            Results.CheckFloat("rest of the way at the new speed", GetSimulationElapsedTime() - ResumeTime, Left / (SpeedCmPerSecond * 2.0), TimeToleranceSeconds)
            Results.CheckFloat("position at point 2", Distance(MoverEntity.GetGlobalTranslation(), P2), 0.0, PositionToleranceCm)
        else:
            Results.Fail("second reached target is point 2", "TargetReachedEvent did not come within 3 s")
        Awaited4 := Finished.Await()
        Results.Check("FinishedEvent after the last point (Once)", if (Awaited4?) then true else false)
        Results.Check("IsFinished after the end", if (Mover.IsFinished[]) then true else false)
        MoverEntity.RemoveFromParent()

    TestPhysicsMover<private>(Results:test_log)<suspends>:void =
        Start := Entity.GetGlobalTranslation() + vector3{Up := 600.0}
        Goal := Start + vector3{Forward := 200.0}
        MoverEntity := entity{}
        Route := mover_path_route_component{Entity := MoverEntity, Mode := mover_path_mode.Once, IncludeStart := false, Points := array{Goal}}
        Mover := mover_component{Entity := MoverEntity, Motion := mover_motion.Physics, SpeedCmPerSecond := 200.0}
        MoverEntity.AddComponents(array{Route, Mover})
        Entity.AddEntities(array{MoverEntity})
        MoverEntity.SetGlobalTransform(MakeTranslationTransform(Start))
        StartTime := GetSimulationElapsedTime()
        Awaited5 := AwaitWithin(Mover.FinishedEvent, 4.0)
        if (Awaited5?):
            Results.CheckFloat("Physics mover reaches the goal in about 1 s (+1 frame start)", GetSimulationElapsedTime() - StartTime, 1.0, TimeToleranceSeconds)
            Results.CheckFloat("Physics mover position at the goal", Distance(MoverEntity.GetGlobalTranslation(), Goal), 0.0, PositionToleranceCm)
        else:
            Results.Fail("Physics mover finishes", "FinishedEvent did not come within 4 s")
        Results.Check("Physics mover does not add keyframed_movement_component", if (MoverEntity.GetComponent[keyframed_movement_component]) then false else true)
        MoverEntity.RemoveFromParent()

    TestRestart<private>(Results:test_log)<suspends>:void =
        Start := Entity.GetGlobalTranslation() + vector3{Up := 900.0}
        P1 := Start + vector3{Forward := 150.0}
        P2 := P1 + vector3{Left := 150.0}
        Parent := entity{}
        Counter := test_mover_event_counter{Entity := Parent}
        Parent.AddComponents(array{Counter})
        Entity.AddEntities(array{Parent})
        MoverEntity := entity{}
        Route := mover_path_route_component{Entity := MoverEntity, Mode := mover_path_mode.Once, IncludeStart := true, Points := array{P1}}
        Mover := mover_component{Entity := MoverEntity, Motion := mover_motion.Keyframe, SpeedCmPerSecond := SpeedCmPerSecond, AlsoSendUp := true}
        MoverEntity.AddComponents(array{Route, Mover})
        Parent.AddEntities(array{MoverEntity})
        MoverEntity.SetGlobalTransform(MakeTranslationTransform(Start))
        Awaited6 := AwaitWithin(Mover.FinishedEvent, 3.0)
        Results.Check("restart: first run finishes (Once)", if (Awaited6?) then true else false)
        Results.CheckInt("send up: parent got mover_target_reached_event", Counter.GetReachedCount(), 1)
        Results.CheckInt("send up: parent got mover_finished_event", Counter.GetFinishedCount(), 1)
        Results.Check("restart: FindStartPosition is the start", if (Found := Mover.FindStartPosition[], Distance(Found, Start) < PositionToleranceCm) then true else false)
        # 終わったあとの Restart は、最初の位置へ戻ってもう一度動く
        RestartTime := GetSimulationElapsedTime()
        Mover.Restart()
        TickEvents.PrePhysics.Await()
        Results.Check("restart: not finished after Restart", if (Mover.IsFinished[]) then false else true)
        Results.CheckFloat("restart: back near the start position", Distance(MoverEntity.GetGlobalTranslation(), Start), 0.0, PositionToleranceCm + 20.0)
        Awaited7 := AwaitWithin(Mover.FinishedEvent, 3.0)
        if (Awaited7?):
            Results.CheckFloat("restart: second run takes distance / speed seconds", GetSimulationElapsedTime() - RestartTime, 150.0 / SpeedCmPerSecond, TimeToleranceSeconds)
            Results.CheckFloat("restart: position at point 1 again", Distance(MoverEntity.GetGlobalTranslation(), P1), 0.0, PositionToleranceCm)
        else:
            Results.Fail("restart: FinishedEvent after Restart", "did not come within 3 s")
        # 今の位置から、入れ替えた地点へ 1 回だけ動く
        Route.SetPoints(array{P2})
        MoveTime := GetSimulationElapsedTime()
        Mover.Restart(?ReturnToStart := false)
        Awaited8 := AwaitWithin(Mover.FinishedEvent, 3.0)
        if (Awaited8?):
            Results.CheckFloat("restart from here: takes distance / speed seconds", GetSimulationElapsedTime() - MoveTime, 150.0 / SpeedCmPerSecond, TimeToleranceSeconds)
            Results.CheckFloat("restart from here: position at the new point", Distance(MoverEntity.GetGlobalTranslation(), P2), 0.0, PositionToleranceCm)
        else:
            Results.Fail("restart from here: FinishedEvent", "did not come within 3 s")
        Parent.RemoveFromParent()

    # Seconds 秒待つ（DeltaTime の足し合わせ）
    WaitSeconds<private>(Seconds:float)<suspends>:void =
        var Left:float = Seconds
        loop:
            if (Left <= 0.0):
                break
            set Left -= TickEvents.PrePhysics.Await()
