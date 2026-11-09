# HoverSystem

ホバーの能力（AbilitySystem の `ability_component` の派生）です。付与された人が空中で `HoverAction`（既定はジャンプ）を押し続けると、落ちる速さを抑えて浮きます。エネルギー（EnergySystem）があれば使います。回復はこの能力では持たず、チェックポイントに乗ったら満たすなら CheckpointSystem の EnergyKit（`checkpoint_energy_refill_component`）、使って回復するなら EnergySystem の RestoreKit を一緒に置きます（HoverSystem は CheckpointSystem に依存しません）。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `hover_ability_component` | 付与の component（AbilitySystem の GrantKit）と同じ entity。アイテムなら、アイテムの entity | 付与された人が空中で `HoverAction` を押し続けると、落ちる速さを `MaxFallSpeedCmPerSecond` までに抑える。ホバー中はその人に `hovering_tag` を付ける |

付与の仕方は、同じ entity に置く component で選びます。
- 全員に最初から／起動しているあいだ → `ability_grant_players_component`（エネルギーをこの entity に置くと全員で分け合う。1 人ずつにするならプレイヤーに付ける）
- アイテムとして（装備しているあいだ） → `item_component`・`item_holder_component`・`ability_grant_item_component` と一緒に置く（エネルギーはアイテムの entity に）
- 条件を満たしているあいだ → `ability_grant_condition_component`（子に条件）
- コードから → `Grant` / `Revoke`

例：「全員がホバーでき、チェックポイントで回復する」
```
区画（または世界）
├ プレイヤー管理（player_manager_component）
├ 足場（checkpoint_component + メッシュ）…
└ ホバー（hover_ability_component + ability_grant_players_component + energy_component + checkpoint_energy_refill_component）
```
`checkpoint_energy_refill_component`（CheckpointSystem/EnergyKit）は、その entity か子の `energy_component` を、能力を付与された人がチェックポイントに乗るたびに満たします。エネルギーをアイテムやプレイヤーに持たせるときは、区画の中の別の entity に `checkpoint_energy_refill_component` だけを置きます（乗った人とその持ち物のエネルギーを満たす）。

## 設定（@editable）
- `hover_ability_component.MaxFallSpeedCmPerSecond : float = 100.0` — ホバー中の落ちる速さの上限（センチメートル毎秒。0〜3000）。0 ならその高さで止まる。
- `hover_ability_component.EnergyPerSecond : float = 20.0` — ホバー中、1 秒に使うエネルギー（0〜1000）。エネルギーが無ければ減らさずにホバーできる。
- `hover_ability_component.HoverAction : input_action(logic) = Character.Jump` — 空中で押し続けるとホバーする操作。
- `hover_ability_component.HoverMapping : input_mapping = Character.TraversalMapping` — 付与しているあいだ有効にするキー割り当て。`HoverAction` を含むものを選ぶ。
- `hover_ability_component.RemoveMappingOnRevoke : logic = false` — 剥奪したときに `HoverMapping` を外す。この能力専用の割り当てのときだけオンにする（`TraversalMapping` のままオンにすると、移動の操作も効かなくなる）。

## イベント
- `hover_changed_event`（scene_event、SendUp）: `Ability : hover_ability_component`、`Agent : agent`、`Active : logic`（true = 始めた、false = やめた）。`hover_ability_component` がホバーを始めた・やめたときに、能力の entity から祖先へ送る（アイテムなら持ち主のプレイヤーまで）。消費しない。
- `hover_ability_component.HoverChangedEvent : listenable(tuple(agent, logic))` — だれかがホバーを始めた・やめたとき、（その人, true = 始めた / false = やめた）で届く。
- 付与・剥奪の `GrantedEvent` / `RevokedEvent` は `ability_component` のものです。
- 受けるもの：scene_event は受けません。

## タグ
- `hovering_tag`（`player_state_tag` の派生）：ホバーしているあいだ（空中で、落ちる速さを抑えているあいだ）、その人（agent）に付けます。押すのをやめた・着地した・エネルギーが 0 になった・剥奪されたときに外します。付け外しは `player_tag_holder` を通すので、ほかの部品が付けた `hovering_tag` は消しません。
- ほかの System は `Agent.HasPlayerTag[hovering_tag]` で確かめます。
- `controlled_movement_tag`（`swinging_tag`・`jetpack_boosting_tag` などの基底）が付いている人はホバーしません。

