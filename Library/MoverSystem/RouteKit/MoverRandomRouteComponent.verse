using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Random }
using { MoverSystem }
using { MoverSystem.TooltipKit }

# 役割：動き出したときの位置（Home）から RadiusCm 以内のランダムな点を、次々に行き先にする道のり（終わらない）。行き先は今の位置から MinStepCm 以上先を選び（何回か選んでもだめならそのまま）、Home より MaxDescentCm 以上は下にしない
# 置き方：エディターで、動かしたい entity（mover_component と同じ entity）に付ける
# 同じ entity：mover_component（ぶつかって跳ね返したいなら Motion = Physics）
mover_random_route_component<public> := class<final_super>(mover_route_component):

    # 動き出した位置から、行き先を選ぶ半径（センチメートル）。既定 1500
    @editable_number(float):
        ToolTip := MoverRandomRadiusToolTip
        Categories := array{MoverCategory, MoverRandomCategory}
        MinValue := option{100.0}
        MaxValue := option{50000.0}
    RadiusCm<public>:float = 1500.0
    # 次の行き先を、今の位置から少なくともこれだけ先にする（センチメートル）。既定 400
    @editable_number(float):
        ToolTip := MoverRandomMinStepToolTip
        Categories := array{MoverCategory, MoverRandomCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    MinStepCm<public>:float = 400.0
    # 動き出した位置から下へ行ける深さ（センチメートル）。これより下の行き先はこの高さに上げる。0 なら下へは行かない。既定 300
    @editable_number(float):
        ToolTip := MoverRandomMaxDescentToolTip
        Categories := array{MoverCategory, MoverRandomCategory}
        MinValue := option{0.0}
        MaxValue := option{50000.0}
    MaxDescentCm<public>:float = 300.0

    MaxAttempts<private>:int = 8

    var Picked<private>:int = 0

    # 選んだ回数（mover_target.Index）を 0 に戻す（mover_component の Restart が呼ぶ）
    Reset<override>():void =
        set Picked = 0

    NextTarget<override>(Home:vector3, Position:vector3):?mover_target =
        var Candidate:vector3 = MakeRandomPoint(Home)
        var Attempt:int = 1
        loop:
            if (Attempt >= MaxAttempts or Distance(Candidate, Position) >= MinStepCm):
                break
            set Candidate = MakeRandomPoint(Home)
            set Attempt += 1
        Index := Picked
        set Picked += 1
        option{mover_target{Position := KeepAboveFloor(Home, Candidate), Index := Index}}

    KeepAboveFloor<private>(Home:vector3, Point:vector3)<reads>:vector3 =
        LowestUp := Home.Up - MaxDescentCm
        if (Point.Up < LowestUp):
            vector3{Forward := Point.Forward, Left := Point.Left, Up := LowestUp}
        else:
            Point

    MakeRandomPoint<private>(Home:vector3)<transacts>:vector3 =
        Home + MakeRandomDirection() * GetRandomFloat(0.0, RadiusCm)

MakeRandomDirection<internal>()<transacts>:vector3 =
    Up := GetRandomFloat(-1.0, 1.0)
    Angle := GetRandomFloat(0.0, 2.0 * PiFloat)
    Flat := Sqrt(Max(1.0 - Up * Up, 0.0))
    vector3:
        Forward := Flat * Cos(Angle)
        Left := Flat * Sin(Angle)
        Up := Up
