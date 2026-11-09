# MoverSystem

entity を、決まった地点やランダムな行き先へ順に動かす System です。地点のあいだを滑らかな曲線で一定の速さで進むこともできます（`mover_spline_route_component`）。中心の `mover_component` が速さ・待ち時間・動かし方を受け持ち、行き先の決め方は同じ entity に置く道のり（`mover_route_component` の派生。RouteKit）で選びます。起動の合図（ActivationSystem）で動き出し、停止の合図で一時停止します。`Restart` で道のりの最初からやり直せます（終わったあとでも）。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `mover_component` | 動かしたい entity（1 entity に 1 つ。実行時に作ってもよい） | 道のりが決める行き先へ `SpeedCmPerSecond` で順に動かす。着くと `WaitSeconds` 秒待って次へ。道のりが終わると止まる |
| `mover_path_route_component`（RouteKit） | `mover_component` と同じ entity | 決まった地点を `Mode`（Loop / PingPong / Once）で回る。地点は `Points`（コード）か、直下の子の `mover_waypoint_component` |
| `mover_spline_route_component`（RouteKit） | `mover_component` と同じ entity | 地点を滑らかな曲線（centripetal Catmull-Rom。地点を必ず通る）でつなぎ、曲線の上を一定の速さで進む。`Closed` で輪、開いた道は `Mode`（PingPong / Once）。地点は `Points`（コード）か、直下の子の `mover_waypoint_component` |
| `mover_waypoint_component`（RouteKit） | `mover_path_route_component` / `mover_spline_route_component` の entity の直下の、見た目の無い entity | 回る地点の目印。`Order` の小さい順に回る（子の並び順は使わない） |
| `mover_random_route_component`（RouteKit） | `mover_component` と同じ entity | 動き出した位置から `RadiusCm` 以内のランダムな点を次々に行き先にする（終わらない） |
| `mover_box_route_component`（RouteKit） | `mover_component` と同じ entity（実行時に作る） | `BoxMinCm`〜`BoxMaxCm` の直方体の中のランダムな点を次々に行き先にする（終わらない） |

道のりの component は 1 entity に 1 つまでです。道のりが無いと、`mover_component` は動かずにすぐ終わります（`FinishedEvent` が届く）。

例：「床が 3 か所を回る」
```
動く床（メッシュ + mover_component + mover_path_route_component）
├ 地点 A（mover_waypoint_component、Order = 1）
├ 地点 B（mover_waypoint_component、Order = 2）
└ 地点 C（mover_waypoint_component、Order = 3）
```
目印の位置は、動き出して最初の行き先を決めるときに 1 回だけ読みます。目印が床と一緒に動いても、地点は変わりません。

例：「床が 4 か所を通る輪を、滑らかに回る」（`mover_path_route_component` を `mover_spline_route_component` に替えるだけ）
```
動く床（メッシュ + mover_component + mover_spline_route_component（Closed = true、IncludeStart = false））
├ 地点 A（mover_waypoint_component、Order = 1。床を置いた位置と同じ）
├ 地点 B（mover_waypoint_component、Order = 2）
├ 地点 C（mover_waypoint_component、Order = 3）
└ 地点 D（mover_waypoint_component、Order = 4）
```
A → B → C → D → A を曲線で回り続けます。着いた知らせ（`TargetReachedEvent`）は地点ごとに届き、`WaitSeconds` も地点ごとに効きます。

