# SpawnSystem

entity（prefab）を出して消す System です。2 通りの出し方があります。
- 帯で出し続ける：基準の点（プレイヤーなど）のまわりの範囲（帯）に、決まった数の entity を出し続け、範囲から外れたものを少しずつ消す。中心の `spawner_component` が数・範囲・置き方・出し入れを受け持ち、「何を出すか」は同じ entity の factory、「だれのまわりに出すか」は同じ entity の origin が決めます。出す場所はグリッド（GridSystem の `grid_component`）から借ります。
- 決めた場所に出す（PrefabKit）：`spawn_prefab_component` が、起動の合図やコードから、決めた場所（子の `spawn_point_component`・自分の位置・好きな transform）に好きな数だけ出し、出したものを数え、まとめて消します。グリッドは要りません。1 つ出すだけなら関数の `SpawnPrefab` もあります。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `spawner_component` | 起動の合図が届く entity（ゲームの流れなら、ノードの entity かその子孫） | `RefillSeconds` ごとに、帯ごとに `Count` 個を保つ。1 つ分の範囲（`FootprintX` × `FootprintY` × `FootprintZ` マス）をグリッドから借りて置く。帯の外のものを `DespawnPerRefill` 個ずつ消す。停止の合図で止まって全部消す |
| `prefab_spawn_factory_component`（PrefabKit） | `spawner_component` と同じ entity | 出すものを `Prefab` にする |
| `players_origin_component`（OriginKit） | `spawner_component` と同じ entity | 参加している全プレイヤーのまわりを基準にする（セーフゾーンとデッドゾーンで、少し動いただけでは計算し直さない） |
| `spawned_component` | 出した entity（spawner が実行時に付ける。エディターでは置かない） | 出したものの目印。世界から外れるときに借用を返し、spawner に知らせる |
| `spawn_prefab_component`（PrefabKit） | 起動の合図が届く entity（ゲームの流れなら、ノードの entity かその子孫）。合図を使わずコードから出すなら、どこでもよい | 起動の合図で `SpawnOnActivate` 個を出し、停止の合図で（`DespawnOnDeactivate` なら）全部消す。出す場所は直下の `spawn_point_component`（`PointOrder` の順）か自分の位置で、`ScatterHalfSizeCm` の箱の中にずらす。`MaxCount` で同時の数を抑える。コードからは `Spawn` / `TrySpawnAt` / `Despawn` / `DespawnAll` |
| `spawn_point_component`（PrefabKit） | `spawn_prefab_component` の entity の直下 | 出す場所の目印（位置と向き）。`Order` の小さい順に使う |
| `prefab_spawned_component`（PrefabKit） | 出した entity（`spawn_prefab_component` が実行時に付ける。エディターでは置かない） | 出したものの目印。世界から外れるときに `spawn_prefab_component` に知らせる |

factory（`spawn_factory_component` の派生）は必須で、1 entity に 1 つまでです。無ければ何も出しません。origin（`spawn_origin_component` の派生）は任意で、置かなければ spawner の entity の位置が基準になります。factory の派生はほかに CheckpointSystem の `checkpoint_factory_component`（SpawnKit）があります。

例：「プレイヤーのまわりに足場を出し続ける」
```
区画（game_scope_component）
├ プレイヤー管理（player_manager_component）
├ グリッド（grid_component）
└ ノード（game_node_component）
  └ 足場の spawner（spawner_component + prefab_spawn_factory_component + players_origin_component）
    └ （出した足場。spawner が実行時に子として足す）
```

例：「本番のあいだ、決めた 3 か所に敵を 1 体ずつ出し、本番が終わったら消す」
```
本番（game_node_component）
└ 敵（spawn_prefab_component、Prefab = 敵、SpawnOnActivate = 3、PointOrder = InOrder）
  ├ 出す場所 1（spawn_point_component、Order 0）
  ├ 出す場所 2（spawn_point_component、Order 1）
  ├ 出す場所 3（spawn_point_component、Order 2）
  └ （出した敵。spawn_prefab_component が実行時に子として足す）
```
コードからは `Prefabs.Spawn(5)`（決めた場所に 5 体）、`Prefabs.TrySpawnAt(Transform)`（好きな場所に 1 体）、`Prefabs.DespawnAll()` などを呼びます。

