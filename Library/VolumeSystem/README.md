# VolumeSystem

箱か円柱の範囲（ボリューム）に、プレイヤーが入った・出たを調べて知らせる System です。`player_volume_component` は知らせるだけで、中で何をするか（条件・起動・画面表示）は同じ entity か祖先に置く別の component が決めます。中にいる人には `in_volume_tag` を付けます。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `player_volume_component` | 範囲の基準にする entity（底面の真ん中がこの entity の位置。見た目が要らなければメッシュは無くてよい） | 起動しているあいだ `PollIntervalSeconds` 秒ごとに出入りを調べ、変わったときだけ `player_volume_entered_event` / `player_volume_exited_event` を上へ送る |
| `player_in_volume_condition_component`（ConditionKit） | `game_transition_component` か `condition_all` / `condition_any` の entity の直下。ボリュームはその子孫に置くか `Volume` で選ぶ | 中に `MinPlayers` 人以上いれば満たす（複数のボリュームは合計） |
| `volume_activation_component`（ActivationKit） | `player_volume_component` と同じ entity か、その祖先 | 最初の 1 人が入ったら起動の合図、最後の 1 人が出たら停止の合図を `Targets`（空なら子の entity）へ送る |
| `widget_show_in_volume_component`（WidgetKit） | `player_volume_component` と同じ entity か、その祖先。同じ entity に `player_widget_component` の派生（`Audience = Chosen`） | 中にいるあいだ、同じ entity の widget（すべて）をその人に出し、出たら消す |

例：「だれかがゴールに入ったら次へ」と「人がいるあいだだけ動く仕掛け」
```
ノード（game_node_component）
└ 次へ（game_transition_component）
  └ ゴールに 1 人以上（player_in_volume_condition_component）
    └ ゴール（player_volume_component）

部屋（player_volume_component + volume_activation_component）
└ 仕掛け（起動の合図で動く component）
```

## 設定（@editable）
- `player_volume_component.Shape : player_volume_shape = player_volume_shape.Box` — 範囲の形。`Box` は幅 × 奥行き × 高さの箱、`Cylinder` は直径が幅の縦の円柱。
- `player_volume_component.WidthCm : float = 100.0` — 範囲の幅（前後、cm。1 以上）。entity の大きさ（Scale）を掛ける。円柱では直径。
- `player_volume_component.DepthCm : float = 100.0` — 範囲の奥行き（左右、cm。1 以上）。Scale を掛ける。円柱では使わない。
- `player_volume_component.HeightCm : float = 100.0` — 範囲の高さ（cm。1 以上）。底面が entity の位置。Scale を掛ける。
- `player_volume_component.HeightMarginCm : float = 100.0` — 範囲の上下に足す余裕（cm、0〜2000）。キャラクターの位置は体の真ん中なので、薄い床のような範囲では 300 くらいにする。
- `player_volume_component.PollIntervalSeconds : float = 0.25` — 出入りを調べる間隔（秒、0.05〜10）。短いほど早く気付くが重くなる。
- `player_volume_component.ActiveOnBegin : logic = true` — オンならシミュレーション開始から調べる。オフなら起動の合図から。
- `player_in_volume_condition_component.MinPlayers : int = 1` — この人数以上が中にいれば満たす（1〜100）。
- `player_in_volume_condition_component.Volume : ?entity = false` — 見張るボリューム（`player_volume_component` を付けた entity）。空なら、この entity か子孫のボリュームから上へ届いた知らせを数える。
- `volume_activation_component.Targets : []entity = array{}` — 合図を送る entity（その entity と子孫に届く）。空ならこの entity の子の entity へ送る。どちらの場合も、`player_volume_component` の付いた entity には送らない。

## イベント
- `player_volume_entered_event`（scene_event、SendUp）: `Volume : player_volume_component`、`Agent : agent`。ボリュームの entity から根へ。受け手は同じ entity と祖先の component（Kit、利用者の component）。消費しない。受け手は `Volume` でどのボリュームの知らせかを見分ける（自分の entity のボリュームだけなら `Entered.Volume.Entity = Entity`）。
- `player_volume_exited_event`（scene_event、SendUp）: 項目・方向・受け手は entered と同じ。出た・キャラクターがいなくなった・退出した・ボリュームが止まったときに送る。
- listenable（外から Signal はできない）
  - `player_volume_component.PlayerEnteredEvent : listenable(agent)` — だれかが入るたびに、その人で届く。
  - `player_volume_component.PlayerExitedEvent : listenable(agent)` — だれかが出るたびに、その人で届く（止まるときは中にいた人ぶんも届く）。
- 送るもの: `volume_activation_component` は最初の 1 人が入ったとき `SendActivatedBy(その人)`（`activated_by_agent_event`）、最後の 1 人が出たとき `deactivated_event`。
- 受けるもの: `player_volume_component` は `activated_event`（調べ始める）/ `deactivated_event`（止める）。Kit の 3 つは entered / exited の知らせ。

