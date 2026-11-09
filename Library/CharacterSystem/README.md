# CharacterSystem

Fortnite のキャラクターの動きを使わず、entity を Verse で動かす「独自キャラクター」の System です。体（`character_motor_component`）が自前の重力・カプセルの掃引・接地を受け持ち、歩く・ジャンプ・ダッシュ・向き・入力・反応・条件は同じ entity や子孫に置く部品で足します。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `character_motor_component` | 独自キャラクターの entity（見た目のメッシュの親）。プレイヤーごとに動かすなら、その entity をロードアウトのプレハブ（LoadoutSystem の `loadout_component.Prefab`）に入れる | 毎フレーム、速度に重力（落ちるときは強め）を足し、カプセルを掃引して当たったら面に沿って滑り（天井の角・低い段は補正して越える）、地面を探して接地を決める（坂・低い段に吸い付く）。入力は知らない（`LockInput` で部品の入力を止められる） |
| `character_walk_component`（MoveKit） | `character_motor_component` と同じ entity | 入力の向きに加速して歩く・走る。入力が無ければ止まる。切り返しは加速を強める |
| `character_jump_component`（MoveKit） | 同上 | 入力でジャンプする（コヨーテタイム・先行入力・空中ジャンプ・離すと低くなる・頂点で少し浮く） |
| `character_dash_component`（MoveKit） | 同上 | 入力で短く鋭く突進する（決まった時間・距離。終わると歩く速さまで落とす。待ち時間・空中の回数・エネルギー） |
| `character_face_movement_component`（BodyKit） | 同上 | entity の水平の向きを回す。向ける先は walk の左右の入力のしかた（`Turn` = 動いている方向、`Strafe` = 歩く向きの前、`TankTurn` = 回さない（walk が回す））。walk が無ければ `Turn` |
| `character_owner_stasis_component`（BodyKit） | 同上 | 動いているあいだ、持ち主の Fortnite のキャラクターを PutInStasis でその場に固定して隠す（独自キャラクターは独立して動く。Fortnite のキャラクターは動かさない） |
| `character_input_mapping_component`（BodyKit） | 独自キャラクターの entity か子孫（持ち主のいる場所） | 持ち主に入力の割り当て（`input_mapping`）を足し、止まると外す |
| `character_action_trigger_component`（EventKit） | 独自キャラクターの entity か子孫 | 決めたこと（着地・ジャンプなど）が起きるたびに `Targets`（空ならこの entity と子孫）へ起動の合図を送る |
| `character_motor_condition_component`（ConditionKit） | 独自キャラクターの entity の子孫。そのうえで `ability_grant_condition_component` / `game_transition_component` / `condition_all` / `condition_any` の entity の直下 | 体が決めた状態（空中・動いているなど）のあいだ満たす |
| `character_camera_component`（CameraExperimentalKit） | `character_motor_component` と同じ entity | 持ち主の視点を、独自キャラクターに付いていくカメラにする（実験的） |
| `character_surface_component`（SurfaceKit） | 足場・壁・ギミック・ゴールの entity（メッシュと同じ entity） | 独自キャラクターが「触れた・乗った」を知れる箱（entity の位置・回転・大きさから決める）。開始時に `character_surface_tag` を付ける |
| `character_touch_component`（SurfaceKit） | `character_motor_component` と同じ entity | 毎フレーム、体の箱と近くの面の箱を比べ、触れ始めた・離れた・乗った・降りたを知らせる |
| `character_ride_component`（SurfaceKit） | `character_motor_component` と同じ entity | 体が立っている物（接地の掃引で当たった entity）が動いたら、体も同じだけ動かす（MoverSystem の動く足場に乗る）。離れるときは足場の速度を受け継ぐ。`character_touch_component`・足場の `character_surface_component` は要らない |
| `character_buff_component`（BuffKit） | 起動の合図が届く場所（PickupSystem の効果のプレハブ・ロードアウトの中・体の子） | 起動の合図から停止の合図まで、体に速さ・ジャンプ・重力の倍率を重ねる（重ねると掛け合わせ。止まると必ず外す） |
| `character_move_grant_component`（BuffKit） | 同上 | 起動の合図から停止の合図まで、体に空中ジャンプの回数を足し、ダッシュを許す（dash の `RequiresGrant`） |

`character_motor_component` 以外の部品は、`FindCharacterMotorAbove`（同じ entity か祖先）で体を探します。

例：「全員に、歩いて跳べる独自キャラクターを付け、着地で音を鳴らす」（動く足場に乗るなら、体に `character_ride_component` も足す。触れた・乗ったを知るなら、体に `character_touch_component`、足場に `character_surface_component` も付ける）
```
ロードアウト（loadout_component（LoadoutSystem）、Prefab = 下のプレハブ、ActiveOnBegin = true）

プレハブ
└ 体（character_motor_component + character_walk_component + character_jump_component + character_owner_stasis_component）
  ├ 見た目（メッシュ）
  └ 着地（character_action_trigger_component、Action = Landed）
    └ 音（device_audio_component（FNDeviceSystem））
```
プレハブは人ごとにその人の slot の下に作られるので、体の持ち主はその人になります。歩く入力（`MoveAction` か 4 つのボタン）を使うなら、その入力を入れた割り当てを `character_input_mapping_component` で持ち主に足します。ジャンプの既定 `Character.Jump` は Fortnite の `TraversalMapping` に入っています。

## 設定（@editable）
体（`character_motor_component`）
- `RadiusCm : float = 40.0` — カプセルの半径（cm、5〜1000）。
- `HeightCm : float = 180.0` — カプセルの高さ（cm、足元から頭まで、10〜2000）。entity の位置が足元（底の中心）。
- `GravityCmPerSecondSquared : float = 1960.0` — 重力の加速度（cm/s²、0〜20000）。
- `MaxFallSpeedCmPerSecond : float = 4000.0` — 落ちる速さの上限（cm/s）。
- `MaxSlopeDegrees : float = 50.0` — 立っていられる坂の上限（度、0〜89）。これより急な面は壁として滑る。
- `FallGravityMultiplier : float = 1.6` — 下がっているとき（上下の速さが負）の重力に掛ける倍率（0.1〜10）。1 なら上がるときと同じ（今までの動き）。ジャンプのあとだけでなく、縁から歩いて落ちたとき・打ち上げられて落ちるときも掛かる。
- `GroundProbeCm : float = 10.0` — 空中から下がってきたとき、足元から下へ地面を探す距離（cm、0〜200）。この距離までに地面があれば吸い付く。
- `GroundSnapCm : float = 20.0` — 地面にいた体が、地面に沿って動いているあいだ（ジャンプ・打ち上げで離れていないあいだ）下へ探す距離（cm、0〜200）。坂を下る・低い段を降りるときに浮かずに吸い付く。`GroundProbeCm` より小さければ `GroundProbeCm`。0 で使わない。
- `StepUpCm : float = 15.0` — 地面にいて（跳んで離れるところでなく）水平に動いているときに、足元が段の角に当たったら乗り上げる高さの上限（cm、0〜200）。階段で使う。空中では使わない。0 で使わない。
- `LedgeAssistCm : float = 0.0` — 空中で下がっているときに、足元が縁の角に当たったら乗り上げる高さの上限（cm、0〜200。ジャンプが少し届かなかった縁の補助）。0 で使わない。
- `CornerCorrectionCm : float = 12.0` — 上がっている途中で頭が天井（下向きの面）の角にかすったとき、横へずらして上がり続ける距離の上限（cm、0〜100）。速度は落ちない。壁には使わない。0 で使わない。
- `MovingSpeedCmPerSecond : float = 10.0` — 水平の速さがこれを超えたら「動いている」。
- `AxisLock : character_axis_lock = None` — 動ける向きを平面に縛る。`Left` なら左右の位置を開始時（か `TeleportTo` した位置）のまま保つ（横スクロール）。
- `SpawnAtOwner : logic = true` — オンなら、開始時に持ち主の Fortnite キャラクターの位置へ移る。

