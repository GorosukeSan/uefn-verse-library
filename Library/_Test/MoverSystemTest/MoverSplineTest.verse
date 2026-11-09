using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { MoverSystem }
using { MoverSystem.RouteKit }
using { SceneGraphSystem }
using { _Test }

# Role: verification of curved routes (RouteKit's mover_spline_route_component). Checked numerically: curve length (2 points are a straight line of exact length; a loop of 8 points on a circle is within 1% of the circumference), passing through the points, that points sampled at equal lengths from the length table are evenly spaced, the loop seam (the last -> first segment is a curve, its turn rate matches the middle, one lap returns to the same position), PingPong turnaround (index order; the points on the way back are the reverse of the way out), and that Loop on an open route returns in a straight line
#   Checked by moving (Keyframe): one lap of the loop takes length / speed, the speed stays constant midway and does not leave the circle, PingPong turnaround time and position midway on the way back, FaceTravelDirection faces the travel direction (without shifting the position), and Restart returns to the initial facing
# Test level: just attach this test component to an entity in the air with nothing within 10 meters (the moved entity is created by the test under its children; no visuals; no player needed). About 7 seconds
# Result: [TEST] MoverSpline in the output log
mover_spline_test_component<public> := class<final_super>(component):

    CircleRadiusCm<private>:float = 400.0
    CircleSpeedCmPerSecond<private>:float = 800.0
    TimeToleranceSeconds<private>:float = 0.3
    PositionToleranceCm<private>:float = 30.0

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "MoverSpline"}
        TestStraight(Results)
        TestCircleShape(Results)
        TestPingPongOrder(Results)
        TickEvents.PrePhysics.Await()
        TestCircleMover(Results)
        TestPingPongMover(Results)
        TestFaceDirection(Results)
        if (Results.Finish[]) {}

    # Two points make a straight line: not subdivided, exact length, no intermediate points
    TestStraight<private>(Results:test_log):void =
        Route := mover_spline_route_component{Entity := entity{}, IncludeStart := false, Mode := mover_path_mode.Once, Points := array{vector3{}, vector3{Forward := 1000.0}}}
        First := Route.NextTarget(vector3{}, vector3{})
        Second := Route.NextTarget(vector3{}, vector3{})
        Results.CheckInt("2 points: the curve is one straight line (2 curve points)", Route.GetCurvePoints().Length, 2)
        Results.CheckFloat("2 points: length is the distance", Route.GetLengthCm(), 1000.0, 0.01)
        if (Target := Second?):
            Results.CheckInt("2 points: no via points on the leg", Route.GetLeg(vector3{}, Target).Via.Length, 0)
        else:
            Results.Fail("2 points: second target", "NextTarget failed")
        Results.Check("2 points: first target is point 0", if (Target := First?, Target.Index = 0) then true else false)

    # 8 points on a circle as a closed loop
    TestCircleShape<private>(Results:test_log):void =
        Radius := 1000.0
        Circle := MakeCirclePoints(vector3{}, Radius, 8)
        Route := mover_spline_route_component{Entity := entity{}, IncludeStart := false, Closed := true, SubdivisionsPerSegment := 16, Points := Circle}
        Route.NextTarget(vector3{}, vector3{})
        Curve := Route.GetCurvePoints()
        LapCm := Route.GetLengthCm()
        Results.CheckInt("closed: 8 segments x 16 + 1 curve points", Curve.Length, 8 * 16 + 1)
        Results.CheckFloat("closed: length is within 1% of the circle", LapCm, 2.0 * PiFloat * Radius, 0.01 * 2.0 * PiFloat * Radius)
        var Passes:logic = true
        for (Index -> Point : Circle):
            if (OnCurve := Curve[Index * 16], Distance(OnCurve, Point) > 0.01):
                set Passes = false
        Results.Check("closed: the curve passes every point", Passes)
        Results.Check("closed: FindDistanceAtPoint[8] is one lap", if (Lap := Route.FindDistanceAtPoint[8], Abs(Lap - LapCm) < 0.01) then true else false)
        # Seam: the last point is the first point. The turn rate at the seam is about the same as midway (360 / 128 degrees for a circle)
        if (Head := Curve[0], Next := Curve[1], Tail := Curve[Curve.Length - 1], BeforeTail := Curve[Curve.Length - 2], Mid0 := Curve[63], Mid1 := Curve[64], Mid2 := Curve[65]):
            Results.CheckFloat("seam: the last curve point is the first", Distance(Head, Tail), 0.0, 0.01)
            SeamCos := DotProduct((Next - Head).MakeUnitVector(), (Tail - BeforeTail).MakeUnitVector())
            MidCos := DotProduct((Mid1 - Mid0).MakeUnitVector(), (Mid2 - Mid1).MakeUnitVector())
            Results.CheckFloat("seam: turns like the middle of the curve (cos of the turn)", SeamCos, MidCos, 0.001)
        else:
            Results.Fail("seam: curve points", "not enough curve points")
        Results.CheckFloat("seam: SampleAtDistance wraps after one lap", Distance(Route.SampleAtDistance(LapCm + 250.0), Route.SampleAtDistance(250.0)), 0.0, 0.5)
        # Length table: points sampled at equal lengths are evenly spaced (slightly shorter because they are chords)
        var Worst:float = 0.0
        var Previous:vector3 = Route.SampleAtDistance(0.0)
        for (Step := 1..60):
            Point := Route.SampleAtDistance(Step * 100.0)
            set Worst = Max(Worst, Abs(Distance(Previous, Point) - 100.0))
            set Previous = Point
        Results.CheckFloat("arc length table: equal distances give equal steps (worst error cm)", Worst, 0.0, 1.0)
        # Loop order: 7 is followed by 0, and the 7 -> 0 segment is a curve too (15 intermediate points)
        for (Index := 1..7):
            Route.NextTarget(vector3{}, vector3{})
        SeamTarget := Route.NextTarget(vector3{}, vector3{})
        if (Target := SeamTarget?):
            Results.CheckInt("closed: after point 7 comes point 0", Target.Index, 0)
            Via := Route.GetLeg(vector3{}, Target).Via
            Results.CheckInt("closed: the 7 -> 0 leg is curved (15 via points)", Via.Length, 15)
            if (LastVia := Via[Via.Length - 1], BeforeTail := Curve[Curve.Length - 2]):
                Results.CheckFloat("closed: the 7 -> 0 leg ends with the last curve point before point 0", Distance(LastVia, BeforeTail), 0.0, 0.01)
        else:
            Results.Fail("closed: target after point 7", "NextTarget failed")

    # Index order of PingPong on an open route, and the points midway on the way back. Loop returns in a straight line
    TestPingPongOrder<private>(Results:test_log):void =
        Points := MakeSPoints(vector3{})
        Route := mover_spline_route_component{Entity := entity{}, IncludeStart := false, Mode := mover_path_mode.PingPong, Points := Points}
        var Order:[]int = array{}
        var Forward23:[]vector3 = array{}
        var Back32:[]vector3 = array{}
        var Previous:int = -1
        for (Step := 1..8):
            MaybeTarget := Route.NextTarget(vector3{}, vector3{})
            if (Target := MaybeTarget?):
                Via := Route.GetLeg(vector3{}, Target).Via
                if (Previous = 2, Target.Index = 3):
                    set Forward23 = Via
                if (Previous = 3, Target.Index = 2):
                    set Back32 = Via
                set Order = Order + array{Target.Index}
                set Previous = Target.Index
        Results.Check("PingPong order 0,1,2,3,2,1,0,1", if (Order.Length = 8, Order[0] = 0, Order[1] = 1, Order[2] = 2, Order[3] = 3, Order[4] = 2, Order[5] = 1, Order[6] = 0, Order[7] = 1) then true else false)
        Results.CheckInt("PingPong: 7 via points per leg (8 subdivisions)", Forward23.Length, 7)
        var Mirrored:logic = if (Forward23.Length = Back32.Length, Forward23.Length > 0) then true else false
        for (Index -> Point : Forward23):
            if (Other := Back32[Back32.Length - 1 - Index], Distance(Point, Other) > 0.01):
                set Mirrored = false
        Results.Check("PingPong: the way back is the same curve in reverse", Mirrored)
        Looping := mover_spline_route_component{Entity := entity{}, IncludeStart := false, Mode := mover_path_mode.Loop, Points := Points}
        var LastLeg:int = -1
        for (Step := 1..5):
            MaybeTarget := Looping.NextTarget(vector3{}, vector3{})
            if (Target := MaybeTarget?, Target.Index = 0, Step > 1):
                set LastLeg = Looping.GetLeg(vector3{}, Target).Via.Length
        Results.CheckInt("open Loop: last -> first goes straight (no via points)", LastLeg, 0)

    # One lap of the loop with a Keyframe mover: time, speed midway, staying on the circle
    TestCircleMover<private>(Results:test_log)<suspends>:void =
        Center := Entity.GetGlobalTranslation() + vector3{Up := 300.0}
        Circle := MakeCirclePoints(Center, CircleRadiusCm, 6)
        Made := MakeMover(Circle, true, mover_path_mode.PingPong, CircleSpeedCmPerSecond, false)
        MoverEntity := Made(0)
        Mover := Made(1)
        Route := Made(2)
        # Point 0 (the placed position) is reached immediately, so wait from before Play
        FirstReached := spawn{AwaitWithin(Mover.TargetReachedEvent, 1.0)}
        Mover.Play()
        Started := FirstReached.Await()
        Results.Check("circle mover: point 0 (the start) is reached at once", if (Target := Started?, Target.Index = 0) then true else false)
        StartTime := GetSimulationElapsedTime()
        Expected := Route.GetLengthCm() / CircleSpeedCmPerSecond
        Lap := sync:
            AwaitPoint(Mover, 0, Expected + 2.0)
            SampleMotion(MoverEntity, Center, Expected - 0.2)
        if (Lap(0)?):
            Results.CheckFloat("circle mover: one lap takes length / speed seconds", GetSimulationElapsedTime() - StartTime, Expected, TimeToleranceSeconds)
        else:
            Results.Fail("circle mover: one lap", "point 0 was not reached again within {Expected + 2.0} s")
        Print("[TEST] MoverSpline: worst speed error {Lap(1)(0) * 100.0}% / worst distance from the circle {Lap(1)(1)} cm")
        Results.CheckFloat("circle mover: speed is constant (worst error ratio over 0.2 s)", Lap(1)(0), 0.0, 0.25)
        Results.CheckFloat("circle mover: stays on the curve (cm from the circle)", Lap(1)(1), 0.0, PositionToleranceCm)
        MoverEntity.RemoveFromParent()

    # Time to return 2 -> 1 with PingPong, and the position midway on the way back
    TestPingPongMover<private>(Results:test_log)<suspends>:void =
        Base := Entity.GetGlobalTranslation() + vector3{Up := 600.0, Forward := -300.0}
        Points := array{Base, Base + vector3{Forward := 300.0, Left := 300.0}, Base + vector3{Forward := 600.0}}
        Speed := 600.0
        Made := MakeMover(Points, false, mover_path_mode.PingPong, Speed, false)
        MoverEntity := Made(0)
        Mover := Made(1)
        Route := Made(2)
        Mover.Play()
        Reached2 := AwaitPoint(Mover, 2, 4.0)
        TurnTime := GetSimulationElapsedTime()
        if (Reached2?, D1 := Route.FindDistanceAtPoint[1], D2 := Route.FindDistanceAtPoint[2]):
            Segment := D2 - D1
            Results.CheckFloat("PingPong mover: turns at point 2", Distance(MoverEntity.GetGlobalTranslation(), Route.SampleAtDistance(D2)), 0.0, PositionToleranceCm)
            Sleep(Segment / Speed / 2.0)
            Half := GetSimulationElapsedTime() - TurnTime
            Results.CheckFloat("PingPong mover: half way back is on the same curve", Distance(MoverEntity.GetGlobalTranslation(), Route.SampleAtDistance(D2 - Half * Speed)), 0.0, PositionToleranceCm)
            Back := AwaitPoint(Mover, 1, 3.0)
            Results.Check("PingPong mover: comes back to point 1", Back)
            Results.CheckFloat("PingPong mover: 2 -> 1 takes the segment length / speed", GetSimulationElapsedTime() - TurnTime, Segment / Speed, TimeToleranceSeconds)
        else:
            Results.Fail("PingPong mover: reaches point 2", "point 2 was not reached within 4 s")
        MoverEntity.RemoveFromParent()

    # FaceTravelDirection: moving left makes forward face left (without shifting the position). Restart returns to the initial facing
    TestFaceDirection<private>(Results:test_log)<suspends>:void =
        Start := Entity.GetGlobalTranslation() + vector3{Up := 900.0}
        Goal := Start + vector3{Left := 400.0}
        Made := MakeMover(array{Start, Goal}, false, mover_path_mode.Once, 800.0, true)
        MoverEntity := Made(0)
        Mover := Made(1)
        Finished := spawn{AwaitWithin(Mover.FinishedEvent, 3.0)}
        Mover.Play()
        Done := Finished.Await()
        if (Done?):
            Axis := MoverEntity.GetGlobalTransform().Rotation.GetForwardAxis()
            Results.CheckFloat("FaceTravelDirection: forward axis points to the travel direction (+Left)", Axis.Left, 1.0, 0.05)
            Results.CheckFloat("FaceTravelDirection: still arrives at the goal", Distance(MoverEntity.GetGlobalTranslation(), Goal), 0.0, PositionToleranceCm)
            Mover.Restart()
            TickEvents.PrePhysics.Await()
            TickEvents.PrePhysics.Await()
            Back := MoverEntity.GetGlobalTransform().Rotation.GetForwardAxis()
            Results.Check("Restart: back to the start rotation (forward axis +Forward)", if (Back.Forward > 0.9) then true else false)
            Results.CheckFloat("Restart: back to the start position", Distance(MoverEntity.GetGlobalTranslation(), Start), 0.0, PositionToleranceCm)
        else:
            Results.Fail("FaceTravelDirection: finishes", "FinishedEvent did not come within 3 s")
        MoverEntity.RemoveFromParent()

    MakeMover<private>(Points:[]vector3, Closed:logic, Mode:mover_path_mode, Speed:float, Face:logic)<suspends>:tuple(entity, mover_component, mover_spline_route_component) =
        MoverEntity := entity{}
        Route := mover_spline_route_component{Entity := MoverEntity, IncludeStart := false, Closed := Closed, Mode := Mode, FaceTravelDirection := Face, Points := Points}
        Mover := mover_component{Entity := MoverEntity, Motion := mover_motion.Keyframe, SpeedCmPerSecond := Speed, StartOnBegin := false}
        MoverEntity.AddComponents(array{Route, Mover})
        Entity.AddEntities(array{MoverEntity})
        if (First := Points[0]):
            MoverEntity.SetGlobalTransform(MakeTranslationTransform(First))
        TickEvents.PrePhysics.Await()
        TickEvents.PrePhysics.Await()
        (MoverEntity, Mover, Route)

    # Waits until Mover reaches point Index (other points are skipped). True when reached within Seconds
    AwaitPoint<private>(Mover:mover_component, Index:int, Seconds:float)<suspends>:logic =
        race:
            block:
                loop:
                    Target := Mover.TargetReachedEvent.Await()
                    if (Target.Index = Index):
                        break
                true
            block:
                Sleep(Seconds)
                false

    # Reads the position every 0.2 seconds for Seconds and returns (max speed deviation ratio, max cm difference between the distance from Center and the radius)
    SampleMotion<private>(MoverEntity:entity, Center:vector3, Seconds:float)<suspends>:tuple(float, float) =
        var WorstSpeed:float = 0.0
        var WorstRadius:float = 0.0
        var Previous:vector3 = MoverEntity.GetGlobalTranslation()
        var PreviousTime:float = GetSimulationElapsedTime()
        var Left:float = Seconds
        loop:
            if (Left < 0.2):
                break
            Sleep(0.2)
            set Left -= 0.2
            Now := MoverEntity.GetGlobalTranslation()
            Time := GetSimulationElapsedTime()
            Speed := Distance(Previous, Now) / Max(Time - PreviousTime, 0.001)
            set WorstSpeed = Max(WorstSpeed, Abs(Speed - CircleSpeedCmPerSecond) / CircleSpeedCmPerSecond)
            set WorstRadius = Max(WorstRadius, Abs(DistanceForwardLeft(Now, Center) - CircleRadiusCm))
            set Previous = Now
            set PreviousTime = Time
        (WorstSpeed, WorstRadius)

    # Count evenly spaced points on a horizontal circle of radius RadiusCm around Center (counter-clockwise from the front)
    MakeCirclePoints<private>(Center:vector3, RadiusCm:float, Count:int)<transacts>:[]vector3 =
        for (Index := 0..Count - 1):
            Angle := (Index * 2.0) * PiFloat / (Count * 1.0)
            Center + vector3{Forward := RadiusCm * Cos(Angle), Left := RadiusCm * Sin(Angle)}

    # 4 points of an S shape
    MakeSPoints<private>(Base:vector3)<transacts>:[]vector3 =
        array{Base, Base + vector3{Forward := 400.0, Left := 400.0}, Base + vector3{Forward := 800.0, Left := -400.0}, Base + vector3{Forward := 1200.0}}
