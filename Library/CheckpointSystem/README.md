# CheckpointSystem

下からは通り抜けて上に乗れ、上からは降りられない足場（チェックポイント）を作る System です。だれが乗った・降りたを区画全体へ知らせ、乗っているあいだはその人にタグを付けます。上へ登っていくゲームの中継地点やリスポーン地点に使います。乗ったらエネルギー（EnergySystem）を満たす部品（EnergyKit）もあります。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `checkpoint_component` | 足場の entity（当たり判定のあるメッシュと同じ entity） | 真下から上へ動いている人を上面へ通し、上に立っているかを毎フレーム確かめて、乗った・降りたを知らせる |
| `checkpoint_presence_component`（PresenceKit） | 区画（`game_scope_component` の entity）の中のどこか 1 つ（区画が無ければ世界のどこか） | 区画のすべてのチェックポイントの「乗った・降りた」をまとめ、だれがどこに乗っているか・最後にどれに乗ったかに答える |
| `checkpoint_energy_refill_component`（EnergyKit） | 区画の中の entity。満たすエネルギー（`energy_component`）と同じ entity（能力の entity など）か、エネルギーの無い別の entity | 区画のどれかのチェックポイントにだれかが乗るたびに、エネルギーを満タンにする（この entity か子の `energy_component`、無ければ乗った人とその持ち物の `energy_component`） |
| `checkpoint_factory_component`（SpawnKit） | `spawner_component`（SpawnSystem）と同じ entity | spawner が出すものを、借りた範囲の大きさのチェックポイントにする |

例：手で置くチェックポイントと、まとめ役
```
区画（game_scope_component）
├ プレイヤー（player_manager_component）
├ まとめ（checkpoint_presence_component）
└ 足場（checkpoint_component + 750 × 750 × 250 センチメートルのメッシュ）
```
例：乗ったらホバーのエネルギーを満たす（HoverSystem）
```
区画（game_scope_component）
├ プレイヤー（player_manager_component）
├ 足場（checkpoint_component + メッシュ）…
└ ホバー（hover_ability_component + ability_grant_players_component + energy_component + checkpoint_energy_refill_component）
```
エネルギーをアイテムやプレイヤー（agent）に持たせるときは、区画の中の別の entity に `checkpoint_energy_refill_component` だけを置きます（乗った人と、その持ち物のエネルギーを満たす。アイテムの entity は inventory の中にあり、区画への知らせが届かないため、アイテムには置かない）。
spawner で出すときは、区画に `grid_component`（GridSystem）も置き、spawner の entity に `spawner_component` + `checkpoint_factory_component`（プレイヤーの位置を基準にするなら `players_origin_component` も）を付けます。spawner は、大きさを `FootprintX` / `FootprintY` / `FootprintZ`（例 3 × 3 × 1）、高さを段ごと（`LevelIntervalCells`、例 50）、見た目を範囲いっぱい（`FitToArea`）にすると、段ごとに 1 つの足場になります。

## 設定（@editable）
- `checkpoint_component.WidthCm : float = 750.0` — 足場の前後（Forward）の幅（cm、50〜10000）。メッシュの大きさに合わせる。
- `checkpoint_component.DepthCm : float = 750.0` — 足場の左右（Left）の幅（cm、50〜10000）。
- `checkpoint_component.ThicknessCm : float = 250.0` — 足場の厚さ（cm、10〜2000）。
- `checkpoint_component.ApproachCm : float = 300.0` — 足場の真下のこの距離（cm、50〜1000）以内から上へ動いている人を、上面の上へ通す。
- `checkpoint_factory_component.Prefab : concrete_subtype(entity) = entity` — 見た目にする prefab（当たり判定のあるメッシュを入れる）。既定の entity のままだと見た目の無いチェックポイントになる。

`checkpoint_energy_refill_component` に設定はありません（満たす先は置いた場所で決まる。下の「前提・注意」）。

`checkpoint_factory_component` が作るチェックポイントの `WidthCm`・`DepthCm`・`ThicknessCm` は、spawner が借りた範囲の大きさ（`spawn_area.GetSize()`）です。大きさ・高さの選び方・置き方は `spawner_component` の設定で決めます。