## 設定（@editable）
spawner_component（数）:
- `spawner_component.Count : int = 20` — 帯ごとにいつも保つ数（0〜200）。0 なら何も出さない。帯どうしがまとまると、まとめた帯の数は 1 つ分。
- `spawner_component.RefillSeconds : float = 1.0` — 数を確かめて足す間隔（秒。0.1〜60）。
- `spawner_component.DespawnPerRefill : int = 2` — どの帯にも入らないものを、1 回の補充で消す数の上限（1〜100）。
- `spawner_component.AppearSeconds : float = 0.5` — 出すとき・消すときに大きさを 0 から元へ（元から 0 へ）変える時間（秒。0〜5）。0 ならすぐ出し入れする。
- `spawner_component.StartOnBegin : logic = false` — オンならゲームの始めから出し入れする。オフなら起動の合図（`activated_event`）か `Start` で動き出す。

spawner_component（範囲。単位はグリッドのマス）:
- `spawner_component.RangeCells : int = 12` — 基準のマスから水平に、前後左右それぞれ何マスまでを帯にするか。
- `spawner_component.MinHeightCells : int = 4` — 基準のマスから少なくとも何マス上に出すか（マイナスなら下にも出す）。
- `spawner_component.MaxHeightCells : int = 32` — 帯の上限。基準のマスから何マス上まで出すか。
- `spawner_component.DespawnBelowCells : int = 0` — 帯の下限。基準のマスよりこのマス数より下に外れたものを少しずつ消す。0 なら消さない。
- `spawner_component.RefillDepthCells : int = 8` — 帯の中にもう `Count` の半分以上あるとき、新しく出すのを上限から何マスのあいだにするか。
- `spawner_component.MergeGapCells : int = 10` — 帯どうしがこのマス数以内まで近づいたら 1 つにまとめる。
- `spawner_component.GapCells : int = 1` — 出す範囲のまわりに借りておく空き（ほかのものが入れない。0〜20）。
- `spawner_component.KeepNearCells : int = 40` — origin の近くに残す点（`spawn_origins.KeepPoints`）からこのマス数以内のものは、帯の外でも消さない。0 なら近くでも消す。
- `spawner_component.FloorCells : int = -2000` — 出す高さの最低（グリッドの 0 番からのマス）。これより下には出さない。
- `spawner_component.MaxAttempts : int = 8` — 借りられる範囲が見つからないときに選び直す回数の上限（1〜50）。だめならその回は出さない。

spawner_component（置き方）:
- `spawner_component.FootprintX` / `FootprintY` / `FootprintZ : int = 1` — 1 つ分が使う範囲のマス数（前・左・上。1〜50）。
- `spawner_component.FitToArea : logic = false` — オンなら借りた範囲いっぱいの大きさに伸ばして置く。オフなら作ったままの大きさで範囲の真ん中に置く。
- `spawner_component.MeshSizeCm : float = 100.0` — メッシュの大きさ 1 のときの 1 辺（センチメートル）。`FitToArea` のときに使う（エンジンの基本のキューブなら 100）。
- `spawner_component.LevelIntervalCells : int = 0` — 0 より大きければ、高さをこのマス数ごとの段（マスの Z がこの倍数。0 は除く）に決め、1 つの段には 1 つだけ出す。一度出した段は、消えても `ForgetUsedLevels` まで出し直さない。0 なら高さもランダム。

prefab_spawn_factory_component:
- `prefab_spawn_factory_component.Prefab : concrete_subtype(entity) = entity` — 出す prefab。既定のままだと何も無い entity を出す。

