# _Test — Library の動作確認テスト

Library の各 System を、UEFN 上で実際に動かして確かめるための component 置き場。公開 API だけを使って書いているので、使い方の見本も兼ねる。

## 使い方
1. テスト用のレベル（またはテスト用の区画）に、確かめたい System の部品と、`_Test/<System>Test/` のテスト component を置く（置き方は各テスト component の先頭のコメント）。
2. セッションを始める。テストはシミュレーション開始（または起動の合図）から自動で進む。
3. 出力ログを `[TEST]` / `[FAIL]` で検索する。
   - `[PASS] テスト名: 項目` … 期待どおり
   - `[FAIL] テスト名: 項目 (詳細)` … 期待と違う
   - `[TEST] テスト名: n passed, m failed` … そのテストのまとめ

## テストの一覧

置き方と確かめる項目の詳しい説明は、各ファイルの先頭のコメントと、各 System の README の「確かめ方」にあります。結果のログは `[TEST] <System 名>`（例 `[TEST] CountdownSystem`）。

| フォルダ | component | 確かめるもの | プレイヤー・人の操作 |
|---|---|---|---|
| `AbilitySystemTest/` | `ability_system_test_component` | コードからの Grant / Revoke と回数の数え方、イベント、付与の component | 要る |
| `ActivationSystemTest/` | `activation_system_test_component` | `SendActivated` / `SendDeactivated` が子孫に届くこと、`activate_on_begin_component` が開始の次のフレームで 1 回だけ送ること | 要らない |
| `CharacterSystemTest/` | `character_system_test_component`、`character_surface_test_component`（SurfaceKit）、`character_buff_test_component`（変更・BuffKit。プレイヤー不要） | 持ち主のいない体（`character_motor_component`）が重力で落ちて接地すること、`AxisLock`、`SetVelocity`、`TeleportTo`。SurfaceKit の触れた・乗った・離れた、動く面に運ばれること、`GetBox` | 要る（平らな床に立つ） |
| `CheckpointSystemTest/` | `checkpoint_system_test_component` | 乗った・降りた知らせと `IsStanding`、足場が消えたとき、まとめて見ているときの引き継ぎ、EnergyKit の回復（`checkpoint_energy_refill_component`） | 要る（床の上で動かない。下から通り抜ける動きはログの `[HUMAN]` の手順で人が見る） |
| `ConditionSystemTest/` | `condition_system_test_component` | `condition_all` / `condition_any` の組み合わせと入れ子、`ChangedEvent`、`event_received_condition_component` | 要らない |
| `CountdownSystemTest/` | `countdown_system_test_component` | 数え終わりまでの実時間、残り秒数の知らせ、`Pause` / `Resume`、`AddSeconds`、`Stop`、起動の合図での開始とやり直し、`Restart`、`AlsoSendUp` | 要らない |
| `EnergySystemTest/` | `energy_system_test_component` | `energy_component` の増減と知らせ（`Spend[]`・`SetAmount`・`StartFull`）、`FindEnergy` / `FindEnergyFor`、`energy_restore_ability_component` | 要る（最後に射撃のボタンを押す） |
| `GameSequenceSystemTest/` | `game_sequence_system_test_component` | 最初のノード、遷移、終わり、`Restart`、`JumpTo`、`Stop`、出た理由、`StartOnActivate` の入れ子の流れ | 要らない |
| `GravitySystemTest/` | `gravity_system_test_component` | `gravity_well_component` が引くこと、`gravity_point_ability_component` の付与と置く・消す・時間切れ | 要る（頭の上 3 m を空ける。射撃のボタンを押す） |
| `GridSystemTest/` | `grid_system_test_component` | `grid_box` の計算、位置とマスの変換、借りる・返す、GridPath の道 | 要らない |
| `HoverSystemTest/` | `hover_system_test_component` | `hover_ability_component` の付与・剥奪、エネルギーの消費、ホバーのイベント | 要る（空中でジャンプを押し続ける） |
| `InputSystemTest/` | `input_system_test_component` | `player_ready_component` の操作（`FindInput`・`ToggleReady` も）、`ReadyChangedEvent`・`player_ready_changed_event`・`all_players_ready_condition_component`、押して準備 OK が切り替わること | 要る（E キーを押す） |
| `InteractSystemTest/` | `interact_system_test_component` | `interact_gate_component` の開け閉め、押したときの知らせ、`interacted_condition_component` | 要る（ボタンを押す） |
| `ItemSystemTest/` | `item_system_test_component` | プレイヤーの inventory の探し方、入力の取り出し など | 要る |
| `JetpackSystemTest/` | `jetpack_system_test_component` | `jetpack_ability_component` の付与・剥奪、ゲージ、チャージして飛ぶときのエネルギー | 要る（空中でジャンプを押し続ける） |
| `LoadoutSystemTest/` | `loadout_system_test_component` | `ApplyTo` で slot の下にロードアウトができること、2 回目で増えないこと、同じ `Group` の入れ替え、`RemoveFrom` | 要る |
| `MCPSystemTest/` | `mcp_system_test_component`（受け口の見本 `mcp_test_echo_component`） | JSON の小道具（逃がし・長い文字列・数の読み取り・範囲の確認）、`ExecuteJson` での振り分け（Core・宛先・インスタンス・ツールの有無・省略できない引数・並びの引数・data の確かめ・batch・help・describe）、タグの名前の表、`mcp_role_tags`、`ClaimPosition` | 要らない |
| `ModeSystemTest/` | `mode_system_test_component` | 候補の並び、受け付け、`Select` の決め方、`Clear`、選んだ知らせ、投票 | 要らない |
| `MovementSystemTest/` | `movement_system_test_component` | 位置の取り出し、`LiftBy`、視線の向きと位置 | 要る（頭の上 3 m を空ける） |
| `MoverSystemTest/` | `mover_system_test_component`、`mover_spline_test_component`（曲線の道のり） | 道のりの回り方、目印の `Order`、着くまでの時間、`Pause` / `Play`、道のりの `Reset`、`Restart`（開始の位置へ戻る・今の位置から）、`AlsoSendUp`。曲線の長さ・長さの表・輪の継ぎ目・PingPong の折り返し・一定の速さ・`FaceTravelDirection` | 要らない |
| `PickupSystemTest/` | `pickup_system_test_component` | 効果の寿命（次のフレームの起動の合図・持ち主・`pickup_effect_tag`・時間で消える・Instant）、重ねがけ（Extend / Stack と MaxStacks / Replace）、`EndPickupEffectsFor`、オーブの拾う・戻る・`RequireGroupMember`、StageKit の合図と重なりの数え方 | 要る（いるだけ） |
| `PlayerSystemTest/` | `player_system_test_component` | slot、`player_count_condition_component`、`player_view_set`、`SubscribePlayers`、プレイヤーのタグ、組と `player_group_count_condition_component` | 要る |
| `SceneGraphSystemTest/` | `scene_graph_system_test_component` | 区画（`game_scope_component`）の中・世界から探すこと、直下の子だけを見ること、一番近い祖先（`FindNearestAncestorComponent`）、`ResolveScopedComponent` | 要らない |
| `ScheduleSystemTest/` | `schedule_system_test_component` | 時刻の計算、時計とデバッグの時刻移動、状態の変化の知らせ、子への合図 | 要らない |
| `SpawnSystemTest/` | `spawn_system_test_component` | `spawner_component` が `Count` 個を出して保つこと、帯の中にあること、グリッドの借用、出した・消えた知らせ、`spawn_prefab_component`（出す場所の順・起動の合図・`MaxCount`・`TrySpawnAt`・`Despawn` / `DespawnAll`）、関数の `SpawnPrefab` | 要らない |
| `SwingSystemTest/` | `swing_system_test_component` | 倍率の重ね方、コードからの `Grant` / `Revoke`、倍率の登録、寿命の的・リフトの的、状態のタグ（`Agent.IsSwinging[]`・`Agent.GetSwingState()`・派生のタグ）、人の操作でのスイング | 要る（人の操作は `RunHumanTests` のとき） |
| `VolumeSystemTest/` | `volume_system_test_component` | 入った・出た（`PlayerEnteredEvent`・`IsInside`・`in_volume_tag`）と合図 | 要る（地面に立つ） |
| `WidgetSystemTest/` | `widget_system_test_component` | 起動で全員に出ること、`SendToWidgets`、`Audience = Chosen` の `ShowFor` / `HideFor`、メニューの 1 人 1 枚、HudKit / MenuKit | 要る |

