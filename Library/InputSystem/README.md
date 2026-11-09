# InputSystem

プレイヤーの入力を扱う System です。能力や view から入力を待つための関数（InputHelpers）、押されたことを区画全体へ知らせる `player_input_component`（InputKit）、1 人ずつの「準備 OK」を持つ `player_ready_component`（ReadyKit）があります。

依存の向き：InputSystem の直下（InputHelpers）は Library のほかの System に依存しません（ほかの System の能力などが使う土台）。InputKit は PlayerSystem・SceneGraphSystem に、ReadyKit は InputKit・PlayerSystem・SceneGraphSystem・ConditionSystem に依存します。直下は Kit に依存しません。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `player_input_component`（InputKit） | 起動の合図が届く場所（ゲームの流れなら、ノードの entity かその子孫）。1 entity に何個でも | 起動しているあいだ各プレイヤーに `InputMapping` を足し、`InputAction` が押されたら区画全体へ `player_input_triggered_event` を送る |
| `player_input_view_component`（InputKit） | 実行時に `player_input_component` が slot の下に作る（エディターでは置かない） | 1 人分のキー割り当てと、押されたときの知らせ（その人の入力が取れるまで待ってから足す） |
| `player_ready_component`（ReadyKit） | 起動の合図が届く場所。同じ entity に `player_input_component` を 1 つ置く（押す操作はその `InputAction`） | 起動しているあいだ、同じ entity の `player_input_component` が押されるたびに、押した人の「準備 OK」を切り替え、区画全体へ `player_ready_changed_event` を送る。停止すると全員の準備は消える |
| `player_ready_view_component`（ReadyKit） | 実行時に `player_ready_component` が slot の下に作る（エディターでは置かない） | 1 人分の「準備 OK」と `player_ready_tag` の付け外し |
| `all_players_ready_condition_component`（ReadyKit） | `game_transition_component` か `condition_all` / `condition_any` の entity の直下 | 参加者が 1 人以上いて、全員が「準備 OK」なら満たす |

例：「全員が E を押したら次へ」
```
ロビー（game_node_component + player_input_component + player_ready_component）
└ 次へ（game_transition_component）
  └ 全員準備 OK（all_players_ready_condition_component）
```
区画（または世界）のどこかに `player_manager_component`（PlayerSystem）を 1 つ置きます。

## 設定（@editable）
- `player_input_component.ActiveOnBegin : logic = false` — オンならシミュレーション開始から受け付ける。オフなら起動の合図から停止の合図まで。
- `player_input_component.InputMapping : input_mapping = MenuNavigationMapping` — 受け付けているあいだ各プレイヤーに足すキー割り当て（既定はメニュー用：E / Q / C / Z / Esc、ゲームパッドは RB / LB / RT / LT / Back）。
- `player_input_component.InputAction : input_action(logic) = NextTab` — 押されたことを知らせる操作。`InputMapping` に含まれるものを選ぶ（既定は E キー、ゲームパッドは RB）。
- `player_ready_component.ActiveOnBegin : logic = false` — オンならシミュレーション開始から「準備 OK」を受け付ける。オフなら起動の合図から停止の合図まで。

## イベント
- `player_input_triggered_event`（InputKit。scene_event、SendScoped：区画全体。区画が無ければ世界全体）: `Input : player_input_component`、`Agent : agent`、`Action : input_action(logic)`。送り手は `player_input_component`、受け手は押されたことを見る component。同じ component の押下だけを見るなら `Input` で絞るか、`TriggeredEvent` を Subscribe する。消費しない。
- `player_ready_changed_event`（scene_event、SendScoped）: `PlayerReady : player_ready_component`、`Agent : agent`、`Ready : logic`。送り手は `player_ready_component`（の view）、受け手は `all_players_ready_condition_component` など。消費しない。
- listenable（外から Signal はできない）
  - `player_input_component.TriggeredEvent : listenable(agent)` — `InputAction` が押されるたびに、押した人で届く。
  - `player_ready_component.ReadyChangedEvent : listenable(tuple(agent, logic))` — だれかの準備が切り替わるたびに、（その人, 準備 OK か）で届く。
- 受けるもの: `player_input_component` と `player_ready_component` は `activated_event` / `deactivated_event`（起動・停止）。`player_ready_component` は同じ entity の `player_input_component.TriggeredEvent` を Subscribe する（scene event では受けない）。`all_players_ready_condition_component` は `player_ready_changed_event` / `player_added_event` / `player_removed_event`。

## タグ
- `player_ready_tag`（`player_state_tag` の派生、ReadyKit）。その人が「準備 OK」になったときに `player_ready_view_component` が `player_tag_holder` で付け、取り消したとき・受け付けをやめた（view が消えた）ときに外す。タグはその人の agent に付く。
- ほかの System は `Agent.HasPlayerTag[player_ready_tag]` で確かめる。

