using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { SceneGraphSystem }
using { MoverSystem }
using { MoverSystem.TooltipKit }

# Direction: SendDown from the route entity (the mover entity) (itself and descendants)
# Sender: mover_spline_route_component (Route). When the curve is built (when the first target is chosen after moving starts / at the first target after SetPoints or Restart)
# Receivers: looks that show the route (point markers, curve lines). Not consumed
mover_spline_changed_event<public> := class(scene_event):
    # The mover_spline_route_component that sent it
    Route<public>:mover_spline_route_component
    # The points the curve passes through (world positions, centimeters), in number order
    Points<public>:[]vector3
    # The subdivided points of the curve (world positions, centimeters). Point i is CurvePoints[i x subdivisions per segment]. With Closed, the last point equals the first
    CurvePoints<public>:[]vector3

# Role: a route that joins the points with a smooth curve (centripetal Catmull-Rom: always passes through the points, rarely forms cusps or small loops) and makes mover_component travel along it at a constant speed. The targets (mover_target) are the points; the curve between points is passed as the intermediate points of GetLeg (mover_leg.Via)
#   Each segment between points is divided into SubdivisionsPerSegment straight lines; the subdivided points and a length table (curve length from the start) are built once, when the first target is chosen after moving starts. The mover travels the subdivided lines at the same speed, so the speed along the curve is constant (sharp turns at points do not change it)
#   With Closed, the last point is also joined to the first with a curve and it keeps going around (Mode is ignored). When not Closed, Mode applies: PingPong goes back and forth along the same curve, Once stops at the last point, Loop returns straight from the last point to the first
#   With 2 points it is a straight line (not subdivided). The points are Points (world positions set from code) when present, otherwise the positions of the mover_waypoint_component direct children (ascending Order). With IncludeStart, the position where moving started becomes the first point (number 0)
#   With FaceTravelDirection, the facing (yaw) of the mover entity is aligned to the direction of travel (the entity's front = Forward axis)
# Placement: attach in the editor to the entity to move (the same entity as mover_component). Do not combine with another route such as mover_path_route_component
# Same entity: mover_component (speed, waits, pause, restart and notifications are handled there)
# Children: when Points is empty, entities (without a look) carrying mover_waypoint_component, as direct children. The order is decided by each marker's Order
# Notifies: mover_spline_changed_event when the curve is built (SendDown from its own entity). Arrival / finish are mover_component's notifications (per point)
# From outside: SetPoints, GetResolvedPoints / GetCurvePoints / GetLengthCm / FindDistanceAtPoint / SampleAtDistance, GetWaypoints
# Requirements / notes: point positions are read once, when the first target is chosen after moving starts (they do not change even when the child markers move with the mover). Even with WaitSeconds = 0, the legs are rebuilt per point, so it may stop for about one frame (⚠ Unverified:)
mover_spline_route_component<public> := class<final_super>(mover_route_component):

    # When on, the last point is also joined to the first with a curve and it keeps going around the loop (Mode is ignored). Use 3 or more points (2 give a straight back-and-forth). Default off
    @editable:
        ToolTip := MoverSplineClosedToolTip
        Categories := array{MoverCategory, MoverSplineCategory}
    Closed<public>:logic = false

    # Traversal when not Closed. PingPong goes back and forth along the same curve, Once stops at the last point, Loop returns straight from the last point to the first. Default PingPong
    @editable:
        ToolTip := MoverSplineModeToolTip
        Categories := array{MoverCategory, MoverSplineCategory}
    Mode<public>:mover_path_mode = mover_path_mode.PingPong

    # When on, the start position becomes the first point (number 0). When off, only the marker points are visited (when the placed position differs from the first marker, it first heads straight there). Default on
    @editable:
        ToolTip := MoverPathIncludeStartToolTip
        Categories := array{MoverCategory, MoverSplineCategory}
    IncludeStart<public>:logic = true

    # How many straight lines each curve between points is divided into (1-64). More is closer to the curve. 1 with 2 points. Default 8
    @editable_number(int):
        ToolTip := MoverSplineSubdivisionsToolTip
        Categories := array{MoverCategory, MoverSplineCategory}
        MinValue := option{1}
        MaxValue := option{64}
    SubdivisionsPerSegment<public>:int = 8

    # When on, the entity's facing (yaw; front = Forward axis) is aligned to the direction of travel. Tilt (pitch / roll) is unchanged. Default off
    @editable:
        ToolTip := MoverSplineFaceToolTip
        Categories := array{MoverCategory, MoverSplineCategory}
    FaceTravelDirection<public>:logic = false

    # Points set from code (world positions, centimeters). When empty, the mover_waypoint_component children are used
    Points<public>:[]vector3 = array{}

    var Override<private>:?[]vector3 = false
    var Resolved<private>:[]vector3 = array{}
    var Curve<private>:[]vector3 = array{}
    var CumulativeCm<private>:[]float = array{}
    var CurveClosed<private>:logic = false
    var Steps<private>:int = 1
    var IsResolved<private>:logic = false
    var Current<private>:int = -1
    var Forward<private>:logic = true
    var LegIndex<private>:int = -1
    var LegVia<private>:[]vector3 = array{}

    # Replace the points (world positions, centimeters). The current target is kept; from the next target on, traversal restarts from the first of the new points (the start position with IncludeStart) (the curve is rebuilt then)
    SetPoints<public>(NewPoints:[]vector3):void =
        set Override = option{NewPoints}
        set IsResolved = false

    # Start over from the first point (called by mover_component's Restart). The points and the curve are rebuilt when the next target is chosen (points set with SetPoints stay in use)
    Reset<override>():void =
        set IsResolved = false

    # The points the curve passes through (world positions, centimeters, in number order). Empty before moving starts
    GetResolvedPoints<public>()<reads>:[]vector3 =
        Resolved

    # The subdivided points of the curve (world positions, centimeters). Point i is GetCurvePoints()[i x subdivisions per segment]. With Closed, the last point equals the first. Empty before moving starts
    GetCurvePoints<public>()<reads>:[]vector3 =
        Curve

    # Length of the curve (centimeters; one lap with Closed). The sum of the subdivided lines, i.e. the distance the mover travels. 0 before moving starts
    GetLengthCm<public>()<reads>:float =
        if (TotalCm := CumulativeCm[CumulativeCm.Length - 1]) then TotalCm else 0.0

    # Curve length (centimeters) from the first point to point Index. With Closed, Index = number of points gives one lap. Fails when out of range or before moving starts
    FindDistanceAtPoint<public>(Index:int)<decides><reads>:float =
        CumulativeCm[Index * Steps]

    # The position (world) DistanceCm (centimeters) along the curve from the first point. With Closed, wraps around the lap length; otherwise clamped at both ends. vector3{} before moving starts
    SampleAtDistance<public>(DistanceCm:float)<transacts>:vector3 =
        Total := GetLengthCm()
        Along := if (CurveClosed?, Total > 0.0, Turns := Floor[DistanceCm / Total]) then DistanceCm - Turns * Total else Max(0.0, Min(DistanceCm, Total))
        if (Index := FindSampleAfter[Along], Index > 0, A := Curve[Index - 1], B := Curve[Index], CA := CumulativeCm[Index - 1], CB := CumulativeCm[Index]):
            Lerp(A, B, (Along - CA) / Max(CB - CA, 0.0001))
        else if (First := Curve[0]):
            First
        else:
            vector3{}

    # The mover_waypoint_component direct children in ascending Order (the order among equal Orders is unspecified)
    GetWaypoints<public>()<transacts>:[]mover_waypoint_component =
        var Sorted:[]mover_waypoint_component = array{}
        for (Waypoint : Entity.GetChildComponents(mover_waypoint_component)):
            set Sorted = InsertByOrder(Sorted, Waypoint)
        Sorted

    NextTarget<override>(Home:vector3, Position:vector3):?mover_target =
        if (not IsResolved?):
            Resolve(Home)
        Previous := Current
        MaybeNext := NextIndex()
        if (Next := MaybeNext?, Point := Resolved[Next]):
            set Current = Next
            set LegIndex = Next
            set LegVia = MakeVia(Previous, Next)
            option{mover_target{Position := Point, Index := Next}}
        else:
            set LegIndex = -1
            set LegVia = array{}
            false

    # The intermediate curve points toward the point returned by NextTarget. Empty (straight) when there is no previous point (the first target) or when Loop returns straight
    GetLeg<override>(From:vector3, Target:mover_target):mover_leg =
        if (Target.Index = LegIndex):
            mover_leg{Via := LegVia, FaceTravelDirection := FaceTravelDirection}
        else:
            mover_leg{FaceTravelDirection := FaceTravelDirection}

    Resolve<private>(Home:vector3):void =
        Base := if (Code := Override?) then Code else if (Points.Length > 0) then Points else ReadWaypoints()
        set Resolved = if (IncludeStart?) then array{Home} + Base else Base
        set Current = if (IncludeStart?) then 0 else -1
        set Forward = true
        set LegIndex = -1
        set LegVia = array{}
        set Steps = if (Resolved.Length <= 2) then 1 else Clamp(SubdivisionsPerSegment, 1, 64)
        set CurveClosed = if (Closed?, Resolved.Length >= 2) then true else false
        set Curve = MakeSplineCurve(Resolved, CurveClosed, Steps)
        set CumulativeCm = MakeCumulativeLengths(Curve)
        set IsResolved = true
        Entity.SendDown(mover_spline_changed_event{Route := Self, Points := Resolved, CurvePoints := Curve})

    ReadWaypoints<private>()<transacts>:[]vector3 =
        for (Waypoint : GetWaypoints()):
            Waypoint.Entity.GetGlobalTranslation()

    # The intermediate curve points from point From to point To (both ends excluded)
    MakeVia<private>(From:int, To:int)<transacts>:[]vector3 =
        if (From < 0 or From = To):
            array{}
        else if (To = From + 1):
            CurveSlice(From, false)
        else if (To = From - 1):
            CurveSlice(To, true)
        else if (CurveClosed?, From = Resolved.Length - 1, To = 0):
            CurveSlice(From, false)
        else:
            array{}

    # The intermediate points of segment Segment (point Segment -> Segment + 1). Reversed with Reverse
    CurveSlice<private>(Segment:int, Reverse:logic)<transacts>:[]vector3 =
        First := Segment * Steps
        Inner := for (Index -> Point : Curve, Index > First, Index < First + Steps):
            Point
        if (Reverse?):
            for (Index -> Point : Inner, Mirrored := Inner[Inner.Length - 1 - Index]):
                Mirrored
        else:
            Inner

    # The number of the first point in the length table at or beyond Along (centimeters)
    FindSampleAfter<private>(Along:float)<decides><reads>:int =
        first (Index -> Cumulative : CumulativeCm, Cumulative >= Along):
            Index

    NextIndex<private>():?int =
        Count := Resolved.Length
        if (Count <= 0):
            false
        else if (Count = 1):
            if (Current < 0) then option{0} else false
        else if (CurveClosed? or Mode = mover_path_mode.Loop):
            option{Mod[Current + 1, Count] or 0}
        else if (Mode = mover_path_mode.Once):
            if (Current + 1 < Count) then option{Current + 1} else false
        else if (Forward?):
            if (Current + 1 < Count):
                option{Current + 1}
            else:
                set Forward = false
                option{Current - 1}
        else:
            if (Current - 1 >= 0):
                option{Current - 1}
            else:
                set Forward = true
                option{Current + 1}

