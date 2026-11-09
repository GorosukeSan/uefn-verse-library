# GravitySystem

引力の点を扱う System です。`gravity_well_component` は近くのプレイヤーを中心へ引き、`gravity_point_ability_component` は、付与された人がレティクルの先にその点を置ける能力（AbilitySystem の `ability_component` の派生）です。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `gravity_well_component` | 引力を持たせたい entity（見た目のメッシュと同じ entity）。実行時に能力が作ることもある | 毎フレーム、`RadiusCm` 以内のプレイヤーを中心へ引く（速度に足す） |
| `gravity_point_ability_component` | 付与の component（AbilitySystem の GrantKit）と同じ entity。アイテムなら、アイテムの entity | 付与された人が `PlaceAction` を押すと、レティクルの先に引力の点を置き、`DurationSeconds` 秒で消す。置いているあいだにもう一度押すとすぐ消す |

付与の仕方（`gravity_point_ability_component`）は、同じ entity に置く component で選びます。
- アイテムとして（装備しているあいだ） → `item_component`・`item_holder_component`・`ability_grant_item_component` と一緒に置く。1 人 1 つまでにするなら `exclusive_item_component`
- 全員に最初から／起動しているあいだ → `ability_grant_players_component`（1 人 1 つずつ置ける）
- 条件を満たしているあいだ → `ability_grant_condition_component`（子に条件）
- コードから → `Grant` / `Revoke`

例：置いておく引力の点と、引力の点を置くアイテム
```
区画（または世界）
├ プレイヤー管理（player_manager_component）
├ 引力の点（gravity_well_component + メッシュ）
└ 引力の銃（item_component + item_holder_component + ability_grant_item_component + gravity_point_ability_component）
```

## 設定（@editable）
- `gravity_well_component.RadiusCm : float = 1500.0` — 引力が届く半径（センチメートル。100〜20000）。中心で一番強く、この距離で 0。
- `gravity_well_component.StrengthCmPerSecondSquared : float = 1200.0` — 中心での引く強さ（センチメートル毎秒毎秒。0〜10000）。毎秒この速さずつ、中心へ向かう速さが増える。
- `gravity_point_ability_component.WellPrefab : concrete_subtype(entity) = entity` — 置く点の見た目にする prefab。置くたびにこれを作り、`gravity_well_component` を足す。既定の entity のままなら見た目の無い点。
- `gravity_point_ability_component.DurationSeconds : float = 30.0` — 置いた点が消えるまでの時間（秒。1〜600）。
- `gravity_point_ability_component.PlaceDistanceCm : float = 800.0` — レティクルの先、何センチメートルに置くか（100〜10000）。あいだに物があればその手前（当たった所から 150 cm 手前）に置く。
- `gravity_point_ability_component.RadiusCm : float = 1500.0` / `StrengthCmPerSecondSquared : float = 1200.0` — 置く点に渡す半径と強さ（意味は `gravity_well_component` と同じ）。
- `gravity_point_ability_component.PlaceAction : input_action(logic) = Character.WeaponPrimary` — 押すと点を置く（置いているときは消す）操作。
- `gravity_point_ability_component.PlaceMapping : input_mapping = Character.RangedWeaponMapping` — 付与しているあいだ有効にするキー割り当て。`PlaceAction` を含むものを選ぶ。
- `gravity_point_ability_component.RemoveMappingOnRevoke : logic = false` — 剥奪したときに `PlaceMapping` を外す。この能力専用の割り当てのときだけオンにする（`RangedWeaponMapping` のままオンにすると、武器の操作も効かなくなる）。

## イベント
- scene_event は送りません。
- `gravity_point_ability_component.PlacedEvent : listenable(tuple(agent, gravity_well_component))` — だれかが点を置いたとき、（置いた人, 置いた点）で届く。
- `gravity_point_ability_component.RemovedEvent : listenable(agent)` — だれかの点が消えたとき（時間切れ・もう一度押した・`RemoveWell`・シミュレーションの終わり）、置いた人で届く。
- 付与・剥奪の `GrantedEvent` / `RevokedEvent` は `ability_component` のものです。

## 公開 API
```verse
gravity_well_component<public> := class<final_super>(component):
    RadiusCm<public>:float
    StrengthCmPerSecondSquared<public>:float

gravity_point_ability_component<public> := class<final_super>(ability_component):
    WellPrefab<public>:concrete_subtype(entity)
    DurationSeconds<public>:float
    PlaceDistanceCm<public>:float
    RadiusCm<public>:float
    StrengthCmPerSecondSquared<public>:float
    PlaceAction<public>:input_action(logic)
    PlaceMapping<public>:input_mapping
    RemoveMappingOnRevoke<public>:logic
    PlacedEvent<public><final>:listenable(tuple(agent, gravity_well_component))   # （置いた人, 置いた点）
    RemovedEvent<public><final>:listenable(agent)
    FindWell<public>(Agent:agent)<decides><transacts>:gravity_well_component     # Agent の点が無ければ失敗
    Toggle<public>(Agent:agent):void       # 押したときと同じ（無ければ置き、あれば消す）。キャラクターがいなければ何もしない
    RemoveWell<public>(Agent:agent):void   # 無ければ何もしない
    # Grant / Revoke / RevokeAll / IsGranted / GetGrantedAgents / GrantedEvent / RevokedEvent は ability_component から
```

## 前提・注意
- 区画（または世界）に `player_manager_component` が 1 つ要ります（引く相手）。`gravity_well_component` は最初に 1 度だけ探して覚えます（見つかるまでは 1 秒ごとに探し直す）。
- `controlled_movement_tag`（PlayerSystem。`swinging_tag`・`jetpack_boosting_tag` などの基底）が付いている人は引きません（その動きを優先する）。
- 1 人が置ける点は、能力 1 つにつき 1 つまでです。剥奪されても、置いた点は時間まで残ります（シミュレーションの終わりには消す）。
- 置いた点は、能力の entity の下ではなく、シミュレーションの根の entity の子に作ります。
- 点の見た目のメッシュに当たり判定があれば、スイングでもつかめます。
- 付与の component をプレイヤーの slot の下（ロードアウトの中など）に置くと、持ち主にだけ付与されます（GrantKit の決まり）。この能力そのものの動きは変わりません。
- 実験的な API は使っていません。

## 確かめ方
- テスト：`_Test/GravitySystemTest/` の `gravity_system_test_component`。`player_manager_component` を付けた entity を 1 つ置き、テスト用の entity に `gravity_system_test_component` だけを付けます（点と能力はテストが実行時に作る）。プレイヤーの頭の上 3 m に物が無い開けた場所で始めます。点がプレイヤーを引き上げること、コードからの `Grant` / `Revoke`、`Toggle` で置く・消す、時間切れを確かめます。「press fire」と出たら、30 秒以内に射撃のボタンを押します。人の操作を除いて約 5 秒かかります。結果は出力ログの `[TEST] GravitySystem`。
- 見本：`_Samples/AbilitySample/` の `ability_sample_component`。`gravity_point_ability_component` を付けた entity に一緒に付けると、`ToggleAction`（既定 E / RB）で自分への付与を切り替えられます。