## 公開 API
```verse
# InputHelpers（InputSystem）
(Agent:agent).FindPlayerInput<public>()<decides><transacts>:player_input        # プレイヤーでない・取れないと失敗
(Agent:agent).AwaitPlayerInput<public>()<suspends>:?player_input                 # 取れるまで 1 フレームずつ待つ。プレイヤーでない・退出で false
(PlayerInput:player_input).AwaitPressed<public>(Action:input_action(logic))<suspends>:void    # BeginDetectEvent を待つ
(PlayerInput:player_input).AwaitReleased<public>(Action:input_action(logic))<suspends>:void   # EndDetectEvent を待つ
(PlayerInput:player_input).HoldInputMapping<public>(Mapping:input_mapping, RemoveOnEnd:logic)<suspends>:void   # race の枝で使う。戻らない

# InputKit
player_input_triggered_event<public> := class(scene_event):
    Input<public>:player_input_component
    Agent<public>:agent
    Action<public>:input_action(logic)

player_input_component<public> := class<final_super>(component):
    ActiveOnBegin<public>:logic
    InputMapping<public>:input_mapping
    InputAction<public>:input_action(logic)
    TriggeredEvent<public><final>:listenable(agent)
    Activate<public>():void                                    # もう受け付けていれば何もしない
    Deactivate<public>():void                                  # 全員から InputMapping を外す
    IsActive<public>()<decides><transacts>:void

player_input_view_component<public> := class<final_super>(component):
    Source<public>:player_input_component
    Player<public>:player

# ReadyKit
player_ready_changed_event<public> := class(scene_event):
    PlayerReady<public>:player_ready_component
    Agent<public>:agent
    Ready<public>:logic

player_ready_tag<public> := class(player_state_tag):

player_ready_component<public> := class<final_super>(component):
    ActiveOnBegin<public>:logic
    ReadyChangedEvent<public><final>:listenable(tuple(agent, logic))
    Activate<public>():void                                    # 全員「準備 OK でない」から始める
    Deactivate<public>():void                                  # 全員の準備を消す（知らせは送らない）
    IsActive<public>()<decides><transacts>:void
    FindInput<public>()<decides><transacts>:player_input_component   # 押されたことを受け取っている同じ entity の入力。無ければ失敗
    IsReady<public>(Agent:agent)<decides><transacts>:void      # 受け付けていない・view が無いと失敗
    SetReady<public>(Agent:agent, Value:logic):void            # 受け付けていない・view が無いと何もしない
    ToggleReady<public>(Agent:agent):void                      # 押されたときと同じ切り替え
    ResetAll<public>():void
    GetReadyCount<public>()<transacts>:int                     # 停止中は 0

player_ready_view_component<public> := class<final_super>(component):
    Source<public>:player_ready_component
    Player<public>:player
    IsReady<public>()<decides><reads>:void
    SetReady<public>(Value:logic):void                         # 変わったときだけ知らせる

all_players_ready_condition_component<public> := class<final_super>(condition_component):
```

