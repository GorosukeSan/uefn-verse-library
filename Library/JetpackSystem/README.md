# JetpackSystem

ジェットパックの能力（AbilitySystem の `ability_component` の派生）です。付与された人が空中でジャンプ（`BoostAction`）を押すとチャージして浮き、離すと決めた向きに飛び出します。飛んだあと着地するまでは、押し続けると落ちる速さを抑えます。エネルギー（EnergySystem）があれば使います。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `jetpack_ability_component` | 付与の component（AbilitySystem の GrantKit）と同じ entity。アイテムにするなら、アイテムの entity | 付与された人ごとに、チャージ・飛び出し・落下の軽減・着地の見張りを動かす。チャージから飛び終わるまで、その人に `jetpack_boosting_tag` を付ける |

付与の仕方は、同じ entity に置く component で選びます。
- アイテムとして（装備しているあいだ） → `item_component`・`item_holder_component`・`ability_grant_item_component` と一緒に置く。エネルギーはアイテムの entity に置く。1 人 1 つまでにするなら `exclusive_item_component`（ItemSystem の ExclusiveKit）。チャージ中・飛行中に持ち替えさせないなら `item_equip_lock_component`（ItemSystem の RuleKit）
- 全員に最初から／起動しているあいだ → `ability_grant_players_component`（エネルギーをこの entity に置くと全員で同じ量を分け合う。1 人ずつにするなら、エネルギーをプレイヤーに付ける）
- 条件を満たしているあいだ → `ability_grant_condition_component`（直下の子に条件）
- コードから → `Grant` / `Revoke`

演出：同じ entity に `fort_item_ability_component` があれば、チャージ中・飛び出しのあいだ・落下の軽減のあいだ、`ItemEquippedAbilities` をその人に使います。

例：エネルギーが尽きると無くなるジェットパックのアイテム
```
区画（または世界）
├ プレイヤー（player_manager_component）
└ ジェットパック（item_component + item_holder_component + ability_grant_item_component
                 + jetpack_ability_component + energy_component + item_equip_lock_component）
```

## 設定（@editable）
飛び出し：
- `jetpack_ability_component.BoostSpeedCmPerSecond : float = 3000.0` — チャージ 1 倍のときの、飛び出した瞬間の速さ（cm/s。0〜20000）。
- `jetpack_ability_component.BoostDurationSeconds : float = 0.8` — チャージ 1 倍のときに、飛び出してから速さが 0 になるまでの秒数（0.1〜5）。そのあとは普通に落ちる。
- `jetpack_ability_component.BoostEaseExponent : float = 2.0` — 速さ = 初速 ×（1 − 経過 / 時間）のこの値乗（0〜5）。0 で一定、大きいほど初めが速い。

飛ぶ向き：
- `jetpack_ability_component.BoostPitchDegrees : float = 90.0` — 上下の角度（度。-90〜90）。90 で真上、0 で水平、-90 で真下。見ている方向の上下には左右されない。
- `jetpack_ability_component.BoostYawDegrees : float = 0.0` — 左右の角度（度。-180〜180）。見ている向きを水平にしたものが 0、プラスで右。

チャージ：
- `jetpack_ability_component.MinChargeSeconds : float = 1.0` — ここまでのチャージは、飛ぶ距離が 1 倍のまま（0〜10 秒）。
- `jetpack_ability_component.MaxChargeSeconds : float = 3.0` — この秒数で距離が最大（`MaxChargeMultiplier` 倍）になり、その瞬間にエネルギーを使う（0.1〜10 秒）。それより長く押しても最大のまま浮き続ける。
- `jetpack_ability_component.MaxChargeMultiplier : float = 3.0` — チャージ最大のときの飛ぶ距離の倍率（1〜10）。距離が N 倍のとき、初速と時間にそれぞれ √N を掛ける。
- `jetpack_ability_component.ChargeLiftCm : float = 50.0` — チャージを始めたときに、位置を直接動かして持ち上げる高さ（cm。0〜300）。
- `jetpack_ability_component.ChargeRiseSpeedCmPerSecond : float = 50.0` — チャージのあいだ上がっていく速さ（cm/s。0〜1000）。横には動かない。0 ならその高さで止まる。