歩く（`character_walk_component`）
- `MoveAction : ?input_action(vector3) = false` — 方向の入力。`ForwardAction` / `BackAction` / `LeftAction` / `RightAction : ?input_action(logic) = false` — 4 つのボタン。`SprintAction : ?input_action(logic) = false` — 押しているあいだ走る。入力はこの 3 通りとコードの `SetMoveInput` を足し合わせる（長さ 1 まで）。
- `Space : character_walk_space = View` — 歩く向きを何に合わせるか（View = 持ち主の視点、World = 世界、Facing = キャラクターの向き、SideView = 横スクロール。入力の左右で世界の前後に動く）。
- `MaxSpeedCmPerSecond : float = 600.0`、`AccelerationCmPerSecondSquared : float = 4000.0`、`BrakingCmPerSecondSquared : float = 5000.0`。
- `SprintMultiplier : float = 1.6` — 走るときの倍率（1〜10）。
- `TurnAroundMultiplier : float = 2.0` — 地面の切り返し（入力の向きが今の水平の動きと 90 度より大きく違う）のとき、加速に掛ける倍率（1〜10）。1 なら普通の加速と同じ。空中は `AirTurnAroundMultiplier`。
- 空中の制御（体が接地していないとき）：
  - `AirControlRatio : float = 0.6` — 空中で入力の向きへ加速するときの、`AccelerationCmPerSecondSquared` に掛ける倍率（0〜1。0 で空中では操作できない）。既定で 2400 cm/s²（0 から 600 cm/s まで約 0.25 秒。ジャンプの滞空は既定で約 0.8 秒）。
  - `AirBrakingRatio : float = 0.2` — 空中で入力が無いときの、`BrakingCmPerSecondSquared` に掛ける倍率（0〜1。0 で減速しない）。既定で 1000 cm/s²（600 cm/s が 0 になるまで約 0.6 秒。短いジャンプでは勢いが残り、長いジャンプの終わりにはほぼ止まる）。
  - `AirTurnAroundMultiplier : float = 2.0` — 空中の切り返しのとき、空中の加速に掛ける倍率の上限（1〜10。地面の `TurnAroundMultiplier` の代わり）。入力の向きが今の動きと逆向きなほど大きく掛かる（真横で 1 倍、真逆でこの倍率。90 度を境に急に変わらない）。既定で真逆なら 4800 cm/s²（600 cm/s から逆向きの 600 cm/s まで約 0.25 秒。地面の切り返し 8000 cm/s² の 0.6 倍＝ `AirControlRatio` とそろう）。
  - `KeepAirMomentum : logic = true` — オンなら、空中で上限（歩く・走る速さ）より速い分（はじき・打ち上げで得た速さ）を、入力の向きへ曲げるだけで減らさない（逆向きに入れたときだけ減る）。入力で上限より速くはならない。オフなら空中でも入力の速さへ近づける（上限まで減らす）。ダッシュの速さは、dash が終わるときに上限までに切るので残らない。
  - 動く床から受け継いだ速度（体の `GetInheritedVelocity`。SurfaceKit の `character_ride_component`）の分は、入力が無くても減速しない（跳んでも床と一緒に進む）。逆向きに入れる・壁に当たると減り、減った分は戻らない（あとで同じ向きに入れても、減速しない分として戻らない）。
  - ダッシュの突進のあいだ（体の `IsMoveOverridden`、internal）は、walk は速度を変えない（入力の向きだけ覚える）。
- `SideStyle : character_side_style = Turn` — 左右の入力でどうするか（基本の値）。`Turn` = 左右へ動き、体は動く向きへ回る（今までどおり）。`Strafe` = 左右へ動くが、体は歩く向きの前（`Space = View` なら視点の向き）を向いたまま（カニ歩き。止まっているあいだも前へ回す）。`TankTurn` = 左右では動かずその場で回り、前後は体の向きへ動く（`Space` は使わない）。体に重ねた変更（`character_modifier.SideStyle`・BuffKit）が決めているあいだはそちらが優先。
- `TankTurnDegreesPerSecond : float = 180.0` — `TankTurn` のとき、左右の入力で 1 秒に回る角度（度、0〜3600）。
- `SideStyleToggleAction : ?input_action(logic) = false` — 押すたびに基本を `SideStyle` と `ToggleSideStyle` で切り替えるボタン（使わなければ空）。`ToggleSideStyle : character_side_style = Strafe` — 切り替える先。

ジャンプ（`character_jump_component`）
- `JumpAction : input_action(logic) = Character.Jump`。
- `JumpSpeedCmPerSecond : float = 900.0` — 跳んだ瞬間の上向きの速さ。`AirJumps : int = 0` — 空中で跳べる回数（2 段ジャンプなら 1）。
- `CoyoteSeconds : float = 0.12` — 歩いて地面を離れてからも地面のジャンプとして扱う秒数（0 で使わない）。自分のジャンプで離れたときは使えない。コヨーテタイムのジャンプは空中ジャンプの回数を減らさない。
- `BufferSeconds : float = 0.12` — 着地より前に押したジャンプを覚えておき、着地した瞬間に跳ぶ秒数（0 で使わない。0 でも前のフレームから今までの押しは使う）。空中ジャンプが残っていれば、押したときに空中ジャンプになる（先行入力にはならない）。
- `ReleaseCutRatio : float = 0.5` — 跳んでから上がっている途中で離したとき、上向きの速さに掛ける倍率（1 なら変えない）。1 回のジャンプに 1 回、下がり始めたら掛けない。
- `ApexSpeedThresholdCmPerSecond : float = 150.0` — 頂点の浮き：跳んでから押したまま、空中で上下の速さ（絶対値）がこれより遅いあいだ重力を弱める（cm/s、0〜5000）。0 で使わない。
- `ApexGravityMultiplier : float = 0.5` — 頂点の浮きのあいだの重力の倍率（0〜1。体の `FallGravityMultiplier` の代わりに使う）。1 なら弱めない。

ダッシュ（`character_dash_component`）
- `DashAction : ?input_action(logic) = false` — 空ならコードの `Dash` だけで出す。
- `DashSpeedCmPerSecond : float = 2200.0`、`DurationSeconds : float = 0.18`（距離は 速さ × 時間 ＝ 既定で 396 cm。フレームの長さによらない）、`CooldownSeconds : float = 0.8`（出した瞬間から数える）、`AirDashes : int = 1`（空中で出せる回数。地面に降りると戻る）。
- `DashEndSpeedRatio : float = 1.0` — 突進が終わったとき、ダッシュの向きの速さを「walk の `MaxSpeedCmPerSecond` × 変更の速さの倍率（走るボタンは含めない）× これ」までに切る（0〜2。0 ならその場で止まる）。横の速さは消す。walk が無ければ 600 cm/s を歩く速さとする。
- `DashGravityScale : float = 0.0` — 突進のあいだ重力に掛ける倍率（0〜1。0 なら空中のダッシュは高さが変わらない）。体の `ScaleGravityThisFrame` で掛ける（`SetGravityScale` は変えない）。
- 流れ（既定値）：0 秒で向きを決め（walk の入力の向き → 今の水平の動き → 体の向き。`AxisLock` の軸は除く）、水平の速度を 2200 cm/s に、空中なら上下の速さを 0 にする → 0.18 秒のあいだ毎フレーム同じ速さ（重力 0 倍、walk は速度を変えない）→ 終わりにダッシュの向きの速さを 600 cm/s（歩く速さの上限）に切る → 出してから 0.8 秒で次を出せる。突進の途中で跳ぶ（`Jumped` / `AirJumped`）・`LockInput` したら、その場で終えて同じように速さを切る（ダッシュの速さのまま跳ばない）。出した瞬間に、動く床から受け継いだ速度（`GetInheritedVelocity`）を消す。
- `EnergyCost : float = 0.0` — 1 回に使うエネルギー（0 なら使わない）。`FindEnergyAbove`（EnergySystem）で見つけた `energy_component` から払い、足りなければ出せない。

BodyKit
- `character_face_movement_component.TurnSpeedDegreesPerSecond : float = 720.0` — 1 秒に回る角度（0 ならすぐ向く）。`Turn` でも `Strafe` でもこの速さで回る（`TankTurn` は walk の `TankTurnDegreesPerSecond`）。
- `character_face_movement_component.AirFacesInput : logic = true` — オンなら、`Turn` のとき空中では動いている方向ではなく walk の入力の向き（`GetInputDirection`）へ回す（入力が無ければ向きを変えない。動く床から受け継いだ勢い・はじかれた向きへは回らない）。オフなら空中でも動いている方向へ（前の動き）。地面ではどちらも動いている方向。
- `character_owner_stasis_component` — 設定なし（固定して隠すだけ。付いていかせる設定は持たない：独自キャラクターは物理・当たり・動きをすべて自前で持つため）。
- `character_input_mapping_component.Mapping : ?input_mapping = false` / `SecondMapping : ?input_mapping = false` — 足す割り当て（2 つまで。アセットの配列は MCP で書けないため 1 つずつのフィールド。3 つ以上なら子の entity にこの部品をもう 1 つ置く）。`RemoveOnEnd : logic = true` — 止まるときに外す（`TraversalMapping` など Fortnite の割り当てを入れたときはオフにする）。

EventKit / ConditionKit
- `character_action_trigger_component.Action : character_action = Landed` — 見張ること。`Targets : []entity = array{}` — 起動の合図を送る entity（空ならこの entity と子孫）。`CooldownSeconds : float = 0.0` — 次を無視する秒数。
- `character_motor_condition_component.State : character_motor_state = Airborne` — 満たす状態。

ダッシュ（続き）
- `RequiresGrant : logic = false` — オンなら、体に「ダッシュを許す変更」（`character_modifier.GrantsDash`。BuffKit の `character_move_grant_component.GrantDash`）が重なっているあいだだけ出せる（拾ったら使える能力にする）。