FNDeviceSystem のテストはありません（デバイスはレベルに置いたものを選ぶので、テストが実行時に作れない）。共通の数え方は `TestLog.verse`（`test_log`）。

## 書き方（テストを足すとき）
- 1 ファイル 1 System。`_Test/<System>Test/<System>Test.verse` に `<system>_test_component` を置く（フォルダを `_Test/<System>/` にすると、モジュール名が本体の System とぶつかって `using` が曖昧になる）。
- 変数名に `Log` を使わない（Verse の組み込みの `Log` とぶつかる）。`Results := test_log{Name := "..."}` とする。
- `<suspends>` の呼び出し（`Task.Await()` など）を `if (...)` の条件の中に書かない（UEFN では 3512。先に `Got := Task.Await()` と受けてから `if (Got?)`）。`<suspends>` と `<decides>` は同じ関数に付けられない。
- 結果は `test_log`（`_Test/TestLog.verse`）で数える。「〜秒以内に知らせが来る」は `AwaitWithin(Event, 秒)`。
- 公開 API（`<public>`）だけを使う。内部（`<internal>`）を使わないと確かめられないなら、それは公開 API が足りないというサインなので、Library 側に足す。
- テストの component は Library の利用者のレベルには置かない（`_Test` は配布物に含めるが、使うのは確認するときだけ）。
