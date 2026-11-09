# ActivationSystem

部品を「動かす・止める」ための共通の合図（起動 `activated_event`・停止 `deactivated_event`）を決める System です。だれが起こしたかの分かる起動の合図（`activated_by_agent_event`）も持ちます。カウントダウン・画面・付与・デバイスの橋渡しなど、起動を待つ部品はこの合図で動き出し、止まります。ゲームの流れ（GameSequenceSystem）のノードに入る・出るときにも、この合図が配下へ届きます。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `activate_on_begin_component` | 起動したい部品の entity か、その祖先 | シミュレーション開始の次のフレームで、この entity と子孫へ起動の合図を 1 回送る |
| `enable_on_activation_component` | 合図が届く場所（起動したい部品の entity か、その子孫） | 起動の合図で有効に、停止の合図で無効にする（`Invert` なら逆）。切り替えるのは `Targets`（空ならこの entity）に付いた、有効・無効を持つ component（`enableable`：メッシュ・ライト・インタラクト・パーティクルなど） |

例：「ゲームの流れを使わずに、開始と同時にカウントダウンを始め、扉を出す」
```
部屋（activate_on_begin_component）
├ タイマー（countdown_component）
└ 扉（メッシュ + enable_on_activation_component）
```
扉は `ApplyOnBegin` で開始時にいったん無効になり、開始の次のフレームに届く起動の合図で有効（表示）になります。タイマーも同じ合図で数え始めます。

## 設定（@editable）
- `enable_on_activation_component.Targets : []entity = array{}` — 有効・無効を切り替える entity。空なら、この entity に付いている component を切り替える。
- `enable_on_activation_component.Invert : logic = false` — オンなら逆にする（起動の合図で無効、停止の合図で有効）。
- `enable_on_activation_component.ApplyOnBegin : logic = true` — オンなら、シミュレーション開始で「停止しているとき」の状態にする（起動されるまで隠しておく、など）。

`activate_on_begin_component` に設定はありません。

## イベント
- `activated_event`（scene_event、SendDown）: 項目なし。送った entity とその子孫に届く。消費しない。主な送り手：ゲームの流れ（`game_node_entered_event` はこの派生）、`activate_on_begin_component`、`interact_trigger_component`、`volume_activation_component`、`schedule_component`、`player_state_trigger_component`、`device_event_component`、ロードアウトの根（`loadout_instance_component`）、利用者のコード（`SendActivated`）。
- `activated_by_agent_event`（`activated_event` の派生、SendDown）: `Agent : agent`（起こした人）。`activated_event` の派生なので、起動を待つ部品はそのまま動く。消費しない。送り手：だれが起こしたか分かる部品（`interact_trigger_component`（Toggle オフのとき）、`choice_menu_component`、`volume_activation_component`、`player_motion_trigger_component`、`character_action_trigger_component`（持ち主がいるとき）、`device_event_component`（鳴らした人が分かるとき））。人が要る受け手（FNDeviceSystem の `device_trigger_component`・`device_audio_component`・`device_sequence_component` など）は `FindActivatingAgent[]` で読む。
- `deactivated_event`（scene_event、SendDown）: 項目なし。送った entity とその子孫に届く。消費しない。ゲームの流れでは `game_node_exited_event` がこの派生。ほかに `interact_trigger_component`（Toggle）、`volume_activation_component`、`schedule_component`、`player_state_trigger_component`、ロードアウトを外すとき、利用者のコード（`SendDeactivated`）。
- 受けるもの: `enable_on_activation_component` は `activated_event`（派生も）/ `deactivated_event`。消費しない。