# The centripetal Catmull-Rom curve through Points, subdivided into Steps straight lines per segment. With Closed, a segment from the last point back to the first is added too (the last point equals the first). The open ends are built by adding points mirrored across the end points on the outside
MakeSplineCurve<internal>(Points:[]vector3, Closed:logic, Steps:int)<transacts>:[]vector3 =
    Count := Points.Length
    if (Count <= 1):
        Points
    else:
        Segments := if (Closed?) then Count else Count - 1
        Divisions := Max(Steps, 1)
        var Out:[]vector3 = array{}
        for (Segment := 0..Segments - 1):
            P0 := SplineControlPoint(Points, Segment - 1, Closed)
            P1 := SplineControlPoint(Points, Segment, Closed)
            P2 := SplineControlPoint(Points, Segment + 1, Closed)
            P3 := SplineControlPoint(Points, Segment + 2, Closed)
            for (Step := 0..Divisions - 1):
                set Out = Out + array{CatmullRomPoint(P0, P1, P2, P3, (Step * 1.0) / (Divisions * 1.0))}
        Out + array{SplineControlPoint(Points, Segments, Closed)}

# Point number Index used to build the curve. With Closed, the number wraps; otherwise, beyond either end, the point mirrored across the end (2 x end - neighbor)
SplineControlPoint<internal>(Points:[]vector3, Index:int, Closed:logic)<transacts>:vector3 =
    Count := Points.Length
    if (Closed?, Wrapped := Mod[Index + Count, Count], Point := Points[Wrapped]):
        Point
    else if (Point := Points[Index]):
        Point
    else if (Index < 0, A := Points[0], B := Points[1]):
        A * 2.0 - B
    else if (A := Points[Count - 1], B := Points[Count - 2]):
        A * 2.0 - B
    else:
        vector3{}