## イベント
- `checkpoint_reached_event`（scene_event、SendScoped。区画の根から SendDown、区画が無ければ世界全体）: `Checkpoint : checkpoint_component`、`Agent : agent`。`checkpoint_component` が、上面に乗ったときに送る（初めてかどうかは問わない）。受け手は `checkpoint_presence_component`、到達を数える component など。消費しない。
- `checkpoint_left_event`（scene_event、SendScoped）: `Checkpoint : checkpoint_component`、`Agent : agent`。上面から降りたとき・退出したとき・チェックポイントが世界から外れたときに送る。消費しない。
- listenable（外から Signal はできない）
  - `checkpoint_component.ReachedEvent : listenable(agent)` / `LeftEvent : listenable(agent)` — そのチェックポイントに乗った・降りた人で届く（scene_event と同じタイミング）。
  - `checkpoint_presence_component.ReachedEvent : listenable(checkpoint_reached_event)` / `LeftEvent : listenable(checkpoint_left_event)` — 区画のどれかのチェックポイントの知らせが、そのまま届く。
  - `checkpoint_energy_refill_component.RefilledEvent : listenable(tuple(agent, energy_component))` — エネルギーを満たしたときに、（乗った人, 満たした energy_component）で届く（もう満タンだったものは届かない）。
- 受けるもの: `checkpoint_presence_component` は `checkpoint_reached_event` / `checkpoint_left_event`。`checkpoint_energy_refill_component` は `checkpoint_reached_event`。

## タグ
- `on_checkpoint_tag`（`player_state_tag` の派生）: `checkpoint_component` が、上に立っているあいだその人（agent）に付ける。降りたとき・退出したとき・止まるとき（`OnEndSimulation`）に外す（付け外しは `player_tag_holder`）。
- ほかの System は `Agent.HasPlayerTag[on_checkpoint_tag]` で確かめます。どのチェックポイントかまで要るときは `checkpoint_presence_component.FindStandingCheckpoint` を使います。

## 公開 API
```verse
checkpoint_reached_event<public> := class(scene_event):
    Checkpoint<public>:checkpoint_component
    Agent<public>:agent

checkpoint_left_event<public> := class(scene_event):
    Checkpoint<public>:checkpoint_component
    Agent<public>:agent

on_checkpoint_tag<public> := class(player_state_tag):

checkpoint_component<public> := class<final_super>(component):
    ReachedEvent<public><final>:listenable(agent)
    LeftEvent<public><final>:listenable(agent)
    WidthCm<public>:float
    DepthCm<public>:float
    ThicknessCm<public>:float
    ApproachCm<public>:float
    IsStanding<public>(Agent:agent)<decides><reads>:void        # 最大 1 フレーム遅れる
    GetStandingAgents<public>()<reads>:[]agent

# PresenceKit
checkpoint_presence_component<public> := class<final_super>(component):
    ReachedEvent<public><final>:listenable(checkpoint_reached_event)
    LeftEvent<public><final>:listenable(checkpoint_left_event)
    IsOnAnyCheckpoint<public>(Agent:agent)<decides><reads>:void
    FindStandingCheckpoint<public>(Agent:agent)<decides><reads>:checkpoint_component   # 重なっていれば、まだ乗っているもののうち最後に乗ったもの
    FindLastReached<public>(Agent:agent)<decides><reads>:checkpoint_component          # 降りた・消えたあとも覚えている
    ForgetLastReached<public>():void                                                   # 全員分忘れる

# EnergyKit
checkpoint_energy_refill_component<public> := class<final_super>(component):
    RefilledEvent<public><final>:listenable(tuple(agent, energy_component))
    TryRefillFor<public>(Agent:agent):logic                     # 乗ったときと同じように満たす。満たしたものがあれば true

# SpawnKit
checkpoint_factory_component<public> := class<final_super>(spawn_factory_component):
    Prefab<public>:concrete_subtype(entity)
    CreateSpawned<override>(Area:spawn_area):entity             # Prefab に checkpoint_component（大きさ = Area.GetSize()）を付けて返す
```

