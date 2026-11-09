# ConditionSystem

「〜なら」を表す条件の基底（`condition_component`）と、条件を組み合わせる `condition_all` / `condition_any`（GroupKit）、届いた scene_event で満たす `event_received_condition_component`（EventKit）の System です。条件は満たしているかを答え、変わったかもしれないときに上へ知らせます。ゲームの流れ（GameSequenceSystem）の遷移、能力の付与（`ability_grant_condition_component`）、スイングの倍率（`swing_modifier_condition_component`）が使います。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `condition_component` の派生 | `game_transition_component` か `condition_all` / `condition_any` の entity の直下（ほかに `ability_grant_condition_component` / `swing_modifier_condition_component` の entity の直下）。直接は置かない（派生を置く） | 満たしているかを答え、変わったかもしれないときに `condition_changed_event` を上へ送り、`ChangedEvent` に届ける |
| `condition_all_component`（GroupKit） | 同上 | 直下の子の条件をすべて満たしたときに満たす（子が無ければ満たす） |
| `condition_any_component`（GroupKit） | 同上 | 直下の子の条件のどれか 1 つを満たしたときに満たす（子が無ければ満たさない） |
| `event_received_condition_component`（EventKit） | 同上。待つ型を `EventType` で選ぶ | 起動してから（起動の合図 `activated_event` を受けてから。合図が来なければ開始から）、`EventType` の scene_event（派生も）がこの entity に届いたら満たす。起動の合図か `Reset` で戻る |

条件の派生はほかの System にあります：`countdown_finished_condition_component`（CountdownSystem）、`player_count_condition_component` / `player_group_count_condition_component`（PlayerSystem / ConditionKit）、`player_state_condition_component`（PlayerSystem / MotionKit）、`interacted_condition_component`（InteractSystem）、`player_in_volume_condition_component`（VolumeSystem）、`all_players_ready_condition_component`（InputSystem / ReadyKit）、`mode_selected_condition_component`（ModeSystem）、`schedule_active_condition_component`（ScheduleSystem）、`character_motor_condition_component`（CharacterSystem）。

例：「2 人以上いて、ボタンが押されたか、だれかが中に入ったら次へ」
```
次へ（game_transition_component）
└ すべて（condition_all_component）
  ├ 2 人以上（player_count_condition_component）
  └ どれか（condition_any_component）
    ├ 押された（interacted_condition_component）
    └ 中にいる（player_in_volume_condition_component）
```
子は直下に 1 つずつ置きます（並び順は関係ない）。

## 設定（@editable）
- `event_received_condition_component.EventType : subtype(scene_event) = no_scene_event` — 待つ scene_event の型（その派生も合う）。既定の `no_scene_event` はどこからも送られないので、選ぶまで満たさない。コードからは `event_received_condition_component{Entity := E, EventType := my_event}` で作る。
- `condition_all_component` / `condition_any_component` に設定はありません。

## イベント
- `condition_changed_event`（scene_event、SendUp）: `Condition : condition_component`（送った条件）。条件の entity から根へ。送り手は `condition_component` の派生（`NotifyChanged`）。受け手は祖先の `game_node_component`（遷移を調べ直す。消費しない）と `condition_all` / `condition_any`（自分以外からのものを受け取って消費し、自分の知らせを送り直す）。
- `condition_component.ChangedEvent : listenable(logic)` — 満たしているかが変わったかもしれないときに、今の結果（満たしていれば true）で届く。外から Signal はできない。`ability_grant_condition_component`・`swing_modifier_condition_component` はこれを購読する。
- 受けるもの: `condition_all_component` / `condition_any_component` は子孫からの `condition_changed_event`。`event_received_condition_component` は、この entity に届く scene_event すべて（`activated_event` で戻し、`EventType` に合えば満たす。消費しない）。