# The position at Ratio (0-1, the curve parameter) on the segment from P1 to P2. Centripetal (the square root of the point spacing is the parameter step; Barry-Goldman form). Ratio 0 gives P1, 1 gives P2
CatmullRomPoint<internal>(P0:vector3, P1:vector3, P2:vector3, P3:vector3, Ratio:float)<reads>:vector3 =
    T1 := Max(Sqrt(Distance(P0, P1)), 0.0001)
    T2 := T1 + Max(Sqrt(Distance(P1, P2)), 0.0001)
    T3 := T2 + Max(Sqrt(Distance(P2, P3)), 0.0001)
    T := T1 + (T2 - T1) * Ratio
    A1 := P0 * ((T1 - T) / T1) + P1 * (T / T1)
    A2 := P1 * ((T2 - T) / (T2 - T1)) + P2 * ((T - T1) / (T2 - T1))
    A3 := P2 * ((T3 - T) / (T3 - T2)) + P3 * ((T - T2) / (T3 - T2))
    B1 := A1 * ((T2 - T) / T2) + A2 * (T / T2)
    B2 := A2 * ((T3 - T) / (T3 - T1)) + A3 * ((T - T1) / (T3 - T1))
    B1 * ((T2 - T) / (T2 - T1)) + B2 * ((T - T1) / (T2 - T1))

# Length table: polyline length (centimeters) from the first point to each point. The first is 0
MakeCumulativeLengths<internal>(Curve:[]vector3)<transacts>:[]float =
    var Total:float = 0.0
    var Previous:?vector3 = false
    for (Point : Curve):
        if (Before := Previous?):
            set Total += Distance(Before, Point)
        set Previous = option{Point}
        Total
