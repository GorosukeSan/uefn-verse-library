# GameSequenceSystem

ゲームの流れ（待機 → 本番 → 結果 のような段階）を、ノードと遷移の entity の木で組む System です。ノードに入ると配下へ起動の合図（ActivationSystem）を送り、出ると停止の合図を送ります。遷移の条件（ConditionSystem）を満たすと次のノードへ進みます。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `game_sequence_component` | 流れの根の entity。1 つの流れに 1 つ。レベルにいくつ置いてもよい（それぞれ自分の直下のノードだけを進める。区画は要らない） | 最初のノードから流れを進める。`Target` の無い遷移で終わる |
| `game_node_component` | `game_sequence_component` の entity の直下 | 流れの 1 段階。入ると配下へ起動、出ると停止を知らせ、子の遷移が進めるようになるまで待つ |
| `game_transition_component` | `game_node_component` の entity の直下 | 直下の条件をすべて満たしたら `Target` のノードへ進む（`Target` が空なら流れを終える）。条件が無ければすぐ進む |

例：「10 秒待ってから本番、ボタンを押したら終わり」
```
流れ（game_sequence_component）
├ 待機（game_node_component、Order 0 + countdown_component）
│ └ 本番へ（game_transition_component、Target = 本番）
│   └ 時間切れ（countdown_finished_condition_component）
└ 本番（game_node_component、Order 1）
  ├ 足場（spawn_prefab_component。SpawnSystem の PrefabKit）
  └ 終わり（game_transition_component、Target 空）
    └ 押された（interacted_condition_component）
      └ ボタン（basic_interactable_component + interact_trigger_component）
```

## 設定（@editable）
- `game_sequence_component.FirstNode : ?entity = false` — 最初に入るノード（`game_node_component` を付けた entity）。空なら直下の子のノードで `Order` が一番小さいもの。
- `game_sequence_component.StartOnRoundStart : logic = true` — オンならラウンドの開始で始め、ラウンドの終わりで止める。オンの流れはどれも同時に始まる。
- `game_sequence_component.StartOnActivate : logic = false` — オンなら起動の合図（`activated_event`）で始め、停止の合図（`deactivated_event`）で止める。受けた合図は消費し、配下のノードの部品へは届けない。ほかの流れのノードの下に置くと、そのノードのあいだだけ進む流れ（入れ子）になる。
- `game_sequence_component.StartOnBegin : logic = false` — オンならシミュレーション開始で始める（1 フレーム待ってから）。
- `game_node_component.Order : int = 0` — `FirstNode` が空のとき、最初のノードを選ぶ順番（0〜1000。小さいほど先）。
- `game_transition_component.Target : ?entity = false` — 条件を満たしたときに進むノード。空ならここで流れを終える。
- `game_transition_component.Priority : int = 0` — 同じノードの遷移が同時に進めるとき、大きいほうを優先する（0〜100）。

`StartOnRoundStart`・`StartOnActivate`・`StartOnBegin` をどれもオフにして、コードから `Start` を呼んでもかまいません。同じレベルに複数のゲーム（流れ）を置くときは `StartOnRoundStart` をオフにし、そのゲームの始まりの合図（`StartOnActivate`）か `Start` で始めます。

例：「ロビーのノードのあいだだけ、ミニゲームの流れを回す」
```
流れ（game_sequence_component、StartOnRoundStart）
├ ロビー（game_node_component、Order 0）
│ ├ ミニゲームの流れ（game_sequence_component、StartOnRoundStart オフ、StartOnActivate オン）
│ │ ├ 準備（game_node_component、Order 0）…
│ │ └ 遊ぶ（game_node_component、Order 1）…
│ └ 本番へ（game_transition_component、Target = 本番）…
└ 本番（game_node_component、Order 1）…
```