### 曲線の道のり（mover_spline_route_component）
- 曲線は地点の区間ごとに `SubdivisionsPerSegment` 個（既定 8）の直線に分け、分けた点と「長さの表」（最初の地点からの曲線の長さ）を、動き出して最初の行き先を決めるときに 1 回作ります。mover は分けた直線を同じ速さで進むので、曲線の上の速さは一定です（曲がりの急な所でも速くも遅くもならない）。曲線の長さは `GetLengthCm`、曲線に沿った位置は `SampleAtDistance` で読めます。
- 地点が 2 つなら直線です（分けない）。3 つ以上で曲線になります。
- `Closed = true` なら最後の地点から最初の地点へも曲線でつなぎ、継ぎ目でも向きがなめらかに変わります（`Mode` は見ない）。`Closed = false` なら `Mode` で、`PingPong` は同じ曲線を逆にたどって戻り、`Once` は最後の地点で止まり、`Loop` は最後の地点から最初の地点へまっすぐ戻ります。
- `FaceTravelDirection = true` なら、進む向きに entity の向き（ヨー。前 = Forward 軸）を合わせます（既定オフ）。`PingPong` の折り返しでは、戻りの最初の短い区間で半回転します。`Restart()` は位置と一緒に向きも最初に戻します。
- 独自キャラクター（CharacterSystem）は、体に SurfaceKit の `character_ride_component` を付けると、当たり判定のある足場に乗ったとき運ばれます（体が接地の掃引で立っている entity の動きを、体が動く前と物理のあとの 2 回、体に足す。`FaceTravelDirection` で足場が回ると、体の位置も足場のまわりに回す（`character_ride_component.FollowYaw`、既定オン）。体の向きは変えない。跳んで離れると足場の速度を受け継ぐ（`InheritVelocity`、既定オン））。足場に `character_surface_component` は要りません（乗った・降りたの知らせが要るときだけ、体に `character_touch_component`、足場に `character_surface_component`）。
- なぜ mover_component と並ぶ別の部品にせず、道のり（RouteKit）にしたか：曲線を「行き先（地点）」と「そこまでの途中の点（`mover_leg.Via`）」に分ければ、速さ・待ち・`Play` / `Pause` / `Restart`・`SetSpeed`・着いた / 終わったの知らせ・Keyframe / Physics を `mover_component` のものがそのまま使えるため（ゲーム側で `mover_component` を探して使う部品もそのまま動く）。道のりの基底に、まっすぐでない道筋を返す `GetLeg`（既定はまっすぐ）を足し、`mover_component` は 1 つの地点までの途中の点をまとめて 1 回の `SetKeyframes` で再生します（分けた点ごとに組み直さないので、途中で止まらない）。

## よくある使い方
| したいこと | 書き方 |
|---|---|
| 片道で止まる（A → B で終わり） | `mover_path_route_component.Mode = Once`。最後の地点に着くと止まり、`FinishedEvent` / `mover_finished_event` が届く |
| 着いたことを知る | 地点ごとなら `TargetReachedEvent` / `mover_target_reached_event`（`WaitSeconds` の待ちの前）、道のりの終わりなら `FinishedEvent` / `mover_finished_event` |
| ノード（祖先）で着いたことを受ける | `AlsoSendUp = true`（知らせを親から上へも送る） |
| もう一度最初から動かす | `Restart()`（シミュレーション開始の位置と向きへ戻してから。一時停止中・終わったあとでも動き出す） |
| 今いる所から別の行き先へ 1 回だけ動かす | `Mode = Once` の道のりに `SetPoints(array{行き先})` を入れて `Restart(?ReturnToStart := false)` |
| ほかの物をすり抜ける | `Motion = Keyframe`（既定）。跳ね返りが要るときだけ `Physics` |
| 曲線で輪を回る・S 字に行き来する | `mover_spline_route_component`（輪は `Closed = true`、行き来は `Closed = false` と `Mode = PingPong`） |
| 進む向きを向かせる | `mover_spline_route_component.FaceTravelDirection = true` |
| 乗った独自キャラクターを運ぶ | 体に `character_ride_component`（CharacterSystem / SurfaceKit）。足場は当たり判定のあるメッシュ |

その場での回転（`mover_rotate_component` の案）・Fortnite のキャラクターを運ぶ・進み具合（0〜1）は、今はありません（下の「今は無いもの」）。

