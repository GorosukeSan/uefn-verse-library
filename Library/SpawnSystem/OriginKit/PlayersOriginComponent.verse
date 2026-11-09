using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { GridSystem }
using { MovementSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { SpawnSystem }
using { SpawnSystem.TooltipKit }

# Role: for every participating player, makes the center of a dead zone the spawner's reference point. The dead zone is a box of +/- DeadHalfCells horizontally and +/- DeadHeightCells vertically centered on the player's position, and it stays where it was placed. Only when the safe zone that moves with the player (+/- SafeHalfCells horizontally, +/- SafeHeightCells vertically) sticks out of that dead zone is it placed again at the player's position (the reference point does not change while the player moves up and down a little, so the spawner does not recompute). Kept separately for spawning (SpawnPoints, narrow) and despawning (DespawnPoints, the Despawn... values, wide). Dead zones nobody uses are dropped. When there is no player (no position available), no points are returned and the spawner does nothing that round. The keep points (KeepPoints) are the players' current positions
# Placement: attach to an entity in the editor
# Same entity: spawner_component
# Requirements: one player_manager_component and one grid_component in the scope (game_scope_component; the world if there is none) (without a grid, one cell is taken as 250 centimeters). Both are remembered once found and not looked up every time
players_origin_component<public> := class<final_super>(spawn_origin_component):

    # Spawning: horizontal half width (cells) of the safe zone that moves with the player. Default 2
    @editable_number(int):
        ToolTip := OriginSafeHalfCellsToolTip
        Categories := array{SpawnerCategory, OriginZoneCategory}
        MinValue := option{0}
        MaxValue := option{400}
    SafeHalfCells<public>:int = 2
    # Spawning: vertical half height (cells) of the safe zone. Default 2
    @editable_number(int):
        ToolTip := OriginSafeHeightCellsToolTip
        Categories := array{SpawnerCategory, OriginZoneCategory}
        MinValue := option{0}
        MaxValue := option{400}
    SafeHeightCells<public>:int = 2
    # Spawning: horizontal half width (cells) of the dead zone (a box that stays where it was placed). Make it wider than the safe zone. Default 4
    @editable_number(int):
        ToolTip := OriginDeadHalfCellsToolTip
        Categories := array{SpawnerCategory, OriginZoneCategory}
        MinValue := option{0}
        MaxValue := option{400}
    DeadHalfCells<public>:int = 4
    # Spawning: vertical half height (cells) of the dead zone. Make it taller than the safe zone. Default 8
    @editable_number(int):
        ToolTip := OriginDeadHeightCellsToolTip
        Categories := array{SpawnerCategory, OriginZoneCategory}
        MinValue := option{0}
        MaxValue := option{400}
    DeadHeightCells<public>:int = 8
    # Despawning: horizontal half width (cells) of the safe zone. Make it wider than the spawning one. Default 8
    @editable_number(int):
        ToolTip := OriginDespawnSafeHalfCellsToolTip
        Categories := array{SpawnerCategory, OriginDespawnZoneCategory}
        MinValue := option{0}
        MaxValue := option{400}
    DespawnSafeHalfCells<public>:int = 8
    # Despawning: vertical half height (cells) of the safe zone. Make it taller than the spawning one. Default 8
    @editable_number(int):
        ToolTip := OriginDespawnSafeHeightCellsToolTip
        Categories := array{SpawnerCategory, OriginDespawnZoneCategory}
        MinValue := option{0}
        MaxValue := option{400}
    DespawnSafeHeightCells<public>:int = 8
    # Despawning: horizontal half width (cells) of the dead zone. Default 16
    @editable_number(int):
        ToolTip := OriginDespawnDeadHalfCellsToolTip
        Categories := array{SpawnerCategory, OriginDespawnZoneCategory}
        MinValue := option{0}
        MaxValue := option{400}
    DespawnDeadHalfCells<public>:int = 16
    # Despawning: vertical half height (cells) of the dead zone. Default 40
    @editable_number(int):
        ToolTip := OriginDespawnDeadHeightCellsToolTip
        Categories := array{SpawnerCategory, OriginDespawnZoneCategory}
        MinValue := option{0}
        MaxValue := option{400}
    DespawnDeadHeightCells<public>:int = 40

    DefaultCellSize<private>:float = 250.0

    var Manager<private>:?player_manager_component = false
    var Grid<private>:?grid_component = false
    var SpawnAnchors<private>:[]vector3 = array{}
    var DespawnAnchors<private>:[]vector3 = array{}

    # Re-places the spawning and despawning dead zones from the players' current positions and returns them (re-placed only when the safe zone sticks out). The keep points are the players' current positions
    UpdateOrigins<override>()<transacts>:spawn_origins =
        Positions := GetPlayerPositions()
        set SpawnAnchors = UpdateAnchors(Positions, SpawnAnchors, DeadHalfCells - SafeHalfCells, DeadHeightCells - SafeHeightCells)
        set DespawnAnchors = UpdateAnchors(Positions, DespawnAnchors, DespawnDeadHalfCells - DespawnSafeHalfCells, DespawnDeadHeightCells - DespawnSafeHeightCells)
        spawn_origins{SpawnPoints := SpawnAnchors, DespawnPoints := DespawnAnchors, KeepPoints := Positions}

    UpdateAnchors<private>(Positions:[]vector3, Current:[]vector3, HalfRoomCells:int, HeightRoomCells:int)<transacts>:[]vector3 =
        CellSize := if (Found := GetGrid()?) then Found.CellSizeCm else DefaultCellSize
        HalfRoom := HalfRoomCells * CellSize
        HeightRoom := HeightRoomCells * CellSize
        var Kept:[]vector3 = array{}
        for (Position : Positions):
            Anchor := if (Found := FindInside[Current, Position, HalfRoom, HeightRoom]) then Found else Position
            if (not Contains[Kept, Anchor]):
                set Kept += array{Anchor}
        Kept

    FindInside<private>(Anchors:[]vector3, Position:vector3, HalfRoom:float, HeightRoom:float)<decides><transacts>:vector3 =
        first:
            Anchor : Anchors
            Abs(Position.Forward - Anchor.Forward) <= HalfRoom
            Abs(Position.Left - Anchor.Left) <= HalfRoom
            Abs(Position.Up - Anchor.Up) <= HeightRoom
        do:
            Anchor

    Contains<private>(Points:[]vector3, Point:vector3)<decides><computes>:void =
        first (Current : Points, Current = Point):
            Current

    GetPlayerPositions<private>()<transacts>:[]vector3 =
        if (Found := GetManager()?):
            for:
                Slot : Found.GetSlots()
                Position := Slot.Player.GetFortCharacter[].FindGlobalTranslation[]
            do:
                Position
        else:
            array{}

    # Finds and remembers the scope's player_manager_component (no lookup once remembered). False if not found
    GetManager<private>()<transacts>:?player_manager_component =
        set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)
        Manager

    # Finds and remembers the scope's grid_component (no lookup once remembered; searches the scope like FindGrid). False if not found
    GetGrid<private>()<transacts>:?grid_component =
        set Grid = Entity.ResolveScopedComponent(Grid, grid_component)
        Grid
