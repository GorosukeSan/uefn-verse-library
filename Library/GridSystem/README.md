# GridSystem

世界をマス（1 辺 `CellSizeCm` センチメートルの立方体）に分け、直方体の範囲の「借用」を管理する System です。出すもの（キューブ・線・チェックポイントなど）は、置く前にここで範囲を借り、借りた範囲の中だけを使うので、互いに重なりません。SpawnSystem の `spawner_component`（出す範囲を借りる）と `players_origin_component`（マスの大きさを読む）が使います。CheckpointSystem の `checkpoint_factory_component` は spawner と同じ entity に置き、借りた範囲の大きさをチェックポイントの大きさにします。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `grid_component` | 区画（`game_scope_component`）に 1 つ（区画が無ければ世界に 1 つ）。マスの 0 番はこの entity の位置 | 位置とマスの変換、直方体の範囲の借用と返却を管理する |

例：
```
区画（game_scope_component）
├ グリッド（grid_component、CellSizeCm = 250）
└ 出すもの（spawner_component + …）
```
使う側は `FindGrid`（区画の中を探す）で見つけて覚えておきます。

## 設定（@editable）
- `grid_component.CellSizeCm : float = 250.0` — 1 マスの 1 辺の長さ（センチメートル。10〜5000）。

## イベント
この System は scene_event を送りません。
- `grid_component.ReleasedEvent : listenable(grid_reservation)` — 借用が返されたとき（`Release`・`ReleaseAll` のどちらでも）、返された借用で届く。

## 公開 API
```verse
# マスと範囲（座標はマスの番号）
grid_cell<public> := struct<computes>:
    X<public>:int       # Forward
    Y<public>:int       # Left
    Z<public>:int       # Up
(A:grid_cell).Plus<public>(B:grid_cell)<computes>:grid_cell

grid_box<public> := struct<computes>:
    Start<public>:grid_cell
    Size<public>:grid_cell                                         # 各軸 1 以上
(Box:grid_box).GetEnd<public>()<computes>:grid_cell                  # Start + Size（このマスは範囲に入らない）
(Box:grid_box).Overlaps<public>(Other:grid_box)<decides><computes>:void   # 面で接しているだけなら失敗
(Box:grid_box).Expand<public>(Margin:int)<computes>:grid_box        # 各軸の両側に Margin マス広げる
(Box:grid_box).IsValid<public>()<decides><computes>:void            # Size がどれも 1 以上なら成功
(Box:grid_box).GetDistanceSquared<public>(Cell:grid_cell)<computes>:int
MakeGridBox<public>(Start:grid_cell, Size:grid_cell)<computes>:grid_box   # Size の各軸を 1 以上に丸める

# グリッドと借用
grid_component<public> := class<final_super>(component):
    CellSizeCm<public>:float
    ReleasedEvent<public><final>:listenable(grid_reservation)
    GetOrigin<public>()<transacts>:vector3                         # マスの 0 番の角（この entity の位置）
    ToCell<public>(Position:vector3)<transacts>:grid_cell
    CellToPosition<public>(Cell:grid_cell)<transacts>:vector3      # マスの始まりの角（真ん中ではない）
    IsFree<public>(Box:grid_box)<decides><transacts>:void
    TryReserve<public>(Box:grid_box)<transacts>:?grid_reservation  # 重なる・大きさ 0 以下なら false
    GetReservationCount<public>()<reads>:int
    GetReservations<public>()<reads>:[]grid_reservation            # 借りた順
    ReleaseAll<public>():void

grid_reservation<public> := class<unique><internal>:              # TryReserve が作る
    Grid<public>:grid_component
    Box<public>:grid_box
    var<private> Released<public>:logic
    Release<public>():void                                         # 2 回目以降は何もしない
    IsHeld<public>()<decides><reads>:void
    GetMinPosition<public>()<transacts>:vector3
    GetMaxPosition<public>()<transacts>:vector3
    GetCenter<public>()<transacts>:vector3
    GetSize<public>()<transacts>:vector3                           # センチメートル

(InEntity:entity).FindGrid<public>()<decides><transacts>:grid_component   # 区画（無ければ世界）の grid_component

# GridPath（範囲の中に軸に沿った道を作る小道具）
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

## 前提・注意
- マスの 0 番はこの entity の位置です。向きは使いません。原点より負の側のマスも切り捨て（Floor）で数えます。
- `grid_component` は区画に 1 つだけ置く前提です。複数あると `FindGrid` でどれが返るかは決まりません。`FindGrid` は区画の中を探すので、毎フレーム・毎回は呼ばず、結果を覚えておきます。InEntity がまだ世界に入っていないと失敗します。
- `TryReserve` は借りる副作用があるので、呼んだ側の失敗で巻き戻らないよう `<decides>` ではなく option を返します。
- `Expand` に負の `Margin` を渡すと `Size` が 0 以下になることがあります（丸めません）。`IsValid` で確かめます。`grid_component` はそういう範囲を借りません。
- `ReleaseAll` は借りた側（spawner が出したものなど）を消しません。そのまま残すと、返した範囲にほかのものが重なって置かれることがあります。
- GridPath はライブラリの中では使っていません（線を並べた足場や、`mover_path_route_component` に渡す地点の列を作るときに使います）。座標はすべてマスの番号なので、世界の位置にするには `grid_component.CellToPosition`（SpawnSystem の `spawn_area` なら `GetMinPosition()` ＋ マス × `CellSizeCm`）を使います。
- この System のコードには `⚠ 未検証` の印はなく、`@experimental` の API も使っていません。

## 確かめ方
- テスト：`_Test/GridSystemTest/` の `grid_system_test_component`。このテストの component を、どこかの entity に付けるだけ（グリッドはテストが自分の子に 1 マス 100 センチメートルで作る。レベルのグリッドは使わない）。`grid_box` の計算（重なり・広げる・大きさの丸め・距離）、位置とマスの変換、借りる・返す・全部返す・返した知らせ、GridPath の道が範囲の中で軸に沿っていることを確かめます。すぐ終わります（1 秒ほど）。結果は出力ログの `[TEST] GridSystem`。
- `_Samples/` に GridSystem の見本はありません。
