using { /Verse.org/Random }

# GridPath: a helper that builds an axis-aligned path (a sequence of lines joining cell corners) inside a reserved region (grid_box). Not used inside the library (you use it to build a platform of lines or the list of points passed to mover_path_route_component). All coordinates are cell indices; to get world positions use grid_component.CellToPosition or spawn_area.GetMinPosition() + cells x CellSizeCm

# Role: one line of the grid (from the corner of the From cell along an axis to the corner of the To cell)
grid_segment<public> := struct<computes>:
    # The cell (corner) where the line starts
    From<public>:grid_cell = grid_cell{}
    # The cell (corner) where the line ends. Differs from From on exactly one axis
    To<public>:grid_cell = grid_cell{}

# Role: how the path is built. SegmentCount is the number of lines (a line that cannot advance is skipped, so the result has at most this many), MaxStepCells is the maximum length of one line (cells). VerticalChance is the chance of turning up or down (0 to 1; smaller spreads more horizontally), BranchChance is the chance that the next line starts from one of the previous corners instead of the current end (branching)
grid_path_style<public> := struct<computes>:
    # Number of lines (a line that cannot advance is skipped, so the result has at most this many). Default 4
    SegmentCount<public>:int = 4
    # Maximum length of one line (cells). Default 4
    MaxStepCells<public>:int = 4
    # Chance of turning up or down (0 to 1; smaller spreads more horizontally). Default 0.33
    VerticalChance<public>:float = 0.33
    # Chance of branching from one of the previous corners (0 to 1). Default 0.0 (no branching)
    BranchChance<public>:float = 0.0

# Role: builds a path inside Box (lines joining cell corners) that advances along the axes with turns. Starts at a random corner inside Box; for each line, picks an axis different from the current direction (vertical with the VerticalChance chance) and advances a length (1 to MaxStepCells cells) that stays inside Box. With the BranchChance chance, branches from one of the previous corners. When it cannot advance in the chosen direction, that line is skipped
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

# The corners of Segments joined in order (even with branches, lists From and To in the order they appear. Consecutive identical corners are merged into one)
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