## 公開 API
```verse
activated_event<public> := class(scene_event):
deactivated_event<public> := class(scene_event):

activated_by_agent_event<public> := class(activated_event):
    Agent<public>:agent

(InEntity:entity).SendActivated<public>():void                 # InEntity とその子孫へ activated_event を送る
(InEntity:entity).SendDeactivated<public>():void               # InEntity とその子孫へ deactivated_event を送る
(InEntity:entity).SendActivatedBy<public>(Agent:agent):void    # InEntity とその子孫へ activated_by_agent_event を送る
(SceneEvent:scene_event).FindActivatingAgent<public>()<decides><transacts>:agent   # activated_by_agent_event なら Agent。そうでなければ失敗

activate_on_begin_component<public> := class<final_super>(component):

enable_on_activation_component<public> := class<final_super>(component):
    Targets<public>:[]entity
    Invert<public>:logic
    ApplyOnBegin<public>:logic
    Apply<public>(Active:logic):void                # 起動した状態（true）か停止した状態（false）にする。Invert なら有効・無効は逆
    SetEnabled<public>(Enabled:logic):void          # Targets の component を直接切り替える（IsOn は変えない）
    IsOn<public>()<decides><transacts>:void         # 最後に起動の合図を受けた（Apply(true)）なら成功
```

## 前提・注意
- 起動の合図を送る部品は、だれが起こしたかが分かるなら `SendActivatedBy(Agent)` を使います（受け手は `activated_event` として受けられるので、送り分けは要りません）。人が要る受け手は `FindActivatingAgent[]` で読み、失敗したとき（ふつうの `activated_event`）の振る舞いを決めておきます。
- `activate_on_begin_component` は停止の合図を送りません。止めたいときは `SendDeactivated` か、各部品の `Stop` / `Deactivate` を呼びます。
- `activate_on_begin_component` は 1 フレーム待ってから送ります（`TickEvents.PrePhysics.Await()`。同じ木の component がみな `OnBeginSimulation` を終えてから届くように）。
- `enable_on_activation_component` は自分自身は切り替えません。`Targets` の entity は子孫まで見ず、その entity に付いた component だけを切り替えます。
- この System のコードに `⚠ 未検証` の項目と `@experimental` の API はありません。

## 確かめ方
- テスト：`_Test/ActivationSystemTest/` の `activation_system_test_component`。この component を付けた entity を 1 つ置くだけ（プレイヤーは要らない）。`SendActivated` / `SendDeactivated` が子に届くこと、`activate_on_begin_component` が同じフレームでは送らず、開始のあと 1 回だけ起動の合図を送ることを確かめます。1 秒かかりません。結果は出力ログの `[TEST] ActivationSystem`。`activated_by_agent_event` / `SendActivatedBy` / `FindActivatingAgent` と `enable_on_activation_component` はテストしていません。
- 見本：`_Samples/` の `AbilitySample`・`InputSampleExperimentalKit`・`VirtualPointerSampleExperimentalKit`・`WidgetSample` は、`StartOnBegin` をオフにすると起動の合図（`activated_event`）で動き出します。

## ラウンド（fort_round_manager）
- `activate_on_round_component`：Fortnite のラウンドが始まったら `Targets`（空ならこの entity とその子孫）へ `round_started_event`（`activated_event` の派生。`RoundNumber`）、終わったら `round_ended_event`（`deactivated_event` の派生）を送る。`FirstRound` / `LastRound` で送るラウンドを絞れる（0 なら絞らない）。`RoundStartedEvent` / `RoundEndedEvent`（listenable(int)）、`IsInRound[]`、`GetRoundNumber()`。
- 合図で動く部品（カウントダウン・スポナー・widget・メニュー・ボリューム・ロードアウトなど）をこの配下に置くと、ラウンドのあいだだけ動き、ラウンドごとにやり直す（その部品の ActiveOnBegin / StartOnBegin はオフにする）。
- `round_watcher`：コードからラウンドを受け取る補助（フィールドに持ち、`Start(Entity, OnStarted, OnEnded)` / `Stop()`）。`OnStarted<suspends>` はラウンドが終わると止められる。もうラウンドの途中なら `Start` の中ですぐ動く。round manager が取れなければ `Start` は false。
- ⚠ 未検証：ラウンドの切り替えで、Scene Graph の entity と component がそのまま残るか（残る前提で、ラウンドごとのやり直しを合図で行っている）。
