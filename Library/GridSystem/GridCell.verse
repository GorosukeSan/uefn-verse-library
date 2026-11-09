using { /Verse.org/SpatialMath }

# Role: the index of one grid cell (three integers: Forward, Left, Up)
grid_cell<public> := struct<computes>:
    # Cell index along Forward
    X<public>:int = 0
    # Cell index along Left
    Y<public>:int = 0
    # Cell index along Up
    Z<public>:int = 0

# Cell added per axis
(A:grid_cell).Plus<public>(B:grid_cell)<computes>:grid_cell =
    grid_cell{X := A.X + B.X, Y := A.Y + B.Y, Z := A.Z + B.Z}

# Role: a box-shaped region of the grid (Size cells from the Start cell; every Size is at least 1). Reservations always have this shape
grid_box<public> := struct<computes>:
    # The starting cell of the box (the smallest corner on each axis)
    Start<public>:grid_cell = grid_cell{}
    # Number of cells on each axis (at least 1). Default 1 x 1 x 1
    Size<public>:grid_cell = grid_cell{X := 1, Y := 1, Z := 1}

# The cell just past the end of the box (Start + Size; this cell itself is not inside the box)
(Box:grid_box).GetEnd<public>()<computes>:grid_cell =
    grid_cell{X := Box.Start.X + Box.Size.X, Y := Box.Start.Y + Box.Size.Y, Z := Box.Start.Z + Box.Size.Z}

# Succeeds if it shares at least one cell with Other. Boxes that only touch at a face do not overlap (fails)
(Box:grid_box).Overlaps<public>(Other:grid_box)<decides><computes>:void =
    Upper := Box.GetEnd()
    OtherEnd := Other.GetEnd()
    Box.Start.X < OtherEnd.X
    Other.Start.X < Upper.X
    Box.Start.Y < OtherEnd.Y
    Other.Start.Y < Upper.Y
    Box.Start.Z < OtherEnd.Z
    Other.Start.Z < Upper.Z

# The box grown by Margin cells all around (Margin on both sides of each axis; the size grows by 2 x Margin). A negative Margin shrinks it, and Size is not clamped even if it becomes 0 or less (check with IsValid)
(Box:grid_box).Expand<public>(Margin:int)<computes>:grid_box =
    grid_box:
        Start := grid_cell{X := Box.Start.X - Margin, Y := Box.Start.Y - Margin, Z := Box.Start.Z - Margin}
        Size := grid_cell{X := Box.Size.X + Margin * 2, Y := Box.Size.Y + Margin * 2, Z := Box.Size.Z + Margin * 2}

# Succeeds if the size (Size) on every axis is at least 1 (Expand with a negative Margin can make it 0 or less. grid_component never reserves such a box)
(Box:grid_box).IsValid<public>()<decides><computes>:void =
    Box.Size.X > 0
    Box.Size.Y > 0
    Box.Size.Z > 0

# Makes a box of Size cells from Start. Each axis of Size below 1 is clamped to 1
MakeGridBox<public>(Start:grid_cell, Size:grid_cell)<computes>:grid_box =
    grid_box:
        Start := Start
        Size := grid_cell{X := Max(Size.X, 1), Y := Max(Size.Y, 1), Z := Max(Size.Z, 1)}

# Squared distance in cells from Box to Cell at the nearest point (0 if inside)
(Box:grid_box).GetDistanceSquared<public>(Cell:grid_cell)<computes>:int =
    End := Box.GetEnd()
    DX := Max(Max(Box.Start.X - Cell.X, Cell.X - End.X), 0)
    DY := Max(Max(Box.Start.Y - Cell.Y, Cell.Y - End.Y), 0)
    DZ := Max(Max(Box.Start.Z - Cell.Z, Cell.Z - End.Z), 0)
    DX * DX + DY * DY + DZ * DZ
