using { GridSystem }

# Role: one spawn / despawn range (band). Horizontally Center +/- Half cells, vertically Bottom to Top cells. Items that fall below Bottom are despawned. New items are spawned between SpawnBottom and Top
spawn_band<public> := struct<computes>:
    # Horizontal center cell of the band (X)
    CenterX<public>:int = 0
    # Horizontal center cell of the band (Y)
    CenterY<public>:int = 0
    # Half width in X (cells). The band is CenterX +/- HalfX
    HalfX<public>:int = 0
    # Half width in Y (cells). The band is CenterY +/- HalfY
    HalfY<public>:int = 0
    # Lower limit cell (Z). Items that fall below this are despawned
    Bottom<public>:int = 0
    # Lowest cell (Z) at which new items are spawned
    SpawnBottom<public>:int = 0
    # Upper limit cell (Z)
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

# Merges bands until no nearby ones (overlapping within GapCells cells) remain
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