spawn_prefab_component:
- `spawn_prefab_component.Prefab : concrete_subtype(entity) = entity` — 出す prefab。既定のままだと何も無い entity を出す。
- `spawn_prefab_component.SpawnOnActivate : int = 1` — 起動の合図が届くたびに出す数（0〜100）。0 なら合図では出さない。
- `spawn_prefab_component.MaxCount : int = 0` — 同時に出しておける数の上限（0〜1000）。届いたらそれ以上出さない。0 なら上限なし。
- `spawn_prefab_component.PointOrder : spawn_point_order = InOrder` — 直下の `spawn_point_component` を使う順。`InOrder`（`Order` の小さい順に 1 つずつ、最後まで行ったら最初へ）か `Random`。
- `spawn_prefab_component.ScatterHalfSizeCm : vector3 = 0` — 出す場所から、前・左・上それぞれ ± この長さの箱の中にランダムにずらす（点の向きの軸で。0 の軸はずらさない）。
- `spawn_prefab_component.DespawnOnDeactivate : logic = true` — オンなら停止の合図で全部消す。

spawn_point_component:
- `spawn_point_component.Order : int = 0` — `PointOrder` が `InOrder` のときの順番（0〜1000）。

players_origin_component（マス。どれも 0〜400）:
- 生成用：`SafeHalfCells = 2` / `SafeHeightCells = 2`（プレイヤーについて動くセーフゾーンの水平・上下の半分）、`DeadHalfCells = 4` / `DeadHeightCells = 8`（置いたら動かないデッドゾーンの水平・上下の半分。セーフゾーンより広くする）。
- 消去用：`DespawnSafeHalfCells = 8` / `DespawnSafeHeightCells = 8`、`DespawnDeadHalfCells = 16` / `DespawnDeadHeightCells = 40`（生成用より広くする）。
- セーフゾーンがデッドゾーンの外へはみ出したときだけ、デッドゾーンをプレイヤーの位置に置き直す。基準の点はデッドゾーンの真ん中。近くに残す点は、プレイヤーの今の位置。

## イベント
- `spawned_event`（scene_event、spawner の entity から SendDown。出したものは spawner の子なので、出したもの自身にも届く）: `Spawner : spawner_component`、`Spawned : entity`、`Area : spawn_area`。1 つ出して置いたあと。消費しない。
- `despawned_event`（scene_event、spawner の entity から SendDown）: `Spawner : spawner_component`、`Spawned : entity`。出したものが世界から外れたとき（縮んで消えた・`ClearAll`・停止）。消費しない。
- `spawner_component.SpawnedEvent : listenable(entity)` — 1 つ出して置いたあと、出した entity で届く（`spawned_event` と同じタイミング）。
- `spawner_component.DespawnedEvent : listenable(entity)` — 出したものが世界から外れたとき、その entity で届く（`despawned_event` と同じタイミング）。
- `spawn_prefab_component.SpawnedEvent : listenable(entity)` — 1 つ出して置いたあと、出した entity で届く。
- `spawn_prefab_component.DespawnedEvent : listenable(entity)` — 出したものが世界から外れたとき（`Despawn`・`DespawnAll`・停止の合図・ほかのコードが消した）、その entity で届く。
- 受けるもの: `spawner_component` は `activated_event`（`Start` と同じ）と `deactivated_event`（`Stop` と同じ）。`spawn_prefab_component` は `activated_event`（`Spawn(SpawnOnActivate)`）と `deactivated_event`（`DespawnOnDeactivate` なら `DespawnAll`）。