BuffKit（どの体に効かせるか：この entity か祖先の体 → 持ち主の体 → だれが起こしたかの分かる起動の合図の人の体）
- `character_buff_component.SpeedMultiplier : float = 1.0`（walk の最高速に掛ける）、`JumpMultiplier : float = 1.0`（跳ぶ速さに掛ける。高さはおよそ 2 乗）、`GravityMultiplier : float = 1.0`（重力に掛ける）、`ActiveOnBegin : logic = false`（オンなら開始から）。どれも 0〜10。
- `character_buff_component.OverrideSideStyle : logic = false` — オンなら、重ねているあいだ walk の左右の入力のしかたを `SideStyle : character_side_style = Strafe` にする（拾うとカニ歩き・その場で回るに変わる効果。PickupSystem の効果のプレハブに入れればコードは要らない）。いくつも重なれば最後に重ねたものが勝ち、全部外れると walk の基本に戻る。
- `character_move_grant_component.ExtraAirJumps : int = 1`（空中ジャンプに足す。空中で増えたらすぐ使える）、`GrantDash : logic = false`、`ActiveOnBegin : logic = false`。

SurfaceKit
- `character_surface_component.SizeCm : vector3 = vector3{}` — 箱の大きさ（cm）。すべて 0 より大きければこれを使い、entity の大きさは見ない。`MeshSizeCm : float = 100.0` — `SizeCm` を使わないとき、entity の大きさ（Scale）に掛ける一辺（100 cm の立方体のメッシュなら 100）。`PivotAtBottom : logic = true` — entity の位置を箱の底面の真ん中とする（オフなら箱の真ん中）。
- `character_touch_component.TouchMarginCm : float = 8.0` — 体の箱に足す余白（体は面の手前 2 cm で止まるので、それより大きくする）。`StandToleranceCm : float = 15.0` — 足元の高さが面の上面からこの距離以内なら「乗っている」。`SearchRadiusCm : float = 3000.0` — 足元からこの距離以内の面だけを候補にする。`RefreshSeconds : float = 0.5` — 候補を探し直す間隔。
- `character_ride_component.MaxCarryCm : float = 300.0` — 1 フレームにこれより大きく動いた床には付いていかない（ワープ・やり直しで連れて行かれないように）。`FollowYaw : logic = true` — 床がヨーで回ったとき、体の位置も床の位置（entity の原点）のまわりに同じだけ回す（体の向きは変えない。MoverSystem の `mover_spline_route_component.FaceTravelDirection` で回る足場など）。オフなら床の位置の動きだけを足す。
- `character_ride_component.GraceSeconds : float = 0.1` — 接地が一瞬切れても、足元から下 50 cm 以内にまだ同じ床があれば、この秒数までは乗っているとして運び続ける（0〜2。上向きに離れたとき（ジャンプ）は使わない）。0 で使わない。
- `character_ride_component.InheritVelocity : logic = true` — オンなら、動く床から離れたとき（ジャンプ・縁から落ちた・`GraceSeconds` を過ぎた）に床の速度（下向きの速さは除く。回る床なら足元の速度）を体の速度に足す（walk は空中でこの分を減速しない）。空中から乗ったときは、体の水平の速度のうち床の動く向きの分を床の速さまで消す（跳んで同じ床に戻っても滑らない。止まった所から乗ったときは消す分が無いので、乗った瞬間から床と一緒に動く）。オフなら足さない・消さない。

CameraExperimentalKit（`character_camera_component`）
- `Projection : character_camera_projection = Perspective`、`OffsetCm : vector3 = vector3{Forward := -600.0, Up := 250.0}`（足元からのずらし）、`YawDegrees : float = 0.0`、`PitchDegrees : float = -15.0`（負で見下ろす）、`FieldOfViewDegrees : float = 90.0`（Perspective の水平の画角）、`OrthographicWidthCm : float = 3000.0`（Orthographic で横幅に写る長さ）、`Priority : int = 10`。

## イベント
- `character_action_event`（scene_event、SendUp）: `Trigger : character_action_trigger_component`、`Action : character_action`。`character_action_trigger_component` の entity から根へ。消費しない。
- 起動の合図：`character_action_trigger_component` は、持ち主がいれば `SendActivatedBy(持ち主)`（`activated_by_agent_event`）、いなければ `SendActivated` を `Targets` へ送る。
- `character_motor_component.PreMoveEvent : listenable(float)` — 毎フレーム、動かす前に（前のフレームからの秒数）。動きの部品はここで `AddVelocity` / `SetVelocity` する。
- `character_motor_component.PostMoveEvent : listenable(float)` — 毎フレーム、動かしたあとに。位置を読んで合わせる部品（body_link・向き・条件）が使う。
- `character_motor_component.ActionEvent : listenable(character_action)` — 起きたことのたびに届く。`Landed` / `LeftGround` / `StartedMoving` / `StoppedMoving` / `HitWall` は体が、`Jumped` / `AirJumped` は jump が、`Dashed` は dash が（`ReportAction` で）知らせる。
- `character_motor_component.LandedEvent : listenable(float)` — 空中から地面に降りるたびに、降りた瞬間の下向きの速さ（cm/s、0 以上）で届く。`ActionEvent` の `Landed` のすぐあと（`Landed` を受けた処理からは `GetLastLandingSpeed` で同じ値を読める）。着地のつぶれ・土煙・音の大きさに使う（見た目は持たない）。段の補正で縁に乗ったときも届く。
- `character_walk_component.SideStyleChangedEvent : listenable(character_side_style)` — 今の左右の入力のしかた（`GetSideStyle`）が変わるたびに、新しいしかたで届く。`SetSideStyle`・`SwitchSideStyle`・切り替えのボタンなら呼んだときすぐ、体に重ねた変更が付いた・外れたときは次のフレームの動きの前（walk が毎フレーム見比べる）。開始時のしかたは届かない（`GetSideStyle` で読む）。
- `character_action_trigger_component.TriggeredEvent : listenable(character_action)` — `Action` が起きるたび（`CooldownSeconds` で無視したものを除く）。
- `character_motor_condition_component` は `condition_changed_event` を上へ送る（ConditionSystem）。体が動いたあと毎フレーム状態を見て、変わったときだけ。
- `character_surface_contact_event`（scene_event、SendUp）: `Surface : character_surface_component`、`Motor : character_motor_component`、`Agent : ?agent`（体の持ち主）、`Contact : character_surface_contact`（`Touched` / `Untouched` / `SteppedOn` / `SteppedOff`）。面の entity から根へ。送り手は `character_touch_component`。消費しない。
- `character_touch_component.ContactEvent : listenable(tuple(character_surface_component, character_surface_contact))` — 体の側。触れ方が変わるたびに（その面, 触れ方）。順番は 降りた → 離れた → 触れ始めた → 乗った。
- `character_surface_component.ContactEvent : listenable(tuple(character_motor_component, character_surface_contact))` — 面の側。同じ知らせが（その体, 触れ方）で届く。ギミックはこれを購読する。

## タグ
- `character_modified_tag`（`player_state_tag` の派生。抽象）と派生 `character_speed_modified_tag` / `character_jump_modified_tag` / `character_gravity_modified_tag`（倍率が 1 でない `character_buff_component`）/ `character_air_jumps_added_tag` / `character_dash_granted_tag`（`character_move_grant_component`）/ `character_side_style_modified_tag`（`OverrideSideStyle` の `character_buff_component`）— 重ねているあいだ体の持ち主に付く（重ねると同じ型が 2 つ以上付く）。
- `custom_character_tag`（`player_state_tag` の派生）— 持ち主のいる `character_motor_component` が、動いているあいだ持ち主（agent）に付け、止まると外す。
- `character_surface_tag`（entity の役割のタグ。`tag` の派生）— `character_surface_component` が開始時に自分の entity に付け、止まると外す。`character_touch_component` はこのタグで面を探す（`SetSearchRoot` で探す場所を絞れる）。

## 持ち主
体はプレイヤーの slot の下（ロードアウトの中など）に置くと持ち主が決まり（`FindOwningPlayer`）、その人だけのキャラクターになります。持ち主は `OnBeginSimulation` のときに一度だけ決めます。
- `character_motor_component`：持ち主に `custom_character_tag` を付ける。`SpawnAtOwner` なら持ち主の Fortnite キャラクターの位置へ移る。持ち主の Fortnite キャラクターには当たらない。持ち主がいなくても物理は動く（テストはこの形）。
- walk / jump / dash：持ち主の入力（`AwaitPlayerInput`）を読む。持ち主がいないと入力は受けないが、`SetMoveInput` / `Jump` / `Dash` はコードから使える。walk の `Space = View` は持ち主の視点の向き。
- `character_owner_stasis_component`・`character_camera_component`・`character_input_mapping_component`：持ち主がいないと何もしない（camera と input_mapping は出力ログに出す）。
- `character_action_trigger_component`：持ち主がいれば、その人が起こした起動の合図にする（`FindActivatingAgent` で読める）。
- `Entity.FindCharacterMotorFor[Agent]`：区画の `player_manager_component` からその人の slot を探し、その下で持ち主がその人の体を返す。