エネルギー：
- `jetpack_ability_component.BoostEnergyCost : float = 30.0` — 1 回飛ぶたびに使う量（0〜1000）。チャージが最大になった瞬間か、それより前に離した瞬間に使う。足りなくても飛べ、0 になる。
- `jetpack_ability_component.GlideEnergyPerSecond : float = 1.0` — 落下の軽減のあいだ、1 秒あたりに使う量（0〜100）。
- `jetpack_ability_component.RemoveItemWhenEmpty : logic = true` — アイテムに置いたとき、エネルギーが 0 になるとアイテムごと無くす（飛行の途中なら飛び終わったとき）。アイテムでなければ使わない。

落下の軽減：
- `jetpack_ability_component.GlideMaxFallSpeedCmPerSecond : float = 300.0` — 落ちる速さの上限（cm/s。0〜5000）。0 で高さを保つ。

入力：
- `jetpack_ability_component.BoostAction : input_action(logic) = Character.Jump` — 空中で押してチャージし、離して飛ぶ操作。飛んだあと着地するまでは、押し続けると落下の軽減。
- `jetpack_ability_component.BoostMapping : input_mapping = Character.TraversalMapping` — 付与しているあいだ足すキー割り当て（`BoostAction` を含むもの）。
- `jetpack_ability_component.RemoveMappingOnRevoke : logic = false` — 剥奪したときに `BoostMapping` を外す。この能力専用の割り当てを選んだときだけオンにする（`TraversalMapping` のままオンにすると移動もできなくなる）。

## イベント
- `jetpack_boost_changed_event`（scene_event、SendUp）: `Ability : jetpack_ability_component`、`Agent : agent`、`Ratio : float`（ゲージ 0.0〜1.0）。能力の entity から上へ送り、同じものを `player_event` に包んで、その人の slot の下へも SendDown する（同じ人の HUD などの view が受ける）。ゲージの値が変わったときだけ送る（付与したとき・着地したとき 1、チャージ中は 0 から 1、飛び出してから着地するまで 0、剥奪で 0）。消費しない。
- `jetpack_ability_component.BoostRatioChangedEvent : listenable(tuple(agent, float))` — `jetpack_boost_changed_event` と同じときに（その人, ゲージ）で届く。外から Signal はできない。
- `GrantedEvent` / `RevokedEvent : listenable(agent)` — 付与・剥奪（`ability_component` から）。
- 受けるもの: なし（入力は `player_input` から直接読む）。

## タグ
- `jetpack_boosting_tag`（`controlled_movement_tag` の派生）：チャージを始めてから飛び終わるまで（速度を操っているあいだ）、その人（`agent`）に付けます。飛び終わったとき・剥奪で止められたときに外します。落下の軽減のあいだは付けません。
- 付け外しは `player_tag_holder`（PlayerSystem）で、`item_equip_lock_component` のロックと同じ区間です。
- ほかの System は `Agent.HasPlayerTag[jetpack_boosting_tag]`（動きを操られているかなら `controlled_movement_tag`）で確かめます。引力やホバーは、このタグが付いた人の速度を書き換えません。