## 公開 API
```verse
condition_changed_event<public> := class(scene_event):
    Condition<public>:condition_component

condition_component<public> := class<abstract><final_super>(component):
    IsSatisfied<public>()<decides><transacts>:void         # 派生が実装する。状態を変えない（副作用を持たない）こと
    ChangedEvent<public><final>:listenable(logic)
    NotifyChanged<protected>():void                        # 派生が、変わったかもしれないときに呼ぶ

(InEntity:entity).AreChildConditionsSatisfied<public>()<decides><transacts>:void    # 直下の子の条件をすべて満たせば成功。子が無ければ成功
(InEntity:entity).IsAnyChildConditionSatisfied<public>()<decides><transacts>:void   # どれか 1 つでも満たせば成功。子が無ければ失敗

# GroupKit
condition_all_component<public> := class<final_super>(condition_component):
condition_any_component<public> := class<final_super>(condition_component):

# EventKit
no_scene_event<public> := class(scene_event):                 # EventType の既定。どこからも送られない
event_received_condition_component<public> := class<final_super>(condition_component):
    EventType<public>:subtype(scene_event)                    # 待つ型（派生も合う）
    Reset<public>():void                                      # 満たさない状態に戻す
    FindReceivedEvent<public>()<decides><transacts>:scene_event   # 満たしたときに受けたもの。まだなら失敗
```

## 前提・注意
- 派生は `IsSatisfied` だけを書き、満たしているかが変わったかもしれないときに `NotifyChanged` を呼びます。`IsSatisfied` は `<transacts>` で何度も呼ばれるので、状態を変えません。
- 見るのは直下の子の条件だけです（孫は見ない）。入れ子にするときは `condition_all` / `condition_any` を挟みます。
- `NotifyChanged` は「変わったかもしれない」の知らせで、実際に変わっていなくても送ってよいです。受け手は `IsSatisfied` を問い直します。
- `event_received_condition_component` が見るのは、この entity に届く scene_event だけです（祖先からの `SendDown`、区画全体への `SendScoped`、世界全体への `SendGlobal`、子孫からの `SendUp`）。ほかの枝で `SendUp` された知らせは届きません。届かない知らせを待つときは、送り手を区画全体へ送る形（`SendScoped`）にするか、条件の派生を書きます。
- `event_received_condition_component` は、起動してから最初に合った 1 つで満たし、2 つ目以降では知らせを送り直しません（`FindReceivedEvent` は最初のもの）。
- 型を `@editable` にするとき、`castable_subtype` は使えない（3604）ので `subtype(scene_event)` にしています。絞り込み（`EventType[SceneEvent]`）は standalone の型チェックと新しい VM の実行で動くことを確かめています。
- ⚠ 未検証（EventReceivedConditionComponent.verse）：`subtype(scene_event)` の `@editable` が UEFN のエディターで型を選べるか（`scene_event` は interface。`subtype(component)` は選べることを確かめ済み）と、型の値での絞り込みが UEFN で動くか。
- `@experimental` の API は使っていません。

## 確かめ方
- テスト：`_Test/ConditionSystemTest/` の `condition_system_test_component`。この component を付けた entity を 1 つ置くだけ（条件の entity はテストが実行時に作る。プレイヤーは要らない）。`condition_all` / `condition_any` の組み合わせ（並び順に関係しないこと）、入れ子（孫の変化が外側の `ChangedEvent` に 1 回ずつ届くこと）、`ChangedEvent` の回数と値、子が無いときの `AreChildConditionsSatisfied` / `IsAnyChildConditionSatisfied`、`event_received_condition_component`（ほかの型では満たさない、合う型・派生で満たす、2 つ目では知らせない、`activated_event` と `Reset` で戻る、既定の `no_scene_event` では満たさない）を確かめます。すぐ終わります。結果は出力ログの `[TEST] ConditionSystem`。同じファイルの `test_condition_component`（`SetSatisfied` で切り替える条件）は、ほかの System のテストからも使います。
- 見本（`_Samples/`）はありません。