## 前提・注意
- `player_input_component`・`player_ready_component`・`all_players_ready_condition_component` は、区画（または世界）に `player_manager_component`（PlayerSystem）が 1 つ要る。`all_players_ready_condition_component` は `player_ready_component` も 1 つ要る（どちらも開始時と知らせを受けたときに探して覚える）。
- 「準備 OK」の数（`GetReadyCount`）と `all_players_ready_condition_component` は、世界に入っている view だけを見る。退出すると slot ごと view が世界から外れ、`player_ready_view_component` は止まるとき（`OnEndSimulation`）に「準備 OK でない」に戻る（知らせは送らない。条件は `player_removed_event` で見直す）。退出した人の view は `player_view_set` が manager の `PlayerRemovedEvent` で一覧から除く。
- `player_ready_component` が押されたことを知るのは、同じ entity の `player_input_component`（の `TriggeredEvent`）から。押す操作はその `InputAction` だけで決まる（ready 側に操作の設定は無い）。同じ entity に `player_input_component` を 2 つ以上置くと、どれを使うか決まらないので、ほかの入力は別の entity に置く。無ければ押しても切り替わらない（`SetReady` / `ToggleReady` だけで動かす）。`player_input_component` は開始時・起動の合図・`Activate` のときに探す（`FindInput` で確かめられる）。
- `player_input_component` は `TriggerActivationEvent` の値が true のときに知らせる。停止すると全員から `InputMapping` を外す。キャラクター操作の割り当てを `InputMapping` に選ぶと、停止で外れて動けなくなる。
- `player_input_view_component` は、その人の入力（`player_input`）が取れるまで 1 フレームずつ待ってから（`AwaitPlayerInput`）`InputMapping` を足して購読する。参加した直後・開始の直後に作られた view でも、取れた時点から受け付ける。
- 同じ `InputMapping` を使う `player_input_component` を 2 つ以上置いてよい。1 つが止まると、その人から `InputMapping` を外したあと、同じ人（同じ slot の下）でまだ動いているほかの `player_input_view_component` の `InputMapping` を足し直す（`input_mapping` は等しいかを比べられないので、同じかどうかは見分けずに全部足し直す）。エンジンが `AddInputMapping` を数えない前提（`HoldInputMapping` の注意と同じ）。⚠ 未検証：エンジンが数えて持つなら足し直した分が残ること、外して同じフレームで足し直したときに押している途中の入力が切れないか。能力の `HoldInputMapping`（`RemoveOnEnd` が true）とは数え合わないので、そちらが外すと切れる。
- `AwaitPressed` / `AwaitReleased` は、`Action` を含む `input_mapping` がその人に足されていないと届かない。`AwaitReleased` を押していないときに呼ぶと、次に押して離すまで戻らない。
- `HoldInputMapping` の `RemoveOnEnd` は、その能力専用の割り当てのときだけ true にする。`RangedWeaponMapping` / `TraversalMapping` など武器や移動にも使う割り当てを外すと、撃てない・動けなくなる。外すときは数えないので、同じ割り当てをほかの機能（別の能力・`player_input_component` など）が使っているときも true にしない。
- 能力の `RunFor` の頭では `FindPlayerInput` ではなく `AwaitPlayerInput` を使う（開始直後や参加直後は入力がまだ取れないことがある。1 回だけ試すと、取れなかった人には能力が動かないまま「付与中」になる）。
- この System のコードは実験的な API を使っていない。関係する見本の `_Samples/InputSampleExperimentalKit/`・`_Samples/VirtualPointerSampleExperimentalKit/` は実験的な API（`InteractMapping`、カメラなど）を使うので、VerseShare で「実験的を含む」をオンにしたプロジェクトにだけ配られる。

## 確かめ方
- テスト：`_Test/InputSystemTest/` の `input_system_test_component`。`player_manager_component` を付けた entity を 1 つと、この component を付けた entity を 1 つ置く（入力と準備の component はテストが実行時に作る）。区画（または世界）にほかの `player_ready_component` を置かない。プレイヤー 1 人で始める（参加を最大 10 秒待つ）。まずコードから `player_ready_component`（`Activate` / `FindInput` / `SetReady` / `ToggleReady` / `IsReady` / `GetReadyCount` / `ResetAll` / `Deactivate`）、`ReadyChangedEvent`、`player_ready_changed_event`、`all_players_ready_condition_component` を確かめる。退出の代わりにその人の slot を manager の下から外し、外れた view の準備 OK が数に残らないこと・準備 OK が戻ること・slot を戻すと数え直すことも確かめる（本物の退出は 2 人以上で人が確かめる）。次にログに「press E」と出たら 10 秒以内に E キー（ゲームパッドは RB）を押す。`TriggeredEvent` と、押して準備 OK が切り替わることを確かめる（押さなければその項目だけ失敗）。長くて 20 秒ほど。結果は出力ログの `[TEST] InputSystem`。
- 見本：`_Samples/InputSampleExperimentalKit/` の `input_sample_component`（標準の入力アクションを `StepSeconds` ごとに 1 つずつ出し、`AwaitPressed` などで押されたかを出す）。`_Samples/VirtualPointerSampleExperimentalKit/`（`TouchMapping` と `PointerSelect` で画面のカーソルを使う）。どちらも「実験的を含む」をオンにしたプロジェクトだけにある。`_Samples/AbilitySample/`（`FindPlayerInput` / `HoldInputMapping` / `AwaitPressed`）・`_Samples/WidgetSample/`（`AwaitPlayerInput` / `HoldInputMapping` / `AwaitPressed`）も使い方の見本になる。

## 移行が要るもの（2026-11-08）
- `player_ready_component.ReadyAction` を消しました。押す操作は同じ entity の `player_input_component.InputAction` だけで決まります。`player_ready_component` と `player_input_component` を別の entity に置いていたなら、同じ entity にまとめます。ToolTip の `ReadyActionToolTip` も消えました。
- `player_ready_view_component` は `player_input_triggered_event` を受けなくなりました（切り替えは `player_ready_component` が `TriggeredEvent` から行う）。
- `player_input_triggered_event` を InputSystem の直下から InputKit へ移しました（直下が Kit に依存しないように）。`using { InputSystem }` だけで使っていたコードは `using { InputSystem.InputKit }` を足します。
- `player_input_triggered_event.Source` → `Input`、`player_ready_changed_event.Source` → `PlayerReady`（送り元の項目名を Library 全体でそろえた。`Ready : logic` とぶつかるので `PlayerReady`）。view の `player_input_view_component.Source` / `player_ready_view_component.Source` は scene_event ではないのでそのまま。