## 公開 API
```verse
jetpack_boosting_tag<public> := class(controlled_movement_tag):

jetpack_boost_changed_event<public> := class(scene_event):
    Ability<public>:jetpack_ability_component
    Agent<public>:agent
    Ratio<public>:float

jetpack_ability_component<public> := class<final_super>(ability_component):
    BoostSpeedCmPerSecond<public>:float
    BoostDurationSeconds<public>:float
    BoostEaseExponent<public>:float
    BoostPitchDegrees<public>:float
    BoostYawDegrees<public>:float
    MinChargeSeconds<public>:float
    MaxChargeSeconds<public>:float
    MaxChargeMultiplier<public>:float
    ChargeLiftCm<public>:float
    ChargeRiseSpeedCmPerSecond<public>:float
    BoostEnergyCost<public>:float
    GlideEnergyPerSecond<public>:float
    RemoveItemWhenEmpty<public>:logic
    GlideMaxFallSpeedCmPerSecond<public>:float
    BoostAction<public>:input_action(logic)
    BoostMapping<public>:input_mapping
    RemoveMappingOnRevoke<public>:logic
    BoostRatioChangedEvent<public><final>:listenable(tuple(agent, float))
    GetBoostRatio<public>(Agent:agent)<transacts>:float     # 0.0〜1.0。付与されていない人は 0.0
    # Grant / Revoke / RevokeAll / IsGranted / GetGrantedAgents / GrantedEvent / RevokedEvent は ability_component から
```

## 前提・注意
- 地面で押したときは何もしません（ふつうのジャンプになります）。チャージを始めたら、着地するまでもう一度チャージできません。そのあいだに押し続けると落下の軽減になります。
- 地面にいると速度が効かないため、チャージの始めに `ChargeLiftCm` だけ位置を直接持ち上げます（MovementSystem の `LiftBy`。当たり判定は見ない）。
- 速度は毎フレーム（`TickEvents.PrePhysics`）`SetLinearVelocity` で入れます。経過時間は届いた秒数の足し合わせで測ります。
- エネルギーは `FindEnergyFor`（この entity か子孫の `energy_component`、無ければプレイヤー（agent）に付いたもの）で探します。どちらも無ければエネルギーを使わずに動きます。0 のときはチャージも落下の軽減もできません。
- 付与されるとすぐゲージは 1 になります。着地でも 1 に戻ります（エネルギーが 0 でも 1 になります）。
- slot へ送るには、区画（または世界）に `player_manager_component` が要ります（無ければ slot へは送りません）。付与された人の分が動き始めるときに探し、見つけたら覚えます（見つかるまでは、そのたびに探し直す）。
- `RunFor` の頭で `AwaitPlayerInput` を使い、入力が取れるまで待ちます。プレイヤーでない agent では動きません。
- 能力の側は持ち主を見ません。ロードアウトなど slot の下に置いたときに持ち主だけに付与されるのは、付与の component（`ability_grant_players_component` / `ability_grant_condition_component`）の働きです（AbilitySystem）。
- タグを agent に付けることは、PlayerSystem の `⚠ 未検証`（`PlayerTags.verse`：agent に付けたタグの付け外し・`ContainsTag` が実機で動くか）に頼っています。
- このフォルダのコードに `⚠ 未検証` と `@experimental` の API はありません。

## 確かめ方
- テスト：`_Test/JetpackSystemTest/` の `jetpack_system_test_component`。`player_manager_component` を付けた entity を 1 つ置き、テスト用の entity に `jetpack_system_test_component` だけを付けます（能力とエネルギーは、テストが実行時に子として作る）。コードからの付与・剥奪（回数の数え方、`GrantedEvent` / `RevokedEvent`、ゲージ、`jetpack_boost_changed_event` が上へ届くこと）を確かめたあと、ログに「jump, then hold jump in the air」と出たら、30 秒以内にジャンプし、空中でジャンプを 1 秒ほど押し続けて離し、着地します（チャージでゲージ 0、着地で 1、エネルギーが `BoostEnergyCost` だけ減ったか）。人の操作を含めて 1 分以内です。結果は出力ログの `[TEST] JetpackSystem`。
- 見本：`_Samples/AbilitySample/` の `ability_sample_component`。`jetpack_ability_component` を付けた entity に一緒に付けると、各プレイヤーが `ToggleAction`（既定 E / RB）で自分への付与を切り替えられます。ログは `[ability_sample]`。

## 移行が要るもの（2026-11-08）
| 旧 | 新 |
|---|---|
| `jetpack_boost_changed_event.Sender` | `jetpack_boost_changed_event.Ability`（送り元の項目名を Library 全体でそろえた。能力から送るものは `Ability`。包んで送る `player_event.Sender` はそのまま） |
