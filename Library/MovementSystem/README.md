# MovementSystem

`fort_character` を Verse の座標（`/Verse.org/SpatialMath` の `vector3`。Forward・Left・Up、センチメートル、世界の座標）で扱う小道具です。位置・速度・視点を読み書きする拡張関数だけで、component はありません。ほかの System（Swing・Jetpack・Hover・Gravity など）がこれを使います。

## 置き方

置く component はありません。`using { MovementSystem }` して、`fort_character` に対して関数を呼びます。

| component | 置く場所 | すること |
|---|---|---|
| （なし） | — | `FortCharacter.LiftBy(...)` などの拡張関数を、コードから呼ぶ |

例：プレイヤーを 2 メートル持ち上げてから、上向きに 1000 cm/s で飛ばす
```
if (FortCharacter := Agent.GetFortCharacter[]):
    FortCharacter.LiftBy(200.0)
    FortCharacter.SetVelocityCmPerSecond(vector3{Up := 1000.0})
```

## 設定（@editable）
ありません。

## イベント
ありません。

## 公開 API
```verse
# CharacterPosition：位置・速度（センチメートル、センチメートル毎秒）
(FortCharacter:fort_character).FindGlobalTranslation<public>()<decides><transacts>:vector3      # entity の原点（足元ではない）。entity が取れなければ失敗
(FortCharacter:fort_character).GetVelocityCmPerSecond<public>()<reads>:vector3                  # GetLinearVelocity（メートル毎秒）の 100 倍
(FortCharacter:fort_character).SetVelocityCmPerSecond<public>(VelocityCmPerSecond:vector3):void # 100 で割って SetLinearVelocity に渡す

# CharacterLift：真上へ動かす
(FortCharacter:fort_character).LiftBy<public>(HeightCm:float)<transacts>:void   # 世界の Up へ HeightCm 動かす（負なら下）。当たり判定は見ない

# CharacterView：視点
(FortCharacter:fort_character).GetViewOrigin<public>()<transacts>:vector3      # カメラの世界での位置
(FortCharacter:fort_character).GetViewDirection<public>()<transacts>:vector3   # 視点の向き（長さ 1）
```

## 前提・注意
- 速度について：Epic の `fort_character.GetLinearVelocity` / `SetLinearVelocity` はメートル毎秒です。センチメートル毎秒で扱うなら `GetVelocityCmPerSecond` / `SetVelocityCmPerSecond` を使います。
- `FindGlobalTranslation` はキャラクターの entity の原点の位置で、足元ではありません。
- `LiftBy` は当たり判定を見ずに、キャラクターの entity の位置を直接変えます（向き・大きさはそのまま）。キャラクターの entity が取れなければ何もしません。
- `GetViewOrigin` / `GetViewDirection` は、Epic の `GetViewLocation` / `GetViewRotation`（UE の XYZ、`/UnrealEngine.com/Temporary/SpatialMath` の座標）を Verse の座標に変えて返します（Forward = X、Left = -Y、Up = Z）。Temporary の座標を使うのは内部の `CharacterViewRaw.verse` だけです。
- 名前は v43.00 の digest（/Fortnite.com・/Verse.org・/UnrealEngine.com）にある `fort_character` のメンバーと重ならないことを確かめてあります。
- 実験的な API は使っていません。

## 確かめ方
- テスト：`_Test/MovementSystemTest/` の `movement_system_test_component`。`player_manager_component` を付けた entity を 1 つ置き、このテストの component をどこかの entity に付けます。プレイヤーの頭の上 3 メートルは空けておきます。最初に参加したプレイヤーで、`FindGlobalTranslation` が取れること、`LiftBy(200.0)` で真上へ 200 cm だけ動き横にずれないこと、`GetViewDirection` が長さ 1 であること、`GetViewOrigin` がキャラクターから 3 メートル以内にあること（座標の変換の向きが逆だと離れる）を確かめます。プレイヤーが参加すれば数フレームで終わります。結果は出力ログの `[TEST] MovementSystem`。
- 見本（`_Samples/`）はありません。

## ワープ（teleport_on_activation_component）
- 行き先の entity に付ける。だれが起こしたかの分かる起動の合図（`activated_by_agent_event`。選択メニュー・インタラクト・ボリュームの入り口の Targets など）を受けたら、その人のキャラクターをこの entity の位置＋`OffsetCm`（既定は上に 100）へ移す。だれが起こしたか分からない合図では何もしない。
- コードからは `TeleportAgent(Agent)`。
- ⚠ 未検証：キャラクターの entity の位置を書き換えたときに、落下中などの移動の状態がそのまま続くか。
