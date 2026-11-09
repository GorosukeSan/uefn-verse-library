# AbilitySystem

1 人ずつに「能力」を付与・剥奪する仕組みの基底です。能力そのものは `ability_component` の派生として各 System にあり、だれにいつ付与するかは同じ entity に置く付与の component（GrantKit）かコードで決めます。能力の側は付与の仕方を知りません。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `ability_component` の派生 | 能力の entity。直接は置かない（派生を置く）。1 entity に何個置いてもよい | 付与されているあいだ、その人について派生の `RunFor` を動かし、剥奪されると止める |
| `ability_grant_players_component`（GrantKit） | 能力と同じ entity | 区画の全プレイヤー（途中参加も）に、同じ entity の能力すべてを付与する。退出した人からは剥奪する。持ち主のいる entity なら持ち主にだけ |
| `ability_grant_item_component`（GrantKit） | アイテムの entity（`item_component`・`item_holder_component`・能力と同じ entity） | アイテムの持ち手（`item_holder_component` が決める）に付与し、外れたら剥奪する |
| `ability_grant_condition_component`（GrantKit） | 能力と同じ entity。直下の子に条件を 1 つ | 条件を満たしているあいだ、区画の全プレイヤー（持ち主のいる entity なら持ち主）に付与する。満たさなくなったら剥奪する |

能力の派生：`swing_ability_component`（SwingSystem）、`jetpack_ability_component`（JetpackSystem）、`hover_ability_component`（HoverSystem）、`gravity_point_ability_component`（GravitySystem）、`energy_restore_ability_component`（EnergySystem / RestoreKit）。

例：「このノードにいるあいだ全員がスイングできる。ロードアウトを付けた人は、しゃがんでいるあいだだけホバーできる」
```
ノード（game_node_component）
└ スイング（swing_ability_component + ability_grant_players_component（GrantOnBegin = false））

ロードアウトのプレハブ（LoadoutSystem の loadout_component.Prefab）
└ ホバー（hover_ability_component + ability_grant_condition_component）
  └ しゃがみ（player_state_condition_component（PlayerSystem / MotionKit）、State = Crouching）
```
ロードアウトの中なので、ホバーは持ち主にだけ付与されます。
アイテムにするなら、能力の entity に `item_component`・`item_holder_component`・`ability_grant_item_component` を一緒に付けます。

## 設定（@editable）
- `ability_grant_players_component.GrantOnBegin : logic = true` — オンなら、シミュレーション開始から（参加したらすぐ）付与する。オフなら起動の合図（ゲームの流れなら、このノードに入ったとき）から停止の合図まで付与する。

`ability_grant_item_component` と `ability_grant_condition_component` に設定はありません（持ち手は `item_holder_component`、条件は直下の子の `condition_component` が決めます）。

## イベント
- scene_event は送りません。
- `ability_component.GrantedEvent : listenable(agent)` — 付与されて `RunFor` を始めたとき（付与の回数が 0 → 1）。
- `ability_component.RevokedEvent : listenable(agent)` — すべての付与元から剥奪されて止めたとき（回数が 0 になったとき、`RevokeAll`）。
- 受けるもの：`ability_grant_players_component` は `activated_event`（付与を始める）と `deactivated_event`（自分が付与した人から剥奪する）。消費しない。`GrantOnBegin` がオンでも、この合図には反応します。
- 見るもの：`ability_grant_item_component` は `item_holder_component.HolderAddedEvent` / `HolderRemovedEvent`、`ability_grant_condition_component` は子の条件の `ChangedEvent`。

## 持ち主
- `ability_grant_players_component` と `ability_grant_condition_component` は、自分の entity が持ち主のいる場所（プレイヤーの slot の下。ロードアウトの中など）にあれば（`FindOwningPlayer[]` が成功すれば）、持ち主にだけ付与します。区画の全員には付与せず、参加・退出も見ません。
- 持ち主がいなければ、区画（または世界）の `player_manager_component` の全員（途中参加も）に付与し、退出した人から剥奪します。
- `ability_grant_item_component` は持ち主を見ません。付与する相手はアイテムの持ち手です。
- 持ち主は付与を始めるとき（`Start`）に探します。

