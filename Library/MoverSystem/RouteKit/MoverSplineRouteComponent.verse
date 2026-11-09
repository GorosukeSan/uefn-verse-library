using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { SceneGraphSystem }
using { MoverSystem }
using { MoverSystem.TooltipKit }

# 方向：道のりの entity（mover の entity）から SendDown（自分と子孫）
# 送り手：mover_spline_route_component（Route）。曲線が決まったとき（動き出して最初の行き先を決めるとき・SetPoints や Restart のあとの最初の行き先のとき）
# 受け手：道のりを見せる見た目（地点の目印・曲線の線）。消費しない
mover_spline_changed_event<public> := class(scene_event):
    # 送った mover_spline_route_component
    Route<public>:mover_spline_route_component
    # 曲線が通る地点（世界の位置、センチメートル）。番号の順
    Points<public>:[]vector3
    # 曲線を細かく分けた点（世界の位置、センチメートル）。地点 i は CurvePoints[i × 区間の分割数]。Closed なら最後の点は最初の点と同じ
    CurvePoints<public>:[]vector3

# 役割：地点を滑らかな曲線（centripetal Catmull-Rom。地点を必ず通り、とがったり輪になったりしにくい）でつなぎ、mover_component にその曲線の上を一定の速さで進ませる道のり。行き先（mover_target）は地点で、地点のあいだの曲線は GetLeg の途中の点（mover_leg.Via）で渡す
#   曲線は地点の区間ごとに SubdivisionsPerSegment 個の直線に分け、分けた点と長さの表（始めからの曲線の長さ）を、動き出して最初の行き先を決めるときに 1 回作る。mover は分けた直線を同じ速さで進むので、曲線の上の速さは一定（地点で曲がりが急でも速さは変わらない）
#   Closed なら最後の地点から最初の地点へも曲線でつないで回り続ける（Mode は見ない）。Closed でなければ Mode で、PingPong は同じ曲線を行き来し、Once は最後の地点で止まり、Loop は最後の地点から最初の地点へまっすぐ戻る
#   地点が 2 つなら直線（分けない）。地点は、Points（コードで入れた世界の位置）があればそれ、無ければ直下の子の mover_waypoint_component の位置（Order の小さい順）。IncludeStart なら、動き出したときの位置を最初の地点（番号 0）にする
#   FaceTravelDirection なら、進む向きに mover の entity の向き（ヨー）を合わせる（entity の前 = Forward 軸）
# 置き方：エディターで、動かしたい entity（mover_component と同じ entity）に付ける。mover_path_route_component など、ほかの道のりと一緒には付けない
# 同じ entity：mover_component（速さ・待ち・一時停止・やり直し・知らせはそちら）
# 子：Points が空なら、mover_waypoint_component を付けた entity（見た目の無いもの）を直下に。順番は各目印の Order で決める
# 知らせ：曲線が決まったとき mover_spline_changed_event（自分の entity から SendDown）。着いた・終わったは mover_component の知らせ（地点ごと）
# 外から：SetPoints、GetResolvedPoints / GetCurvePoints / GetLengthCm / FindDistanceAtPoint / SampleAtDistance、GetWaypoints
# 前提・注意：地点の位置は動き出して最初の行き先を決めるときに 1 回だけ読む（子の目印が mover と一緒に動いても変わらない）。WaitSeconds が 0 でも、地点ごとに区間を組み直すので 1 フレームほど止まることがある（⚠ 未検証：）
mover_spline_route_component<public> := class<final_super>(mover_route_component):

    # オンなら最後の地点から最初の地点へも曲線でつなぎ、輪を回り続ける（Mode は見ない）。地点は 3 つ以上にする（2 つなら直線の行き来）。既定オフ
    @editable:
        ToolTip := MoverSplineClosedToolTip
        Categories := array{MoverCategory, MoverSplineCategory}
    Closed<public>:logic = false

    # Closed でないときの回り方。PingPong は同じ曲線を行き来、Once は最後の地点で止まる、Loop は最後の地点から最初の地点へまっすぐ戻る。既定 PingPong
    @editable:
        ToolTip := MoverSplineModeToolTip
        Categories := array{MoverCategory, MoverSplineCategory}
    Mode<public>:mover_path_mode = mover_path_mode.PingPong

    # オンなら動き出した位置を最初の地点（番号 0）にする。オフなら目印の地点だけを通る（置いた位置が最初の目印と違えば、最初はそこへまっすぐ向かう）。既定オン
    @editable:
        ToolTip := MoverPathIncludeStartToolTip
        Categories := array{MoverCategory, MoverSplineCategory}
    IncludeStart<public>:logic = true

    # 地点のあいだの曲線を、いくつの直線に分けるか（1〜64）。多いほど曲線に近い。地点が 2 つのときは 1。既定 8
    @editable_number(int):
        ToolTip := MoverSplineSubdivisionsToolTip
        Categories := array{MoverCategory, MoverSplineCategory}
        MinValue := option{1}
        MaxValue := option{64}
    SubdivisionsPerSegment<public>:int = 8

    # オンなら、進む向きに entity の向き（ヨー。前 = Forward 軸）を合わせる。傾き（ピッチ・ロール）は変えない。既定オフ
    @editable:
        ToolTip := MoverSplineFaceToolTip
        Categories := array{MoverCategory, MoverSplineCategory}
    FaceTravelDirection<public>:logic = false

    # コードで入れる地点（世界の位置、センチメートル）。空なら子の mover_waypoint_component を使う
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

    # 地点を入れ替える（世界の位置、センチメートル）。今向かっている行き先はそのままで、次の行き先から、新しい地点の最初（IncludeStart なら動き出した位置）から通り直す（曲線もそのとき作り直す）
    SetPoints<public>(NewPoints:[]vector3):void =
        set Override = option{NewPoints}
        set IsResolved = false

    # 最初の地点から通り直す（mover_component の Restart が呼ぶ）。地点と曲線は次の行き先を決めるときに作り直す（SetPoints で入れた地点はそのまま使う）
    Reset<override>():void =
        set IsResolved = false

    # 曲線が通る地点（世界の位置、センチメートル。番号の順）。まだ動き出していなければ空
    GetResolvedPoints<public>()<reads>:[]vector3 =
        Resolved

    # 曲線を細かく分けた点（世界の位置、センチメートル）。地点 i は GetCurvePoints()[i × 区間の分割数]。Closed なら最後の点は最初の点と同じ。まだ動き出していなければ空
    GetCurvePoints<public>()<reads>:[]vector3 =
        Curve

    # 曲線の長さ（センチメートル。Closed なら 1 周）。分けた直線の長さの合計で、mover が進む長さと同じ。まだ動き出していなければ 0
    GetLengthCm<public>()<reads>:float =
        if (TotalCm := CumulativeCm[CumulativeCm.Length - 1]) then TotalCm else 0.0

    # 最初の地点から地点 Index までの曲線の長さ（センチメートル）。Closed なら Index = 地点の数 で 1 周の長さ。範囲の外・まだ動き出していなければ失敗する
    FindDistanceAtPoint<public>(Index:int)<decides><reads>:float =
        CumulativeCm[Index * Steps]

    # 最初の地点から曲線に沿って DistanceCm（センチメートル）進んだ位置（世界の位置）。Closed なら 1 周の長さで回り、そうでなければ両端で止まる。まだ動き出していなければ vector3{}
    SampleAtDistance<public>(DistanceCm:float)<transacts>:vector3 =
        Total := GetLengthCm()
        Along := if (CurveClosed?, Total > 0.0, Turns := Floor[DistanceCm / Total]) then DistanceCm - Turns * Total else Max(0.0, Min(DistanceCm, Total))
        if (Index := FindSampleAfter[Along], Index > 0, A := Curve[Index - 1], B := Curve[Index], CA := CumulativeCm[Index - 1], CB := CumulativeCm[Index]):
            Lerp(A, B, (Along - CA) / Max(CB - CA, 0.0001))
        else if (First := Curve[0]):
            First
        else:
            vector3{}

    # 直下の子の mover_waypoint_component を Order の小さい順に返す（Order が同じものどうしの順は決まらない）
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

    # NextTarget が返した地点へ向かう曲線の途中の点。前の地点が無い（最初の行き先）・Loop でまっすぐ戻るときは空（まっすぐ）
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

    # From 番の地点から To 番の地点への曲線の途中の点（両端は含めない）
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

    # 区間 Segment（地点 Segment → Segment + 1）の途中の点。Reverse なら逆の順
    CurveSlice<private>(Segment:int, Reverse:logic)<transacts>:[]vector3 =
        First := Segment * Steps
        Inner := for (Index -> Point : Curve, Index > First, Index < First + Steps):
            Point
        if (Reverse?):
            for (Index -> Point : Inner, Mirrored := Inner[Inner.Length - 1 - Index]):
                Mirrored
        else:
            Inner

    # 長さの表で、Along（センチメートル）以上になる最初の点の番号
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

# Points を通る centripetal Catmull-Rom の曲線を、区間ごとに Steps 個の直線に分けた点。Closed なら最後の地点から最初の地点へも区間を作る（最後の点は最初の点と同じ）。開いた両端は、端の地点で折り返した点を外側に足して作る
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

# 曲線を作るときの Index 番の点。Closed なら番号を回し、そうでなければ両端の外は端で折り返した点（2 × 端 − 隣）
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

# P1 から P2 への区間で、Ratio（0〜1。曲線の媒介変数）の位置。centripetal（点の間隔の平方根を媒介変数の幅にする。Barry–Goldman の形）。Ratio が 0 なら P1、1 なら P2
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

# 長さの表：最初の点から各点までの折れ線の長さ（センチメートル）。最初は 0
MakeCumulativeLengths<internal>(Curve:[]vector3)<transacts>:[]float =
    var Total:float = 0.0
    var Previous:?vector3 = false
    for (Point : Curve):
        if (Before := Previous?):
            set Total += Distance(Before, Point)
        set Previous = option{Point}
        Total