## 設定（@editable）
- `mover_component.Motion : mover_motion = mover_motion.Keyframe` — 動かし方。`Keyframe` はエンジン（`keyframed_movement_component`）が行き先までまっすぐ一定の速さで動かす（全員の画面で滑らか。ほかの物はすり抜ける。おすすめ）。`Physics` は毎フレーム Verse で動かし、ほかの物に当たると跳ね返る。
- `mover_component.SpeedCmPerSecond : float = 300.0` — 動く速さ（センチメートル毎秒。1〜10000）。
- `mover_component.StartOnBegin : logic = true` — オンならゲームの始めから動く。オフなら起動の合図か `Play` で動き出す。
- `mover_component.WaitSeconds : float = 0.0` — 行き先に着くたびに、次へ向かう前に止まっている時間（秒。0〜60）。
- `mover_component.BounceSeconds : float = 0.3` — Physics のとき、当たって跳ね返った向きに進む時間（秒。0〜10）。そのあと同じ行き先へ戻る。0 ならその行き先をあきらめて次へ。
- `mover_component.AlsoSendUp : logic = false` — オンなら知らせ（`mover_target_changed_event` / `mover_target_reached_event` / `mover_finished_event`）を、子孫へに加えて親から祖先へ（SendUp）も送る。自分の entity には 1 回だけ届く。
- `mover_path_route_component.Mode : mover_path_mode = mover_path_mode.Loop` — 地点の回り方。`Loop` は最後のあと最初へ戻る、`PingPong` は行き来する、`Once` は最後の地点で止まる。
- `mover_path_route_component.IncludeStart : logic = true` — オンなら動き出した位置を最初の地点（番号 0）にする。オフなら目印の地点だけを回る。
- `mover_spline_route_component.Closed : logic = false` — オンなら最後の地点から最初の地点へも曲線でつなぎ、輪を回り続ける（`Mode` は見ない）。地点は 3 つ以上（2 つなら直線の行き来）。
- `mover_spline_route_component.Mode : mover_path_mode = mover_path_mode.PingPong` — `Closed` でないときの回り方。`PingPong` は同じ曲線を行き来、`Once` は最後の地点で止まる、`Loop` は最後の地点から最初の地点へまっすぐ戻る。
- `mover_spline_route_component.IncludeStart : logic = true` — オンなら動き出した位置を最初の地点（番号 0）にする。オフなら目印の地点だけを通る（置いた位置と最初の目印が違えば、最初はそこへまっすぐ向かう）。
- `mover_spline_route_component.SubdivisionsPerSegment : int = 8` — 地点のあいだの曲線を分ける直線の数（1〜64）。地点が 2 つのときは 1。
- `mover_spline_route_component.FaceTravelDirection : logic = false` — オンなら進む向きに entity の向き（ヨー。前 = Forward 軸）を合わせる。傾きは変えない。
- `mover_waypoint_component.Order : int = 0` — 回る順番。小さい順。同じ数どうしの順は決まらない。
- `mover_random_route_component.RadiusCm : float = 1500.0` — 動き出した位置から行き先を選ぶ半径（センチメートル。100〜50000）。
- `mover_random_route_component.MinStepCm : float = 400.0` — 次の行き先を、今の位置から少なくともこれだけ先にする（センチメートル）。
- `mover_random_route_component.MaxDescentCm : float = 300.0` — 動き出した位置から下へ行ける深さ（センチメートル）。これより下の行き先はこの高さに上げる。0 なら下へ行かない。

コードで入れる値（エディターには出ない）：`mover_path_route_component.Points : []vector3` と `mover_spline_route_component.Points : []vector3`（空なら子の目印を使う）、`mover_box_route_component` の `BoxMinCm` / `BoxMaxCm : vector3`、`MarginCm : float = 0.0`（各面から内側へ空ける幅）、`MinStepCm : float = 100.0`。

## イベント
- `mover_target_changed_event`（scene_event、mover の entity から SendDown。`AlsoSendUp` なら親から SendUp も。次の 2 つも同じ）: `Mover : mover_component`、`Target : mover_target`。`mover_component` が次の行き先を決めて向かい始めたとき。消費しない。
- `mover_target_reached_event`（scene_event、SendDown）: `Mover : mover_component`、`Target : mover_target`。行き先に着いたとき（`WaitSeconds` の待ちの前）。消費しない。
- `mover_finished_event`（scene_event、SendDown）: `Mover : mover_component`。道のりが終わって止まったとき（`Once` の最後の地点に着いた・道のりの component が無い）。消費しない。
- `mover_path_changed_event`（RouteKit。scene_event、道のりの entity から SendDown）: `Route : mover_path_route_component`、`Points : []vector3`。`mover_path_route_component` が回る地点を決めたとき（動き出して最初の行き先を決めるとき・`SetPoints` のあと）。地点の目印や線の見た目用。消費しない。
- `mover_spline_changed_event`（RouteKit。scene_event、道のりの entity から SendDown）: `Route : mover_spline_route_component`、`Points : []vector3`（曲線が通る地点）、`CurvePoints : []vector3`（曲線を細かく分けた点。地点 i は `CurvePoints[i × 分割数]`。`Closed` なら最後は最初と同じ）。曲線を作ったとき（動き出して最初の行き先を決めるとき・`SetPoints` や `Restart` のあとの最初の行き先のとき）。曲線の線の見た目用。消費しない。
- `mover_component.TargetChangedEvent : listenable(mover_target)` — 次の行き先を決めて向かい始めたとき。
- `mover_component.TargetReachedEvent : listenable(mover_target)` — 行き先に着いたとき（`WaitSeconds` の待ちの前）。
- `mover_component.FinishedEvent : listenable(tuple())` — 道のりが終わって止まったとき。Loop / PingPong / ランダムの道のりでは届かない。`Restart` でやり直すと、また終わったときにもう一度届く。
- 受けるもの: `mover_component` は `activated_event`（動き出す・再開）と `deactivated_event`（その場で一時停止。次の起動で続きから）。

