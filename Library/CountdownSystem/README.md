# CountdownSystem

決めた秒数（小数も可）を数え、残り秒数（切り上げた整数）が変わるたびと数え終わりを知らせる System です。ゲームの流れ（GameSequenceSystem）の「〜秒たったら次へ」の条件にも、流れの外のタイマーにも使えます。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `countdown_component` | 起動の合図が届く entity（ゲームの流れなら、ノードの entity かその子孫。`schedule_component` の子孫など）。流れの外でも使える | `DurationSeconds` 秒を数え、残り秒数の変化と数え終わりを子孫へ（`AlsoSendUp` なら祖先へも）知らせる |
| `countdown_finished_condition_component`（ConditionKit） | `game_transition_component` か `condition_all` / `condition_any` の entity の直下。そのうえで `countdown_component` の entity の子孫 | カウントダウンが 0 になったら満たす。起動し直す・数え直すと満たさなくなる |

例：「ノードに入って 10 秒たったら次へ」
```
ノード（game_node_component + countdown_component、DurationSeconds = 10）
└ 次へ（game_transition_component）
  └ 時間切れ（countdown_finished_condition_component）
```
遷移はノードの直下に置く決まりなので、タイマーはノードと同じ entity に付けます（`countdown_component` は子孫へ知らせるので、条件はその子孫になります）。

ノードの外（祖先）に置いた HUD や部品で残り秒数・終わりを受けたいときは、`AlsoSendUp` をオンにします（親から上へも送る）。

## 設定（@editable）
- `countdown_component.DurationSeconds : float = 5.0` — 数える秒数（0.1〜3600 秒。小数可）。今回だけ違う長さにするときは `Restart(?Seconds := option{…})`。
- `countdown_component.StartOnActivated : logic = true` — オンなら起動の合図で最初から数え直し（数えている途中でもやり直す）、停止の合図で止める（ゲームの流れなら、ノードに入ってから出るまで）。オフなら合図を無視する。
- `countdown_component.StartOnBegin : logic = false` — オンならシミュレーション開始と同時に数え始める（ゲームの流れを使わないとき）。
- `countdown_component.AlsoSendUp : logic = false` — オンなら知らせ（`countdown_remaining_changed_event` / `countdown_finished_event`）を、子孫へに加えて親から祖先へ（SendUp）も送る。自分の entity には 1 回だけ届く。

`StartOnActivated` と `StartOnBegin` をどちらもオフにして、コードから `Start` / `Restart` / `Stop` を呼んでもかまいません。`countdown_finished_condition_component` に設定はありません。

## イベント
- `countdown_remaining_changed_event`（scene_event、SendDown。`AlsoSendUp` なら親から SendUp も）: `Countdown : countdown_component`、`RemainingWholeSeconds : int`（切り上げた整数。1 以上）。数え始め・1 秒ごと・`AddSeconds`・`Resume` で、値が変わったときに届く（0 になったときは届かない）。送り手は `countdown_component`、受け手は子孫の `countdown_finished_condition_component` など。消費しない。
- `countdown_finished_event`（scene_event、SendDown。`AlsoSendUp` なら親から SendUp も）: `Countdown : countdown_component`。残りが 0 になったときに届く。`Stop` や停止の合図で止めたときは届かない。消費しない。
- `countdown_component.RemainingChangedEvent : listenable(int)` — 残り秒数（切り上げた整数）が変わるたび（1 秒ごと）、その値で届く。
- `countdown_component.FinishedEvent : listenable(tuple())` — 数え終わったときに届く。
- 受けるもの: `countdown_component` は `activated_event`（最初から数え直す）/ `deactivated_event`（止める）（`StartOnActivated` のとき。消費しない）。`countdown_finished_condition_component` は `activated_event` と `countdown_remaining_changed_event`（満たさない状態に戻す）、`countdown_finished_event`（満たす）。どれも消費しない。