## イベント
- `game_node_entered_event`（`activated_event` の派生、SendDown）: `Node : game_node_component`。`game_node_component` がノードに入ったとき、ノードの entity から下へ送る。起動を待つ部品はこれで動き出す。消費しない。
- `game_node_exited_event`（`deactivated_event` の派生、SendDown）: `Node : game_node_component`、`Reason : game_node_exit_reason`。`game_node_component` がノードから出たとき、ノードの entity から下へ送る。起動を待つ部品はこれで止まる。消費しない。
- `game_sequence_state_changed_event`（scene_event、SendUp）: `Sequence : game_sequence_component`、`State : game_sequence_state`。`game_sequence_component` が状態の変わったときに根へ送る。受け手は祖先の component（流れの外の進行役など）。消費しない。
- `game_sequence_component.StateChangedEvent : listenable(game_sequence_state)` — 状態が変わるたびに、新しい状態で届く。
- `game_node_component.EnteredEvent : listenable(tuple())` — ノードに入ったときに届く。
- `game_node_component.ExitedEvent : listenable(game_node_exit_reason)` — ノードから出たときに、出た理由で届く。
- 出た理由（`game_node_exit_reason` の enum）: `Transitioned`（遷移の条件を満たして進んだ、または流れを終えた）、`Stopped`（`Stop`・ラウンドの終わり・シミュレーションの終わり）、`Jumped`（`JumpTo` / `Restart` で別のノードへ移った）。
- 受けるもの: `game_node_component` は `condition_changed_event`（遷移を調べ直す）。`game_sequence_component` は `StartOnActivate` のとき `activated_event`（`Start`）/ `deactivated_event`（`Stop`）を受けて消費する。

## 公開 API
```verse
game_sequence_state<public> := enum:
    Idle        # まだ始めていない
    Running     # ノードを進めている
    Stopped     # Stop・ラウンドの終わりで止まった
    Finished    # 最後の遷移（Target が空）まで進んだ
    Failed      # 最初のノードが無い・Target にノードが無いなどで止まった
(State:game_sequence_state).ToString<public>()<computes>:string

game_sequence_state_changed_event<public> := class(scene_event):
    Sequence<public>:game_sequence_component
    State<public>:game_sequence_state

game_sequence_component<public> := class<final_super>(component):
    FirstNode<public>:?entity
    StartOnRoundStart<public>:logic
    StartOnActivate<public>:logic
    StartOnBegin<public>:logic
    var<private> State<public>:game_sequence_state
    var<private> CurrentNode<public>:?game_node_component
    var<private> LastError<public>:?game_node_error             # 最後に Failed になった理由。次に失敗するまで残る
    StateChangedEvent<public><final>:listenable(game_sequence_state)
    Start<public>():void                                        # 最初のノードから始める。進めていれば何もしない（Stop のすぐあとなら、止まってから始める）
    Stop<public>():void                                         # 止める（ノードからは Stopped で出る）
    Restart<public>():void                                      # 最初のノードからやり直す
    JumpTo<public>(Node:game_node_component):void               # Node へ移る（ノードからは Jumped で出る）
    IsRunning<public>()<decides><transacts>:void                # State が Running のあいだ成功
    FindFirstNode<public>()<decides><transacts>:game_node_component

game_node_exit_reason<public> := enum:
    Transitioned
    Stopped
    Jumped

game_node_entered_event<public> := class(activated_event):
    Node<public>:game_node_component

game_node_exited_event<public> := class(deactivated_event):
    Node<public>:game_node_component
    Reason<public>:game_node_exit_reason

game_node_component<public> := class<final_super>(component):
    Order<public>:int
    EnteredEvent<public><final>:listenable(tuple())
    ExitedEvent<public><final>:listenable(game_node_exit_reason)
    IsActive<public>()<decides><reads>:void                    # 入ってから出るまで成功
    FindReadyTransition<public>()<decides><transacts>:game_transition_component   # 今進める遷移のうち Priority が一番大きいもの

game_transition_component<public> := class<final_super>(component):
    Target<public>:?entity
    Priority<public>:int
    IsReady<public>()<decides><transacts>:void                  # 直下の条件をすべて満たしていれば成功（条件が無ければいつも）
    IsFinish<public>()<decides><transacts>:void                 # Target が空（この遷移で流れを終える）なら成功

game_node_error<public> := class<computes>:
game_node_not_found_error<public> := class<computes>(game_node_error):
    Target<public>:entity                                       # game_node_component が付いていなかった遷移先
game_node_empty_error<public> := class<computes>(game_node_error):
```

