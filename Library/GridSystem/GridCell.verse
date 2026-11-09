using { /Verse.org/SpatialMath }

# 役割：グリッドの 1 マスの番号（Forward・Left・Up の 3 つの整数）
grid_cell<public> := struct<computes>:
    # Forward 方向のマス番号
    X<public>:int = 0
    # Left 方向のマス番号
    Y<public>:int = 0
    # Up 方向のマス番号
    Z<public>:int = 0

# 軸ごとに足したマス
(A:grid_cell).Plus<public>(B:grid_cell)<computes>:grid_cell =
    grid_cell{X := A.X + B.X, Y := A.Y + B.Y, Z := A.Z + B.Z}

# 役割：グリッドの直方体の範囲（Start のマスから Size マス分。Size はどれも 1 以上）。借用はいつもこの形
grid_box<public> := struct<computes>:
    # 範囲の始まりのマス（各軸でいちばん小さい角）
    Start<public>:grid_cell = grid_cell{}
    # 各軸のマス数（1 以上）。既定 1 × 1 × 1
    Size<public>:grid_cell = grid_cell{X := 1, Y := 1, Z := 1}

# 範囲の終わりの次のマス（Start + Size。このマス自体は範囲に入らない）
(Box:grid_box).GetEnd<public>()<computes>:grid_cell =
    grid_cell{X := Box.Start.X + Box.Size.X, Y := Box.Start.Y + Box.Size.Y, Z := Box.Start.Z + Box.Size.Z}

# Other と 1 マスでも重なれば成功する。面で接しているだけなら重ならない（失敗する）
(Box:grid_box).Overlaps<public>(Other:grid_box)<decides><computes>:void =
    Upper := Box.GetEnd()
    OtherEnd := Other.GetEnd()
    Box.Start.X < OtherEnd.X
    Other.Start.X < Upper.X
    Box.Start.Y < OtherEnd.Y
    Other.Start.Y < Upper.Y
    Box.Start.Z < OtherEnd.Z
    Other.Start.Z < Upper.Z

# まわりに Margin マスずつ広げた範囲（各軸で両側に Margin、大きさは 2 × Margin 増える）。Margin が負なら縮み、Size が 0 以下になっても丸めない（IsValid で確かめる）
(Box:grid_box).Expand<public>(Margin:int)<computes>:grid_box =
    grid_box:
        Start := grid_cell{X := Box.Start.X - Margin, Y := Box.Start.Y - Margin, Z := Box.Start.Z - Margin}
        Size := grid_cell{X := Box.Size.X + Margin * 2, Y := Box.Size.Y + Margin * 2, Z := Box.Size.Z + Margin * 2}

# 各軸の大きさ（Size）がどれも 1 以上なら成功する（Expand に負の Margin を渡すと 0 以下になることがある。grid_component はそういう範囲を借りない）
(Box:grid_box).IsValid<public>()<decides><computes>:void =
    Box.Size.X > 0
    Box.Size.Y > 0
    Box.Size.Z > 0

# Start から Size マス分の範囲を作る。Size の各軸は 1 未満なら 1 に丸める
MakeGridBox<public>(Start:grid_cell, Size:grid_cell)<computes>:grid_box =
    grid_box:
        Start := Start
        Size := grid_cell{X := Max(Size.X, 1), Y := Max(Size.Y, 1), Z := Max(Size.Z, 1)}

# Box から Cell までの、いちばん近い所とのマス数の 2 乗（中にあれば 0）
(Box:grid_box).GetDistanceSquared<public>(Cell:grid_cell)<computes>:int =
    End := Box.GetEnd()
    DX := Max(Max(Box.Start.X - Cell.X, Cell.X - End.X), 0)
    DY := Max(Max(Box.Start.Y - Cell.Y, Cell.Y - End.Y), 0)
    DZ := Max(Max(Box.Start.Z - Cell.Z, Cell.Z - End.Z), 0)
    DX * DX + DY * DY + DZ * DZ
