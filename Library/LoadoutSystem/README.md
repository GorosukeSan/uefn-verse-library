# LoadoutSystem

プレイヤー 1 人分の部品をまとめたプレハブ（ロードアウト）を、人ごとに作ってその人の slot の下に置く System です。中の部品は持ち主（その人）だけに効くので、能力・エネルギー・HUD・付ける物・独自キャラクターなどを、コードを書かずにプレイヤーへまとめて付けられます。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `loadout_component` | entity（区画の中ならどこでも） | 起動したら `Prefab` を人ごとに作り、その人の slot の下に置く。外すときは停止の合図を送ってから消す |
| `loadout_instance_component` | 置かない（`loadout_component` が作ったロードアウトの根に実行時に付ける） | だれのロードアウトか・どの `loadout_component` が作ったかを持ち、作った次のフレームでロードアウトの entity と子孫へ起動の合図を送る |

例：「全員に、歩いて跳べる独自キャラクター（CharacterSystem）を付け、着地で音を鳴らす」
```
ロードアウト（loadout_component、Prefab = 下のプレハブ、ActiveOnBegin = true）

プレハブ
└ 体（character_motor_component + character_walk_component + character_jump_component + character_owner_stasis_component）
  ├ 見た目（メッシュ）
  └ 着地（character_action_trigger_component、Action = Landed）
    └ 音（device_audio_component（FNDeviceSystem））
```
プレハブの中身は人ごとに別の entity になり、それぞれの持ち主だけに効きます。同じプレハブに能力（能力の派生 + `ability_grant_players_component`）や `energy_component`、widget を入れてもかまいません。

## 設定（@editable）
- `loadout_component.Prefab : concrete_subtype(entity) = entity` — 1 人分のロードアウトのプレハブ。
- `loadout_component.ApplyToEveryone : logic = true` — オンなら、起動したら今いる全員と、あとから参加する人に付ける。オフなら `ApplyTo` で決めた人だけ。
- `loadout_component.ActiveOnBegin : logic = false` — オンならシミュレーション開始で起動する。オフなら起動の合図（`activated_event`）か `Activate` から。
- `loadout_component.Group : string = ""` — 入れ替えのグループ。空でなければ、同じ `Group` のほかのロードアウトをその人から外してから付ける（1 人 1 つの職業など）。

## イベント
- `loadout_changed_event`（scene_event、SendScoped）: `Loadout : loadout_component`（送った部品）、`Agent : agent`、`Applied : logic`（true なら付けた、false なら外した）。区画全体（区画が無ければ世界全体）へ。送り手は `loadout_component`。消費しない。
- `loadout_component.AppliedEvent : listenable(tuple(agent, entity))` — 付けたときに（その人, ロードアウトの entity）で届く。
- `loadout_component.RemovedEvent : listenable(agent)` — 外したときに、その人で届く。
- 送るもの：ロードアウトの entity と子孫へ、作った次のフレームに `activated_event`（`loadout_instance_component` から）、外すときに `deactivated_event`（消す前）。
- 受けるもの：`loadout_component` は `activated_event`（`Activate`）と `deactivated_event`（`Deactivate`。全員から外す）。どちらも消費しない。起動の合図がだれが起こしたかの分かるもの（`activated_by_agent_event`）でも、その人に付けることはしません（起動するだけ。付けるのは `ApplyToEveryone` か `ApplyTo`）。

## 持ち主
- ロードアウトは `player_manager_component` の下のその人の slot（`player_slot_component` の entity）の子に作るので、中の部品は `FindOwningPlayer[]` が成功し、持ち主だけに効きます。持ち主に絞る部品：能力の付与（`ability_grant_players_component` / `ability_grant_condition_component`）、widget（`player_widget_component`）、`player_attach_component`、`item_grant_component`、`hud_hide_component`、MotionKit の部品（PlayerSystem）、独自キャラクター（CharacterSystem）、FNDeviceSystem の `device_target_agents.Owner`。
- ロードアウトは `loadout_component` の entity の下には作られません。位置は slot の entity の下になるので、場所が要る部品は自分で移ります（独自キャラクターの `SpawnAtOwner` など）。
- `Entity.FindLoadoutInstance[]` で、部品から自分のロードアウト（`Source`・`Player`）を探せます。
- 同じ人には 1 つの `loadout_component` から 1 つだけ作ります（`ApplyTo` を何度呼んでも 1 つ）。

