using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { SceneGraphSystem }
using { GridSystem.TooltipKit }

# Role: one reservation of a box-shaped region of the grid. Return it with Release (until then, overlapping regions cannot be reserved by others)
# Creation: created by grid_component.TryReserve (never from outside)
grid_reservation<public> := class<unique><internal>:

    # The grid it was reserved on
    Grid<public>:grid_component

    # The reserved region (cells)
    Box<public>:grid_box

    # true once released (after Release or ReleaseAll)
    var<private> Released<public>:logic = false

    # Releases the reservation (overlapping regions can be reserved by others again). Does nothing from the second call on
    Release<public>():void =
        if (not Released?):
            set Released = true
            Grid.Forget(Self)

    # Succeeds if not released
    IsHeld<public>()<decides><reads>:void =
        not Released?

    # World position of the starting corner of the region (centimeters)
    GetMinPosition<public>()<transacts>:vector3 =
        Grid.CellToPosition(Box.Start)

    # World position of the end corner of the region (the corner of the GetEnd cell) (centimeters)
    GetMaxPosition<public>()<transacts>:vector3 =
        Grid.CellToPosition(Box.GetEnd())

    # World position of the center of the region (centimeters)
    GetCenter<public>()<transacts>:vector3 =
        (GetMinPosition() + GetMaxPosition()) / 2.0

    # Length of the region on each axis (centimeters; cells x CellSizeCm)
    GetSize<public>()<transacts>:vector3 =
        GetMaxPosition() - GetMinPosition()

# Role: divides the world into cells (sides of CellSizeCm centimeters) and manages reservations of box-shaped regions. Things that get spawned (cubes, lines, checkpoints, etc.) reserve a region here before being placed and use only the inside of it. Cell 0 is at this entity's position (rotation is not used)
# Placement: attach to an entity in the editor. One per scope (game_scope_component) (one in the world without a scope). Users find it with FindGrid (searches the scope) and remember it
# Notifies: ReleasedEvent when a reservation is released (fires with the released reservation)
grid_component<public> := class<final_super>(component):

    # Side length of one cell (centimeters). Spawned things reserve box-shaped regions of these cells. Default 250
    @editable_number(float):
        ToolTip := GridCellSizeToolTip
        Categories := array{GridCategory}
        MinValue := option{10.0}
        MaxValue := option{5000.0}
    CellSizeCm<public>:float = 250.0

    ReleasedEventInternal<private><final>:event(grid_reservation) = event(grid_reservation){}

    # Fires with the reservation when it is released (by either Release or ReleaseAll. Await / Subscribe; cannot be signaled from outside)
    ReleasedEvent<public><final>:listenable(grid_reservation) = MakeProxyListenable(ReleasedEventInternal)

    var Reservations<private>:[]grid_reservation = array{}

    # World position of the corner of cell 0 (this entity's position; centimeters)
    GetOrigin<public>()<transacts>:vector3 =
        Entity.GetGlobalTranslation()

    # The cell containing a world position (centimeters). The negative side of the origin is also counted with truncation (Floor)
    ToCell<public>(Position:vector3)<transacts>:grid_cell =
        Local := (Position - GetOrigin()) / CellSizeCm
        grid_cell:
            X := Floor[Local.Forward] or 0
            Y := Floor[Local.Left] or 0
            Z := Floor[Local.Up] or 0

    # World position of the cell's starting corner (not the center) (centimeters)
    CellToPosition<public>(Cell:grid_cell)<transacts>:vector3 =
        GetOrigin() + vector3{Forward := Cell.X * CellSizeCm, Left := Cell.Y * CellSizeCm, Up := Cell.Z * CellSizeCm}

    # Succeeds if Box has a valid size (IsValid) and overlaps none of the current reservations (does not reserve)
    IsFree<public>(Box:grid_box)<decides><transacts>:void =
        Box.IsValid[]
        for (Reservation : Reservations):
            not Reservation.Box.Overlaps[Box]

    # Reserves Box if it is free and returns the reservation. false (reserves nothing) when an overlapping reservation exists or an axis of Box has a size of 0 or less
    # It can fail, but returns an option instead of being <decides> so that a failure in the caller does not roll back the reservation side effect
    TryReserve<public>(Box:grid_box)<transacts>:?grid_reservation =
        if (IsFree[Box]):
            Reservation := grid_reservation{Grid := Self, Box := Box}
            set Reservations += array{Reservation}
            option{Reservation}
        else:
            false

    # Number of current (not yet released) reservations
    GetReservationCount<public>()<reads>:int =
        Reservations.Length

    # List of current (not yet released) reservations, in reservation order
    GetReservations<public>()<reads>:[]grid_reservation =
        Reservations

    # Releases every reservation (same as calling Release on each: Released becomes true, it leaves the list and ReleasedEvent fires one by one). The holders (things spawned by a spawner, etc.) do not disappear, so if they stay, other things may be placed overlapping the released region
    ReleaseAll<public>():void =
        for (Reservation : Reservations):
            Reservation.Release()

    Forget<internal>(Reservation:grid_reservation):void =
        set Reservations = for:
            Current : Reservations
            Current <> Reservation
        do:
            Current
        ReleasedEventInternal.Signal(Reservation)

# Finds the grid_component in InEntity's scope (game_scope_component; the world without one). Assumes only one per scope; with several, it is unspecified which one is returned
# Fails if none exists or InEntity is not yet in the world. It searches the scope, so do not call it every frame or every time; remember the result
(InEntity:entity).FindGrid<public>()<decides><transacts>:grid_component =
    InEntity.FindScopedComponent[grid_component]
