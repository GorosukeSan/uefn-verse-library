# EnergySystem

能力やアイテムが使う「エネルギー」の量を持つ System です。`energy_component` が量を持ち、減らす・戻すと上へ知らせます。エネルギーを回復する能力（RestoreKit の `energy_restore_ability_component`）もあります。チェックポイントに乗ったら満たすときは CheckpointSystem の EnergyKit（`checkpoint_energy_refill_component`）を使います（EnergySystem はチェックポイントを知りません）。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `energy_component` | エネルギーを使う能力・アイテムの entity か、その子。ロードアウト・独自キャラクターの根に 1 つ置けば、その中の部品が同じエネルギーを使う。プレイヤーごとに持たせるなら、実行時にプレイヤー（agent の entity）に付ける | 量を持つ（`StartFull` なら満タン、そうでなければ 0 で始まる）。量が変わったら `energy_changed_event` を上へ送る |
| `energy_restore_ability_component`（RestoreKit） | 能力の entity。付与の仕方は同じ entity に置く component（AbilitySystem / ItemSystem）で選ぶ | 付与された人が `RestoreAction` を押すと、その人のエネルギー（`FindRestoreTarget`）を `RestoreAmount` 回復する。アイテムなら 1 つ減らす |

`energy_restore_ability_component` の付与の仕方：
- アイテムとして（装備しているあいだ。使うと 1 つ減る） → アイテムの entity に `item_component`・`item_holder_component`・`ability_grant_item_component` と一緒に置く。重ねて持つなら `basic_stackable_component`。
- 全員に最初から（回数無制限） → `ability_grant_players_component`。連打を防ぐなら `CooldownSeconds` を決める。
- 条件を満たしているあいだ → `ability_grant_condition_component`（子に条件）。
- コードから → `Grant` / `Revoke`。

例：エネルギーを使う能力（jetpack・hover は `FindEnergyFor` で探す）と、回復アイテム
```
ジェットパック（jetpack_ability_component + 付与の component）
└ 燃料（energy_component）

回復薬（item_component + item_holder_component + ability_grant_item_component + basic_stackable_component + energy_restore_ability_component）
```

## 設定（@editable）
- `energy_component.MaxEnergy : float = 100.0` — 最初の最大量（1〜10000）。`SetMax` で変えたあとの最大は `GetMax` で読む。
- `energy_component.StartFull : logic = true` — オンなら満タンで始める。オフなら 0 で始める（チェックポイントや回復で満たしてから使うとき）。
- `energy_restore_ability_component.RestoreAmount : float = 100.0` — 使ったときに回復する量（0〜10000）。
- `energy_restore_ability_component.CooldownSeconds : float = 0.0` — 回復してから次に使えるまでの秒数（0〜600）。0 ならすぐ使える。
- `energy_restore_ability_component.ConsumeItemOnUse : logic = true` — オンなら、アイテムに置いたとき回復するたびにアイテムを 1 つ減らす（最後の 1 つなら無くなり、能力も剥奪される）。アイテムでなければ使わない。
- `energy_restore_ability_component.RestoreAction : input_action(logic) = Character.WeaponPrimary` — 押すと回復する操作（攻撃のボタン）。
- `energy_restore_ability_component.RestoreMapping : input_mapping = Character.RangedWeaponMapping` — 付与しているあいだ足すキー割り当て。`RestoreAction` を含むものを選ぶ。
- `energy_restore_ability_component.RemoveMappingOnRevoke : logic = false` — オンなら剥奪したとき（アイテムなら装備を外したとき）に `RestoreMapping` を外す。この能力専用の割り当てのときだけオンにする。

