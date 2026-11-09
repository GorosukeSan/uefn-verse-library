using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { GridSystem }
using { SceneGraphSystem }
using { _Test }

# Role: verification of GridSystem. Checks grid_box math (overlap, expand, size rounding, distance), grid_component position / cell conversion, borrow / return / return all / returned notification, and that GridPath paths stay inside the bounds and follow the axes
# Test level: just attach this test component to any entity (the test creates its own grid under its children with 100 cm cells; the level's grid is not used)
# Result: [TEST] GridSystem in the output log
grid_system_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "GridSystem"}
        TestBoxMath(Results)
        GridEntity := entity{}
        Grid := grid_component{Entity := GridEntity, CellSizeCm := 100.0}
        GridEntity.AddComponents(array{Grid})
        Entity.AddEntities(array{GridEntity})
        Origin := Entity.GetGlobalTranslation()
        GridEntity.SetGlobalTransform(MakeTranslationTransform(Origin))
        TickEvents.PrePhysics.Await()
        TestConversion(Results, Grid, Origin)
        TestReservations(Results, Grid)
        TestPath(Results)
        GridEntity.RemoveFromParent()
        if (Results.Finish[]) {}

    TestBoxMath<private>(Results:test_log):void =
        A := MakeGridBox(grid_cell{}, grid_cell{X := 2, Y := 2, Z := 2})
        B := MakeGridBox(grid_cell{X := 1, Y := 1, Z := 1}, grid_cell{X := 2, Y := 2, Z := 2})
        Touching := MakeGridBox(grid_cell{X := 2}, grid_cell{X := 1, Y := 1, Z := 1})
        Results.Check("overlapping boxes overlap", if (A.Overlaps[B]) then true else false)
        Results.Check("boxes that only touch do not overlap", if (A.Overlaps[Touching]) then false else true)
        End := A.GetEnd()
        Results.Check("GetEnd = Start + Size", if (End.X = 2, End.Y = 2, End.Z = 2) then true else false)
        Grown := A.Expand(1)
        Results.Check("Expand(1) grows each side by 1", if (Grown.Start.X = -1, Grown.Size.X = 4) then true else false)
        Results.Check("Expand(-1) of size 2 is not valid", if (A.Expand(-1).IsValid[]) then false else true)
        Clamped := MakeGridBox(grid_cell{}, grid_cell{X := 0, Y := -3, Z := 1})
        Results.Check("MakeGridBox clamps size to 1", if (Clamped.Size.X = 1, Clamped.Size.Y = 1, Clamped.IsValid[]) then true else false)
        Results.CheckInt("distance inside is 0", A.GetDistanceSquared(grid_cell{X := 1, Y := 1, Z := 1}), 0)
        Results.CheckInt("distance squared to (5,2,2)", A.GetDistanceSquared(grid_cell{X := 5, Y := 2, Z := 2}), 9)
        Results.Check("Plus adds per axis", if (Sum := grid_cell{X := 1, Y := 2, Z := 3}.Plus(grid_cell{X := 1, Y := 1, Z := 1}), Sum.X = 2, Sum.Y = 3, Sum.Z = 4) then true else false)

    TestConversion<private>(Results:test_log, Grid:grid_component, Origin:vector3):void =
        Cell := Grid.ToCell(Origin + vector3{Forward := 150.0, Left := -50.0, Up := 250.0})
        Results.Check("ToCell floors (150, -50, 250) -> (1, -1, 2)", if (Cell.X = 1, Cell.Y = -1, Cell.Z = 2) then true else false)
        Position := Grid.CellToPosition(grid_cell{X := 1, Y := 2, Z := 3})
        Expected := Origin + vector3{Forward := 100.0, Left := 200.0, Up := 300.0}
        Results.CheckFloat("CellToPosition is the cell corner", Distance(Position, Expected), 0.0, 0.5)

    TestReservations<private>(Results:test_log, Grid:grid_component)<suspends>:void =
        A := MakeGridBox(grid_cell{}, grid_cell{X := 2, Y := 2, Z := 2})
        B := MakeGridBox(grid_cell{X := 1, Y := 1, Z := 1}, grid_cell{X := 2, Y := 2, Z := 2})
        Far := MakeGridBox(grid_cell{X := 10}, grid_cell{X := 1, Y := 1, Z := 1})
        Results.CheckInt("no reservations at start", Grid.GetReservationCount(), 0)
        if (First := Grid.TryReserve(A)?):
            Results.Pass("TryReserve on a free box")
            Results.Check("overlapping box is not free", if (Grid.IsFree[B]) then false else true)
            Results.Check("TryReserve on an overlapping box fails", if (Grid.TryReserve(B)?) then false else true)
            Results.Check("invalid box cannot be reserved", if (Grid.TryReserve(A.Expand(-1))?) then false else true)
            Results.Check("far box can be reserved", if (Grid.TryReserve(Far)?) then true else false)
            Results.CheckInt("two reservations", Grid.GetReservations().Length, 2)
            Results.CheckFloat("reservation size in cm", First.GetSize().Forward, 200.0, 0.5)
            Released := spawn{AwaitWithin(Grid.ReleasedEvent, 1.0)}
            First.Release()
            Awaited1 := Released.Await()
            Results.Check("ReleasedEvent on Release", if (Got := Awaited1?, Got = First) then true else false)
            Results.Check("released reservation is not held", if (First.IsHeld[]) then false else true)
            Results.Check("box is free again after Release", if (Grid.IsFree[B]) then true else false)
            First.Release()
            Results.CheckInt("second Release does nothing", Grid.GetReservationCount(), 1)
            Grid.ReleaseAll()
            Results.CheckInt("ReleaseAll empties the grid", Grid.GetReservationCount(), 0)
        else:
            Results.Fail("TryReserve on a free box", "returned false")

    TestPath<private>(Results:test_log):void =
        Box := MakeGridBox(grid_cell{X := 2, Y := -3, Z := 1}, grid_cell{X := 4, Y := 4, Z := 4})
        Style := grid_path_style{SegmentCount := 8, MaxStepCells := 3, VerticalChance := 0.3, BranchChance := 0.2}
        Segments := MakeGridPath(Box, Style)
        Results.Check("MakeGridPath makes at most SegmentCount segments", if (Segments.Length <= 8) then true else false)
        var Ok:logic = true
        for (Segment : Segments):
            if (not IsInsideCorners[Box, Segment.From] or not IsInsideCorners[Box, Segment.To] or not IsOneAxis[Segment]):
                set Ok = false
        Results.Check("path segments stay inside the box and follow one axis", Ok)
        Corners := GetPathCorners(Segments)
        Results.Check("GetPathCorners has corners when there are segments", if (Segments.Length = 0 or Corners.Length >= 2) then true else false)

    IsInsideCorners<private>(Box:grid_box, Cell:grid_cell)<decides><computes>:void =
        End := Box.GetEnd()
        Cell.X >= Box.Start.X
        Cell.X <= End.X
        Cell.Y >= Box.Start.Y
        Cell.Y <= End.Y
        Cell.Z >= Box.Start.Z
        Cell.Z <= End.Z

    IsOneAxis<private>(Segment:grid_segment)<decides><computes>:void =
        Changed := (if (Segment.From.X <> Segment.To.X) then 1 else 0) + (if (Segment.From.Y <> Segment.To.Y) then 1 else 0) + (if (Segment.From.Z <> Segment.To.Z) then 1 else 0)
        Changed = 1
