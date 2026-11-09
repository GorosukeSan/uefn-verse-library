# SpawnSystem

The System that spawns and despawns entities (prefabs). There are two ways to spawn.
- Keep spawning in bands: keeps a fixed number of entities in a range (band) around reference points (players etc.) and despawns, a few at a time, the ones that fall outside. The central `spawner_component` handles count, range, placement and spawning / despawning; "what to spawn" is decided by the factory on the same entity and "around whom" by the origin on the same entity. Spawn places are reserved from the grid (GridSystem's `grid_component`).
- Spawn at chosen places (PrefabKit): `spawn_prefab_component` spawns any number at chosen places (child `spawn_point_component`s, its own position, or any transform) on an activation signal or from code, counts the spawned items and removes them in bulk. No grid needed. To spawn just one, there is also the `SpawnPrefab` function.

## Setup (placement)

| component | Where to place | What it does |
|---|---|---|
| `spawner_component` | An entity the activation signal reaches (in a game flow, the node's entity or a descendant) | Every `RefillSeconds`, keeps `Count` items per band. Reserves one item's range (`FootprintX` x `FootprintY` x `FootprintZ` cells) from the grid and places the item. Despawns items outside the band `DespawnPerRefill` at a time. Stops and removes everything on the deactivation signal |
| `prefab_spawn_factory_component` (PrefabKit) | Same entity as `spawner_component` | Makes the spawned item `Prefab` |
| `players_origin_component` (OriginKit) | Same entity as `spawner_component` | Uses the surroundings of every participating player as the reference (with a safe zone and a dead zone, so small movements do not trigger a recompute) |
| `spawned_component` | The spawned entity (attached by the spawner at runtime; not placed in the editor) | Marker of a spawned item. Releases the reservation and notifies the spawner when leaving the world |
| `spawn_prefab_component` (PrefabKit) | An entity the activation signal reaches (in a game flow, the node's entity or a descendant). Anywhere if you spawn from code instead of signals | Spawns `SpawnOnActivate` items on the activation signal and removes everything on the deactivation signal (when `DespawnOnDeactivate`). Spawn places are the direct-child `spawn_point_component`s (in `PointOrder` order) or its own position, offset inside a box of `ScatterHalfSizeCm`. `MaxCount` limits how many exist at once. From code: `Spawn` / `TrySpawnAt` / `Despawn` / `DespawnAll` |
| `spawn_point_component` (PrefabKit) | Directly under the entity of a `spawn_prefab_component` | Marks a spawn place (position and rotation). Used by ascending `Order` |
| `prefab_spawned_component` (PrefabKit) | The spawned entity (attached by `spawn_prefab_component` at runtime; not placed in the editor) | Marker of a spawned item. Notifies `spawn_prefab_component` when leaving the world |

A factory (a `spawn_factory_component` subclass) is required, at most one per entity. Nothing is spawned without it. An origin (a `spawn_origin_component` subclass) is optional; without one, the spawner entity's position is the reference. Another factory subclass is CheckpointSystem's `checkpoint_factory_component` (SpawnKit).

Example: "keep spawning footholds around the players"
```
Scope (game_scope_component)
├ Player manager (player_manager_component)
├ Grid (grid_component)
└ Node (game_node_component)
  └ Foothold spawner (spawner_component + prefab_spawn_factory_component + players_origin_component)
    └ (spawned footholds; added as children by the spawner at runtime)
```

Example: "during the main phase, spawn one enemy at each of 3 chosen places, and remove them when the phase ends"
```
Main phase (game_node_component)
└ Enemies (spawn_prefab_component, Prefab = enemy, SpawnOnActivate = 3, PointOrder = InOrder)
  ├ Spawn point 1 (spawn_point_component, Order 0)
  ├ Spawn point 2 (spawn_point_component, Order 1)
  ├ Spawn point 3 (spawn_point_component, Order 2)
  └ (spawned enemies; added as children by spawn_prefab_component at runtime)
```
From code, call `Prefabs.Spawn(5)` (5 at the chosen places), `Prefabs.TrySpawnAt(Transform)` (one at any place), `Prefabs.DespawnAll()` and so on.

## Settings (@editable)
spawner_component (count):
- `spawner_component.Count : int = 20` — number always kept per band (0-200). 0 spawns nothing. When bands merge, the merged band keeps the count of one.
- `spawner_component.RefillSeconds : float = 1.0` — interval at which the count is checked and missing items are added (seconds; 0.1-60).
- `spawner_component.DespawnPerRefill : int = 2` — maximum number of items in no band despawned per refill (1-100).
- `spawner_component.AppearSeconds : float = 0.5` — time over which the scale changes from 0 to full on spawn (full to 0 on despawn) (seconds; 0-5). 0 spawns and despawns instantly.
- `spawner_component.StartOnBegin : logic = false` — when on, runs from the start of the game. When off, starts on the activation signal (`activated_event`) or `Start`.

spawner_component (range; the unit is grid cells):
- `spawner_component.RangeCells : int = 12` — how many cells horizontally from the reference cell, in each of the four directions, the band covers.
- `spawner_component.MinHeightCells : int = 4` — how many cells above the reference cell items are spawned at least (negative also spawns below).
- `spawner_component.MaxHeightCells : int = 32` — upper limit of the band. How many cells above the reference cell items are spawned at most.
- `spawner_component.DespawnBelowCells : int = 0` — lower limit of the band. Items that fall more than this many cells below the reference cell are despawned a few at a time. 0 despawns nothing.
- `spawner_component.RefillDepthCells : int = 8` — when the band already holds half of `Count` or more, new items are spawned within this many cells of the upper limit.
- `spawner_component.MergeGapCells : int = 10` — bands that come within this many cells of each other are merged into one.
- `spawner_component.GapCells : int = 1` — gap reserved around the spawn range (nothing else can enter; 0-20).
- `spawner_component.KeepNearCells : int = 40` — items within this many cells of the origin's keep points (`spawn_origins.KeepPoints`) are not despawned even outside the band. 0 despawns even nearby items.
- `spawner_component.FloorCells : int = -2000` — lowest spawn height (cells from grid cell 0). Nothing is spawned below it.
- `spawner_component.MaxAttempts : int = 8` — maximum number of times a place is re-picked when no reservable range is found (1-50). If still none, nothing is spawned that round.

spawner_component (placement):
- `spawner_component.FootprintX` / `FootprintY` / `FootprintZ : int = 1` — cells one item uses (forward, left, up; 1-50).
- `spawner_component.FitToArea : logic = false` — when on, the item is stretched to fill the reserved range. When off, it keeps its created size and is placed at the center of the range.
- `spawner_component.MeshSizeCm : float = 100.0` — edge length (centimeters) of the mesh at scale 1. Used with `FitToArea` (100 for the engine's basic cube).
- `spawner_component.LevelIntervalCells : int = 0` — if greater than 0, heights are fixed to levels every this many cells (the cell Z is a multiple of it; 0 excluded) and only one item is spawned per level. A level used once is not respawned, even after it disappears, until `ForgetUsedLevels`. 0 makes the height random too.

prefab_spawn_factory_component:
- `prefab_spawn_factory_component.Prefab : concrete_subtype(entity) = entity` — the prefab to spawn. Left at the default, an empty entity is spawned.

spawn_prefab_component:
- `spawn_prefab_component.Prefab : concrete_subtype(entity) = entity` — the prefab to spawn. Left at the default, an empty entity is spawned.
- `spawn_prefab_component.SpawnOnActivate : int = 1` — number spawned each time the activation signal arrives (0-100). 0 spawns nothing on the signal.
- `spawn_prefab_component.MaxCount : int = 0` — maximum number that can exist at once (0-1000). Once reached, nothing more is spawned. 0 means no limit.
- `spawn_prefab_component.PointOrder : spawn_point_order = InOrder` — the order in which the direct-child `spawn_point_component`s are used. `InOrder` (one by one by ascending `Order`, back to the first after the last) or `Random`.
- `spawn_prefab_component.ScatterHalfSizeCm : vector3 = 0` — offset at random inside a box of +/- this length forward, left and up from the spawn place (along the point's rotation axes; an axis set to 0 is not offset).
- `spawn_prefab_component.DespawnOnDeactivate : logic = true` — when on, everything is removed on the deactivation signal.

spawn_point_component:
- `spawn_point_component.Order : int = 0` — the order used when `PointOrder` is `InOrder` (0-1000).

players_origin_component (cells; all 0-400):
- Spawning: `SafeHalfCells = 2` / `SafeHeightCells = 2` (horizontal / vertical half size of the safe zone that moves with the player), `DeadHalfCells = 4` / `DeadHeightCells = 8` (horizontal / vertical half size of the dead zone that stays where it was placed. Make it larger than the safe zone).
- Despawning: `DespawnSafeHalfCells = 8` / `DespawnSafeHeightCells = 8`, `DespawnDeadHalfCells = 16` / `DespawnDeadHeightCells = 40` (make them larger than the spawning ones).
- Only when the safe zone sticks out of the dead zone is the dead zone placed again at the player's position. The reference point is the center of the dead zone. The keep points are the players' current positions.

## Events
- `spawned_event` (scene_event, SendDown from the spawner's entity; spawned items are children of the spawner, so they receive it too): `Spawner : spawner_component`, `Spawned : entity`, `Area : spawn_area`. After one item is spawned and placed. Not consumed.
- `despawned_event` (scene_event, SendDown from the spawner's entity): `Spawner : spawner_component`, `Spawned : entity`. When a spawned item leaves the world (shrank away, `ClearAll`, stop). Not consumed.
- `spawner_component.SpawnedEvent : listenable(entity)` — delivered with the spawned entity after one item is spawned and placed (same timing as `spawned_event`).
- `spawner_component.DespawnedEvent : listenable(entity)` — delivered with the entity when a spawned item leaves the world (same timing as `despawned_event`).
- `spawn_prefab_component.SpawnedEvent : listenable(entity)` — delivered with the spawned entity after one item is spawned and placed.
- `spawn_prefab_component.DespawnedEvent : listenable(entity)` — delivered with the entity when a spawned item leaves the world (`Despawn`, `DespawnAll`, the deactivation signal, removed by other code).
- Received: `spawner_component` receives `activated_event` (same as `Start`) and `deactivated_event` (same as `Stop`). `spawn_prefab_component` receives `activated_event` (`Spawn(SpawnOnActivate)`) and `deactivated_event` (`DespawnAll` when `DespawnOnDeactivate`).

## Public API
```verse
# Function version (SpawnSystem). Creates Prefab as a child of Parent and places it at the world Transform. No counting, no bulk removal
(Parent:entity).SpawnPrefab<public>(Prefab:concrete_subtype(entity), Transform:transform):entity

spawner_component<public> := class<final_super>(component):
    Count<public>:int
    RefillSeconds<public>:float
    DespawnPerRefill<public>:int
    AppearSeconds<public>:float
    StartOnBegin<public>:logic
    RangeCells<public>:int
    MinHeightCells<public>:int
    MaxHeightCells<public>:int
    DespawnBelowCells<public>:int
    RefillDepthCells<public>:int
    MergeGapCells<public>:int
    GapCells<public>:int
    KeepNearCells<public>:int
    FloorCells<public>:int
    MaxAttempts<public>:int
    FootprintX<public>:int
    FootprintY<public>:int
    FootprintZ<public>:int
    FitToArea<public>:logic
    MeshSizeCm<public>:float
    LevelIntervalCells<public>:int
    SpawnedEvent<public><final>:listenable(entity)
    DespawnedEvent<public><final>:listenable(entity)
    Start<public>():void                                # Does nothing if running
    Stop<public>():void                                 # Stops and removes every spawned item right away
    IsRunning<public>()<decides><reads>:void
    GetSpawned<public>()<reads>:[]spawned_component     # Direct children only. Excludes items that started disappearing. Order is undefined
    GetSpawnedCount<public>()<reads>:int
    IsLevelUsed<public>(Level:int)<decides><reads>:void # Succeeds if the level (height cell / LevelIntervalCells) has been spawned on
    ForgetUsedLevels<public>():void                     # Forgets every used level
    GetFootprint<public>()<transacts>:grid_cell         # FootprintX/Y/Z (less than 1 becomes 1)
    PickStartCell<public>(Band:spawn_band, Low:int, High:int)<decides><transacts>:grid_cell   # Picks the start cell of one item's range
    RefillNow<public>():void                            # One refill right now, only while running
    ClearAll<public>():void                             # Removes everything right away. While running, the next refill spawns again

# Base of what to spawn. Subclasses write only CreateSpawned
spawn_factory_component<public> := class<abstract><final_super>(component):
    CreateSpawned<public>(Area:spawn_area):entity       # Not yet in the world. The spawner places it

# Points a spawn_origin_component returns on each refill (world position, cm)
spawn_origins<public> := struct:
    SpawnPoints<public>:[]vector3                       # If empty, the spawner does nothing that round
    DespawnPoints<public>:[]vector3                     # If empty, SpawnPoints is used
    KeepPoints<public>:[]vector3                        # Nothing within KeepNearCells of these is despawned

# Base of around whom to spawn. Subclasses write only UpdateOrigins
spawn_origin_component<public> := class<abstract><final_super>(component):
    UpdateOrigins<public>()<transacts>:spawn_origins    # Called once per refill. The subclass may update its state here

spawn_band<public> := struct<computes>:
    CenterX<public>:int
    CenterY<public>:int
    HalfX<public>:int
    HalfY<public>:int
    Bottom<public>:int                                  # Items that fall below this are despawned
    SpawnBottom<public>:int                             # Lowest height for new items
    Top<public>:int

spawn_area<public> := class:
    Grid<public>:grid_component
    Inner<public>:grid_box                              # Usable range (cells)
    Reservation<public>:grid_reservation                # Reservation including the GapCells gap
    GetMinPosition<public>()<transacts>:vector3
    GetMaxPosition<public>()<transacts>:vector3
    GetCenter<public>()<transacts>:vector3
    GetSize<public>()<transacts>:vector3
    MakeFitTransform<public>(MeshSizeCm:float)<transacts>:transform   # Transform at the center, stretched to fill the range

spawned_component<public> := class<final_super>(component):
    Spawner<public>:spawner_component
    Area<public>:spawn_area
    var<private> Leaving<public>:logic
    Leave<public>(Seconds:float):void                   # Shrinks, then removes. Returns right away. Does nothing the second time and later
    IsLeaving<public>()<decides><reads>:void

spawned_event<public> := class(scene_event):
    Spawner<public>:spawner_component
    Spawned<public>:entity
    Area<public>:spawn_area

despawned_event<public> := class(scene_event):
    Spawner<public>:spawner_component
    Spawned<public>:entity

# PrefabKit
prefab_spawn_factory_component<public> := class<final_super>(spawn_factory_component):
    Prefab<public>:concrete_subtype(entity)

spawn_point_order<public> := enum:
    InOrder     # One by one by ascending Order, back to the first after the last
    Random      # Random each time

spawn_prefab_component<public> := class<final_super>(component):
    Prefab<public>:concrete_subtype(entity)
    SpawnOnActivate<public>:int
    MaxCount<public>:int
    PointOrder<public>:spawn_point_order
    ScatterHalfSizeCm<public>:vector3
    DespawnOnDeactivate<public>:logic
    SpawnedEvent<public><final>:listenable(entity)
    DespawnedEvent<public><final>:listenable(entity)
    Spawn<public>(Count:int):[]entity                   # Count items at the chosen places. Stops when MaxCount is reached
    TrySpawnAt<public>(Transform:transform):?entity     # One at any place. False when MaxCount is reached
    Despawn<public>(Spawned:entity):void                # Removes only items it spawned itself
    DespawnAll<public>():void
    GetSpawned<public>()<reads>:[]entity                # Direct children only. Excludes items being removed. Order is undefined
    GetSpawnedCount<public>()<reads>:int
    IsFull<public>()<decides><reads>:void               # Succeeds when MaxCount > 0 and reached
    GetSpawnPoints<public>()<transacts>:[]spawn_point_component   # Direct children only. By ascending Order

spawn_point_component<public> := class<final_super>(component):
    Order<public>:int

prefab_spawned_component<public> := class<final_super>(component):
    Source<public>:spawn_prefab_component
    IsLeaving<public>()<decides><reads>:void

# OriginKit
players_origin_component<public> := class<final_super>(spawn_origin_component):
    SafeHalfCells<public>:int
    SafeHeightCells<public>:int
    DeadHalfCells<public>:int
    DeadHeightCells<public>:int
    DespawnSafeHalfCells<public>:int
    DespawnSafeHeightCells<public>:int
    DespawnDeadHalfCells<public>:int
    DespawnDeadHeightCells<public>:int
```

## Requirements, caveats and limits
- One `grid_component` is needed in the scope (`game_scope_component`; the world if there is none). Nothing is spawned without it (looked up on every refill until found, then remembered).
- `players_origin_component` also needs a `player_manager_component` in the scope. Without a grid, one cell is taken as 250 cm. When there is no player (no position available), no points are returned and the spawner does nothing that round.
- Bands are rebuilt only when the reference points change. Bands overlapping within `MergeGapCells` merge into one, and the merged band keeps one `Count`.
- The scale change on spawn and despawn calls `SetGlobalTransform` every frame. When spawning an entity moved by `keyframed_movement_component` (MoverSystem's Keyframe etc.), set `AppearSeconds` to 0.
- The despawn order is undefined. Reservations of removed items are returned to the grid.
- `spawn_prefab_component` does not use the grid (no overlap check). Spawned items are children of this entity, so moving this entity moves them too. They are placed with scale 1 (the scale of the point entity is not used).
- Each activation signal to `spawn_prefab_component` adds `SpawnOnActivate` items (no rebuild. With `DespawnOnDeactivate` on, the deactivation signal removes them, so entering the node again spawns anew). Everything is always removed at the end of the simulation.
- `Despawn` / `DespawnAll` drop items from the count right away (a `Spawn` in the same frame does not count them toward the limit). There is no shrink effect.
- No experimental API is used.

## Verifying
- Test: `spawn_system_test_component` in `_Test/SpawnSystemTest/`. Just attach it to an entity with nothing within 10 meters (the test creates the scope, grid, spawner and spawn_prefab_component as its own children; no player needed). It checks that `Count` items are spawned and kept on activation, the band and reservation counts, the spawn / despawn notifications, `RefillNow`, `ClearAll` / `Stop`, the activation / deactivation signals, then `spawn_prefab_component` (the `Order` of `spawn_point_component`s, `SpawnOnActivate` items on the activation signal, `MaxCount`, `TrySpawnAt`, `Despawn` / `DespawnAll` and their notifications, the deactivation signal) and the `SpawnPrefab` function. Takes about 3 seconds. Results are in the output log under `[TEST] SpawnSystem`.
- There is no SpawnSystem sample in `_Samples/`. CheckpointSystem's `checkpoint_factory_component` is an example of a factory subclass.

## Migration notes (2026-11-08)
- `spawn_prefab_component` moved from GameSequenceSystem's FeatureKit to SpawnSystem's PrefabKit. `using { GameSequenceSystem.FeatureKit }` -> `using { SpawnSystem.PrefabKit }`. Instances placed in the editor need to be placed again because the module changed (⚠ Unverified: how UEFN shows the old component).
- `Spawn():void` (rebuild one) -> `Spawn(Count:int):[]entity` (add). `Despawn():void` -> `DespawnAll()` (`Despawn(Spawned)` removes just one). `FindSpawned[]` -> `GetSpawned()`.
- The ToolTips `SpawnCategory` / `SpawnPrefabToolTip` (GameSequenceSystem.TooltipKit) became `SpawnPrefabCategory` / `SpawnPrefabToolTip` etc. in SpawnSystem.TooltipKit.