## 公開 API
```verse
countdown_remaining_changed_event<public> := class(scene_event):
    Countdown<public>:countdown_component
    RemainingWholeSeconds<public>:int

countdown_finished_event<public> := class(scene_event):
    Countdown<public>:countdown_component

countdown_component<public> := class<final_super>(component):
    DurationSeconds<public>:float
    StartOnActivated<public>:logic
    StartOnBegin<public>:logic
    AlsoSendUp<public>:logic
    RemainingChangedEvent<public><final>:listenable(int)
    FinishedEvent<public><final>:listenable(tuple())
    Start<public>():void                                    # 数えていなければ DurationSeconds 秒から始める。数えている途中（一時停止中も）なら何もしない
    Restart<public>(?Seconds:?float = false):void           # 最初から数え直す（途中・一時停止中・終わったあとでも）。Seconds で今回だけの長さ
    Stop<public>():void                                     # やめる（FinishedEvent は届かない）。数えていなければ何もしない
    IsRunning<public>()<decides><transacts>:void            # 数えている途中（一時停止中を除く）なら成功
    IsPaused<public>()<decides><transacts>:void             # 数えている途中で一時停止しているなら成功
    Pause<public>():void
    Resume<public>():void
    AddSeconds<public>(DeltaSeconds:float):void             # 残りを増やす（マイナスなら減らす）。0 以下でその場で数え終わる
    GetRemainingSeconds<public>()<transacts>:float          # 残り（小数）。数えていなければ 0.0
    GetRemainingWholeSeconds<public>()<transacts>:int       # 残りを切り上げた整数。数えていなければ 0

# ConditionKit
countdown_finished_condition_component<public> := class<final_super>(condition_component):
```

## 名前の決まり
- 秒の値は、小数（float）なら `…Seconds`、切り上げた整数（int。画面に出す値）なら `…WholeSeconds` と書きます。ScheduleSystem（`schedule_snapshot.GetRemainingSeconds` は小数、`schedule_text_component.GetRemainingWholeSeconds` は整数）とそろえています。

## 前提・注意
- 残りは「終わる時刻 − 今のシミュレーション時刻」で決めます。フレームの数や待ちの積み重ねで数えないので、ずれません。一時停止中は残りが減りません。
- `Start` は数えている途中なら何もしません（GameSequenceSystem の `Start` / `Restart` と同じ分け方）。途中でやり直すのは `Restart` か起動の合図です。同じフレームに `Stop` してから `Restart` しても取りこぼしません。
- `AddSeconds` は数えている途中（一時停止中も含む）だけ効きます。一時停止中に残りが 0 以下になったときは、再開したときに数え終わります。
- `AlsoSendUp` をオンにすると、祖先にある `countdown_finished_condition_component`（ほかのカウントダウン用に置いたもの）にも知らせが届きます。祖先に別の条件があるときはオフのままにします。
- `countdown_finished_condition_component` は ConditionSystem の条件です。置き方は ConditionSystem の決まり（遷移か `condition_all` / `condition_any` の直下）に従います。
- この System のコードに `⚠ 未検証` の項目と `@experimental` の API はありません。

## 確かめ方
- テスト：`_Test/CountdownSystemTest/` の `countdown_system_test_component`。この component を付けた entity を 1 つ置くだけ（`countdown_component` はテストが実行時に作る。プレイヤーは要らない）。`Start` から `FinishedEvent` までの実時間、残り秒数の知らせの回数と値、`Pause` / `Resume`、`AddSeconds`（増やす・残りより多く減らす）、`Stop`、起動・停止の合図での開始と停止と途中のやり直し、`Restart`（途中・秒数を渡す・1 秒未満）、`AlsoSendUp`（親の entity で受ける）を確かめます。約 20 秒かかります。結果は出力ログの `[TEST] CountdownSystem`。
- 見本（`_Samples/`）はありません。

## 移行が要るもの（2026-11-08）
- `countdown_component.Seconds : int` → `DurationSeconds : float`（エディターで置いたものは値を入れ直す）。
- `GetRemainingTimeSeconds():float` → `GetRemainingSeconds():float`、`GetRemainingSeconds():int` → `GetRemainingWholeSeconds():int`（同じ名前で型が変わったので、int として使っていた所はコンパイルエラーになる）。
- `countdown_remaining_changed_event.RemainingSeconds` → `RemainingWholeSeconds`。
- `Start()` は数えている途中なら何もしなくなった（前は最初からやり直していた）。やり直すなら `Restart()`。起動の合図は前と同じく最初からやり直す。