## 公開 API
```verse
loadout_changed_event<public> := class(scene_event):
    Character<public>:loadout_component
    Agent<public>:agent
    Applied<public>:logic

loadout_component<public> := class<final_super>(component):
    Prefab<public>:concrete_subtype(entity)
    ApplyToEveryone<public>:logic
    ActiveOnBegin<public>:logic
    Group<public>:string
    AppliedEvent<public><final>:listenable(tuple(agent, entity))
    RemovedEvent<public><final>:listenable(agent)
    Activate<public>():void                                    # 付け始める（ApplyToEveryone なら全員と途中参加）。起動中なら何もしない
    Deactivate<public>():void                                  # 全員から外し、付けるのをやめる
    ApplyTo<public>(Agent:agent):logic                         # 起動していなければ起動する。同じ Group のほかは外す。参加していなければ false
    RemoveFrom<public>(Agent:agent):void                       # 停止の合図を送ってから消す
    RemoveFromAll<public>():void
    IsAppliedTo<public>(Agent:agent)<decides><transacts>:void
    FindInstance<public>(Agent:agent)<decides><transacts>:entity
    GetAppliedAgents<public>()<transacts>:[]agent              # 並び順は決まっていない

loadout_instance_component<public> := class<final_super><internal>(component):
    Source<public>:loadout_component
    Player<public>:player

(InEntity:entity).FindLoadoutInstance<public>()<decides><transacts>:loadout_instance_component   # InEntity か祖先。ロードアウトの外なら失敗
```

## 前提・注意
- 区画（または世界）に `player_manager_component` が 1 つ要ります。見つからないと付けられず、出力ログに出ます。
- 起動の合図は作った次のフレームに送ります（同じプレハブの部品がみな `OnBeginSimulation` を終えてから届くように）。ロードアウトの中で起動を待つ部品（`GrantOnBegin` オフの付与、カウントダウン、`enable_on_activation_component` など）はここで動き出します。反応の部品（`character_action_trigger_component` や `player_motion_trigger_component` の `Targets` の先）もこの合図を受けるので、音などは付いた直後に 1 回鳴ることがあります。
- 退出した人のロードアウトは外します。シミュレーションの終わりにも全員から外します。
- `ApplyToEveryone` がオフのときに起動の合図が届くと、起動だけします（だれにも付けません）。メニューやボリュームから人ごとに付けるときは、コードから `ApplyTo` を呼びます。
- この System のコードに `⚠ 未検証` の項目と `@experimental` の API はありません。

## 確かめ方
- テスト：`_Test/LoadoutSystemTest/` の `loadout_system_test_component`。`player_manager_component` を付けた entity を 1 つと、この component を付けた entity を 1 つ置き、プレイヤー 1 人以上で始めます（参加を最大 10 秒待つ）。`ApplyTo` で slot の下にロードアウトができ持ち主がその人になること、`loadout_instance_component` が付くこと、2 回目の `ApplyTo` で増えないこと、同じ `Group` のほかのロードアウトが外れること、`RemoveFrom` で消えることを確かめます。すぐ終わります。結果は出力ログの `[TEST] LoadoutSystem`。
- 見本：`loadout_component` を使う見本は `_Samples/` にありません。`_Samples/Platformer2DSampleExperimentalKit/` は、ロードアウトを使わずにコードで slot の下へ独自キャラクターを作る形です（持ち主の決まり方は同じ）。
