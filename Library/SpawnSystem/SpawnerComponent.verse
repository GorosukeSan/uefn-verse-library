using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Random }
using { ActivationSystem }
using { GridSystem }
using { SceneGraphSystem }
using { SpawnSystem.TooltipKit }

# 役割：動いているあいだ、RefillSeconds ごとに、基準の点（同じ entity の spawn_origin_component の派生が UpdateOrigins で返す点。無ければこの entity の位置）のまわりの帯に、同じ entity の spawn_factory_component の派生が作る entity を Count 個ずつ保つ。中身（何を出すか）は factory、場所の基準（だれのまわりか）は origin が決め、この component は数と範囲と出し入れだけを受け持つ
# 帯：点ごとに、水平 ±RangeCells マス、縦は点のマスから下に DespawnBelowCells（下限）〜上に MaxHeightCells（上限）。新しく出すのは上に MinHeightCells〜上限のあいだ（グリッドの高さ FloorCells マスより下には出さない）で、帯の中にもう Count の半分以上あるときは上限から RefillDepthCells マスのあいだに出す。点が変わったときだけ帯を作り直す。帯どうしが MergeGapCells マス以内で重なるときは 1 つにまとめる（まとめた帯の Count は 1 つ分）
# 消す：どの帯（origin の DespawnPoints から作る）にも入らないものを、1 回に DespawnPerRefill 個ずつ消す（DespawnBelowCells が 0 なら消さない。origin の KeepPoints から KeepNearCells マス以内のものは消さない。消す順は決まっていない）
# 置く場所：1 つ分の範囲（マス）は FootprintX × FootprintY × FootprintZ（高さは LevelIntervalCells が 0 ならランダム、0 より大きければ段ごとに 1 つ）。そのまわりに GapCells マスの空き（だれも借りられない）を足して、区画の grid_component から借りる。借りられなければ MaxAttempts 回まで選び直し、だめならその回は出さない。出した entity はこの entity の子にして spawned_component を付け、FitToArea なら範囲いっぱいに伸ばし、そうでなければ範囲の真ん中に置く。出すときは AppearSeconds 秒で大きさを 0 から元へ、消すときは元から 0 へ変えてから消す。消えたものの借用は返す
# いつ：StartOnBegin なら始めから。起動の合図（activated_event）か Start で動き出し、停止の合図（deactivated_event）か Stop で止まって全部消す
# 置き方：エディターで entity に付ける
# 親：起動の合図が届く場所（ゲームの流れなら、ノードの entity かその子孫）
# 同じ entity：spawn_factory_component の派生を 1 つ（必須。無ければ何も出さない）。基準を変えるなら spawn_origin_component の派生を 1 つ
# 知らせ：出したとき spawned_event と SpawnedEvent、外れたとき despawned_event と DespawnedEvent（scene event はこの entity から SendDown）
# 外から：Start / Stop / RefillNow / ClearAll、GetSpawned / GetSpawnedCount / IsRunning
# 前提：区画（game_scope_component。無ければ世界）に grid_component が 1 つ（無ければ何も出さない。見つかるまで補充のたびに探し、見つかったら覚えておく）
spawner_component<public> := class<final_super>(component):

    # 帯ごとにいつも保つ数。0 なら何も出さない。既定 20
    @editable_number(int):
        ToolTip := SpawnerCountToolTip
        Categories := array{SpawnerCategory, SpawnerCountCategory}
        MinValue := option{0}
        MaxValue := option{200}
    Count<public>:int = 20
    # 数を確かめて足りない分を足す間隔（秒）。既定 1.0
    @editable_number(float):
        ToolTip := SpawnerRefillSecondsToolTip
        Categories := array{SpawnerCategory, SpawnerCountCategory}
        MinValue := option{0.1}
        MaxValue := option{60.0}
    RefillSeconds<public>:float = 1.0
    # どの帯にも入らないものを、1 回の補充で消す数の上限。既定 2
    @editable_number(int):
        ToolTip := SpawnerDespawnPerRefillToolTip
        Categories := array{SpawnerCategory, SpawnerCountCategory}
        MinValue := option{1}
        MaxValue := option{100}
    DespawnPerRefill<public>:int = 2
    # 出すとき・消すときに大きさを変える時間（秒）。0 ならすぐ出し入れする。既定 0.5
    @editable_number(float):
        ToolTip := SpawnerAppearSecondsToolTip
        Categories := array{SpawnerCategory, SpawnerCountCategory}
        MinValue := option{0.0}
        MaxValue := option{5.0}
    AppearSeconds<public>:float = 0.5
    # オンならゲームの始めから出し入れする。オフなら起動の合図（activated_event）か Start で動き出す。既定オフ
    @editable:
        ToolTip := SpawnerStartOnBeginToolTip
        Categories := array{SpawnerCategory, SpawnerCountCategory}
    StartOnBegin<public>:logic = false
    # 基準のマスから水平に、前後左右それぞれ何マスまでを帯にするか。既定 12
    @editable_number(int):
        ToolTip := SpawnerRangeCellsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{0}
        MaxValue := option{400}
    RangeCells<public>:int = 12
    # 基準のマスから少なくとも何マス上に出すか（マイナスなら下にも出す）。既定 4
    @editable_number(int):
        ToolTip := SpawnerMinHeightCellsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{-2000}
        MaxValue := option{2000}
    MinHeightCells<public>:int = 4
    # 帯の上限。基準のマスから何マス上まで出すか。既定 32
    @editable_number(int):
        ToolTip := SpawnerMaxHeightCellsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{0}
        MaxValue := option{2000}
    MaxHeightCells<public>:int = 32
    # 帯の下限。基準のマスよりこのマス数より下に外れたものを少しずつ消す。0 なら消さない（既定）
    @editable_number(int):
        ToolTip := SpawnerDespawnBelowCellsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{0}
        MaxValue := option{2000}
    DespawnBelowCells<public>:int = 0
    # 帯の中にもう Count の半分以上あるとき、新しく出すのを上限から何マスのあいだにするか。既定 8
    @editable_number(int):
        ToolTip := SpawnerRefillDepthCellsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{1}
        MaxValue := option{500}
    RefillDepthCells<public>:int = 8
    # 帯どうしがこのマス数以内まで近づいたら 1 つにまとめる。既定 10
    @editable_number(int):
        ToolTip := SpawnerMergeGapCellsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{0}
        MaxValue := option{500}
    MergeGapCells<public>:int = 10
    # 出す範囲のまわりに借りておく空きのマス数（ほかのものが入れない）。既定 1
    @editable_number(int):
        ToolTip := SpawnerGapCellsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{0}
        MaxValue := option{20}
    GapCells<public>:int = 1
    # 近くに残す点（KeepPoints（UpdateOrigins の結果））からこのマス数以内のものは、帯の外でも消さない。0 なら近くでも消す。既定 40
    @editable_number(int):
        ToolTip := SpawnerKeepNearCellsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{0}
        MaxValue := option{400}
    KeepNearCells<public>:int = 40
    # 出す高さの最低（グリッドの 0 番からのマス）。これより下には出さない。既定 -2000
    @editable_number(int):
        ToolTip := SpawnerFloorCellsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{-2000}
        MaxValue := option{2000}
    FloorCells<public>:int = -2000
    # 借りられる範囲が見つからないときに場所を選び直す回数の上限。だめならその回は出さない。既定 8
    @editable_number(int):
        ToolTip := SpawnerMaxAttemptsToolTip
        Categories := array{SpawnerCategory, SpawnerRangeCategory}
        MinValue := option{1}
        MaxValue := option{50}
    MaxAttempts<public>:int = 8
    # 1 つ分が使う範囲の前（X）のマス数。既定 1
    @editable_number(int):
        ToolTip := SpawnerFootprintToolTip
        Categories := array{SpawnerCategory, SpawnerPlaceCategory}
        MinValue := option{1}
        MaxValue := option{50}
    FootprintX<public>:int = 1
    # 1 つ分が使う範囲の左（Y）のマス数。既定 1
    @editable_number(int):
        ToolTip := SpawnerFootprintToolTip
        Categories := array{SpawnerCategory, SpawnerPlaceCategory}
        MinValue := option{1}
        MaxValue := option{50}
    FootprintY<public>:int = 1
    # 1 つ分が使う範囲の上（Z）のマス数。既定 1
    @editable_number(int):
        ToolTip := SpawnerFootprintToolTip
        Categories := array{SpawnerCategory, SpawnerPlaceCategory}
        MinValue := option{1}
        MaxValue := option{50}
    FootprintZ<public>:int = 1
    # オンなら借りた範囲いっぱいの大きさに伸ばして置く。オフなら作ったままの大きさで範囲の真ん中に置く。既定オフ
    @editable:
        ToolTip := SpawnerFitToAreaToolTip
        Categories := array{SpawnerCategory, SpawnerPlaceCategory}
    FitToArea<public>:logic = false
    # メッシュの大きさ 1 のときの 1 辺（センチメートル）。FitToArea のときに使う。既定 100（エンジンの基本のキューブ）
    @editable_number(float):
        ToolTip := SpawnerMeshSizeToolTip
        Categories := array{SpawnerCategory, SpawnerPlaceCategory}
        MinValue := option{1.0}
        MaxValue := option{10000.0}
    MeshSizeCm<public>:float = 100.0
    # 0 より大きければ、高さをこのマス数ごとの段（マスの Z がこの倍数。0 は除く）に決め、1 つの段には 1 つだけ出す（一度出した段は、消えても ForgetUsedLevels まで出し直さない）。0 なら高さもランダム。既定 0
    @editable_number(int):
        ToolTip := SpawnerLevelIntervalToolTip
        Categories := array{SpawnerCategory, SpawnerPlaceCategory}
        MinValue := option{0}
        MaxValue := option{1000}
    LevelIntervalCells<public>:int = 0

    LowestCell<private>:int = -1000000

    SpawnedEventInternal<private><final>:event(entity) = event(entity){}

    # 1 つ出して置いたあとに、出した entity で届く（spawned_event と同じタイミング。Await / Subscribe する。外から Signal はできない）
    SpawnedEvent<public><final>:listenable(entity) = MakeProxyListenable(SpawnedEventInternal)

    DespawnedEventInternal<private><final>:event(entity) = event(entity){}

    # 出したものが世界から外れたときに、その entity で届く（縮んで消えた・ClearAll・停止。despawned_event と同じタイミング。Await / Subscribe する。外から Signal はできない）
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

    # 動き出す（起動の合図と同じ）。動いていれば何もしない
    Start<public>():void =
        if (not WantRunning?):
            set WantRunning = true
            StartEvent.Signal()

    # 止まって、出したものを全部すぐ消す（停止の合図と同じ）。止まっていても、出したものは消す
    Stop<public>():void =
        set WantRunning = false
        set Running = false
        StopEvent.Signal()
        Clear()

    # 動いていれば成功する
    IsRunning<public>()<decides><reads>:void =
        Running?

    # 今出ているもの（消えはじめたものは除く）。この entity の直下の子だけを数える。並び順は決まっていない
    GetSpawned<public>()<reads>:[]spawned_component =
        for (Marker : Entity.GetChildComponents(spawned_component), not Marker.Leaving?):
            Marker

    # 今出ているものの数（GetSpawned の数）
    GetSpawnedCount<public>()<reads>:int =
        GetSpawned().Length

    # 段（LevelIntervalCells を使うとき。高さのマス ÷ LevelIntervalCells）にもう出したなら成功する
    IsLevelUsed<public>(Level:int)<decides><reads>:void =
        UsedLevels[Level]?

    # 出した段を全部忘れる（次の補充から、同じ段にもまた出す）
    ForgetUsedLevels<public>():void =
        set UsedLevels = map{}

    # 1 つ分が使う範囲のマス数（FootprintX/Y/Z。1 未満は 1）
    GetFootprint<public>()<transacts>:grid_cell =
        grid_cell{X := Max(FootprintX, 1), Y := Max(FootprintY, 1), Z := Max(FootprintZ, 1)}

    # Band の中で、1 つ分の範囲の始まり（小さい側の角）のマスを選ぶ。高さは Low〜High（LevelIntervalCells が 0 より大きければ、その中のまだ使っていない段）。選べなければ失敗する
    PickStartCell<public>(Band:spawn_band, Low:int, High:int)<decides><transacts>:grid_cell =
        Footprint := GetFootprint()
        Height := PickHeight[Footprint, Low, High]
        grid_cell:
            X := Band.CenterX + GetRandomInt(-Band.HalfX, Band.HalfX) - (Quotient[Footprint.X, 2] or 0)
            Y := Band.CenterY + GetRandomInt(-Band.HalfY, Band.HalfY) - (Quotient[Footprint.Y, 2] or 0)
            Z := Height

    # 動いているあいだなら、次の補充を待たずに今すぐ 1 回分の補充をする（帯の作り直し・外れたものを DespawnPerRefill 個消す・足りない分を足す。いつもの補充と同じ）。いつもの補充の間隔は変わらない。止まっているときは何もしない
    RefillNow<public>():void =
        if (Running?):
            RefillOnce()

    # 出したものを全部、今すぐ消す（縮む演出なし。借用は消えたものから返る）。止まったときと同じ消し方。動いているあいだは、次の補充でまた出る（止めたいなら Stop）
    ClearAll<public>():void =
        Clear()

    # Points の点ごとに帯を作り、MergeGapCells マス以内で重なる帯を 1 つにまとめて返す（spawner が中で使う計算）
    GetBands<internal>(Grid:grid_component, Points:[]vector3)<transacts>:[]spawn_band =
        Bands := for (Point : Points):
            MakeBand(Grid.ToCell(Point))
        MergeBands(Bands, MergeGapCells)

    # spawned_component が世界から外れるときに呼ぶ
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

    # 今回の基準の点。origin があればその UpdateOrigins（出す点が空なら false）、無ければこの entity の位置 1 つ
    GetOrigins<private>()<transacts>:?spawn_origins =
        if (Source := Entity.GetComponent[spawn_origin_component]):
            Origins := Source.UpdateOrigins()
            if (Origins.SpawnPoints.Length > 0) then option{Origins} else false
        else:
            Here := Entity.GetGlobalTranslation()
            option{spawn_origins{SpawnPoints := array{Here}}}

    # 高さ（マスの Z）を選ぶ。LevelIntervalCells が 0 より大きければ Low〜High の中のまだ使っていない段、そうでなければランダム
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

    # 出したものを置く（FitToArea なら範囲いっぱい、そうでなければ範囲の真ん中に大きさ 1）
    PlaceSpawned<private>(Spawned:entity, Area:spawn_area):void =
        if (FitToArea?):
            Spawned.SetGlobalTransform(Area.MakeFitTransform(MeshSizeCm))
        else:
            Spawned.SetGlobalTransform(MakeTranslationTransform(Area.GetCenter()))