## 公開 API
```verse
# 関数版（SpawnSystem）。Prefab を作って Parent の子にし、世界の Transform に置く。数えない・まとめて消さない
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
    Start<public>():void                                # 動いていれば何もしない
    Stop<public>():void                                 # 止まって、出したものを全部すぐ消す
    IsRunning<public>()<decides><reads>:void
    GetSpawned<public>()<reads>:[]spawned_component     # 直下の子だけ。消えはじめたものは除く。並び順は決まらない
    GetSpawnedCount<public>()<reads>:int
    IsLevelUsed<public>(Level:int)<decides><reads>:void # 段（高さのマス ÷ LevelIntervalCells）にもう出したなら成功
    ForgetUsedLevels<public>():void                     # 出した段を全部忘れる
    GetFootprint<public>()<transacts>:grid_cell         # FootprintX/Y/Z（1 未満は 1）
    PickStartCell<public>(Band:spawn_band, Low:int, High:int)<decides><transacts>:grid_cell   # 1 つ分の範囲の始まりのマスを選ぶ
    RefillNow<public>():void                            # 動いているあいだだけ、今すぐ 1 回分補充する
    ClearAll<public>():void                             # 全部すぐ消す。動いていれば次の補充でまた出る

# 何を出すかの基底。派生は CreateSpawned だけを書く
spawn_factory_component<public> := class<abstract><final_super>(component):
    CreateSpawned<public>(Area:spawn_area):entity       # 世界にはまだ入れない。置くのは spawner

# spawn_origin_component が補充ごとに返す点（世界の位置、cm）
spawn_origins<public> := struct:
    SpawnPoints<public>:[]vector3                       # 空なら spawner はその回は何もしない
    DespawnPoints<public>:[]vector3                     # 空なら SpawnPoints を使う
    KeepPoints<public>:[]vector3                        # ここから KeepNearCells 以内のものは消さない

# だれのまわりに出すかの基底。派生は UpdateOrigins だけを書く
spawn_origin_component<public> := class<abstract><final_super>(component):
    UpdateOrigins<public>()<transacts>:spawn_origins    # 補充のたびに 1 回呼ばれる。派生はここで状態を更新してよい

spawn_band<public> := struct<computes>:
    CenterX<public>:int
    CenterY<public>:int
    HalfX<public>:int
    HalfY<public>:int
    Bottom<public>:int                                  # これより下に外れたものは消える
    SpawnBottom<public>:int                             # 新しく出す高さの最低
    Top<public>:int

spawn_area<public> := class:
    Grid<public>:grid_component
    Inner<public>:grid_box                              # 使ってよい範囲（マス）
    Reservation<public>:grid_reservation                # GapCells の空きも含めた借用
    GetMinPosition<public>()<transacts>:vector3
    GetMaxPosition<public>()<transacts>:vector3
    GetCenter<public>()<transacts>:vector3
    GetSize<public>()<transacts>:vector3
    MakeFitTransform<public>(MeshSizeCm:float)<transacts>:transform   # 範囲いっぱいの大きさで真ん中に置く transform

spawned_component<public> := class<final_super>(component):
    Spawner<public>:spawner_component
    Area<public>:spawn_area
    var<private> Leaving<public>:logic
    Leave<public>(Seconds:float):void                   # 縮めてから消す。すぐ戻る。2 回目以降は何もしない
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
    InOrder     # Order の小さい順に 1 つずつ、最後まで行ったら最初へ
    Random      # 毎回ランダム

spawn_prefab_component<public> := class<final_super>(component):
    Prefab<public>:concrete_subtype(entity)
    SpawnOnActivate<public>:int
    MaxCount<public>:int
    PointOrder<public>:spawn_point_order
    ScatterHalfSizeCm<public>:vector3
    DespawnOnDeactivate<public>:logic
    SpawnedEvent<public><final>:listenable(entity)
    DespawnedEvent<public><final>:listenable(entity)
    Spawn<public>(Count:int):[]entity                   # 決めた場所に Count 個。MaxCount に届いたらそこでやめる
    TrySpawnAt<public>(Transform:transform):?entity     # 好きな場所に 1 つ。MaxCount に届いていれば false
    Despawn<public>(Spawned:entity):void                # 自分が出したものだけ消す
    DespawnAll<public>():void
    GetSpawned<public>()<reads>:[]entity                # 直下の子だけ。消しはじめたものは除く。並び順は決まらない
    GetSpawnedCount<public>()<reads>:int
    IsFull<public>()<decides><reads>:void               # MaxCount > 0 で、届いていれば成功
    GetSpawnPoints<public>()<transacts>:[]spawn_point_component   # 直下の子だけ。Order の小さい順

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

## 前提・注意
- 区画（`game_scope_component`。無ければ世界）に `grid_component` が 1 つ要ります。無ければ何も出しません（見つかるまで補充のたびに探し、見つかったら覚えておく）。
- `players_origin_component` は区画に `player_manager_component` も要ります。グリッドが無ければ 1 マス 250 cm とみなします。プレイヤーが 1 人もいない（位置が取れない）ときは点を返さず、spawner はその回は何もしません。
- 帯は基準の点が変わったときだけ作り直します。帯どうしが `MergeGapCells` 以内で重なると 1 つにまとまり、まとめた帯の数は `Count` 1 つ分です。
- 出すとき・消すときの大きさの変化は毎フレーム `SetGlobalTransform` します。`keyframed_movement_component` で動く entity（MoverSystem の Keyframe など）を出すなら `AppearSeconds` を 0 にします。
- 消す順は決まっていません。消えたものの借用はグリッドに返ります。
- `spawn_prefab_component` はグリッドを使いません（重なりは調べない）。出したものはこの entity の子になるので、この entity を動かすと一緒に動きます。大きさは 1 で置きます（点の entity の大きさは使わない）。
- `spawn_prefab_component` の起動の合図は、届くたびに `SpawnOnActivate` 個を足します（作り直しはしない。`DespawnOnDeactivate` がオンなら停止の合図で消えるので、ノードに入るたびに出し直しになる）。シミュレーションの終わりには必ず全部消します。
- `Despawn` / `DespawnAll` はすぐに数から外します（同じフレームで `Spawn` しても上限に数えない）。縮む演出はありません。
- 実験的な API は使っていません。

## 確かめ方
- テスト：`_Test/SpawnSystemTest/` の `spawn_system_test_component`。まわり 10 メートルに何も無い entity に付けるだけです（区画・グリッド・spawner・spawn_prefab_component はテストが自分の子に作る。プレイヤーは要らない）。起動で `Count` 個を出して保つこと、帯と借用の数、出した・消えたの知らせ、`RefillNow`、`ClearAll` / `Stop`、起動・停止の合図を確かめ、続けて `spawn_prefab_component`（`spawn_point_component` の `Order` の順、起動の合図で `SpawnOnActivate` 個、`MaxCount`、`TrySpawnAt`、`Despawn` / `DespawnAll` と知らせ、停止の合図）と、関数の `SpawnPrefab` を確かめます。約 3 秒かかります。結果は出力ログの `[TEST] SpawnSystem`。
- `_Samples/` に SpawnSystem の見本はありません。CheckpointSystem の `checkpoint_factory_component` が factory の派生の例です。

## 移行が要るもの（2026-11-08）
- `spawn_prefab_component` は GameSequenceSystem の FeatureKit から SpawnSystem の PrefabKit へ移りました。`using { GameSequenceSystem.FeatureKit }` → `using { SpawnSystem.PrefabKit }`。エディターに置いたものは、モジュールが変わったので置き直しが要ります（⚠ 未検証：UEFN で古い component がどう見えるか）。
- `Spawn():void`（作り直して 1 つ）→ `Spawn(Count:int):[]entity`（足す）。`Despawn():void` → `DespawnAll()`（`Despawn(Spawned)` は 1 つだけ消す）。`FindSpawned[]` → `GetSpawned()`。
- ToolTip の `SpawnCategory` / `SpawnPrefabToolTip`（GameSequenceSystem.TooltipKit）は、SpawnSystem.TooltipKit の `SpawnPrefabCategory` / `SpawnPrefabToolTip` などに変わりました。