## 公開 API
```verse
hovering_tag<public> := class(player_state_tag):

hover_changed_event<public> := class(scene_event):
    Ability<public>:hover_ability_component
    Agent<public>:agent
    Active<public>:logic

hover_ability_component<public> := class<final_super>(ability_component):
    MaxFallSpeedCmPerSecond<public>:float
    EnergyPerSecond<public>:float
    HoverAction<public>:input_action(logic)
    HoverMapping<public>:input_mapping
    RemoveMappingOnRevoke<public>:logic
    HoverChangedEvent<public><final>:listenable(tuple(agent, logic))   # （その人, true = 始めた / false = やめた）
    IsHovering<public>(Agent:agent)<decides><transacts>:void          # 今落ちる速さを抑えているなら成功
    # Grant / Revoke / RevokeAll / IsGranted / GetGrantedAgents / GrantedEvent / RevokedEvent は ability_component から
```

## 前提・注意
- 区画（または世界）に `player_manager_component` が要ります（付与の component が使う）。
- `RunFor` の頭で `AwaitPlayerInput` を使い、入力が取れるまで待ちます。プレイヤーでない agent に付与すると動かず、出力ログに `[hover_ability_component] プレイヤーでない agent に付与されました…` と出ます。
- エネルギーは `FindEnergyFor`（EnergySystem。この entity か子孫の `energy_component`、無ければプレイヤー（agent）に付いたもの）で探します。0 になるとホバーできませんが、アイテムは無くなりません。
- エネルギーの回復は持ちません。チェックポイントで満たすなら CheckpointSystem の EnergyKit（`checkpoint_energy_refill_component`）、使って回復するなら EnergySystem の RestoreKit（`energy_restore_ability_component`）を使います。
- タグを agent に付けることは、PlayerSystem の `PlayerTags.verse` で「⚠ 未検証：agent に付けたタグの付け外し・ContainsTag が実機で動くか」とされています（`_Test/PlayerSystemTest` で確かめる）。
- 付与の component をプレイヤーの slot の下（ロードアウトの中など）に置くと、持ち主にだけ付与されます（GrantKit の決まり）。この能力そのものの動きは変わりません。
- 実験的な API は使っていません。

## 確かめ方
- テスト：`_Test/HoverSystemTest/` の `hover_system_test_component`。`player_manager_component` を付けた entity を 1 つ置き、テスト用の entity に `hover_system_test_component` だけを付けます（能力とエネルギーはテストが実行時に子として作る）。コードからの `Grant` / `Revoke`、ホバーの知らせ・`IsHovering`・エネルギーの減りを確かめます（チェックポイントでの回復は `_Test/CheckpointSystemTest` で確かめる）。「jump and hold jump in the air」と出たら、30 秒以内にジャンプし、空中でジャンプを 1 秒ほど押し続けて離します。結果は出力ログの `[TEST] HoverSystem`。
- 見本：`_Samples/AbilitySample/` の `ability_sample_component`。`hover_ability_component` を付けた entity に一緒に付けると、`ToggleAction`（既定 E / RB）で自分への付与を切り替えられます。

## 移行が要るもの（2026-11-08）
| 旧 | 新 |
|---|---|
| `hover_ability_component.RefillOnCheckpoint : logic = true`（区画の `checkpoint_presence_component` を購読してエネルギーを満たす） | 削除。ホバーの entity に `checkpoint_energy_refill_component`（CheckpointSystem/EnergyKit）を足す。その entity か子の `energy_component` を、付与された人が乗ったときに満たす（今までと同じ）。エネルギーがアイテム・プレイヤーにあるときは、区画の中の別の entity に置く。エディターで `RefillOnCheckpoint` を変えていたレベルは、その値が消える |
| `hover_changed_event.Sender` | `hover_changed_event.Ability`（送り元の項目名を Library 全体でそろえた。能力から送るものは `Ability`） |
