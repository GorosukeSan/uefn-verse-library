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

# 役割：参加している全プレイヤーについて、デッドゾーンの真ん中を spawner の基準の点にする。デッドゾーンは、プレイヤーの位置を真ん中にした水平 ±DeadHalfCells・上下 ±DeadHeightCells マスの箱で、置いたら動かない。プレイヤーについて動くセーフゾーン（水平 ±SafeHalfCells・上下 ±SafeHeightCells マス）が、そのデッドゾーンの外へはみ出したときだけ、そのプレイヤーの位置に置き直す（少し上下しているあいだは基準の点が変わらないので、spawner は計算し直さない）。生成用（SpawnPoints、狭い）と消去用（DespawnPoints、Despawn… の値、広い）で別々に持つ。だれも使っていないデッドゾーンは消す。1 人もいない（位置が取れない）ときは点を返さず、spawner はその回は何もしない。近くに残す点（KeepPoints）は、プレイヤーの今の位置
# 置き方：エディターで entity に付ける
# 同じ entity：spawner_component
# 前提：区画（game_scope_component。無ければ世界）に player_manager_component と grid_component が 1 つずつ（グリッドが無ければ 1 マス 250 センチメートルとみなす）。どちらも最初に見つけたものを覚えておき、毎回は探さない
players_origin_component<public> := class<final_super>(spawn_origin_component):

    # 生成用：プレイヤーについて動くセーフゾーンの、水平の半分の幅（マス）。既定 2
    @editable_number(int):
        ToolTip := OriginSafeHalfCellsToolTip
        Categories := array{SpawnerCategory, OriginZoneCategory}
        MinValue := option{0}
        MaxValue := option{400}
    SafeHalfCells<public>:int = 2
    # 生成用：セーフゾーンの、上下の半分の高さ（マス）。既定 2
    @editable_number(int):
        ToolTip := OriginSafeHeightCellsToolTip
        Categories := array{SpawnerCategory, OriginZoneCategory}
        MinValue := option{0}
        MaxValue := option{400}
    SafeHeightCells<public>:int = 2
    # 生成用：デッドゾーン（置いたら動かない箱）の、水平の半分の幅（マス）。セーフゾーンより広くする。既定 4
    @editable_number(int):
        ToolTip := OriginDeadHalfCellsToolTip
        Categories := array{SpawnerCategory, OriginZoneCategory}
        MinValue := option{0}
        MaxValue := option{400}
    DeadHalfCells<public>:int = 4
    # 生成用：デッドゾーンの、上下の半分の高さ（マス）。セーフゾーンより広くする。既定 8
    @editable_number(int):
        ToolTip := OriginDeadHeightCellsToolTip
        Categories := array{SpawnerCategory, OriginZoneCategory}
        MinValue := option{0}
        MaxValue := option{400}
    DeadHeightCells<public>:int = 8
    # 消去用：セーフゾーンの、水平の半分の幅（マス）。生成用より広くする。既定 8
    @editable_number(int):
        ToolTip := OriginDespawnSafeHalfCellsToolTip
        Categories := array{SpawnerCategory, OriginDespawnZoneCategory}
        MinValue := option{0}
        MaxValue := option{400}
    DespawnSafeHalfCells<public>:int = 8
    # 消去用：セーフゾーンの、上下の半分の高さ（マス）。生成用より広くする。既定 8
    @editable_number(int):
        ToolTip := OriginDespawnSafeHeightCellsToolTip
        Categories := array{SpawnerCategory, OriginDespawnZoneCategory}
        MinValue := option{0}
        MaxValue := option{400}
    DespawnSafeHeightCells<public>:int = 8
    # 消去用：デッドゾーンの、水平の半分の幅（マス）。既定 16
    @editable_number(int):
        ToolTip := OriginDespawnDeadHalfCellsToolTip
        Categories := array{SpawnerCategory, OriginDespawnZoneCategory}
        MinValue := option{0}
        MaxValue := option{400}
    DespawnDeadHalfCells<public>:int = 16
    # 消去用：デッドゾーンの、上下の半分の高さ（マス）。既定 40
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

    # 今のプレイヤーの位置から、生成用・消去用のデッドゾーンを置き直して返す（はみ出したときだけ置き直す）。近くに残す点はプレイヤーの今の位置
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

    # 区画の player_manager_component を探して覚える（覚えていれば探さない）。見つからなければ false
    GetManager<private>()<transacts>:?player_manager_component =
        set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)
        Manager

    # 区画の grid_component を探して覚える（覚えていれば探さない。FindGrid と同じく区画から探す）。見つからなければ false
    GetGrid<private>()<transacts>:?grid_component =
        set Grid = Entity.ResolveScopedComponent(Grid, grid_component)
        Grid