## 公開 API
```verse
character_action<public> := enum:
    Jumped
    AirJumped
    Dashed
    Landed
    LeftGround
    StartedMoving
    StoppedMoving
    HitWall

character_motor_state<public> := enum:
    Grounded
    Airborne
    Rising
    Falling
    Moving
    Still

character_axis_lock<public> := enum:
    None
    Left
    Forward

character_side_style<public> := enum:                                  # 左右の入力でどうするか（walk が持ち、face が読む）
    Turn                                                               # 左右へ動き、体は動く向きへ回る（既定）
    Strafe                                                             # 左右へ動くが、体は歩く向きの前を向いたまま（カニ歩き）
    TankTurn                                                           # 左右ではその場で回り、前後は体の向きへ動く

custom_character_tag<public> := class(player_state_tag):

character_motor_component<public> := class<final_super>(component):
    RadiusCm<public>:float
    HeightCm<public>:float
    GravityCmPerSecondSquared<public>:float
    MaxFallSpeedCmPerSecond<public>:float
    FallGravityMultiplier<public>:float                                     # 下がっているときの重力の倍率
    MaxSlopeDegrees<public>:float
    GroundProbeCm<public>:float
    GroundSnapCm<public>:float                                              # 地面に沿って動いているときに下へ探す距離
    StepUpCm<public>:float                                                  # 乗り上げる段の高さの上限（地面にいるときだけ）
    LedgeAssistCm<public>:float                                             # 空中で下がっているときに縁へ乗り上げる高さの上限（0 で使わない）
    CornerCorrectionCm<public>:float                                        # 天井の角で横へずらす距離の上限
    MovingSpeedCmPerSecond<public>:float
    AxisLock<public>:character_axis_lock
    SpawnAtOwner<public>:logic
    PreMoveEvent<public><final>:listenable(float)
    PostMoveEvent<public><final>:listenable(float)
    ActionEvent<public><final>:listenable(character_action)
    LandedEvent<public><final>:listenable(float)                            # 着地した瞬間の下向きの速さ（cm/s）
    FindOwner<public>()<decides><transacts>:player                          # 持ち主。持ち主のいない場所なら失敗
    GetVelocity<public>()<transacts>:vector3                               # cm/s。世界の向き
    SetVelocity<public>(NewVelocity:vector3):void
    AddVelocity<public>(Delta:vector3):void
    IsGrounded<public>()<decides><transacts>:void
    IsInState<public>(State:character_motor_state)<decides><transacts>:void
    GetGroundNormal<public>()<transacts>:vector3                           # 地面にいないときは最後に立っていた地面
    GetGroundEntity<public>()<decides><transacts>:entity                    # 立っている物（接地の掃引で当たった entity）。地面にいなければ失敗
    GetGroundVelocity<public>()<transacts>:vector3                         # 乗って運ばれている地面の速度（character_ride_component が入れる。無ければ 0）
    GetInheritedVelocity<public>()<transacts>:vector3                      # 動く地面から離れたときに受け継いだ水平の速度（着地で 0）
    SetGravityScale<public>(Scale:float):void                              # 1.0 で既定どおり、0 で無重力
    GetGravityScale<public>()<transacts>:float
    ScaleGravityThisFrame<public>(Multiplier:float):void                   # このフレームの重力にだけ掛ける（PreMoveEvent の中で呼ぶ。毎フレーム 1 に戻る）
    GetLastLandingSpeed<public>()<transacts>:float                         # 最後に着地した瞬間の下向きの速さ（cm/s）
    LockInput<public>()<transacts>:cancelable                              # 部品の入力を止める。返った cancelable の Cancel で外す（重ねられる）
    IsInputLocked<public>()<decides><transacts>:void                       # LockInput が 1 つでも効いていれば成功
    TeleportTo<public>(Position:vector3):void                              # 当たりを見ずに足元を Position へ。速度はそのまま
    ReportAction<public>(Action:character_action):void                     # ActionEvent に届ける（自分で作る動きの部品から）
    AddModifier<public>(Modifier:character_modifier)<transacts>:cancelable  # 体に変更を重ねる。返った cancelable の Cancel で外す
    GetModifierCount<public>()<transacts>:int
    GetSpeedMultiplier<public>()<transacts>:float                          # 重ねた変更の掛け合わせ（無ければ 1）
    GetJumpMultiplier<public>()<transacts>:float
    GetGravityMultiplier<public>()<transacts>:float                        # SetGravityScale とは別に掛かる
    GetExtraAirJumps<public>()<transacts>:int                              # 足し合わせ（無ければ 0）
    IsDashGranted<public>()<decides><transacts>:void                       # GrantsDash の変更が 1 つでもあれば成功
    GetSideStyleOverride<public>()<decides><transacts>:character_side_style  # SideStyle を持つ変更のうち最後に足したもの。無ければ失敗

character_modifier<public> := struct:
    SpeedMultiplier<public>:float = 1.0
    JumpMultiplier<public>:float = 1.0
    GravityMultiplier<public>:float = 1.0
    ExtraAirJumps<public>:int = 0
    GrantsDash<public>:logic = false
    SideStyle<public>:?character_side_style = false                       # 重ねているあいだの walk の左右の入力のしかた（最後に足したものが勝つ）

(InEntity:entity).FindCharacterMotorFor<public>(Agent:agent)<decides><transacts>:character_motor_component
(InEntity:entity).FindCharacterMotorAbove<public>()<decides><transacts>:character_motor_component   # InEntity か祖先

# MoveKit
character_walk_space<public> := enum:
    View
    World
    Facing
    SideView

character_walk_component<public> := class<final_super>(component):
    MoveAction<public>:?input_action(vector3)
    ForwardAction<public>:?input_action(logic)
    BackAction<public>:?input_action(logic)
    LeftAction<public>:?input_action(logic)
    RightAction<public>:?input_action(logic)
    SprintAction<public>:?input_action(logic)
    Space<public>:character_walk_space
    MaxSpeedCmPerSecond<public>:float
    AccelerationCmPerSecondSquared<public>:float
    BrakingCmPerSecondSquared<public>:float
    AirControlRatio<public>:float                                          # 空中の加速の倍率
    AirBrakingRatio<public>:float                                          # 空中で入力が無いときの減速の倍率
    AirTurnAroundMultiplier<public>:float                                  # 空中の切り返しの加速の倍率
    KeepAirMomentum<public>:logic                                          # 空中で上限より速い分を減らさない
    SprintMultiplier<public>:float
    TurnAroundMultiplier<public>:float                                     # 地面の切り返しの加速の倍率
    SideStyle<public>:character_side_style
    TankTurnDegreesPerSecond<public>:float
    SideStyleToggleAction<public>:?input_action(logic)
    ToggleSideStyle<public>:character_side_style
    SideStyleChangedEvent<public><final>:listenable(character_side_style)  # 今のしかたが変わるたび（新しいしかた）
    SetMoveInput<public>(Input:vector3):void                               # Forward = 前、Left = 左。次に入れるまで残る
    GetSideStyle<public>()<transacts>:character_side_style                 # 今のしかた（体に重ねた変更があればそれ、無ければ基本）
    GetBaseSideStyle<public>()<transacts>:character_side_style             # 基本（SetSideStyle・切り替えで変えたもの。変えていなければ SideStyle）
    SetSideStyle<public>(Style:character_side_style):void                  # 基本を変える（変更が決めているあいだは、外れてから効く）
    SwitchSideStyle<public>():void                                         # 基本を SideStyle と ToggleSideStyle で切り替える（ボタンと同じ）
    GetWalkBasis<public>()<transacts>:tuple(vector3, vector3)              # 今の歩く向きの（前, 左）。TankTurn なら体の向き、SideView なら前は vector3{}
    GetWalkFront<public>()<transacts>:vector3                              # GetWalkBasis の前（Strafe で face が向く先）
    GetRawMoveAxis<public>()<transacts>:vector3                            # 診断用：MoveAction の生の値
    GetInputDirection<public>()<transacts>:vector3                         # 最後のフレームの入力の向き（世界の水平。長さ 0〜1。止めていれば 0）

(Motor:character_motor_component).FindCharacterWalk<public>()<decides><transacts>:character_walk_component  # 体の walk（体の entity、無ければ子孫）

character_jump_component<public> := class<final_super>(component):
    JumpAction<public>:input_action(logic)
    JumpSpeedCmPerSecond<public>:float
    AirJumps<public>:int
    CoyoteSeconds<public>:float
    BufferSeconds<public>:float
    ReleaseCutRatio<public>:float
    ApexSpeedThresholdCmPerSecond<public>:float                            # 頂点の浮きの速さの幅（0 で使わない）
    ApexGravityMultiplier<public>:float                                    # 頂点の浮きの重力の倍率
    Jump<public>():logic                                                   # 入力なしで跳ばせる。跳べなければ false。ReleaseJump か着地まで押しているとみなす
    ReleaseJump<public>():void                                             # コードの入力で離したことにする（上がっている途中なら高さの調整）

character_dash_component<public> := class<final_super>(component):
    DashAction<public>:?input_action(logic)
    DashSpeedCmPerSecond<public>:float
    DurationSeconds<public>:float
    DashEndSpeedRatio<public>:float                                        # 終わりに歩く速さの上限の何倍まで切るか
    DashGravityScale<public>:float                                         # 突進のあいだの重力の倍率
    CooldownSeconds<public>:float
    AirDashes<public>:int
    EnergyCost<public>:float
    RequiresGrant<public>:logic
    IsDashing<public>()<decides><transacts>:void
    Dash<public>():logic                                                   # 待ち時間・空中の回数・エネルギーが足りなければ false

# BodyKit
character_face_movement_component<public> := class<final_super>(component):
    TurnSpeedDegreesPerSecond<public>:float
    AirFacesInput<public>:logic                                            # Turn のとき、空中では入力の向きへ回す

character_owner_stasis_component<public> := class<final_super>(component):
    FindParkedCharacter<public>()<decides><transacts>:fort_character   # 今固定している Fortnite のキャラクター

character_input_mapping_component<public> := class<final_super>(component):
    Mapping<public>:?input_mapping
    SecondMapping<public>:?input_mapping
    RemoveOnEnd<public>:logic

# EventKit
character_action_event<public> := class(scene_event):
    Trigger<public>:character_action_trigger_component
    Action<public>:character_action

character_action_trigger_component<public> := class<final_super>(component):
    Action<public>:character_action
    Targets<public>:[]entity
    CooldownSeconds<public>:float
    TriggeredEvent<public><final>:listenable(character_action)

# ConditionKit
character_motor_condition_component<public> := class<final_super>(condition_component):
    State<public>:character_motor_state

# SurfaceKit
character_surface_contact<public> := enum:
    Touched
    Untouched
    SteppedOn
    SteppedOff

character_surface_box<public> := struct<computes>:
    MinCm<public>:vector3
    MaxCm<public>:vector3

character_surface_contact_event<public> := class(scene_event):
    Surface<public>:character_surface_component
    Motor<public>:character_motor_component
    Agent<public>:?agent
    Contact<public>:character_surface_contact

character_surface_tag<public> := class(tag):

character_surface_component<public> := class<final_super>(component):
    SizeCm<public>:vector3
    MeshSizeCm<public>:float
    PivotAtBottom<public>:logic
    ContactEvent<public><final>:listenable(tuple(character_motor_component, character_surface_contact))
    GetBox<public>()<transacts>:character_surface_box                     # 世界の軸にそろえた箱（回転した面は囲む箱）
    SetActive<public>(Value:logic):void                                    # false のあいだは触れない（当たり判定・見た目は変えない）
    IsActive<public>()<decides><transacts>:void

character_touch_component<public> := class<final_super>(component):
    TouchMarginCm<public>:float
    StandToleranceCm<public>:float
    SearchRadiusCm<public>:float
    RefreshSeconds<public>:float
    ContactEvent<public><final>:listenable(tuple(character_surface_component, character_surface_contact))
    SetSearchRoot<public>(Root:?entity):void                               # 面を探す場所を Root の子孫に絞る（false で世界）
    GetTouchingSurfaces<public>()<transacts>:[]character_surface_component
    IsTouching<public>(Surface:character_surface_component)<decides><transacts>:void
    FindStandingSurface<public>()<decides><transacts>:character_surface_component

character_ride_component<public> := class<final_super>(component):
    MaxCarryCm<public>:float
    FollowYaw<public>:logic
    GraceSeconds<public>:float                                             # 接地が一瞬切れても運び続ける秒数
    InheritVelocity<public>:logic                                          # 離れたら床の速度を受け継ぐ・乗ったら消す
    FindRidingEntity<public>()<decides><transacts>:entity                  # 今乗って運んでいる物
    GetRideVelocity<public>()<transacts>:vector3                           # その速度（乗っていなければ 0）

# BuffKit
character_modified_tag<public> := class<abstract>(player_state_tag):
character_speed_modified_tag<public> := class(character_modified_tag):
character_jump_modified_tag<public> := class(character_modified_tag):
character_gravity_modified_tag<public> := class(character_modified_tag):
character_air_jumps_added_tag<public> := class(character_modified_tag):
character_dash_granted_tag<public> := class(character_modified_tag):
character_side_style_modified_tag<public> := class(character_modified_tag):

character_buff_component<public> := class<final_super>(component):
    SpeedMultiplier<public>:float
    JumpMultiplier<public>:float
    GravityMultiplier<public>:float
    OverrideSideStyle<public>:logic
    SideStyle<public>:character_side_style
    ActiveOnBegin<public>:logic
    Apply<public>(Activator:?agent):void
    Remove<public>():void
    IsApplied<public>()<decides><transacts>:void

character_move_grant_component<public> := class<final_super>(component):
    ExtraAirJumps<public>:int
    GrantDash<public>:logic
    ActiveOnBegin<public>:logic
    Apply<public>(Activator:?agent):void
    Remove<public>():void
    IsApplied<public>()<decides><transacts>:void

# CameraExperimentalKit
character_camera_projection<public> := enum:
    Perspective
    Orthographic

character_camera_component<public> := class<final_super>(component):
    Projection<public>:character_camera_projection
    OffsetCm<public>:vector3
    YawDegrees<public>:float
    PitchDegrees<public>:float
    FieldOfViewDegrees<public>:float
    OrthographicWidthCm<public>:float
    Priority<public>:int
```