## イベント
- `energy_changed_event`（scene_event、SendUp）: `Energy : energy_component`（割合は `Energy.GetRatio()`）、`Amount : float`（変わったあとの量）、`Delta : float`（前に知らせた量からの差。増えたらプラス）。`energy_component` の entity から上へ（アイテムなら持ち主のプレイヤーまで）。前に知らせた量から変わったときだけ送る。`Consume` / `Restore` / `SetAmount` / `Fill` / `SetMax` ではすぐ、`Spend[]` では同じフレームの物理のあと（`TickEvents.PostPhysics`）に送る。消費しない。
- `energy_restore_failed_event`（scene_event、SendUp）: `Ability : energy_restore_ability_component`、`Agent : agent`。使ったが回復するものが無かったときに、能力の entity から上へ送る（HUD で「回復するものが無い」と出すなど）。消費しない。
- listenable（外から Signal はできない）
  - `energy_component.ChangedEvent : listenable(float)` — 量が変わるたびに、変わったあとの量で届く（`energy_changed_event` と同じタイミング。`Spend[]` のときは物理のあと）。
  - `energy_restore_ability_component.RestoredEvent : listenable(tuple(agent, energy_component))` — 回復したときに、（使った人, 回復した energy_component）で届く。
  - `energy_restore_ability_component.FailedEvent : listenable(agent)` — 回復するものが無かったときに、使った人で届く。

## 公開 API
```verse
energy_changed_event<public> := class(scene_event):
    Energy<public>:energy_component
    Amount<public>:float                                   # 変わったあとの量
    Delta<public>:float                                    # 前に知らせた量からの差（増えたらプラス）

energy_component<public> := class<final_super>(component):
    MaxEnergy<public>:float
    StartFull<public>:logic                                # 既定 true。false なら 0 で始まる
    var<private> CurrentAmount<public>:float               # 今の量（0〜最大）
    ChangedEvent<public><final>:listenable(float)
    GetMax<public>()<reads>:float                          # SetMax を呼ぶまでは MaxEnergy
    IsEmpty<public>()<decides><reads>:void
    IsFull<public>()<decides><reads>:void
    HasEnough<public>(Amount:float)<decides><reads>:void   # Spend[] が成功するかを、量を変えずに確かめる
    GetRatio<public>()<reads>:float                        # 0.0〜1.0。最大が 0 なら 0.0
    Spend<public>(Amount:float)<decides><transacts>:void   # 足りれば減らす。足りない・マイナスなら失敗して何も変えない。if の条件に書ける。知らせは物理のあと
    Consume<public>(Amount:float):void                     # 足りなくても失敗せず 0 で止まる
    Restore<public>(Amount:float):void                     # 最大を超える分は捨てる
    SetAmount<public>(Value:float):void                    # 0〜最大に丸めて量を決める
    Fill<public>():void
    SetMax<public>(NewMax:float):void                      # マイナスは 0。今の量が超えていれば丸める

(InEntity:entity).FindEnergy<public>()<decides><transacts>:energy_component                # 自身か子孫。無ければ失敗
(InEntity:entity).FindEnergyFor<public>(Agent:agent)<decides><transacts>:energy_component  # FindEnergy、無ければ Agent 自身
(InEntity:entity).FindEnergyAbove<public>()<decides><transacts>:energy_component           # FindEnergy、無ければ祖先（近い順）

# RestoreKit
energy_restore_failed_event<public> := class(scene_event):
    Ability<public>:energy_restore_ability_component
    Agent<public>:agent

energy_restore_ability_component<public> := class<final_super>(ability_component):
    RestoreAmount<public>:float
    CooldownSeconds<public>:float
    ConsumeItemOnUse<public>:logic
    RestoreAction<public>:input_action(logic)
    RestoreMapping<public>:input_mapping
    RemoveMappingOnRevoke<public>:logic
    RestoredEvent<public><final>:listenable(tuple(agent, energy_component))
    FailedEvent<public><final>:listenable(agent)
    TryRestoreFor<public>(Agent:agent):logic               # 押したときと同じ処理。回復できたら true
    FindRestoreTarget<public>(Agent:agent)<decides><transacts>:energy_component
```