## 前提・注意
- ノードを移るときは 1 フレーム空けます（同じフレームで遷移が回り続けないように）。
- `Stop` のあと、まだ止まりきらないうちに（同じフレームに）`Start` / `Restart` / `JumpTo` が来たら、来た順に処理します。今のノードから `Stopped` で出て状態が `Stopped` になってから、改めて始めます（`Start` は最初のノードから、`JumpTo` はその Node から）。`Start` → `Stop` の順なら始まりません。`StartOnActivate` の流れを置いたノードへ親の流れが入り直したとき（同じノードへの `JumpTo` / `Restart`）に、子の流れは停止と起動の合図を続けて受けますが、止まったままにはならず最初のノードから進み直します。
- `FirstNode` を決めたときは、その entity の `game_node_component` だけを見ます（付いていなければ失敗し、子へは探しにいきません）。空のときは直下の子だけを見ます（孫は見ません）。
- `Order`・`Priority` が同じ値どうしだと、どれが選ばれるかは決まりません。
- `JumpTo` の `Node` は、この流れの直下でなくてもかまいません。
- 遷移先の entity に `game_node_component` が無いときは `game_node_not_found_error`、最初のノードが見つからないときは `game_node_empty_error` で `Failed` になり、理由が `LastError` に残ります。遷移の結果を返す関数（以前の `GetResult`）はありません。流れを終える遷移かどうかは `IsFinish` で調べます。
- `StartOnRoundStart` はラウンドの管理（`GetFortRoundManager`）が見つかるときだけ効きます。
- `game_sequence_component` はほかの部品から探されません（`FindScopedComponent` の対象ではない）。区画（`game_scope_component`）が無くても、いくつ置いても取り合いません。ただし `StartOnRoundStart` がオンの流れはラウンドの開始でどれも同時に始まります。
- `StartOnActivate` の合図の消費で、配下のノードの部品に外の合図が届かなくなるのは、`SendDown` で消費すると下へ配られないことによります（⚠ 未検証：UEFN 実機で、消費した `SendDown` が子孫へ届かないこと）。
- ノードに入ったら prefab を出す部品 `spawn_prefab_component` は SpawnSystem の PrefabKit にあります（`using { SpawnSystem.PrefabKit }`。ノードの entity かその子孫に置くと、起動の合図で `SpawnOnActivate` 個を出し、停止の合図で消す（`DespawnOnDeactivate` が既定オン））。
- この System のコードには `⚠ 未検証` の印はなく、`@experimental` の API も使っていません。

## 確かめ方
- テスト：`_Test/GameSequenceSystemTest/` の `game_sequence_system_test_component`。この component を付けた entity を 1 つ置くだけ（流れ・ノード・遷移・条件はテストが実行時に作る。プレイヤーは要らない）。`Order` で決まる最初のノード、遷移（条件が 2 つなら両方満たすまで進まない）、`Finished`、`Restart`、`JumpTo`、`Stop`、出た理由、`StartOnActivate` の入れ子の流れ、同じフレームの `Stop` → `Start`（止まってから最初のノードで始め直す。親が同じノードに入り直したときの子の流れ）を確かめます。約 2 秒。結果は出力ログの `[TEST] GameSequenceSystem`。
- 入れ子の流れは、ノード C の下の流れが C に入ると始まり、C から出ると止まることを見ます。`_Samples/` に GameSequenceSystem の見本はありません。

## ラウンド
- `StartOnRoundStart` は `round_watcher`（ActivationSystem）で、ラウンドの始まりに `Start`、終わりに `Stop` する。流れの中の部品をラウンドに合わせるには、ノードの起動・停止の合図がそのまま使える。ゲームの流れを使わずにラウンドへ合わせるなら `activate_on_round_component`。

## 移行が要るもの（2026-11-08）
- FeatureKit は無くなりました。`spawn_prefab_component` は `SpawnSystem.PrefabKit` へ移り、出す場所・数・消す機能が増えました（`Spawn(Count)` / `TrySpawnAt` / `Despawn(Spawned)` / `DespawnAll` など。SpawnSystem の README）。`using { GameSequenceSystem.FeatureKit }` → `using { SpawnSystem.PrefabKit }`。
- ToolTip の `SpawnCategory` / `SpawnPrefabToolTip` は GameSequenceSystem.TooltipKit から消えました。
- `game_sequence_component.StartOnActivate` を足しました（既定オフなので、今の置き方はそのまま動く）。
