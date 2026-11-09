# InteractSystem

その場で「押して使う」物（ボタン・レバー・宝箱など）を、ライブラリの起動の合図（ActivationSystem）と条件（ConditionSystem）につなぐ System です。押す仕組みそのものは Epic 標準の `interactable_component`（`basic_interactable_component` など）を使い、この System は同じ entity に置いて結果を受け取ります。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `interact_trigger_component` | `interactable_component` と同じ entity | 押し終わるたびに `interacted_event` を上へ送り、`Targets` の entity へ起動の合図（だれが押したか付き）を送る。`Toggle` なら起動の合図と停止の合図を交互に送る（スイッチ・レバー） |
| `interacted_condition_component`（ConditionKit） | `game_transition_component` か `condition_all` / `condition_any` の entity の直下 | 押されたら満たす。起動の合図を受ける（ノードに入り直す）と満たさなくなる |
| `interact_gate_component`（GateKit） | `interactable_component` と同じ entity。起動の合図が届く場所（`interact_trigger_component` の `Targets` で選ばれた entity でもよい） | 開いているあいだだけ押せる。起動の合図で開き、停止の合図で閉じる（`OpenOnBegin` なら最初から開く。コードから `Open` / `Close`） |

例：「ボタンを押したら次へ」
```
ノード（game_node_component）
└ 次へ（game_transition_component）
  └ 押された（interacted_condition_component）
    └ ボタン（basic_interactable_component + interact_trigger_component + interact_gate_component + メッシュ）
```
ノードに入ると起動の合図がボタンまで届いてゲートが開き、ノードを出ると閉じます。ボタンを条件の下に置けないときは、条件の `Trigger` でボタンの entity を選びます。

## 設定（@editable）
- `interact_trigger_component.Targets : []entity = array{}` — 押し終わるたびに起動の合図を送る entity（その entity と子孫に届く）。空なら上へ知らせるだけ。
- `interact_trigger_component.Toggle : logic = false` — オンなら、押すたびに `Targets` へ起動の合図と停止の合図を交互に送る。オフなら起動の合図だけ。
- `interacted_condition_component.Trigger : ?entity = false` — 見張るボタン（`interact_trigger_component` を付けた entity）。子孫に置いたボタンは選ばなくても数える。
- `interact_gate_component.OpenOnBegin : logic = false` — オンならシミュレーション開始から押せる（ゲームの流れを使わないとき）。オフなら起動の合図から。

押せる回数・待ち時間・押し続ける長さは `basic_interactable_component` の設定で決めます。

## イベント
- `interacted_event`（scene_event、SendUp）: `Trigger : interact_trigger_component`、`Agent : agent`。`interact_trigger_component` が押し終わるたびに、自分の entity から根まで送る。受け手は祖先の `interacted_condition_component` など。消費しない。
- `interact_trigger_component` の listenable（どれも `listenable(agent)`、外から Signal はできない）
  - `InteractedEvent` — 押し終わるたびに、押した人で届く。
  - `StartedEvent` — 押し始めるたびに届く（長押しなら押し始めた時点。押す時間が 0 なら `InteractedEvent` と同じ時点）。
  - `CanceledEvent` — 長押しを途中でやめるたびに届く。
- 送るもの: `interact_trigger_component` は `Targets` へ、`Toggle` がオフなら `activated_by_agent_event`（`SendActivatedBy`。受け手は `FindActivatingAgent[]` で押した人を読める）。`Toggle` がオンなら `activated_event` / `deactivated_event`（`SendActivated` / `SendDeactivated`。押した人は付かない）。
- 受けるもの: `interacted_condition_component` は `activated_event`（元に戻す）と `interacted_event`（満たす）。`interact_gate_component` は `activated_event`（開く）/ `deactivated_event`（閉じる）。

## 公開 API
```verse
interacted_event<public> := class(scene_event):
    Trigger<public>:interact_trigger_component
    Agent<public>:agent

interact_trigger_component<public> := class<final_super>(component):
    Targets<public>:[]entity
    Toggle<public>:logic
    InteractedEvent<public><final>:listenable(agent)   # 押し終わった
    StartedEvent<public><final>:listenable(agent)      # 押し始めた
    CanceledEvent<public><final>:listenable(agent)     # 長押しを途中でやめた
    IsOn<public>()<decides><transacts>:void            # Toggle で今オンなら成功。Toggle でなければ失敗
    SetOn<public>(Value:logic):void                    # オン・オフを決めて Targets へ合図を送る。変わらなければ何もしない

# ConditionKit
interacted_condition_component<public> := class<final_super>(condition_component):
    Trigger<public>:?entity
    Reset<public>():void                               # 満たさない状態に戻す

# GateKit
interact_gate_component<public> := class<final_super>(component):
    OpenOnBegin<public>:logic
    Open<public>():void
    Close<public>():void
    IsOpen<public>()<decides><transacts>:void
```
実行時のコードからは `Trigger.InteractedEvent.Await()` で押した人を待てます。

## 前提・注意
- 同じ entity に `interactable_component`（`basic_interactable_component` など）が要る。無ければトリガーもゲートも何もしない。
- `StartedEvent` は v43.00 から押し始めた時点で届く（コードのコメントによる）。
- `IsOn` / `SetOn` のオン・オフは `Toggle` のための状態。`Toggle` でないとき `IsOn` は失敗する。`SetOn` は `Toggle` でなくても使え、`Targets` へ起動・停止の合図を送る（押した人は付かない）。
- ゲームの流れの外で使うときは、`interact_gate_component.OpenOnBegin` をオンにする（ゲートを置かなければいつでも押せる）か、コードから `Open` / `Close` を呼ぶ。
- `interact_gate_component` は開始時と最初のフレームの 2 回、`interactable_component` の Enable / Disable を合わせる（同じ entity の `interactable_component` の開始の処理のあとにもう一度合わせるため）。
- `interacted_condition_component` は `Trigger` で選んだボタンの `InteractedEvent` と、子孫のボタンから上がってくる `interacted_event` の両方で満たす。
- 実験的な API は使っていない。

## 確かめ方
- テスト：`_Test/InteractSystemTest/` の `interact_system_test_component`。ボタンの entity（メッシュ + `basic_interactable_component` + `interact_trigger_component` + `interact_gate_component`、`OpenOnBegin` はオフ）をプレイヤーの近くに置き、テストの component を付けた entity の `Button` にボタンの entity を入れる。ゲートの `Open` / `Close` / `IsOpen`、`InteractedEvent`、`interacted_condition_component`（`Trigger` で選ぶ形）と `Reset` を確かめる。ログに「interact」と出たら 15 秒以内にボタンを押す（押さなければその項目だけ失敗）。長くて 16 秒ほど。結果は出力ログの `[TEST] InteractSystem`。
- 見本（`_Samples/`）はありません。