## 前提・注意
- 体はキネマティックです。当たりは `FindSweepHits`（自分の entity と子孫、持ち主の Fortnite キャラクターは除く）。1 フレームの順番：
  1. このフレームだけの重力の倍率を 1 に戻す。
  2. `PreMoveEvent`：同じ entity の部品が速度を決める（購読した順。walk・jump・dash・ride は互いの結果に頼らない）。
     - ride（`character_ride_component`）：立っている物が前に覚えた位置から動いた分だけ体を運ぶ（体の速度は変えない）。床の速度を出す。
     - jump：地面にいれば空中ジャンプの回数とコヨーテタイムを戻す → 押し（前のフレームからの押しと `BufferSeconds` 秒前までの先行入力）があれば、地面（コヨーテタイムを含む）→ 空中ジャンプの順に跳ぶ。跳べなければ先行入力として残す → 離していれば、上がっている途中のジャンプに `ReleaseCutRatio` を掛ける → 押したまま頂点の近くなら `ScaleGravityThisFrame(ApexGravityMultiplier)`。
     - walk：地面では入力の向きへ加速（切り返しは `TurnAroundMultiplier` 倍）、入力が無ければ `BrakingCmPerSecondSquared` で止まる。空中では加速 × `AirControlRatio`（逆向きなほどさらに最大 × `AirTurnAroundMultiplier`）、入力が無ければ減速 × `AirBrakingRatio`。`KeepAirMomentum` なら上限より速い分は曲げるだけで減らさない。動く床から受け継いだ分は減速しない（減った分は体の受け継いだ速度からも消す）。上下の速さは変えない。dash の突進のあいだは速度を変えない。
     - dash：突進中は水平の速度を決め、`ScaleGravityThisFrame(DashGravityScale)` で重力を弱める。終わった次のフレームの動きの前に速さを切る。
  3. 重力：空中か、地面から離れようとしている（ジャンプ）ときだけ。`GravityCmPerSecondSquared` × `SetGravityScale` × 変更の `GravityMultiplier` × `ScaleGravityThisFrame` × 下がっていれば `FallGravityMultiplier`（`MaxFallSpeedCmPerSecond` まで）。`SetGravityScale(0)` なら必ず 0。
  4. 掃引して動かす（最大 4 回）。当たるたびに：
     - 掃引の始めから触れている当たり（距離 0。めり込みかけ）なら、返る法線を使わずに押し出して（物理の法線 → 最近触れた壁の外向き → 動きの水平の逆 → 速度の水平の逆 → 真上 → 真下の順に、2.5 cm と 8 cm を試す）掃引し直す。押し出せなければ、そのフレームはその物を無視して動く。
     - そうでなければ、面の法線の向きに 2 cm（`SkinCm`）離れたところで止まり、角の補正（上がっていて頭が天井（下向きの面）の角にかすった → 横へ `CornerCorrectionCm` までずらして続ける）→ 段の補正（地面にいて足元が `StepUpCm` 以下の段の角に当たった → 段の上へ乗る。空中で下がっていれば `LedgeAssistCm` 以下）→ どちらも無理なら面に沿って滑る。
     - 滑り方：床・坂・天井は面に向かう動きと速度を消す。壁（歩けない面で、法線の上下の成分が -0.3 より上のもの）は上下の動きと速さを変えず、水平の壁に向かう分だけを消す。歩けない面に向かう速度を消したら `HitWall`。
  5. 接地：地面にいた体は地面から離れていなければ `GroundSnapCm` まで、空中の体は下がっていれば `GroundProbeCm` まで下を探して吸い付き、速度を地面に沿わせる（坂を上り下りしても接地のまま）。掃引の始めから触れている当たり（横の壁）は地面にしない（押し出すか、その物を除いて探し直す）。変われば `LeftGround` / `Landed`（と `LandedEvent`）。
  6. `PostMoveEvent`：位置を読む部品（face・カメラ・条件・touch）。ride はここで、立っている物（`GetGroundEntity`）が変わったら乗り換え、離れたら（一瞬なら `GraceSeconds` まで待って）床の速度を体に足す。
  7. 物理のあと（`TickEvents.PostPhysics`）：ride が、体より後に動いた床の分をもう一度運ぶ（フレームの終わりに床の上へそろえる）。
