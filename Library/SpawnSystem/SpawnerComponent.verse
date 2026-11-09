using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Random }
using { ActivationSystem }
using { GridSystem }
using { SceneGraphSystem }
using { SpawnSystem.TooltipKit }

# Role: while running, every RefillSeconds keeps Count entities, created by the spawn_factory_component subclass on the same entity, in the band around each reference point (the points the spawn_origin_component subclass on the same entity returns from UpdateOrigins; this entity's position if there is none). The factory decides the content (what to spawn), the origin decides the reference (around whom), and this component handles only count, range and spawning / despawning
# Band: per point, +/- RangeCells cells horizontally; vertically from DespawnBelowCells below the point's cell (lower limit) to MaxHeightCells above it (upper limit). New items go between MinHeightCells above and the upper limit (never below the grid height FloorCells), and when the band already holds half of Count or more, within RefillDepthCells of the upper limit. Bands are rebuilt only when the points change. Bands overlapping within MergeGapCells are merged into one (a merged band keeps the Count of one)
# Despawn: items in no band (built from the origin's DespawnPoints) are despawned DespawnPerRefill at a time (never when DespawnBelowCells is 0; items within KeepNearCells of the origin's KeepPoints are not despawned; the order is undefined)
# Placement of items: one item's range (cells) is FootprintX x FootprintY x FootprintZ (height random when LevelIntervalCells is 0, one per level when greater than 0). A gap of GapCells (nobody can reserve it) is added around it and the whole is reserved from the scope's grid_component. If it cannot be reserved, re-picked up to MaxAttempts times; if still not, nothing is spawned that round. The spawned entity becomes a child of this entity with spawned_component attached, stretched to fill the range when FitToArea, otherwise placed at the center of the range. On spawn the scale goes from 0 to full over AppearSeconds, on despawn from full to 0 before removal. Reservations of removed items are released
# When: from the start if StartOnBegin. Starts on the activation signal (activated_event) or Start, stops and removes everything on the deactivation signal (deactivated_event) or Stop
# Placement: attach to an entity in the editor
# Parent: wherever the activation signal reaches (in a game flow, the node's entity or a descendant)
# Same entity: one spawn_factory_component subclass (required; nothing is spawned without it). One spawn_origin_component subclass to change the reference
# Notifies: spawned_event and SpawnedEvent on spawn, despawned_event and DespawnedEvent on leaving (scene events are SendDown from this entity)
# From outside: Start / Stop / RefillNow / ClearAll, GetSpawned / GetSpawnedCount / IsRunning
# Requirements: one grid_component in the scope (game_scope_component; the world if there is none) (nothing is spawned without it; looked up on every refill until found, then remembered)
spawner_component<public> := class<final_super>(component):

    # Number always kept per band. 0 spawns nothing. Default 20
    @editable_number(int):
        ToolTip := SpawnerCountToolTip
        Categories := array{SpawnerCategory, SpawnerCountCategory}
        MinValue := option{0}
        MaxValue := option{200}
    Count<public>:int = 20
    # Interval (seconds) at which the count is checked and missing items are added. Default 1.0
    @editable_number(float):
        ToolTip := SpawnerRefillSecondsToolTip
        Categories := array{SpawnerCategory, SpawnerCountCategory}
        MinValue := option{0.1}
        MaxValue := option{60.0}
    RefillSeconds<public>:float = 1.0
    # Maximum number of items in no band despawned per refill. Default 2
    @editable_number(int):
        ToolTip := SpawnerDespawnPerRefillToolTip
        Categories := array{SpawnerCategory, SpawnerCountCategory}
        MinValue := option{1}
        MaxValue := option{100}
    DespawnPerRefill<public>:int = 2
    # Time (seconds) over which the scale changes on spawn and despawn. 0 spawns and despawns instantly. Default 0.5
    @editable_number(float):
        ToolTip := SpawnerAppearSecondsToolTip
        Categories := array{SpawnerCategory, SpawnerCountCategory}
        MinValue := option{0.0}
        MaxValue := option{5.0}
    AppearSeconds<public>:float = 0.5
    # When on, runs from the start of the game. When off, starts on the activation signal (activated_event) or Start. Default off
    @editable:
        ToolTip := SpawnerStartOnBeginToolTip
        Categories := array{SpawnerCategory, SpawnerCountCategory}
    StartOnBegin<public>:logic = false
    # How many cells horizontally from the reference cell, in each of the four directions, the band covers. Default 12
    @editable_number(int):
        ToolTip := SpawnerRangeCellsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{0}
        MaxValue := option{400}
    RangeCells<public>:int = 12
    # How many cells above the reference cell items are spawned at least (negative also spawns below). Default 4
    @editable_number(int):
        ToolTip := SpawnerMinHeightCellsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{-2000}
        MaxValue := option{2000}
    MinHeightCells<public>:int = 4
    # Upper limit of the band. How many cells above the reference cell items are spawned at most. Default 32
    @editable_number(int):
        ToolTip := SpawnerMaxHeightCellsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{0}
        MaxValue := option{2000}
    MaxHeightCells<public>:int = 32
    # Lower limit of the band. Items that fall more than this many cells below the reference cell are despawned a few at a time. 0 despawns nothing (default)
    @editable_number(int):
        ToolTip := SpawnerDespawnBelowCellsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{0}
        MaxValue := option{2000}
    DespawnBelowCells<public>:int = 0
    # When the band already holds half of Count or more, new items are spawned within this many cells of the upper limit. Default 8
    @editable_number(int):
        ToolTip := SpawnerRefillDepthCellsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{1}
        MaxValue := option{500}
    RefillDepthCells<public>:int = 8
    # Bands that come within this many cells of each other are merged into one. Default 10
    @editable_number(int):
        ToolTip := SpawnerMergeGapCellsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{0}
        MaxValue := option{500}
    MergeGapCells<public>:int = 10
    # Cells of gap reserved around the spawn range (nothing else can enter). Default 1
    @editable_number(int):
        ToolTip := SpawnerGapCellsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{0}
        MaxValue := option{20}
    GapCells<public>:int = 1
    # Items within this many cells of a keep point (KeepPoints from the result of UpdateOrigins) are not despawned even outside the band. 0 despawns even nearby items. Default 40
    @editable_number(int):
        ToolTip := SpawnerKeepNearCellsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{0}
        MaxValue := option{400}
    KeepNearCells<public>:int = 40
    # Lowest spawn height (cells from grid cell 0). Nothing is spawned below it. Default -2000
    @editable_number(int):
        ToolTip := SpawnerFloorCellsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{-2000}
        MaxValue := option{2000}
    FloorCells<public>:int = -2000
    # Maximum number of times a place is re-picked when no reservable range is found. If still none, nothing is spawned that round. Default 8
    @editable_number(int):
        ToolTip := SpawnerMaxAttemptsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{1}
        MaxValue := option{50}
    MaxAttempts<public>:int = 8
    # Cells one item uses forward (X). Default 1
    @editable_number(int):
        ToolTip := SpawnerFootprintToolTip
        Categories := array{SpawnerCategory, SpawnerPlaceCategory}
        MinValue := option{1}
        MaxValue := option{50}
    FootprintX<public>:int = 1
    # Cells one item uses to the left (Y). Default 1
    @editable_number(int):
        ToolTip := SpawnerFootprintToolTip
        Categories := array{SpawnerCategory, SpawnerPlaceCategory}
        MinValue := option{1}
        MaxValue := option{50}
    FootprintY<public>:int = 1
    # Cells one item uses upward (Z). Default 1
    @editable_number(int):
        ToolTip := SpawnerFootprintToolTip
        Categories := array{SpawnerCategory, SpawnerPlaceCategory}
        MinValue := option{1}
        MaxValue := option{50}
    FootprintZ<public>:int = 1
    # When on, the item is stretched to fill the reserved range. When off, it keeps its created size and is placed at the center of the range. Default off
    @editable:
        ToolTip := SpawnerFitToAreaToolTip
        Categories := array{SpawnerCategory, SpawnerPlaceCategory}
    FitToArea<public>:logic = false
    # Edge length (centimeters) of the mesh at scale 1. Used with FitToArea. Default 100 (the engine's basic cube)
    @editable_number(float):
        ToolTip := SpawnerMeshSizeToolTip
        Categories := array{SpawnerCategory, SpawnerPlaceCategory}
        MinValue := option{1.0}
        MaxValue := option{10000.0}
    MeshSizeCm<public>:float = 100.0
    # If greater than 0, heights are fixed to levels every this many cells (the cell Z is a multiple of it; 0 excluded) and only one item is spawned per level (a level used once is not respawned, even after it disappears, until ForgetUsedLevels). 0 makes the height random too. Default 0
    @editable_number(int):
        ToolTip := SpawnerLevelIntervalToolTip
        Categories := array{SpawnerCategory, SpawnerPlaceCategory}
        MinValue := option{0}
        MaxValue := option{1000}
    LevelIntervalCells<public>:int = 0

    LowestCell<private>:int = -1000000

    SpawnedEventInternal<private><final>:event(entity) = event(entity){}

    # Delivered with the spawned entity after one item is spawned and placed (same timing as spawned_event. Await / Subscribe to it; it cannot be Signaled from outside)
    SpawnedEvent<public><final>:listenable(entity) = MakeProxyListenable(SpawnedEventInternal)

    DespawnedEventInternal<private><final>:event(entity) = event(entity){}

    # Delivered with the entity when a spawned item leaves the world (shrank away, ClearAll, stop. Same timing as despawned_event. Await / Subscribe to it; it cannot be Signaled from outside)
    DespawnedEvent<public><final>:listenable(entity) = MakeProxyListenable(DespawnedEventInternal)

    var LastPoints<private>:[]vector3 = array{}
    var LastBands<private>:[]spawn_band = array{}
    var LastDespawnPoints<private>:[]vector3 = array{}
    var LastDespawnBands<private>:[]spawn_band = array{}
    var CachedGrid<private>:?grid_component = false
    var UsedLevels<private>:[int]logic = map{}

    StartEvent<private>:event() = event(){}
    StopEvent<private>:event() = event(){}

    var Running<private>:logic = false
    var WantRunning<private>:logic = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (StartOnBegin?):
            set WantRunning = true

    OnSimulate<override>()<suspends>:void =
        loop:
            if (not WantRunning?):
                StartEvent.Await()
            set Running = true
            race:
                KeepFilled()
                StopEvent.Await()
            set Running = false

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Start()
        else if (deactivated_event[SceneEvent]):
            Stop()
        false

    OnEndSimulation<override>():void =
        Clear()
        (super:)OnEndSimulation()

    # Start running (same as the activation signal). Does nothing if already running
    Start<public>():void =
        if (not WantRunning?):
            set WantRunning = true
            StartEvent.Signal()

    # Stop and remove every spawned item right away (same as the deactivation signal). Spawned items are removed even if already stopped
    Stop<public>():void =
        set WantRunning = false
        set Running = false
        StopEvent.Signal()
        Clear()

    # Succeeds if running
    IsRunning<public>()<decides><reads>:void =
        Running?

    # Items currently spawned (excluding those that started disappearing). Counts only the direct children of this entity. Order is undefined
    GetSpawned<public>()<reads>:[]spawned_component =
        for (Marker : Entity.GetChildComponents(spawned_component), not Marker.Leaving?):
            Marker

    # Number of items currently spawned (the count of GetSpawned)
    GetSpawnedCount<public>()<reads>:int =
        GetSpawned().Length

    # Succeeds if the level (when LevelIntervalCells is used; height cell / LevelIntervalCells) has already been spawned on
    IsLevelUsed<public>(Level:int)<decides><reads>:void =
        UsedLevels[Level]?

    # Forget every used level (from the next refill, the same levels are spawned on again)
    ForgetUsedLevels<public>():void =
        set UsedLevels = map{}

    # Cells one item uses (FootprintX/Y/Z; less than 1 becomes 1)
    GetFootprint<public>()<transacts>:grid_cell =
        grid_cell{X := Max(FootprintX, 1), Y := Max(FootprintY, 1), Z := Max(FootprintZ, 1)}

    # Picks the start cell (the corner on the small side) of one item's range inside Band. Height is Low to High (an unused level within it when LevelIntervalCells is greater than 0). Fails if none can be picked
    PickStartCell<public>(Band:spawn_band, Low:int, High:int)<decides><transacts>:grid_cell =
        Footprint := GetFootprint()
        Height := PickHeight[Footprint, Low, High]
        grid_cell:
            X := Band.CenterX + GetRandomInt(-Band.HalfX, Band.HalfX) - (Quotient[Footprint.X, 2] or 0)
            Y := Band.CenterY + GetRandomInt(-Band.HalfY, Band.HalfY) - (Quotient[Footprint.Y, 2] or 0)
            Z := Height

    # While running, does one refill right now without waiting for the next (rebuild bands, despawn DespawnPerRefill items outside, add missing items; same as a regular refill). The regular refill interval is unchanged. Does nothing while stopped
    RefillNow<public>():void =
        if (Running?):
            RefillOnce()

    # Remove every spawned item right now (no shrink effect; reservations are released as items go). Same removal as on stop. While running, the next refill spawns again (use Stop to stop)
    ClearAll<public>():void =
        Clear()

    # Builds a band per point in Points and returns them with bands overlapping within MergeGapCells merged into one (calculation used inside the spawner)
    GetBands<internal>(Grid:grid_component, Points:[]vector3)<transacts>:[]spawn_band =
        Bands := for (Point : Points):
            MakeBand(Grid.ToCell(Point))
        MergeBands(Bands, MergeGapCells)

    # Called by spawned_component when it leaves the world
    NotifyDespawned<internal>(Spawned:entity):void =
        DespawnedEventInternal.Signal(Spawned)
        Entity.SendDown(despawned_event{Spawner := Self, Spawned := Spawned})

    KeepFilled<private>()<suspends>:void =
        set LastPoints = array{}
        set LastBands = array{}
        set LastDespawnPoints = array{}
        set LastDespawnBands = array{}
        loop:
            RefillOnce()
            Sleep(RefillSeconds)

    RefillOnce<private>():void =
        if (Grid := GetGrid()?, Factory := Entity.GetComponent[spawn_factory_component], Origins := GetOrigins()?):
            Points := Origins.SpawnPoints
            if (not IsSamePoints[Points, LastPoints] or LastBands.Length = 0):
                set LastPoints = Points
                set LastBands = GetBands(Grid, Points)
            DespawnPoints := if (Origins.DespawnPoints.Length > 0) then Origins.DespawnPoints else Points
            if (not IsSamePoints[DespawnPoints, LastDespawnPoints] or LastDespawnBands.Length = 0):
                set LastDespawnPoints = DespawnPoints
                set LastDespawnBands = GetBands(Grid, DespawnPoints)
            KeepCells := for (Point : Origins.KeepPoints):
                Grid.ToCell(Point)
            RemoveOutside(LastDespawnBands, KeepCells)
            for (Band : LastBands):
                Fill(Grid, Factory, Band)

    GetGrid<private>()<transacts>:?grid_component =
        if (Grid := CachedGrid?):
            option{Grid}
        else if (Found := Entity.FindGrid[]):
            set CachedGrid = option{Found}
            option{Found}
        else:
            false

    IsSamePoints<private>(Points:[]vector3, Others:[]vector3)<decides><computes>:void =
        Points.Length = Others.Length
        for (Index -> Point : Points):
            Others[Index] = Point

    MakeBand<private>(Cell:grid_cell)<computes>:spawn_band =
        spawn_band:
            CenterX := Cell.X
            CenterY := Cell.Y
            HalfX := RangeCells
            HalfY := RangeCells
            Bottom := if (DespawnBelowCells > 0) then Cell.Z - DespawnBelowCells else LowestCell
            SpawnBottom := Max(Cell.Z + MinHeightCells, FloorCells)
            Top := Cell.Z + MaxHeightCells

    Fill<private>(Grid:grid_component, Factory:spawn_factory_component, Band:spawn_band):void =
        if (Band.SpawnBottom > Band.Top):
            return
        Inside := CountInside(Band)
        var Missing:int = Count - Inside
        Low := if (Inside * 2 >= Count) then Max(Band.SpawnBottom, Band.Top - RefillDepthCells) else Band.SpawnBottom
        loop:
            if (Missing <= 0):
                break
            SpawnOne(Grid, Factory, Band, Low)
            set Missing -= 1

    CountInside<private>(Band:spawn_band)<reads>:int =
        Inside := for (Marker : GetSpawned(), Band.Contains[Marker.Area.Inner]):
            Marker
        Inside.Length

    SpawnOne<private>(Grid:grid_component, Factory:spawn_factory_component, Band:spawn_band, Low:int):void =
        if (Area := ReserveArea[Grid, Band, Low]):
            Spawned := Factory.CreateSpawned(Area)
            Spawned.AddComponents(array{spawned_component{Entity := Spawned, Spawner := Self, Area := Area}})
            Entity.AddEntities(array{Spawned})
            PlaceSpawned(Spawned, Area)
            if (LevelIntervalCells > 0, Level := Quotient[Area.Inner.Start.Z, LevelIntervalCells], set UsedLevels[Level] = true) {}
            if (AppearSeconds > 0.0):
                spawn{Spawned.GrowIn(AppearSeconds, TickEvents.PrePhysics)}
            Entity.SendDown(spawned_event{Spawner := Self, Spawned := Spawned, Area := Area})
            SpawnedEventInternal.Signal(Spawned)

    ReserveArea<private>(Grid:grid_component, Band:spawn_band, Low:int)<decides><transacts>:spawn_area =
        var Found:?spawn_area = false
        var Attempt:int = 0
        loop:
            if (Found? or Attempt >= MaxAttempts):
                break
            set Attempt += 1
            if:
                StartCell := PickStartCell[Band, Low, Band.Top]
                Inner := MakeGridBox(StartCell, GetFootprint())
                Reservation := Grid.TryReserve(Inner.Expand(GapCells))?
            then:
                set Found = option{spawn_area{Grid := Grid, Inner := Inner, Reservation := Reservation}}
        Found?

    RemoveOutside<private>(Bands:[]spawn_band, KeepCells:[]grid_cell):void =
        if (DespawnBelowCells > 0):
            var Left:int = DespawnPerRefill
            for (Marker : GetSpawned()):
                if (Left > 0, not IsInAnyBand[Marker.Area.Inner, Bands], not IsNearAny[Marker.Area.Inner, KeepCells]):
                    Marker.Leave(AppearSeconds)
                    set Left -= 1

    IsNearAny<private>(Box:grid_box, Cells:[]grid_cell)<decides><computes>:void =
        first (Cell : Cells, Box.GetDistanceSquared(Cell) <= KeepNearCells * KeepNearCells):
            Cell

    IsInAnyBand<private>(Box:grid_box, Bands:[]spawn_band)<decides><computes>:void =
        first (Current : Bands, Current.Contains[Box]):
            Current

    Clear<private>():void =
        for (Marker : Entity.GetChildComponents(spawned_component)):
            Marker.Entity.RemoveFromParent()

    # This round's reference points. With an origin, its UpdateOrigins (false if the spawn points are empty); without one, this entity's position as a single point
    GetOrigins<private>()<transacts>:?spawn_origins =
        if (Source := Entity.GetComponent[spawn_origin_component]):
            Origins := Source.UpdateOrigins()
            if (Origins.SpawnPoints.Length > 0) then option{Origins} else false
        else:
            Here := Entity.GetGlobalTranslation()
            option{spawn_origins{SpawnPoints := array{Here}}}

    # Picks the height (cell Z). An unused level between Low and High when LevelIntervalCells is greater than 0, otherwise random
    PickHeight<private>(Footprint:grid_cell, Low:int, High:int)<decides><transacts>:int =
        if (LevelIntervalCells > 0):
            Interval := LevelIntervalCells
            FirstLevel := Max(Quotient[Max(Low, 0) + Interval - 1, Interval], 1)
            LastLevel := Quotient[High, Interval] + 1
            FindFreeLevel[FirstLevel, LastLevel + 1] * Interval
        else:
            GetRandomInt(Low, Max(Low, High - Footprint.Z))

    FindFreeLevel<private>(From:int, To:int)<decides><transacts>:int =
        var Found:?int = false
        var Level:int = From
        loop:
            if (Found? or Level >= To):
                break
            if (not UsedLevels[Level]):
                set Found = option{Level}
            set Level += 1
        Found?

    # Places the spawned item (stretched to fill the range when FitToArea, otherwise at the center of the range with scale 1)
    PlaceSpawned<private>(Spawned:entity, Area:spawn_area):void =
        if (FitToArea?):
            Spawned.SetGlobalTransform(Area.MakeFitTransform(MeshSizeCm))
        else:
            Spawned.SetGlobalTransform(MakeTranslationTransform(Area.GetCenter()))