## タグ
- `in_volume_tag`（`player_state_tag` の派生）: `player_volume_component` が、中にいるあいだその人（agent）に付ける。出たとき・ボリュームが止まったときに外す。どのボリュームかは区別しない（付け外しは `player_tag_holder` なので、ほかのボリュームが付けた分は残る）。
- ほかの System は `Agent.HasPlayerTag[in_volume_tag]` で確かめます。どのボリュームかまで要るときは `player_volume_component.IsInside[Agent]` を使います。

## 公開 API
```verse
player_volume_shape<public> := enum:
    Box
    Cylinder

player_volume_entered_event<public> := class(scene_event):
    Volume<public>:player_volume_component
    Agent<public>:agent

player_volume_exited_event<public> := class(scene_event):
    Volume<public>:player_volume_component
    Agent<public>:agent

player_volume_component<public> := class<final_super>(component):
    Shape<public>:player_volume_shape
    WidthCm<public>:float
    DepthCm<public>:float
    HeightCm<public>:float
    HeightMarginCm<public>:float
    PollIntervalSeconds<public>:float
    ActiveOnBegin<public>:logic
    PlayerEnteredEvent<public><final>:listenable(agent)
    PlayerExitedEvent<public><final>:listenable(agent)
    Activate<public>():void                                 # もう調べていれば何もしない
    Deactivate<public>():void                               # 中にいた人ぶんの「出た」を送って空にする
    IsActive<public>()<decides><transacts>:void
    GetAgentsInside<public>()<transacts>:[]agent            # 並び順は決まっていない
    GetInsideCount<public>()<transacts>:int
    IsInside<public>(Agent:agent)<decides><transacts>:void
    AwaitLeft<public>(Agent:agent)<suspends>:void           # 今いなければすぐ戻る
    Contains<public>(Position:vector3)<decides><transacts>:void   # ワールドの位置（cm）が今の範囲の中なら成功

in_volume_tag<public> := class(player_state_tag):

# ConditionKit
player_in_volume_condition_component<public> := class<final_super>(condition_component):
    MinPlayers<public>:int
    Volume<public>:?entity

# ActivationKit
volume_activation_component<public> := class<final_super>(component):
    Targets<public>:[]entity
    IsOccupied<public>()<decides><transacts>:void           # 今だれかが中にいれば成功

# WidgetKit
widget_show_in_volume_component<public> := class<final_super>(component):
```

## 前提・注意
- 区画（または世界）に `player_manager_component`（PlayerSystem）が 1 つ要る（見つけたら覚えておく）。
- 出入りの調べ方：(1) この entity のメッシュに重なっている entity を `FindOverlapHits` で調べ、`possessable_component` の Agent で人を出す。(2) そこで見つからなかった人は、キャラクターの位置を範囲と比べる（位置での判定は実機で確認済み、とコードに記録がある）。どちらかで見つかれば中にいる。
- ⚠ 未検証（`PlayerVolumeComponent.verse`）：プレイヤーのキャラクターの entity が重なりの結果に入り、`possessable_component` から agent が取れるか。取れなくても位置での判定で見つかる。
- 範囲は entity の大きさ（Scale）を掛けるが、回転は見ない。
- `volume_activation_component` が数えるのは、この entity か子孫のボリュームから上へ届いた知らせ（複数あれば合計の人数）。ボリュームの entity に停止の合図を送らないのは、ボリュームが止まって出入りを調べなくなるため。
- `widget_show_in_volume_component` で `Mode = Menu` の widget を出したとき、閉じるボタンで閉じても、ボリュームにいるあいだは出し直さない（入り直すとまた出る）。
- `widget_show_in_volume_component` は WidgetSystem を使う。

## 確かめ方
- テスト：`_Test/VolumeSystemTest/` の `volume_system_test_component`。`player_manager_component` を付けた entity を 1 つと、この component を付けた entity を 1 つ置き、プレイヤー 1 人で始める（地面に立っていること）。プレイヤーの位置にボリューム（600 × 600 × 600 cm）を作り、`Contains`、「入った」（`PlayerEnteredEvent`・`IsInside`・`GetInsideCount`・`in_volume_tag`）、`player_in_volume_condition_component` が満たされること、`volume_activation_component` が子へ起動の合図を送ることを確かめます。そのあとボリュームを遠くへ動かして「出た」（`PlayerExitedEvent`・タグが外れる・条件が満たされなくなる・停止の合図・ボリュームは止まらない）と、`Deactivate` を確かめます。数秒で終わります。結果は出力ログの `[TEST] VolumeSystem`。
- 見本（`_Samples/`）は無い。
