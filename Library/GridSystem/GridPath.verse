using { /Verse.org/Random }

# GridPath：借りた範囲（grid_box）の中に、マスの角を結ぶ軸に沿った道（線の並び）を作る小道具。ライブラリの中では使っていない（利用者が、線を並べた足場や、mover_path_route_component に渡す地点の列を作るときに使う）。座標はすべてマスの番号で、世界の位置にするには grid_component.CellToPosition か spawn_area.GetMinPosition() + マス × CellSizeCm

# 役割：グリッドの線の 1 本（From のマスの角から、軸に沿って To のマスの角まで）
grid_segment<public> := struct<computes>:
    # 線の始まりのマス（の角）
    From<public>:grid_cell = grid_cell{}
    # 線の終わりのマス（の角）。From と 1 軸だけ違う
    To<public>:grid_cell = grid_cell{}

# 役割：道の作り方。SegmentCount は線の本数（進めない 1 本は飛ばすので、できる本数はこれ以下）、MaxStepCells は 1 本の長さの上限（マス）。VerticalChance は上下に曲がる割合（0〜1。小さいほど横に広がる）、BranchChance は、次の 1 本を今の先ではなく、これまでの角のどれかから出す割合（枝分かれ）
grid_path_style<public> := struct<computes>:
    # 線の本数（進めない 1 本は飛ばすので、できる本数はこれ以下）。既定 4
    SegmentCount<public>:int = 4
    # 1 本の長さの上限（マス）。既定 4
    MaxStepCells<public>:int = 4
    # 上下に曲がる割合（0〜1。小さいほど横に広がる）。既定 0.33
    VerticalChance<public>:float = 0.33
    # これまでの角のどれかから枝分かれする割合（0〜1）。既定 0.0（枝分かれしない）
    BranchChance<public>:float = 0.0

# 役割：Box の中（マスの角を結ぶ線）を、軸に沿って曲がりながら進む道を作る。最初は Box の中のランダムな角から、1 本ごとに今の向きと違う軸を選び（上下は VerticalChance の割合）、Box の外へ出ない長さ（1〜MaxStepCells マス）だけ進む。BranchChance の割合で、これまでの角のどれかから枝分かれする。進めない向きのときは、その 1 本は飛ばす
MakeGridPath<public>(Box:grid_box, Style:grid_path_style)<transacts>:[]grid_segment =
    Upper := Box.GetEnd()
    var Current:grid_cell = grid_cell:
        X := GetRandomInt(Box.Start.X, Upper.X)
        Y := GetRandomInt(Box.Start.Y, Upper.Y)
        Z := GetRandomInt(Box.Start.Z, Upper.Z)
    var Corners:[]grid_cell = array{Current}
    var LastAxis:int = -1
    var Segments:[]grid_segment = array{}
    var Index:int = 0
    loop:
        if (Index >= Style.SegmentCount):
            break
        if (GetRandomFloat(0.0, 1.0) < Style.BranchChance, Branch := Corners[GetRandomInt(0, Corners.Length - 1)]):
            set Current = Branch
            set LastAxis = -1
        Axis := PickAxis(LastAxis, Style.VerticalChance)
        if (Next := StepInside[Box, Current, Axis, Style.MaxStepCells]):
            set Segments += array{grid_segment{From := Current, To := Next}}
            set Corners += array{Next}
            set Current = Next
            set LastAxis = Axis
        set Index += 1
    Segments

# Segments を順につないだ角の列（枝分かれしていても、出てきた順に From と To を並べる。同じ角が続くときは 1 つにする）
GetPathCorners<public>(Segments:[]grid_segment)<transacts>:[]grid_cell =
    var Result:[]grid_cell = array{}
    for (Segment : Segments):
        set Result = AppendCorner(Result, Segment.From)
        set Result = AppendCorner(Result, Segment.To)
    Result

AppendCorner<internal>(Corners:[]grid_cell, Corner:grid_cell)<computes>:[]grid_cell =
    if (Last := Corners[Corners.Length - 1], Last = Corner):
        Corners
    else:
        Corners + array{Corner}

PickAxis<internal>(LastAxis:int, VerticalChance:float)<transacts>:int =
    Vertical := if (LastAxis <> 2, GetRandomFloat(0.0, 1.0) < VerticalChance) then true else false
    if (Vertical?):
        2
    else if (LastAxis = 0):
        1
    else if (LastAxis = 1):
        0
    else:
        GetRandomInt(0, 1)

StepInside<internal>(Box:grid_box, From:grid_cell, Axis:int, MaxStep:int)<decides><transacts>:grid_cell =
    Upper := Box.GetEnd()
    Low := GetAxis(Box.Start, Axis)
    High := GetAxis(Upper, Axis)
    Here := GetAxis(From, Axis)
    Room := if (GetRandomInt(0, 1) = 0) then High - Here else Low - Here
    Room <> 0
    Limit := Min(Abs(Room), Max(MaxStep, 1))
    Length := GetRandomInt(1, Limit)
    Step := if (Room > 0) then Length else -Length
    SetAxis(From, Axis, Here + Step)

GetAxis<internal>(Cell:grid_cell, Axis:int)<computes>:int =
    if (Axis = 0):
        Cell.X
    else if (Axis = 1):
        Cell.Y
    else:
        Cell.Z

SetAxis<internal>(Cell:grid_cell, Axis:int, Value:int)<computes>:grid_cell =
    if (Axis = 0):
        grid_cell{X := Value, Y := Cell.Y, Z := Cell.Z}
    else if (Axis = 1):
        grid_cell{X := Cell.X, Y := Value, Z := Cell.Z}
    else:
        grid_cell{X := Cell.X, Y := Cell.Y, Z := Value}
