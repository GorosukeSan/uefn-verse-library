# GridSystem

A System that divides the world into cells (cubes with sides of `CellSizeCm` centimeters) and manages "reservations" of box-shaped regions. Things that get spawned (cubes, lines, checkpoints, etc.) reserve a region here before being placed and use only the inside of the reserved region, so they never overlap each other. Used by SpawnSystem's `spawner_component` (reserves the spawn region) and `players_origin_component` (reads the cell size). CheckpointSystem's `checkpoint_factory_component` is placed on the same entity as the spawner and uses the size of the reserved region as the checkpoint size.

## Placement

| component | Where to place | What it does |
|---|---|---|
| `grid_component` | one per scope (`game_scope_component`) (one in the world without a scope). Cell 0 is at this entity's position | converts between positions and cells, and manages reserving and releasing box-shaped regions |

Example:
```
Scope (game_scope_component)
├ Grid (grid_component, CellSizeCm = 250)
└ Spawned things (spawner_component + ...)
```
Users find it with `FindGrid` (searches the scope) and remember it.

## Settings (@editable)
- `grid_component.CellSizeCm : float = 250.0` — side length of one cell (centimeters, 10–5000).

## Events
This System sends no scene_event.
- `grid_component.ReleasedEvent : listenable(grid_reservation)` — fires with the released reservation when one is released (by either `Release` or `ReleaseAll`).

## Public API
```verse
# Cells and boxes (coordinates are cell indices)
grid_cell<public> := struct<computes>:
    X<public>:int       # Forward
    Y<public>:int       # Left
    Z<public>:int       # Up
(A:grid_cell).Plus<public>(B:grid_cell)<computes>:grid_cell

grid_box<public> := struct<computes>:
    Start<public>:grid_cell
    Size<public>:grid_cell                                         # at least 1 on each axis
(Box:grid_box).GetEnd<public>()<computes>:grid_cell                  # Start + Size (this cell is not inside the box)
(Box:grid_box).Overlaps<public>(Other:grid_box)<decides><computes>:void   # fails if they only touch at a face
(Box:grid_box).Expand<public>(Margin:int)<computes>:grid_box        # grows by Margin cells on both sides of each axis
(Box:grid_box).IsValid<public>()<decides><computes>:void            # succeeds if every Size is at least 1
(Box:grid_box).GetDistanceSquared<public>(Cell:grid_cell)<computes>:int
MakeGridBox<public>(Start:grid_cell, Size:grid_cell)<computes>:grid_box   # clamps each axis of Size to at least 1

# Grid and reservations
grid_component<public> := class<final_super>(component):
    CellSizeCm<public>:float
    ReleasedEvent<public><final>:listenable(grid_reservation)
    GetOrigin<public>()<transacts>:vector3                         # corner of cell 0 (this entity's position)
    ToCell<public>(Position:vector3)<transacts>:grid_cell
    CellToPosition<public>(Cell:grid_cell)<transacts>:vector3      # the cell's starting corner (not the center)
    IsFree<public>(Box:grid_box)<decides><transacts>:void
    TryReserve<public>(Box:grid_box)<transacts>:?grid_reservation  # false if overlapping or a size is 0 or less
    GetReservationCount<public>()<reads>:int
    GetReservations<public>()<reads>:[]grid_reservation            # in reservation order
    ReleaseAll<public>():void

grid_reservation<public> := class<unique><internal>:              # created by TryReserve
    Grid<public>:grid_component
    Box<public>:grid_box
    var<private> Released<public>:logic
    Release<public>():void                                         # does nothing from the second call on
    IsHeld<public>()<decides><reads>:void
    GetMinPosition<public>()<transacts>:vector3
    GetMaxPosition<public>()<transacts>:vector3
    GetCenter<public>()<transacts>:vector3
    GetSize<public>()<transacts>:vector3                           # centimeters

(InEntity:entity).FindGrid<public>()<decides><transacts>:grid_component   # the grid_component of the scope (or the world)

# GridPath (a helper that builds an axis-aligned path inside a box)
grid_segment<public> := struct<computes>:
    From<public>:grid_cell
    To<public>:grid_cell

grid_path_style<public> := struct<computes>:
    SegmentCount<public>:int = 4
    MaxStepCells<public>:int = 4
    VerticalChance<public>:float = 0.33
    BranchChance<public>:float = 0.0

MakeGridPath<public>(Box:grid_box, Style:grid_path_style)<transacts>:[]grid_segment
GetPathCorners<public>(Segments:[]grid_segment)<transacts>:[]grid_cell
```

## Requirements, caveats and limits
- Cell 0 is at this entity's position. Rotation is not used. Cells on the negative side of the origin are also counted with truncation (Floor).
- Only one `grid_component` per scope is assumed. With several, it is unspecified which one `FindGrid` returns. `FindGrid` searches the scope, so do not call it every frame or every time; remember the result. It fails while InEntity is not yet in the world.
- `TryReserve` has the side effect of reserving, so it returns an option instead of being `<decides>`, so that a failure in the caller does not roll it back.
- Passing a negative `Margin` to `Expand` can make `Size` 0 or less (it is not clamped). Check with `IsValid`. `grid_component` never reserves such a box.
- `ReleaseAll` does not remove the holders (things spawned by a spawner, etc.). If they stay, other things may be placed overlapping the released region.
- GridPath is not used inside the library (use it to build a platform of lines or the list of points passed to `mover_path_route_component`). All coordinates are cell indices; to get world positions use `grid_component.CellToPosition` (for SpawnSystem's `spawn_area`, `GetMinPosition()` + cells x `CellSizeCm`).
- The code of this System has no `⚠ Unverified` marks and uses no `@experimental` API.

## Verifying
- Test: `grid_system_test_component` in `_Test/GridSystemTest/`. Just attach this test component to any entity (the test creates its own grid as a child with 100-centimeter cells; the level's grid is not used). It checks the `grid_box` math (overlap, expand, size clamping, distance), position/cell conversion, reserve / release / release all / the release notification, and that GridPath paths are axis-aligned and inside the box. It finishes right away (about 1 second). Results go to the output log as `[TEST] GridSystem`.
- There is no GridSystem sample in `_Samples/`.