## 前提・注意
- `checkpoint_component` には、区画（`game_scope_component`。無ければ世界）に `player_manager_component` が 1 つ要ります。最初に見つけたものを覚えておき、見つかるまでは 1 秒ごとに探します。
- 毎フレーム、区画の全プレイヤーを見ます。Verse ではコリジョンを人ごとに変えられないので、真下から上へ動いている人を上面の上へ移して、メッシュをすり抜けたように見せています。
- 見るのは同じ区画のチェックポイントでまとめて 1 か所です（内部の `checkpoint_tracker`）。シミュレーション開始時に、同じ区画で先に始まったチェックポイントが使っているものに登録し、そのうち 1 つ（先に始まったもの）の `TickEvents.PrePhysics` で全部をまとめて確かめます。プレイヤーの位置は 1 フレームに 1 人 1 回だけ読み、すべてのチェックポイントと比べます（以前はチェックポイントごとに全員の位置を読んでいたので、数 × 人数ぶんの問い合わせだった。比べる計算は数 × 人数のまま）。まとめ役のチェックポイントが消えたら残りの 1 つが引き継ぎます。区画が入れ子のときは、一番近い区画が同じチェックポイントだけでまとめます。
- 立っているとみなすのは、足場の範囲の上（縁に少しの余裕あり）で、上面から一定の高さ以内にいて、地面に立っている（`IsOnGround`）ときです。
- `WidthCm`・`DepthCm`・`ThicknessCm` はメッシュの大きさに合わせます（合っていないと、見た目と乗れる範囲がずれます）。足場の回転は見ません。
- `checkpoint_energy_refill_component` の満たす先：この entity か子孫に `energy_component` があればそれだけ（同じ entity に能力（`ability_component` の派生）があれば、どれかを付与されている人が乗ったときだけ）。無ければ乗った人（agent）に付いた `energy_component` と、持ち物（アイテム）の `energy_component`（`FindEnergy`）すべて。プレイヤーの slot の下（ロードアウトの中など）に置いたときは持ち主が乗ったときだけ。区画の根など、関係のない `energy_component` を子孫に持つ entity には置きません（そのどれかを満たしてしまう）。乗った知らせは区画の根から下へ届くので、区画の外や inventory の中には置きません。
- `checkpoint_presence_component` は知らせを受けて覚えるだけで、自分では探しません。置く前（シミュレーション開始より前）に乗っていた人は数えません。実行時に出たチェックポイントも数えます。重なったチェックポイントに同時に乗っているときは、人ごとに乗っているものを全部覚えます（どれか 1 つから降りても、残りに乗っている扱いのまま。`FindStandingCheckpoint` はまだ乗っているもののうち最後に乗ったもの）。
- `checkpoint_factory_component` を使うときは、区画に `grid_component`（spawner の前提）と `player_manager_component`（`checkpoint_component` の前提）が 1 つずつ要ります。段ごとに出すとき（`LevelIntervalCells` が 0 より大きいとき）、1 つの段には 1 つだけで、一度出した段は消えても `spawner_component.ForgetUsedLevels` まで出し直しません。

## 確かめ方
- テスト：`_Test/CheckpointSystemTest/` の `checkpoint_system_test_component`。置き方：
  - `player_manager_component` を付けた entity を 1 つ（区画を使うなら、このテストの entity と同じ区画に）
  - このテストの component を、平らな床の近くの entity に付ける（プレイヤーは床の上に立ったまま動かない）

  `checkpoint_factory_component` と `spawner_component` の段の選び方・作ったチェックポイントの大きさを確かめたあと、最初に参加したプレイヤーが床に立つのを待って（10 秒まで）、足元に見た目の無いチェックポイントを作ります。乗った知らせ・`IsStanding`、足場を横へ動かしたときの降りた知らせ、戻したときの乗った知らせ、足場が消えたときの降りた知らせ、`checkpoint_presence_component` のまとめ（乗っているか・最後に乗ったもの・重なった 2 つの後に乗った方から降りても先の方に乗っている扱い）、2 つのチェックポイントをまとめて見ているときに先に始まった方を消しても残りが確かめ続けること、`checkpoint_energy_refill_component`（同じ entity のエネルギー・能力を付与されていない人では満たさない・乗った人のエネルギー・`RefilledEvent`）を確かめます。下から通り抜ける動きは自動では確かめないので、ログの `[HUMAN]` の手順で人が確かめます。数秒で終わります。結果は出力ログの `[TEST] CheckpointSystem`。
- 見本（`_Samples/`）は無い。

## 移行が要るもの（2026-11-08）
| 旧 | 新 |
|---|---|
| `hover_ability_component.RefillOnCheckpoint`（HoverSystem） | EnergyKit の `checkpoint_energy_refill_component` をホバーの entity に置く（HoverSystem の README） |
| `checkpoint_component` がそれぞれ毎フレーム全員を見る | 同じ区画でまとめて 1 か所で見る（公開 API・知らせ・タグは同じ。置き方も変わらない） |
| `checkpoint_reached_event` / `checkpoint_left_event` の項目の並び `Agent`, `Checkpoint` | `Checkpoint`, `Agent`（送り元を先に置く Library 全体の決まりに合わせた。名前付きで作っていれば変更不要） |