- 地面にいるとき、地面から離れる向きの速さが 200 cm/s（`GroundStickSpeedCmPerSecond`、private）以下の上向きの速度は地面に沿わせて消します（坂で浮かないため）。体を地面から打ち上げるときは、それより速く `SetVelocity` / `AddVelocity` します。
- 壁沿いの上下の動き：壁に押し付けたまま跳ぶ・落ちても、壁は上下の動きを止めません（水平の壁に向かう分だけ消す）。体は壁から法線の向きに 2 cm 離れて止まり、めり込みかけたら押し出します。天井（法線が -0.3 より下向き）にぶつかると上向きの動きは止まります。
- 登れる段は `StepUpCm` まで（それより高い段は坂にする）。段の補正は地面にいるときだけです（空中は `LedgeAssistCm`。既定 0 で使わない）。角に乗っても滑り落ちないところまで進めるので、このフレームの動きより数 cm 先へ進むことがあります。体だけでは動く床に乗っても一緒には動きません（SurfaceKit の `character_ride_component` を足すと運ばれる。立っている物は接地の掃引で当たった entity＝`GetGroundEntity`）。
- 入力を止める（`LockInput`）：walk は入力を 0 として扱い（減速だけ続く・TankTurn でも回さない・切り替えのボタンも効かない）、jump は跳ばず押しを捨て（頂点の浮きも止まる）、dash は出さず突進の途中なら終え（速さを歩く速さまで切る）、face は回しません。体の物理（重力・掃引・接地）は止めないので、体ごと止めるなら別に `SetGravityScale(0)` と `SetVelocity(vector3{})` をします（dash は `SetGravityScale` を変えないので、呼ぶ順は問わない）。返った cancelable は呼ぶ側ごとに持ち、外すときに `Cancel` します（全部外れると戻る）。自分で作る動きの部品も `IsInputLocked` を見ます。
- walk を探す：face（と自分で作る部品）は `FindCharacterWalk`（体の entity、無ければその子孫のどれか 1 つ）で walk を探します。walk を子孫に置くなら 1 つだけにします。
- 変更（`AddModifier`・BuffKit）：倍率は掛け合わせ、回数は足し合わせ。全部外すと各部品の `@editable` の値どおりに戻ります。速さは walk の最高速（走るときも）、ジャンプは jump の跳ぶ速さ、重力は体の重力（`SetGravityScale` の倍率とは別に掛かる。ダッシュ・体を止める処理が `SetGravityScale` を 1 に戻しても、変更の分は残る）。左右の入力のしかた（`SideStyle`）は最後に足した変更が勝ち、全部外れると walk の基本（`GetBaseSideStyle`）に戻ります。BuffKit の部品は停止の合図と `OnEndSimulation` の両方で外すので、効果のプレハブ（PickupSystem）が消えても残りません。独自キャラクターの体だけに効きます（Fortnite のキャラクターには効かない）。
- SurfaceKit：独自キャラクターは自前のカプセルで動くので、メッシュの重なりの知らせ（`EntityEnteredEvent`）は来ません。「触れた・乗った」は `character_touch_component` が体の箱と `character_surface_component` の箱（世界の軸にそろえた直方体）を比べて決めます（体が接地の掃引で立っている entity に面が付いていれば、箱を比べずにその面に乗っているとします）。1 フレームで通り抜けるほど速いと触れません（薄い面は厚くする）。回った面の「乗っている」を箱で決めるときは、回った箱を囲む世界の軸の箱なので、45 度ほど回った足場では角の外側でも乗っていることがあります。
- 動く床（`character_ride_component`）：運ぶのは、体が接地の掃引で立っている entity（当たり判定のあるメッシュ）です。当たり判定の無い面（`character_surface_component` の箱だけ）は運びません。運ぶのは体の位置だけです（体の向きは変えない）。床がヨーで回ると、`FollowYaw`（既定オン）なら体の位置も床のまわりに回します。床のピッチ・ロールには合わせません。上下はそのまま動かし（床が上がって体が床にめり込んだまま掃引しない）、水平は床以外に当たれば手前で止めます（運ばれて壁にめり込まない。壁に押されて床から落ちることはある）。上の天井に挟まれても押し返しません。体の `AxisLock` で縛った軸には運びません。
- 左右の入力のしかたを足すとき（`character_side_style` に値を足す）に直す場所：`CharacterMotorComponent.verse` の `SideInputTurnsBody`、BodyKit の `character_face_movement_component.OnPostMove`（向ける先の `case`）、MCPSystem の CharacterKit（`SideStyleName` / `SideStyleTitle` の `case` と、名前から探す一覧）、TooltipKit の `WalkSideStyleToolTip`、この README。`case` はどれも `_` を書いていないので、直し忘れるとコンパイルが通りません（名前から探す一覧だけは配列なので、足し忘れても通る）。
- 体に重ねた変更（`character_modifier.SideStyle`）がいくつもあるときは、最後に足したものが勝ちます（決まり）。それが外れると、その前に足したもののうち最後のもの、全部外れると walk の基本に戻ります。
- 左右の入力のしかた：1 つの値（walk の `GetSideStyle`）を walk・face・MCP が読みます（変える口は `SideStyle`（@editable）・`SetSideStyle` / `SwitchSideStyle`・`SideStyleToggleAction`・`character_modifier.SideStyle`（BuffKit の `OverrideSideStyle`）・MCP の `character.set_side_style`）。`TankTurn` は walk が体（motor の entity）を回し、face は何もしません。`Strafe` の前は `GetWalkFront`（`Space = Facing` なら体の向きそのものなので回らない、`SideView` は前が無いので回さない）。ヨーの向きは `YawSign`（CharacterSystem の直下。v43.00 実機でヨーの正は右回り）で合わせます。
- ダッシュのあいだは、重力を毎フレーム `ScaleGravityThisFrame(DashGravityScale)` で弱めます（`SetGravityScale` は変えないので、ほかの部品が決めた倍率はそのまま残ります）。突進のあいだは walk が速度を変えないので、部品の並び順（`PreMoveEvent` の届く順）によらず距離は同じです。
- `character_owner_stasis_component` は Fortnite のキャラクターを動かしません。視点は `character_camera_component`（CameraExperimentalKit）などで独自キャラクターに向けます（標準のカメラは固定された Fortnite のキャラクターのまま）。
- `character_input_mapping_component` の `RemoveOnEnd` は、独自キャラクター専用の割り当てのときだけオンにします（Fortnite の割り当てを外すと、ほかの操作もできなくなります）。
- MCP でレベルを組むとき：Fortnite 標準の `input_action` / `input_mapping`（`Character.Jump`・`TraversalMapping` など）は、MCP の `SetComponentProperty` で参照として設定できません。コードの既定値（`JumpAction = Character.Jump` など）として使うのはかまいません。`Mapping` に `TraversalMapping` を入れるなど、別のものにしたいときはエディターで選びます。
- ロードアウトの中の反応（`character_action_trigger_component` の子の部品など）は、ロードアウトが付いた次のフレームに届く起動の合図と、外すときの停止の合図も受けます（LoadoutSystem）。
- `Character.Move`（Fortnite の移動の方向入力）は `@experimental` です（v43.00 の digest）。`MoveAction` に使うコードは `…ExperimentalKit` に置きます（`_Samples/Platformer2DSampleExperimentalKit` がこの形）。
- `CameraExperimentalKit` は `@experimental` のカメラ API（`camera_director_component` に足す `perspective_camera_component` / `orthographic_camera_component`）を使います。使うと島を公開できません。VerseShare は「実験的を含む」をオンにしたプロジェクトにだけ、このフォルダを配ります。
- ⚠ 未検証（コードに書かれているもの）：
  - `FindSweepHits` にカプセルを渡したときの当たり・法線・距離が、説明どおりに返るか（CharacterMotorComponent.verse）。角・段の補正は `ContactPosition`（当たった点）の高さと横のずれで決めるので、その値が説明どおりか（ずれていると補正が効かないだけで、いつもどおり滑る）。
  - 掃引の始めから触れている（めり込みかけの）ときに、`FindSweepHits` が距離 0（`StartHitCm` = 0.01 cm 以下）の当たりを返すか、そのとき法線が掃引の逆向きになるか（UE の物理の決まりからの推測。壁に貼り付く件の原因の見立て）。押し出しの空き確かめ（逆向きへ 2 cm 掃引して距離 0 の当たりが無いか）が、めり込みを見分けられるか。
  - 壁沿いの動き・ダッシュ・空中の制御の新しい既定値（`AirBrakingRatio = 0.2`・`AirTurnAroundMultiplier = 2.0`・ダッシュ 2200 cm/s × 0.18 秒）の手触り。
  - 落ちるときの重力・頂点の浮き・切り返し・コヨーテタイム・先行入力の既定値の手触り（実機で触って決める値）。
  - `character_face_movement_component` の Yaw の正の向き。逆に向くなら見た目のメッシュを 180 度回して置く（BodyKit/CharacterBodyComponents.verse）。
  - stasis 中の Fortnite キャラクターの位置を毎フレーム書き換えたとき、標準のカメラが滑らかに追うか（BodyKit/CharacterBodyComponents.verse）。
  - `MoveAction` の値の向き（Forward = 前、Left = 左として読む）（MoveKit/CharacterWalkComponent.verse）。
  - `Strafe` / `TankTurn` の実機での見え方（`TankTurn` の左右で回る向き、`Strafe` で視点に合わせて回る向き）（MoveKit/CharacterWalkComponent.verse・BodyKit/CharacterBodyComponents.verse）。
  - カメラの Yaw / Pitch の正の向き（CameraExperimentalKit/CharacterCameraComponent.verse）。
  - keyframed_movement_component で動いている床の `GetGlobalTransform` が、サーバーで毎フレーム動いた位置を返すか。運ばれる体（サーバーの位置が届く）と床（クライアントで再生する）が、クライアントの画面でずれないか（SurfaceKit/CharacterSurfaceComponents.verse）。
  - `TickEvents.PostPhysics` で体を動かしたとき、その位置がそのフレームのうちに見た目・送る位置に入るか（ride の 2 回目の運び）。