## 公開 API
```verse
ability_component<public> := class<abstract><final_super>(component):
    GrantedEvent<public><final>:listenable(agent)
    RevokedEvent<public><final>:listenable(agent)
    RunFor<protected>(Agent:agent)<suspends>:void         # 派生が実装する。剥奪されると race で止められる
    Grant<public>(Agent:agent):void                        # 付与の回数を 1 増やす。0 → 1 で RunFor を始める
    Revoke<public>(Agent:agent):void                       # 付与の回数を 1 減らす。0 になったら止める。付与されていなければ何もしない
    RevokeAll<public>():void                               # 回数にかかわらず全員から剥奪する
    IsGranted<public>(Agent:agent)<decides><transacts>:void
    GetGrantedAgents<public>()<transacts>:[]agent          # 並び順は決まっていない

(InEntity:entity).GetAbilities<public>()<reads>:[]ability_component   # InEntity に付いている能力すべて

# GrantKit
ability_grant_players_component<public> := class<final_super>(component):
    GrantOnBegin<public>:logic
    IsGranting<public>()<decides><transacts>:void          # 付与しているあいだ成功

ability_grant_item_component<public> := class<final_super>(component):

ability_grant_condition_component<public> := class<final_super>(component):
    IsGranting<public>()<decides><transacts>:void          # 条件を満たして付与しているあいだ成功
```

## 前提・注意
- 同じ人に複数の付与元から付与されても `RunFor` は 1 つだけ動きます。付与の回数を数え、すべて剥奪されたときに止めます。`Revoke` を 1 回呼んでも、ほかの付与元の分が残っていれば止まりません。
- 付与の component は、自分が付与した人だけを覚えて剥奪します（ほかの付与元の分には触りません）。同じ entity の付与の component は、その entity の能力すべてを付与します。
- `RunFor` の後片付けは `RunFor` の中の `defer` で行います（剥奪で race により止められるため）。`RunFor` が戻ると、付与が続いていても能力はそこで終わります。
- 剥奪してすぐ付与し直しても、前の `RunFor` は止まり、新しい `RunFor` が始まります（人ごとの番号で見分ける）。
- `ability_grant_players_component` と `ability_grant_condition_component` は、持ち主がいないとき区画（または世界）に `player_manager_component` が 1 つ要ります。`ability_grant_item_component` は同じ entity に `item_holder_component` が要ります。`ability_grant_condition_component` は直下の子に条件が要ります（複数の条件は `condition_all` / `condition_any` でまとめる）。これらが無いときは何もしません（出力ログにも出ません）。
- シミュレーションの終わり（`OnEndSimulation`）に、能力は全員から剥奪し、付与の component は自分の分を剥奪します。
- この System のコードに `⚠ 未検証` の項目と `@experimental` の API はありません。

## 確かめ方
- テスト：`_Test/AbilitySystemTest/` の `ability_system_test_component`。`player_manager_component` を付けた entity を 1 つ置き、テスト用の entity に `ability_system_test_component` と `ability_test_probe_component` を付けます（付与の component は付けない）。別の entity に `ability_test_probe_component` と `ability_grant_players_component`（`GrantOnBegin = true`）を付け、その entity を `GrantedByPlayers` に入れます。最初に参加したプレイヤーで、コードからの `Grant` / `Revoke` と回数の数え方、`GrantedEvent` / `RevokedEvent`、`RevokeAll`、`ability_grant_players_component` が参加者に 1 回ずつ付与することを確かめます。持ち主のいる形と、item / condition の付与はテストしていません。結果は出力ログの `[TEST] AbilitySystem`。
- 見本：`_Samples/AbilitySample/` の `ability_sample_component`。能力の component（swing / jetpack / hover / gravity_point など）を 1 つ以上付けた entity に付けます（付与の component は任意。区画に `player_manager_component` が 1 つ）。開始時に同じ entity の能力と付与の component を出力ログに一覧し、`GrantedEvent` / `RevokedEvent` を Print します。`ToggleAction`（既定 `NextTab`、E / RB。`MenuNavigationMapping`）を押すと、自分への `Grant` / `Revoke` を切り替えます。`StartOnBegin` オフなら起動の合図から動きます。
