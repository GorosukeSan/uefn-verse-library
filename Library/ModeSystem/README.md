# ModeSystem

ゲームのモード（遊び方の種類）の候補を置き、そのうち 1 つを選ぶ System です。選ばれたモードは区画全体へ知らせ、ゲームの流れ（GameSequenceSystem）の遷移の条件にも使えます。多数決で決めるときは VoteKit を足します。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `mode_select_component` | 区画（または世界）に 1 つ。起動の合図が届く場所（ゲームの流れなら、ノードの entity かその子孫） | 子のモードを持ち、受け付けているあいだに `TrySelect` で決まったモードを覚え、区画全体へ知らせる |
| `game_mode_component` | `mode_select_component` の entity の直下に、モードの数だけ 1 つずつ | モードを 1 つ表す（`Title` は画面に出す名前、`Order` は候補の順番） |
| `mode_vote_component`（VoteKit） | `mode_select_component` と同じ entity | 参加者の投票を集め、多数決で `mode_select_component` にモードを決めさせる |
| `mode_selected_condition_component`（ConditionKit） | `game_transition_component` か `condition_all` / `condition_any` の entity の直下 | `Mode` の entity のモードが選ばれていたら満たす |

例：「投票でモードを選び、選ばれたモードのノードへ進む」
```
流れ（game_sequence_component）
├ 投票（game_node_component）
│ ├ モード選び（mode_select_component + mode_vote_component）
│ │ ├ 鬼ごっこ（game_mode_component、Order 0）
│ │ └ 宝さがし（game_mode_component、Order 1）
│ ├ 鬼ごっこへ（game_transition_component、Target = 鬼ごっこのノード）
│ │ └ mode_selected_condition_component（Mode = 鬼ごっこ）
│ └ 宝さがしへ（game_transition_component、Target = 宝さがしのノード）
│   └ mode_selected_condition_component（Mode = 宝さがし）
├ 鬼ごっこのノード（game_node_component）
└ 宝さがしのノード（game_node_component）
```
この形ではノードから出ると停止の合図で受け付けが終わり、選びも消えます。次のノードでも選んだモードを使うなら、`mode_select_component` をノードの外に置き、`ActiveOnBegin` かコードの `Activate` / `Deactivate` で受け付ける期間を決めます。投票のボタンや画面は、`TryVote` を呼ぶ部品を利用者が用意します。

## 設定（@editable）
- `game_mode_component.Title : string = "Mode"` — 画面に出すモードの名前。
- `game_mode_component.Order : int = 0` — 候補の順番（0〜1000。小さいほど先）。投票が同数のときは小さいほうに決まる。
- `mode_select_component.ActiveOnBegin : logic = false` — オンならシミュレーション開始から受け付ける。オフなら起動の合図から。
- `mode_select_component.AllowReselect : logic = false` — オンなら決まったあとも `TrySelect` で選び直せる。オフなら最初に決まったモードのまま（取り消すまで次の `TrySelect` は効かない）。
- `mode_selected_condition_component.Mode : ?entity = false` — このモード（`game_mode_component` を付けた entity）が選ばれていたら満たす。空なら満たさない。
- `mode_vote_component.MajorityEnds : logic = false` — オンなら過半数が同じモードに入れた時点で決める。オフなら全員が投票してから。

## イベント
- `mode_changed_event`（scene_event、SendScoped：区画全体。区画が無ければ世界全体）: `Selector : mode_select_component`、`Mode : ?game_mode_component`（取り消されたときは false）。`mode_select_component` が、モードが決まった・変わった・取り消されたときに送る。受け手は `mode_selected_condition_component`・モードを出す画面など。消費しない。
- `mode_vote_changed_event`（scene_event、SendScoped）: `Vote : mode_vote_component`、`Agent : ?agent`（全員の票が消えたときは false）、`Mode : ?game_mode_component`（取り消したときは false）。`mode_vote_component` が、だれかの投票が変わったとき・全員の票が消えたときに送る。受け手は票数を出す画面など。消費しない。
- listenable（外から Signal はできない）
  - `mode_select_component.SelectedEvent : listenable(?game_mode_component)` — 決まった・変わったとき（`option{Mode}`）と、選びが消えたとき（false）。
  - `mode_vote_component.VoteChangedEvent : listenable(tuple(agent, ?game_mode_component))` — だれかが投票・取り消しをするたびに（その人, 今投票しているモード。取り消しなら false）。
  - `mode_vote_component.VotesClearedEvent : listenable(tuple())` — 全員の票がまとめて消えたとき（このとき `VoteChangedEvent` は届かない）。
