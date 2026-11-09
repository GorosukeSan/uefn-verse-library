using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { SceneGraphSystem }
using { MoverSystem }
using { MoverSystem.TooltipKit }

# 決まった地点の回り方
mover_path_mode<public> := enum:
    # 最後の地点のあと最初の地点へ戻り、ずっと回る
    Loop
    # 最後まで行ったら逆の順に戻り、ずっと行き来する
    PingPong
    # 最後の地点に着いたら止まる（mover は FinishedEvent を出す）
    Once

# 方向：道のりの entity（mover の entity）から SendDown（自分と子孫）
# 送り手：mover_path_route_component（Route）。回る地点が決まったとき（動き出して最初の行き先を決めるとき・SetPoints のあと）
# 受け手：道のりを見せる見た目（地点の目印・線）。消費しない
mover_path_changed_event<public> := class(scene_event):
    # 送った mover_path_route_component
    Route<public>:mover_path_route_component
    # 回る地点（世界の位置、センチメートル）。Index の順
    Points<public>:[]vector3

# 役割：決まった地点を Mode の回り方で回る道のり。地点は、Points（コードで入れた世界の位置）があればそれ、無ければ直下の子の mover_waypoint_component の位置（Order の小さい順。子の並び順は使わない）。IncludeStart なら、動き出したときの位置を最初の地点（番号 0）にする。地点の位置は動き出して最初の行き先を決めるときに 1 回だけ読み（子の目印が mover と一緒に動いても変わらない）、mover_path_changed_event で自分の entity へ送る（見た目用）
# 置き方：エディターで、動かしたい entity（mover_component と同じ entity）に付ける。実行時に作るなら Points を入れて付ける
# 同じ entity：mover_component
# 子：Points が空なら、mover_waypoint_component を付けた entity（見た目の無いもの）を直下に。順番は各目印の Order で決める
# 外から：SetPoints で地点を入れ替える（次の行き先から使う。終わったあとなら mover_component の Restart で動き直す）
mover_path_route_component<public> := class<final_super>(mover_route_component):

    # 地点の回り方（Loop / PingPong / Once）。既定 Loop
    @editable:
        ToolTip := MoverPathModeToolTip
        Categories := array{MoverCategory, MoverPathCategory}
    Mode<public>:mover_path_mode = mover_path_mode.Loop

    # オンなら動き出した位置を最初の地点（番号 0）にする。オフなら目印の地点だけを回る。既定オン
    @editable:
        ToolTip := MoverPathIncludeStartToolTip
        Categories := array{MoverCategory, MoverPathCategory}
    IncludeStart<public>:logic = true

    # コードで入れる地点（世界の位置、センチメートル）。空なら子の mover_waypoint_component を使う
    Points<public>:[]vector3 = array{}

    var Override<private>:?[]vector3 = false
    var Resolved<private>:[]vector3 = array{}
    var IsResolved<private>:logic = false
    var Current<private>:int = -1
    var Forward<private>:logic = true

    # 地点を入れ替える（世界の位置、センチメートル）。今向かっている行き先はそのままで、次の行き先から、新しい地点の最初（IncludeStart なら動き出した位置）から回り直す
    SetPoints<public>(NewPoints:[]vector3):void =
        set Override = option{NewPoints}
        set IsResolved = false

    # 最初の地点から回り直す（mover_component の Restart が呼ぶ）。地点は次の行き先を決めるときに読み直す（SetPoints で入れた地点はそのまま使う）
    Reset<override>():void =
        set IsResolved = false

    # 回る地点（世界の位置、センチメートル。番号の順）。まだ動き出していなければ空
    GetResolvedPoints<public>()<reads>:[]vector3 =
        Resolved

    # 直下の子の mover_waypoint_component を Order の小さい順に返す（Order が同じものどうしの順は決まらない）
    GetWaypoints<public>()<transacts>:[]mover_waypoint_component =
        var Sorted:[]mover_waypoint_component = array{}
        for (Waypoint : Entity.GetChildComponents(mover_waypoint_component)):
            set Sorted = InsertByOrder(Sorted, Waypoint)
        Sorted

    NextTarget<override>(Home:vector3, Position:vector3):?mover_target =
        if (not IsResolved?):
            Resolve(Home)
        MaybeNext := NextIndex()
        if (Next := MaybeNext?, Point := Resolved[Next]):
            set Current = Next
            option{mover_target{Position := Point, Index := Next}}
        else:
            false

    Resolve<private>(Home:vector3):void =
        Base := if (Code := Override?) then Code else if (Points.Length > 0) then Points else ReadWaypoints()
        set Resolved = if (IncludeStart?) then array{Home} + Base else Base
        set Current = if (IncludeStart?) then 0 else -1
        set Forward = true
        set IsResolved = true
        Entity.SendDown(mover_path_changed_event{Route := Self, Points := Resolved})

    ReadWaypoints<private>()<transacts>:[]vector3 =
        for (Waypoint : GetWaypoints()):
            Waypoint.Entity.GetGlobalTranslation()

    NextIndex<private>():?int =
        Count := Resolved.Length
        if (Count <= 0):
            false
        else if (Count = 1):
            if (Current < 0) then option{0} else false
        else if (Mode = mover_path_mode.Loop):
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

# 役割：mover_path_route_component が回る地点の目印。Order の小さい順に回る
# 置き方：エディターで、見た目の無い entity に付ける
# 親：mover_path_route_component を付けた entity（直下に置く。子の並び順は関係ない）
mover_waypoint_component<public> := class<final_super>(component):

    # 回る順番。小さい順に回る（子の並び順は使わない。同じ数どうしの順は決まらない）。既定 0
    @editable_number(int):
        ToolTip := MoverWaypointOrderToolTip
        Categories := array{MoverCategory, MoverPathCategory}
    Order<public>:int = 0

InsertByOrder<internal>(Sorted:[]mover_waypoint_component, Item:mover_waypoint_component)<reads>:[]mover_waypoint_component =
    Index := FindInsertIndex[Sorted, Item.Order] or Sorted.Length
    Before := for (I -> Current : Sorted, I < Index):
        Current
    After := for (I -> Current : Sorted, I >= Index):
        Current
    Before + array{Item} + After

FindInsertIndex<internal>(Sorted:[]mover_waypoint_component, Order:int)<decides><reads>:int =
    first (I -> Current : Sorted, Current.Order > Order):
        I