## 公開 API
```verse
mover_motion<public> := enum:
    Keyframe
    Physics

mover_component<public> := class<final_super>(component):
    Motion<public>:mover_motion
    SpeedCmPerSecond<public>:float
    StartOnBegin<public>:logic
    WaitSeconds<public>:float
    BounceSeconds<public>:float
    AlsoSendUp<public>:logic
    TargetChangedEvent<public><final>:listenable(mover_target)
    TargetReachedEvent<public><final>:listenable(mover_target)
    FinishedEvent<public><final>:listenable(tuple())
    Play<public>():void                                 # 動き出す・止まった位置から続ける
    Pause<public>():void                                # その場で一時停止
    Restart<public>(?ReturnToStart:logic = true):void   # 道のりの最初からやり直す（途中・一時停止中・終わったあとでも）。true なら開始の位置と向きへ戻してから、false なら今の位置から
    SetSpeed<public>(CmPerSecond:float):void            # 1 未満は 1。動いている途中の区間にもすぐ効く
    GetSpeedCmPerSecond<public>()<reads>:float          # SetSpeed で変えていなければ SpeedCmPerSecond
    IsMoving<public>()<decides><reads>:void             # Play されていて終わっていない。待ちのあいだも成功する
    IsFinished<public>()<decides><reads>:void
    FindTarget<public>()<decides><reads>:mover_target   # 動き出す前と終わったあとは失敗する
    FindStartPosition<public>()<decides><reads>:vector3 # シミュレーション開始の 1 フレーム後の位置（Restart で戻る位置）。読む前は失敗する

mover_target<public> := struct<computes>:
    Position<public>:vector3                            # 世界の位置（cm）
    Index<public>:int                                   # 決まった地点なら地点の番号、ランダムなら選んだ回数（0 から）

mover_target_changed_event<public> := class(scene_event):
    Mover<public>:mover_component
    Target<public>:mover_target

mover_target_reached_event<public> := class(scene_event):
    Mover<public>:mover_component
    Target<public>:mover_target

mover_finished_event<public> := class(scene_event):
    Mover<public>:mover_component

# 1 つの行き先へ向かう道筋（曲線の道のりが返す）
mover_leg<public> := struct<computes>:
    Via<public>:[]vector3                               # 行き先までに通る途中の点（世界の位置。行き先は含めない）。空ならまっすぐ
    FaceTravelDirection<public>:logic                   # 進む向きにヨーを合わせる

# 道のりの基底。派生は NextTarget を書く（回り方の状態を持つなら Reset も、まっすぐでない道筋なら GetLeg も）
mover_route_component<public> := class<abstract><final_super>(component):
    NextTarget<public>(Home:vector3, Position:vector3):?mover_target   # もう行き先が無ければ false（mover は止まる）
    Reset<public>():void                                               # 回り方の状態を最初に戻す（mover の Restart が呼ぶ）。既定は何もしない
    GetLeg<public>(From:vector3, Target:mover_target):mover_leg        # NextTarget のすぐあとに mover が呼ぶ。既定はまっすぐ（mover_leg{}）

# RouteKit
mover_path_changed_event<public> := class(scene_event):
    Route<public>:mover_path_route_component
    Points<public>:[]vector3

mover_path_mode<public> := enum:
    Loop
    PingPong
    Once

mover_path_route_component<public> := class<final_super>(mover_route_component):
    Mode<public>:mover_path_mode
    IncludeStart<public>:logic
    Points<public>:[]vector3
    SetPoints<public>(NewPoints:[]vector3):void         # 次の行き先から、新しい地点の最初から回り直す
    GetResolvedPoints<public>()<reads>:[]vector3        # 動き出す前は空
    GetWaypoints<public>()<transacts>:[]mover_waypoint_component   # 直下の子の目印を Order の小さい順に

mover_spline_changed_event<public> := class(scene_event):
    Route<public>:mover_spline_route_component
    Points<public>:[]vector3
    CurvePoints<public>:[]vector3

mover_spline_route_component<public> := class<final_super>(mover_route_component):
    Closed<public>:logic
    Mode<public>:mover_path_mode
    IncludeStart<public>:logic
    SubdivisionsPerSegment<public>:int
    FaceTravelDirection<public>:logic
    Points<public>:[]vector3
    SetPoints<public>(NewPoints:[]vector3):void         # 次の行き先から、新しい地点の最初から通り直す（曲線も作り直す）
    GetResolvedPoints<public>()<reads>:[]vector3        # 曲線が通る地点。動き出す前は空
    GetCurvePoints<public>()<reads>:[]vector3           # 曲線を分けた点。動き出す前は空
    GetLengthCm<public>()<reads>:float                  # 曲線の長さ（Closed なら 1 周）。動き出す前は 0
    FindDistanceAtPoint<public>(Index:int)<decides><reads>:float   # 最初の地点から地点 Index までの曲線の長さ（Closed なら Index = 地点の数 で 1 周）
    SampleAtDistance<public>(DistanceCm:float)<transacts>:vector3  # 曲線に沿って DistanceCm 進んだ位置（Closed なら回る、そうでなければ両端で止まる）
    GetWaypoints<public>()<transacts>:[]mover_waypoint_component

mover_waypoint_component<public> := class<final_super>(component):
    Order<public>:int

mover_random_route_component<public> := class<final_super>(mover_route_component):
    RadiusCm<public>:float
    MinStepCm<public>:float
    MaxDescentCm<public>:float

mover_box_route_component<public> := class<final_super>(mover_route_component):
    BoxMinCm<public>:vector3
    BoxMaxCm<public>:vector3
    MarginCm<public>:float
    MinStepCm<public>:float
```

