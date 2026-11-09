using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { SceneGraphSystem }
using { GridSystem.TooltipKit }

# 役割：グリッドの直方体の借用 1 つ。Release で返す（返すまで、重なる範囲はほかから借りられない）
# 作り方：grid_component.TryReserve が作る（外からは作らない）
grid_reservation<public> := class<unique><internal>:

    # 借りた先のグリッド
    Grid<public>:grid_component

    # 借りている範囲（マス）
    Box<public>:grid_box

    # 返したら true（Release・ReleaseAll のあと）
    var<private> Released<public>:logic = false

    # 借用を返す（重なる範囲をほかが借りられるようになる）。2 回目以降は何もしない
    Release<public>():void =
        if (not Released?):
            set Released = true
            Grid.Forget(Self)

    # 返していなければ成功する
    IsHeld<public>()<decides><reads>:void =
        not Released?

    # 範囲の始まりの角の世界での位置（センチメートル）
    GetMinPosition<public>()<transacts>:vector3 =
        Grid.CellToPosition(Box.Start)

    # 範囲の終わりの角（GetEnd のマスの角）の世界での位置（センチメートル）
    GetMaxPosition<public>()<transacts>:vector3 =
        Grid.CellToPosition(Box.GetEnd())

    # 範囲の真ん中の世界での位置（センチメートル）
    GetCenter<public>()<transacts>:vector3 =
        (GetMinPosition() + GetMaxPosition()) / 2.0

    # 範囲の各軸の長さ（センチメートル。マス数 × CellSizeCm）
    GetSize<public>()<transacts>:vector3 =
        GetMaxPosition() - GetMinPosition()

# 役割：世界をマス（1 辺 CellSizeCm センチメートル）に分け、直方体の範囲の借用を管理する。出すもの（キューブ・線・チェックポイントなど）は、置く前にここで範囲を借り、借りた範囲の中だけを使う。マスの 0 番はこの entity の位置（向きは使わない）
# 置き方：エディターで entity に付ける。区画（game_scope_component）に 1 つ（区画が無ければ世界に 1 つ）。使う側は FindGrid（区画の中を探す）で見つけて覚えておく
# 知らせ：借用が返されたとき ReleasedEvent（返された借用で届く）
grid_component<public> := class<final_super>(component):

    # 1 マスの 1 辺の長さ（センチメートル）。出すものはこのマスの直方体の範囲を借りて置く。既定 250
    @editable_number(float):
        ToolTip := GridCellSizeToolTip
        Categories := array{GridCategory}
        MinValue := option{10.0}
        MaxValue := option{5000.0}
    CellSizeCm<public>:float = 250.0

    ReleasedEventInternal<private><final>:event(grid_reservation) = event(grid_reservation){}

    # 借用が返されたときに、その借用で届く（Release・ReleaseAll のどちらでも。Await / Subscribe する。外から Signal はできない）
    ReleasedEvent<public><final>:listenable(grid_reservation) = MakeProxyListenable(ReleasedEventInternal)

    var Reservations<private>:[]grid_reservation = array{}

    # マスの 0 番の角の世界での位置（この entity の位置。センチメートル）
    GetOrigin<public>()<transacts>:vector3 =
        Entity.GetGlobalTranslation()

    # 世界での位置（センチメートル）が入っているマス。原点より負の側も切り捨て（Floor）で数える
    ToCell<public>(Position:vector3)<transacts>:grid_cell =
        Local := (Position - GetOrigin()) / CellSizeCm
        grid_cell:
            X := Floor[Local.Forward] or 0
            Y := Floor[Local.Left] or 0
            Z := Floor[Local.Up] or 0

    # マスの始まりの角（真ん中ではない）の世界での位置（センチメートル）
    CellToPosition<public>(Cell:grid_cell)<transacts>:vector3 =
        GetOrigin() + vector3{Forward := Cell.X * CellSizeCm, Left := Cell.Y * CellSizeCm, Up := Cell.Z * CellSizeCm}

    # Box が正しい大きさ（IsValid）で、今の借用のどれとも重ならなければ成功する（借りはしない）
    IsFree<public>(Box:grid_box)<decides><transacts>:void =
        Box.IsValid[]
        for (Reservation : Reservations):
            not Reservation.Box.Overlaps[Box]

    # Box が空いていれば借りて借用を返す。重なる借用があるとき・Box の大きさが 0 以下の軸があるときは false（何も借りない）
    # 失敗しうるが、借りる副作用を呼んだ側の失敗で巻き戻させないため <decides> ではなく option を返す
    TryReserve<public>(Box:grid_box)<transacts>:?grid_reservation =
        if (IsFree[Box]):
            Reservation := grid_reservation{Grid := Self, Box := Box}
            set Reservations += array{Reservation}
            option{Reservation}
        else:
            false

    # 今借りられている（まだ返していない）借用の数
    GetReservationCount<public>()<reads>:int =
        Reservations.Length

    # 今借りられている（まだ返していない）借用の一覧。借りた順
    GetReservations<public>()<reads>:[]grid_reservation =
        Reservations

    # 借りられている借用を全部返す（それぞれ Release を呼ぶのと同じ。Released が true になり、一覧から消え、ReleasedEvent が 1 つずつ届く）。借りた側（spawner が出したものなど）は消えないので、そのまま残すと、返した範囲にほかのものが重なって置かれることがある
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

# InEntity の区画（game_scope_component。無ければ世界）にある grid_component を探す。区画に 1 つだけ置く前提で、複数あるとどれが返るかは決まらない
# 無いとき・InEntity がまだ世界に入っていないときは失敗する。区画の中を探すので、毎フレーム・毎回は呼ばず、結果を覚えておく
(InEntity:entity).FindGrid<public>()<decides><transacts>:grid_component =
    InEntity.FindScopedComponent[grid_component]