## 確かめ方
- テスト：`_Test/CharacterSystemTest/` の `character_system_test_component`。`player_manager_component` を付けた entity を 1 つと、この component を付けた entity を 1 つ置き、プレイヤー 1 人が平らな床に立った状態で始めます。プレイヤーの前 3 m・上 3 m に持ち主のいない体（`AxisLock = Left`、`SpawnAtOwner = false`）を作り、持ち主がいないこと、重力で落ちて接地すること（`IsGrounded`・`Landed` が 1 回）、`SetVelocity` で前へ動き `AxisLock` で左右が変わらないこと、`TeleportTo` で移ることを確かめます。着地の速さ（`GetLastLandingSpeed` が 100 cm/s より速い）と、`LockInput` を 2 つ重ねて 1 つ外しても止まったまま・全部外すと戻ることも見ます。約 4 秒かかります。結果は出力ログの `[TEST] CharacterSystem`。歩く・ジャンプ・入力・持ち主のいる形、角・段の補正、坂への吸い付きはテストしていません。
- 手で確かめる（遊んで見る）：
  - コヨーテタイム：縁から歩いて落ちた直後に跳べる。跳んで縁を離れたあとは、空中ジャンプが無ければ跳べない。
  - 先行入力：着地の少し前に押すと、着地した瞬間に跳ぶ。空中ジャンプが残っていれば、押したときに空中で跳ぶ。
  - 高さの調整・頂点の浮き：短く押すと低く、長く押すと高く、頂点で少し長く浮く。落ちるときは上がるときより速い。
  - 角の補正：天井の角に頭がかすっても止まらず、横へ少しずれて上がる。段の補正：低い段（15 cm まで）を歩いて登れる。`LedgeAssistCm` を入れたときだけ、少し届かなかった縁に乗れる。
  - 坂：上り下りで `LeftGround` / `Landed` が出続けない（`character_action_trigger_component` の `Landed` で音を鳴らして確かめる）。
  - `LockInput`：止めているあいだ、歩く・跳ぶ・ダッシュ・向きが変わらない（TankTurn・Strafe でも）。外すと戻る。
  - 空中の制御：短いジャンプで入力を離すと勢いは残り、長いジャンプの終わりにはほぼ止まる（`AirBrakingRatio`）。空中で逆に入れると、逆向きなほど早く向きが変わる（`AirTurnAroundMultiplier`。斜め後ろに入れても急に変わらない）。`Turn` で空中では入力の向きを向く（`AirFacesInput`）。
  - 壁：壁に押し付けたまま跳ぶ・落ちる・2 段ジャンプしても、壁の途中で止まらない（上下の速さが変わらない。`HitWall` は出る）。壁際で地面に立ったまま跳べる。
  - ダッシュ：毎回同じ距離（既定 396 cm）だけ進み、終わると歩く速さに戻る（空中で前に入れ続けても、ダッシュの速さのまま流れない）。空中のダッシュは高さが変わらない。突進の途中で跳ぶと、普段のジャンプになる。
  - 動く床（体に `character_ride_component`）：MoverSystem の `mover_component`（Keyframe・Physics の両方）で動く床に乗ると、上り・下り・横・回る（`FaceTravelDirection`）床で一緒に動き、床にめり込まない・浮かない。床の上で跳ぶと床と一緒に進み、同じ床に戻れる。床から跳ぶ・縁から落ちると床の速度で飛ぶ。
- テスト：`_Test/CharacterSystemTest/CharacterSurfaceTest.verse` の `character_surface_test_component`（SurfaceKit）。置き方は上のテストと同じ（プレイヤーの前 3 m に 5 m 四方の床が要る）。持ち主のいない体（motor + touch + ride）を床に落とし、床の高さに見た目の無い面（`SizeCm` の箱）を作って、乗った（`Touched`・`SteppedOn` が 1 回・`FindStandingSurface`）、ride が立っている床（`GetGroundEntity`）に乗り、当たり判定の無い面を前へ 150 cm 動かしても体は運ばれない（`GetGroundVelocity` が 0）、`SetActive(false)` で離れる・降りる、`GetBox` が大きさ・回転・底の原点どおりかを確かめます（動く床に運ばれるかは、メッシュを作れないのでテストしない。上の「手で確かめる」で見る）。約 5 秒。結果は出力ログの `[TEST] CharacterSurface`。
- テスト：`_Test/CharacterSystemTest/CharacterBuffTest.verse` の `character_buff_test_component`（変更と BuffKit）。この component を付けた entity を 1 つ置くだけ（プレイヤーは要らない）。宙に持ち主のいない体を作り、`AddModifier` の掛け合わせ・足し合わせ・`Cancel` で戻ること、体の子の `character_buff_component` / `character_move_grant_component` が起動の合図で重ね、停止の合図と entity を消したときに外すことを確かめます。約 1 秒。結果は出力ログの `[TEST] CharacterBuff`。
- 見本：`_Samples/Platformer2DSampleExperimentalKit/` の `platformer_2d_sample_component`（実験的。「実験的を含む」のプロジェクトだけ）。床の上の空の entity に付けると、参加した人ごとに slot の下へ体（motor `AxisLock = Left`・walk `SideView`（`Character.Move`）・jump（2 段ジャンプ）・body_link（隠さない）・正射影のカメラ）を作り、横スクロールで動けます。ゴールの箱に入るとスタートへ戻ります。区画（または世界）に `player_manager_component` が 1 つ要ります。

## ラウンド
- `character_motor_component.ResetOnRoundStart`（既定オン）：Fortnite のラウンドが始まるたびに、速度を消して持ち主の Fortnite キャラクター（スポーン地点に出直している）の位置へ移る。`round_watcher` を使う。
- 2D の見本（`_Samples/Platformer2DSampleExperimentalKit`）は体のこれをオフにし、ラウンドの始まりで全員をスタートへ戻す。

## 移行が要るもの（2026-11-09・壁・ダッシュ・空中の手触り）
遊んでみての直し（壁に押し付けて上下に動くと止まる・ダッシュがブーストのよう・空中の制御の違和感）。既定値で今までと動きが変わるもの（前の動きに戻す値）：
- 体（壁に貼り付く件）：原因は 2 つが重なったもの。(1) 当たったら掃引の向きに 2 cm 戻して止めていたので、壁に浅い角度で近づく（壁に押し付けたまま跳ぶ・落ちる）たびに壁との隙間が縮み、数フレームで 0 になった。(2) 隙間 0 で掃引すると、始めから触れている当たり（距離 0）が返り、その法線が掃引の逆向き（落ちていれば真上）になるので、壁を床・天井と取り違えて上下の速度を消し、接地の探りでは壁の途中に「立って」重力も止まっていた（見立て。未検証に書いた）。加えて、壁の法線に上下の成分が少しあると、滑らせるたびに上下の速さが削られていた。
  - 止まる距離を面の法線の向きに 2 cm にした。距離 0 の当たりは法線を使わずに押し出す（押し出せなければそのフレームは無視して動く）。接地・ride の `GraceSeconds` の探りでも距離 0 の当たりは地面にしない。壁（歩けない面で天井でないもの）は上下の動きと速さを変えない。戻す値は無い（前の動きには戻せない）。
  - `StepUpCm` は地面にいるときだけ使う（前は空中で下がっているときも使った）。空中の縁の補助は新しい `LedgeAssistCm`（既定 0）。前の動きにするなら `LedgeAssistCm = 15`。
  - `CornerCorrectionCm` は天井（法線の上下の成分が -0.3 より下向き）だけに使う（前は少しでも下を向いた面なら使った）。