## 前提・注意
- 動き出す位置は、シミュレーション開始の 1 フレーム後の位置です（spawner などが同じフレームに置き直すため）。
- Keyframe のとき、同じ entity に `keyframed_movement_component` が無ければ実行時に付けます。ほかの component で同じ entity を keyframe で動かさないでください。
- Keyframe の区間は親の entity から見た差分で作ります。親が回っていても世界の行き先に着くはずですが、実機で確かめていません（`MoverComponent.verse` の前提・注意に「⚠ 実機で確かめる」）。
- 同じ entity に道のりの component（`mover_route_component` の派生）が無いと、動かずにすぐ終わり（`FinishedEvent` / `mover_finished_event` が届く）、出力ログに `[mover_component] 同じ entity に道のりの component…がありません` と出ます。
- Physics のときは当たり判定のあるメッシュが要ります（動く先を `FindSweepHits` で調べる）。
- ランダムの道のりは、何回か選んでも `MinStepCm` 以上先が見つからなければ、そのままの点を使います。
- SpawnSystem で出した entity を Keyframe で動かすなら、spawner の `AppearSeconds` を 0 にします（大きさの変化が毎フレーム `SetGlobalTransform` するため）。
- `Restart` は、Keyframe なら再生中の区間を `keyframed_movement_component.Stop` で止めてから `SetGlobalTransform` で開始の位置へ戻します。止めたあとの位置の扱い（エンジンが止めた位置を全員に送り直すか）は実機で確かめていません（`MoverComponent.verse` の `PrepareRestart`。⚠ 未検証）。
- `Restart(?ReturnToStart := false)` は道のりの Home（`IncludeStart` の最初の地点・ランダムの中心）も今の位置にします。次の `Restart()`（既定）で戻るのは、いつもシミュレーション開始の位置です。
- 曲線の道のり：Keyframe のとき、1 つの地点までの途中の点をまとめて 1 回の `SetKeyframes`（分けた区間ごとの keyframe）で再生します。地点に着くたびに次の区間を組み直すので、`WaitSeconds = 0` でも地点で 1 フレームほど止まることがあります（⚠ 未検証：`_Test` の `mover_spline_test_component` が出す `worst speed error` で分かる）。
- 曲線の道のりの `FaceTravelDirection`：Keyframe では区間ごとの keyframe にヨーの回転を足します。keyframe の位置の差分（加算）が、その回転で回されずに親から見た向きのまま足される前提です（⚠ 未検証：`mover_spline_test_component` の `still arrives at the goal` で分かる）。ヨーの回す向きは `MakeRotationRadians` で回した前の軸を見て決めます。Physics では毎フレーム進む向きへヨーだけを向けます（傾きは無くなる）。
- Physics の曲線は、分けた点ごとに着いてから次へ進むので、点ごとに 1 フレームの端数ぶん少し遅くなります（Keyframe はちょうど一定）。
- 曲線は地点の位置だけで決まります（地点の向き・接線は使わない）。centripetal（点の間隔の平方根を媒介変数の幅にする）なので、間隔のばらばらな地点でも、とがったり小さな輪になったりしにくい。開いた道の両端は、端の地点で折り返した点を外側に足して作ります。
- 実験的な API は使っていません。

