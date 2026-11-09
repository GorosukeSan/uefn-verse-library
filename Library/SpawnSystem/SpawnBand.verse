using { GridSystem }

# 役割：出し入れする範囲（帯）1 つ。水平は Center ± Half マス、縦は Bottom〜Top マス。Bottom より下に外れたものは消える。新しく出すのは SpawnBottom〜Top のあいだ
spawn_band<public> := struct<computes>:
    # 帯の水平の真ん中のマス（X）
    CenterX<public>:int = 0
    # 帯の水平の真ん中のマス（Y）
    CenterY<public>:int = 0
    # X の半分の幅（マス）。CenterX ± HalfX が帯
    HalfX<public>:int = 0
    # Y の半分の幅（マス）。CenterY ± HalfY が帯
    HalfY<public>:int = 0
    # 下限のマス（Z）。これより下に外れたものは消える
    Bottom<public>:int = 0
    # 新しく出す高さの最低のマス（Z）
    SpawnBottom<public>:int = 0
    # 上限のマス（Z）
    Top<public>:int = 0

(Band:spawn_band).Contains<internal>(Box:grid_box)<decides><computes>:void =
    End := Box.GetEnd()
    End.Z > Band.Bottom
    Box.Start.Z <= Band.Top
    End.X > Band.CenterX - Band.HalfX
    Box.Start.X <= Band.CenterX + Band.HalfX
    End.Y > Band.CenterY - Band.HalfY
    Box.Start.Y <= Band.CenterY + Band.HalfY

(Band:spawn_band).IsNear<internal>(Other:spawn_band, GapCells:int)<decides><computes>:void =
    Abs(Band.CenterX - Other.CenterX) <= Band.HalfX + Other.HalfX + GapCells
    Abs(Band.CenterY - Other.CenterY) <= Band.HalfY + Other.HalfY + GapCells
    Other.Bottom <= Band.Top + GapCells
    Band.Bottom <= Other.Top + GapCells

(Band:spawn_band).Merge<internal>(Other:spawn_band)<computes>:spawn_band =
    MinX := Min(Band.CenterX - Band.HalfX, Other.CenterX - Other.HalfX)
    MaxX := Max(Band.CenterX + Band.HalfX, Other.CenterX + Other.HalfX)
    MinY := Min(Band.CenterY - Band.HalfY, Other.CenterY - Other.HalfY)
    MaxY := Max(Band.CenterY + Band.HalfY, Other.CenterY + Other.HalfY)
    spawn_band:
        CenterX := MinX + (Quotient[MaxX - MinX, 2] or 0)
        CenterY := MinY + (Quotient[MaxY - MinY, 2] or 0)
        HalfX := (Quotient[MaxX - MinX + 1, 2] or 0)
        HalfY := (Quotient[MaxY - MinY + 1, 2] or 0)
        Bottom := Min(Band.Bottom, Other.Bottom)
        SpawnBottom := Min(Band.SpawnBottom, Other.SpawnBottom)
        Top := Max(Band.Top, Other.Top)

# 帯を、近いもの（GapCells マス以内で重なるもの）がなくなるまでまとめる
MergeBands<internal>(Bands:[]spawn_band, GapCells:int)<transacts>:[]spawn_band =
    var Result:[]spawn_band = Bands
    var Merged:logic = true
    loop:
        if (not Merged?):
            break
        set Merged = false
        if (Pair := FindNearPair[Result, GapCells]):
            First := Result[Pair(0)] or spawn_band{}
            Second := Result[Pair(1)] or spawn_band{}
            Rest := for (Index -> Band : Result, Index <> Pair(0), Index <> Pair(1)):
                Band
            set Result = Rest + array{First.Merge(Second)}
            set Merged = true
    Result

FindNearPair<internal>(Bands:[]spawn_band, GapCells:int)<decides><computes>:tuple(int, int) =
    first:
        I -> A : Bands
        J -> B : Bands
        I < J
        A.IsNear[B, GapCells]
    do:
        (I, J)