- dash：前は、重力の倍率を `SetGravityScale` で 0 → 1 にし、終わりに 600 cm/s へ落としていた（walk の速さを見ない。walk が先に動くフレームはダッシュの速さを削り、並び順で距離が変わった）。
  - 既定を `DashSpeedCmPerSecond = 2000 → 2200`・`DurationSeconds = 0.2 → 0.18` に（距離 400 → 396 cm。速く短く）。前の動きにするなら 2000 / 0.2。
  - 新しい `DashEndSpeedRatio = 1.0`：終わりに、ダッシュの向きの速さを walk の歩く速さの上限 ×（変更の速さの倍率）× これ までに切り、横の速さを消す（前は 600 cm/s 固定）。新しい `DashGravityScale = 0`：重力は `ScaleGravityThisFrame` で弱める（`SetGravityScale` を変えない。前は終わりに 1 に戻していた）。
  - 向きは walk の入力の向きを先に使う（前は今の水平の動き → 体の向き）。`AxisLock` の軸は除く。
  - 突進の途中で跳ぶ・`LockInput` すると、その場で終えて速さを切る（前は跳んでもダッシュの速さのまま突進が続いた。`LockInput` では速さをそのまま残した）。
  - 突進のあいだ walk は速度を変えない（体の `SetMoveOverride` / `IsMoveOverridden`、internal）。出した瞬間に動く床から受け継いだ速度を消す。
  - 流れ：0 秒 向きを決めて 2200 cm/s（空中なら上下 0）→ 0.18 秒 同じ速さ（重力 0 倍。最後のフレームは残りの秒数の分だけ突進の速さなので、距離はフレームの長さによらず 396 cm）→ 次のフレームの動きの前に 600 cm/s（歩く速さの上限）へ切る → 0.8 秒（出した瞬間から）で次を出せる。
- walk（空中の制御）：`AirBrakingRatio = 0.1 → 0.2`（入力を離したとき 600 cm/s が止まるまで 1.2 → 0.6 秒。氷の上のように流れ続けた）。`AirTurnAroundMultiplier = 2.5 → 2.0`、逆向きの度合いで滑らかに掛ける（前は 90 度を境に 2400 → 6000 cm/s² へ急に変わり、斜め後ろに入れたときだけ急に曲がった）。`AirControlRatio = 0.6` は変えない。前の動きにするなら `AirBrakingRatio = 0.1`・`AirTurnAroundMultiplier = 2.5`（滑らかに掛けるのは戻せない）。
  - 動く床から受け継いだ速度は、逆向きの入力・壁で減ったら体の受け継いだ速度も縮める（前は、壁に当たったあと同じ向きに入れると、受け継いだ分として減速しない速さが戻り、離しても流れ続けた）。
- 追加のみ（移行は要らない）：体の `LedgeAssistCm`、dash の `DashEndSpeedRatio` / `DashGravityScale`。internal の `SetInheritedVelocity` / `SetMoveOverride` / `IsMoveOverridden`。

## 移行が要るもの（2026-11-09・空中の制御と動く床）
空中の制御を分け、動く床に乗る仕組みを作り直しました。既定値で今までと動きが変わるもの（前の動きに近づける値）：
- walk：`AirControlRatio` は空中の加速だけに掛かるようになりました（前は加速と減速の両方）。既定を 0.35 → 0.6 に上げました。空中で入力が無いときの減速は新しい `AirBrakingRatio = 0.1`（前は `AirControlRatio` と同じ 0.35）、空中の切り返しは新しい `AirTurnAroundMultiplier = 2.5`（前は `TurnAroundMultiplier` × `AirControlRatio`）。前の動きにするなら `AirControlRatio = 0.35`・`AirBrakingRatio = 0.35`・`AirTurnAroundMultiplier = 2`・`KeepAirMomentum = false`。
- walk：`KeepAirMomentum = true`（空中で上限より速い分を、逆向きに入れない限り減らさない）。前は空中でも入力の速さへ近づけていた（ダッシュ・はじきの勢いが入力で落ちた）。`false` で前の動き。
- face：`AirFacesInput = true`（`Turn` のとき、空中では入力の向きへ回す。入力が無ければ回さない）。`false` で前の動き（空中でも動いている方向へ）。
- ride：乗っている物を `character_touch_component` の `FindStandingSurface`（面の箱）ではなく、体の接地の掃引で当たった entity（`GetGroundEntity`）で決めるようになりました。`character_touch_component` と足場の `character_surface_component` は要りません（付けたままでよい）。当たり判定の無い面（箱だけ）が動いても運ばなくなりました（前は運んだ）。
- ride：運ぶのを `TeleportTo` から体の `CarryBy`（internal）に替えました。水平は床以外に当たると手前で止まります（前は壁にめり込んだ）。体の `AxisLock` で縛った軸には運びません（前は縛る位置が床と一緒に動いた）。運んでも `SpawnAtOwner` の 1 フレーム後の移動を止めません（前は TeleportTo の扱いで止めた）。
- ride：`InheritVelocity = true`（離れると床の速度を受け継ぐ、乗ると消す）。`false` で前の動き（離れた瞬間に床の動きが無くなる）。`GraceSeconds = 0.1`（0 で前の動き）。物理のあと（`TickEvents.PostPhysics`）にも運ぶようにしました。
- touch：体が立っている entity に `character_surface_component` が付いていれば、箱を比べずにその面に乗っているとします（箱の大きさ・原点の設定がずれていても乗っているになる）。
- 追加のみ（移行は要らない）：体の `GetGroundEntity` / `GetGroundVelocity` / `GetInheritedVelocity`、walk の `GetInputDirection`、ride の `FindRidingEntity` / `GetRideVelocity`。

## 移行が要るもの（2026-11-09・手触り）
動きの手触りを足しました。既定値で今までと動きが変わるもの（前の動きに戻す値）：
- 体：`FallGravityMultiplier = 1.6`（落ちるのが速くなる。1 で前の動き）、`GroundSnapCm = 20`（坂・20 cm までの段を降りるときに吸い付く。0 で前の動き）、`StepUpCm = 15`（15 cm までの段を登れる・縁に乗れる。0 で前の動き）、`CornerCorrectionCm = 12`（天井の角で横へずれる。0 で前の動き）。
- 体：地面にいるとき、200 cm/s 以下の上向きの速度は地面に沿わせて消すようになりました（前は少しでも上向きなら一度浮いた）。坂を上るあいだも接地のままです（前は浮いたり着いたりして、`LeftGround` / `Landed` が出続けていた）。接地したときの速度は地面に沿わせます（前は下向きの速さを 0 にするだけ）。
- walk：`TurnAroundMultiplier = 2`（切り返しが速くなる。1 で前の動き）。
- jump：`ApexSpeedThresholdCmPerSecond = 150` / `ApexGravityMultiplier = 0.5`（押したまま頂点で浮く。0 / 1 で前の動き）。コードの `Jump`（MCP の `jump` を含む）は、前はすぐに高さの調整が掛かって低いジャンプになっていましたが、`ReleaseJump` を呼ぶか着地するまで押しているとみなすようになりました（高く跳ぶ）。低くしたいときは跳んだあとに `ReleaseJump` を呼びます。
- jump：1 フレームに跳ぶのは 1 回まで。`BufferSeconds = 0` でも、前のフレームから今までの押しで跳べるようにしました（前は 0 にするとほとんど跳べなかった）。高さの調整は、下がり始めたジャンプ・打ち上げには掛けないようにしました。
- face：walk を体の entity だけでなく子孫からも探します（`FindCharacterWalk`）。
- 追加のみ（移行は要らない）：`LandedEvent`・`GetLastLandingSpeed`・`ScaleGravityThisFrame`・`LockInput` / `IsInputLocked`・`ReleaseJump`・`FindCharacterWalk`。
- MCPSystem の CharacterKit はまだ walk を体の entity だけで探します（`Motor.Entity.GetComponent[character_walk_component]`）。子孫の walk も使うなら、そこを `Motor.FindCharacterWalk[]` に替えます。

## 移行が要るもの（2026-11-09）
- 追加のみ（移行は要らない）：左右の入力のしかた `character_side_style`（walk の `SideStyle`（既定 `Turn` で今までどおり）・`TankTurnDegreesPerSecond`・`SideStyleToggleAction`・`ToggleSideStyle`・`GetSideStyle` / `GetBaseSideStyle` / `SetSideStyle` / `SwitchSideStyle` / `GetWalkFront` / `SideStyleChangedEvent`、`character_modifier.SideStyle`、`character_motor_component.GetSideStyleOverride`、`character_buff_component.OverrideSideStyle` / `SideStyle`、`character_side_style_modified_tag`）。`YawSign` は BodyKit から CharacterSystem の直下へ移した（internal。外から使っていなければ影響なし）。

## 移行が要るもの（2026-11-08）
- `character_ride_component.FollowYaw`（既定オン）を追加：乗っている面がヨーで回ると、体の位置も面のまわりに回すようになりました。回らない面では今までと同じです。前の動き（位置の動きだけ）に戻すならオフにします。
- 追加のみ（移行は要らない）：`character_modifier` と `character_motor_component.AddModifier` ほか、`character_dash_component.RequiresGrant`（既定オフで今までどおり）、BuffKit。
- `character_body_link_component`（OffsetCm / HideBody）→ `character_owner_stasis_component`（設定なし）。Fortnite のキャラクターを独自キャラクターに付いていかせる動きは無くした（独自キャラクターは全部自前で動かすのが目的のため）。置き直しが要る