## 今は無いもの
- その場での回転（`mover_rotate_component` の案。進む向きに合わせるのは `mover_spline_route_component.FaceTravelDirection` でできる）、乗っている人を一緒に運ぶ（`CarryRiders`。独自キャラクター（CharacterSystem）なら、体に SurfaceKit の `character_ride_component` を付けると運ばれる。Fortnite のキャラクターは今も運ばない）、Physics でプレイヤーにだけ当たらない設定（`IgnorePlayers`）、進み具合（`GetProgress`）、道なりの経路（PathKit の `path_follower_component`）。ジャンル実装の要望（`GAP_SUMMARY.md` の L-17）にあるが、2026-11-08 の時点では入れていない。

## 確かめ方
- テスト：`_Test/MoverSystemTest/` の `mover_system_test_component`。まわり 10 メートルに何も無い空中の entity に付けるだけです（動かす entity はテストが自分の子に作る。プレイヤーは要らない）。道のりの回り方（Loop / PingPong / Once）と `IncludeStart`、`Order` の並び、Keyframe の到着時間と位置、`Pause` / `Play`、`SetSpeed`、終わりの知らせ、Physics の到着、道のりの `Reset`、`Restart`（開始の位置へ戻ってもう一度・今の位置から入れ替えた地点へ）、`AlsoSendUp`（親の entity で受ける）を確かめます。約 6 秒かかります。結果は出力ログの `[TEST] MoverSystem`。
- テスト（曲線）：`_Test/MoverSystemTest/MoverSplineTest.verse` の `mover_spline_test_component`。置き方は上と同じ（まわり 10 メートルに何も無い空中の entity に付けるだけ）。数値で、曲線の長さ（2 点の直線はちょうど・円の上の 8 点の輪は円周の 1% 以内）、地点を通ること、長さの表で等しい長さごとに取った点が等間隔なこと、輪の継ぎ目（最後 → 最初の区間も曲線・継ぎ目の曲がり方が途中と同じ・1 周で同じ位置）、PingPong の番号の順と戻りの途中の点が行きの逆の順なこと、開いた道の Loop がまっすぐ戻ることを確かめます。動かして（Keyframe）、輪を 1 周する時間が 長さ ÷ 速さ、0.2 秒ごとの速さが一定で円から外れないこと、PingPong で折り返して戻る時間と戻りの途中の位置、`FaceTravelDirection` で進む向きを向いて位置もずれないこと、`Restart` で最初の向きに戻ることを確かめます。約 7 秒。結果は出力ログの `[TEST] MoverSpline`（`worst speed error` の行に、速さの外れの最大と円からの外れの最大も出る）。
- `_Samples/` に MoverSystem の見本はありません。作者のゲームの足場のマップが、輪と S 字の `mover_spline_route_component` を使っています。

## 移行が要るもの（2026-11-08）
- 追加（曲線）：RouteKit の `mover_spline_route_component` と `mover_spline_changed_event`、MoverSystem の `mover_leg` と `mover_route_component.GetLeg`（既定はまっすぐなので、今ある道のりと自分で書いた派生はそのまま動く）。
- `Restart()`（`ReturnToStart` が true）は、位置に加えて向きもシミュレーション開始のときに戻すようにしました（今までは向きはそのまま）。向きを変えない道のりでは違いはありません。
- 追加：`Restart`・`AlsoSendUp`・`FindStartPosition`・`mover_route_component.Reset`。
- `mover_target_changed_event.Mover`・`mover_target_reached_event.Mover`・`mover_finished_event.Mover` の型を `component` → `mover_component` にしました（Library 全体の決まり「送り元は具体型のまま」にそろえた）。受ける側で `mover_component[Event.Mover]` とキャストしていたなら、キャストを外して `Event.Mover` をそのまま使います（キャストを残しても動く）。`component` 型の変数に入れていたコードはそのまま動きます。
- `mover_path_changed_event` を MoverSystem の直下から RouteKit へ移し、`Route` の型を `component` → `mover_path_route_component` にしました。`using { MoverSystem }` だけで受けていたコードは `using { MoverSystem.RouteKit }` を足します。
- 自分で `mover_route_component` の派生を書いていて、回り方の状態（今の番号など）を持つなら、`Reset<override>()` でその状態を最初に戻すと `Restart` が効きます（書かなければ、やり直しても続きの行き先から）。