## 前提・注意
- 量は 0〜最大（`GetMax`）に丸めます。`SetMax` をシミュレーション開始前に呼んだときは知らせず、開始時に新しい最大で始まります（`StartFull` なら満タン）。
- 最初の量（`StartFull` なら最大、そうでなければ 0）は、シミュレーション開始時か、それより前に量を変える関数（`Spend` / `Consume` / `Restore` / `SetAmount` / `Fill`）を最初に呼んだときに決まります。開始前に `SetAmount` で決めた量は、開始時に上書きしません。
- 足りるときだけ減らすなら `if (Energy.Spend[10.0]):` と書きます（足りなければ失敗し、何も変えない）。量はすぐ変わりますが、知らせる処理（SendUp・Signal）は巻き戻せないので、`energy_changed_event` と `ChangedEvent` は同じフレームの物理のあと（`TickEvents.PostPhysics`）に 1 回だけ送ります。それより前に `Consume` などで量を変えたときは、そのときにまとめて送ります（`Delta` は前に知らせた量からの差）。
- `FindEnergy` は、自身に無ければ子孫で最初に見つかったものを返します。子孫に複数あるとどれが返るか決まらないので、1 つだけ置きます。
- `FindEnergyFor`（jetpack・hover が使う）は、能力の entity（とその子孫）の `energy_component` を先に探し、無ければプレイヤー（agent の entity）自身に付いたものを探します（持ち物の中は探さない）。能力の entity に置いたエネルギーは、付与された全員が分け合います。どちらも無ければ失敗し、能力はエネルギーを使わずに動きます。
- `FindEnergyAbove`（CharacterSystem のダッシュなどが使う）は、自身か子孫に無ければ祖先を近い順に探します。ロードアウト・独自キャラクターの根に 1 つ置くと、その中の部品がみな同じエネルギーを使います。
- `TryRestoreFor` は、知らせる処理（SendUp・Signal）やアイテムを減らす処理が巻き戻せないので `<decides>` にしていません。確かめるだけなら `FindRestoreTarget[]` を使います。
- 回復する先（`FindRestoreTarget`）は、持ち物（この entity 以外のアイテム）の `energy_component` のうち満タンでなく割合が一番低いもの、無ければプレイヤー自身の `energy_component`（満タンでなければ）です。すべて満タン・どれも無いなら失敗します。
- `RemoveMappingOnRevoke` を既定の `RangedWeaponMapping` のままオンにすると、武器の操作も効かなくなります。
- `energy_restore_ability_component` は AbilitySystem・ItemSystem・InputSystem を使います。`RunFor` の頭で `AwaitPlayerInput` を使い、入力が取れるまで待ちます。プレイヤーでない agent に付与すると動かず、出力ログに `[energy_restore_ability_component] プレイヤーでない agent に付与されました…` と出ます。

## 確かめ方
- テスト：`_Test/EnergySystemTest/` の `energy_system_test_component`。`player_manager_component` を付けた entity を 1 つと、`energy_system_test_component` だけを付けた entity を 1 つ置く（`energy_component` や能力はテストが実行時に子として作る）。`energy_component` の増減・丸め・`Spend[]`（失敗したら量が戻ること・知らせが物理のあとに 1 回だけ届くこと）・`SetAmount`・`StartFull`・`SetMax`・知らせ（`ChangedEvent` と `energy_changed_event` の `Amount` / `Delta`）、`FindEnergy` / `FindEnergyFor`、`energy_restore_ability_component` の `TryRestoreFor`・`FailedEvent` / `RestoredEvent`・コードからの `Grant` / `Revoke` を確かめます。プレイヤー（agent の entity）に `energy_component` を一時的に付けて確かめ、終わったら外します。最後にログに「press the fire button」と出たら 20 秒以内に射撃のボタンを押します（押さなければその項目だけ `[FAIL]`）。結果は出力ログの `[TEST] EnergySystem`。
- 見本（`_Samples/`）は無い。

## 移行が要るもの（2026-11-08）
| 旧 | 新 |
|---|---|
| `energy_component.TryConsume(Amount):logic` | `Spend[Amount]`（`<decides><transacts>`）。`if (Energy.Spend[X]):` と書く。logic が要るなら `logic{Energy.Spend[X]}`。知らせは同じフレームの物理のあと |
| `energy_changed_event{Energy}` | `energy_changed_event{Energy; Amount; Delta}`（項目を足しただけ。読む側はそのまま動く。作る側は無い想定） |
| （無し） | `energy_component.SetAmount(Value)`、`@editable StartFull`（既定 true = 今までどおり満タンで始まる） |
| `energy_restore_failed_event.Sender` | `energy_restore_failed_event.Ability`（送り元の項目名を Library 全体でそろえた。能力から送るものは `Ability`） |