- 受けるもの: `mode_select_component` は `activated_event`（受け付けを始める）と `deactivated_event`（受け付けをやめ、選びを消す）。`mode_selected_condition_component` は `mode_changed_event`。`mode_vote_component` は scene_event を受けず、同じ entity の `SelectedEvent` と `player_manager_component.PlayerRemovedEvent` を購読する。

## 公開 API
```verse
game_mode_component<public> := class<final_super>(component):
    Title<public>:string
    Order<public>:int

mode_changed_event<public> := class(scene_event):
    Selector<public>:mode_select_component
    Mode<public>:?game_mode_component

mode_select_component<public> := class<final_super>(component):
    ActiveOnBegin<public>:logic
    AllowReselect<public>:logic
    var<private> Selected<public>:?game_mode_component = false
    SelectedEvent<public><final>:listenable(?game_mode_component)
    Activate<public>():void                                     # 受け付けを始める
    Deactivate<public>():void                                   # 受け付けをやめ、選びを消す
    IsActive<public>()<decides><transacts>:void
    FindSelected<public>()<decides><transacts>:game_mode_component
    IsSelected<public>(Mode:game_mode_component)<decides><transacts>:void
    GetModes<public>()<transacts>:[]game_mode_component         # 直下の子を Order の小さい順（孫は見ない）
    TrySelect<public>(Mode:game_mode_component):logic           # 効いたら true
    Clear<public>():void                                        # 選びを取り消す

# ConditionKit
mode_selected_condition_component<public> := class<final_super>(condition_component):
    Mode<public>:?entity

# VoteKit
mode_vote_changed_event<public> := class(scene_event):
    Vote<public>:mode_vote_component
    Agent<public>:?agent
    Mode<public>:?game_mode_component

mode_vote_component<public> := class<final_super>(component):
    MajorityEnds<public>:logic
    VoteChangedEvent<public><final>:listenable(tuple(agent, ?game_mode_component))
    VotesClearedEvent<public><final>:listenable(tuple())
    TryVote<public>(Agent:agent, Mode:game_mode_component):logic   # 効いたら true。入れ直しもできる
    Unvote<public>(Agent:agent):void                               # 投票していなければ何もしない
    GetVoteCount<public>(Mode:game_mode_component)<transacts>:int  # 退出した人の票は数えない
    FindVote<public>(Agent:agent)<decides><transacts>:game_mode_component
```

## 前提・注意
- `mode_select_component` は区画（または世界）に 1 つです。`mode_selected_condition_component` や画面は `FindScopedComponent` で探します（条件は開始時と知らせを受けたときに探し、見つけたら覚えておきます）。
- `TrySelect` は、受け付けていない・もう決まっていて `AllowReselect` がオフ・もう同じモードに決まっているときは何もせず false を返します。`TrySelect` に渡すモードが自分の子かどうかは確かめません。
- 受け付けをやめる（停止の合図・`Deactivate`・シミュレーションの終わり）と、選びは消え、決まっていれば `mode_changed_event{Mode := false}` を送ります。
- `mode_vote_component` には区画（または世界）に `player_manager_component` が 1 つ要ります（開始時に探して覚える）。区画の参加者が全員投票したら（`MajorityEnds` なら過半数が同じモードに入れた時点で）、票の一番多いモードを `TrySelect` します。同数なら `Order` の小さいモードです。決まったあとは票を受け付けません。受け付けが終わるか `Clear` されると票は消えます。退出した人の票は取り消され、残りの人で決まるかをもう一度調べます。
- `TryVote` は、同じ entity に `mode_select_component` が無い・受け付けていない・もう決まっている・`Mode` がその直下のモードでないときは false を返します。
- 実験的な API は使っていません。

## 確かめ方
- テスト：`_Test/ModeSystemTest/` の `mode_system_test_component`。この component を付けた entity を 1 つ置きます（`mode_select_component` と `mode_vote_component` はテストが実行時に作る）。区画（または世界）にほかの `mode_select_component` を置かないでください。投票のテストには `player_manager_component` とプレイヤー 1 人が要ります（いなければ投票のテストは飛ばし、票が 0 であることだけを見る）。`Order` による候補の並び、受け付け（`Activate` / `Deactivate`）、`TrySelect` の決め方（`AllowReselect` がオフなら最初のまま）、`Clear`、`SelectedEvent` と `mode_changed_event`、`mode_selected_condition_component`、投票（全員が投票したら決まる、受け付けの終わりで票が消える）を確かめます。開始の次のフレームで終わります。結果は出力ログの `[TEST] ModeSystem`。
- 見本（`_Samples/`）はありません。
