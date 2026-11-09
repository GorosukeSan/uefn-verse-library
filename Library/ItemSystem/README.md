# ItemSystem

Fortnite のアイテム（`item_component` を付けた entity）を、ライブラリの部品とつなぐ System です。だれがアイテムを持っているか（持ち手）の見張り、プレイヤーの inventory の探し方、アイテムの配布・1 人 1 つまで・装備のロックを受け持ちます。アイテムで能力を付ける（AbilitySystem の `ability_grant_item_component`）・持ち手にだけ画面を出す（WidgetSystem の `widget_show_item_holder_component`）ときの土台になります。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `item_holder_component` | アイテムの entity（`item_component` と同じ entity） | 持ち手（`Rule` で決める人）が付いた・外れたを知らせる。装備や inventory が変わるたびに調べ直す |
| `item_holder_friend_component` | `item_holder_component` を付けたアイテムの entity の直下（見た目の無い entity。種類ごとに 1 つ） | 持ち主がこの種類のアイテムを装備しているあいだも、親のアイテムの持ち手とみなす（親の `Rule` が `Equipped` のとき） |
| `item_grant_component`（GrantKit） | 起動の合図が届く場所（ゲームの流れなら、ノードの entity かその子孫） | 起動したとき、子のアイテムを全プレイヤーに配る（持ち主のいる場所なら持ち主にだけ）。`RevokeOnDeactivate` なら停止の合図で回収する |
| `item_grant_entry_component`（GrantKit） | `item_grant_component` の entity の直下（1 種類ずつ） | 配るアイテム 1 種類と個数 |
| `exclusive_item_component`（ExclusiveKit） | アイテムの entity（`item_component` と同じ entity） | 同じ種類のアイテムを 1 人 1 つまでにする |
| `item_equip_lock_component`（RuleKit） | アイテムの entity（`item_component` と同じ entity） | ロックしているあいだ、装備を外させない |

例：「ノードに入ったら全員にジェットパックを 1 つ配り、出たら回収する」
```
ノード（game_node_component）
└ 配る（item_grant_component、RevokeOnDeactivate オン）
  └ ジェットパック（item_grant_entry_component、Item = ジェットパックのアイテムの prefab）
```
アイテムの prefab の側には `item_component` + `item_holder_component`（`Equipped`）+ `exclusive_item_component` + `item_equip_lock_component` と、能力（`jetpack_ability_component` など）+ `ability_grant_item_component` を付けます。

## 設定（@editable）
- `item_holder_component.Rule : item_holder_rule = item_holder_rule.Equipped` — だれを持ち手とみなすか。`Owned` は手持ちにあるあいだ（ほかのアイテムを装備していても）、`Equipped` は装備しているあいだ。
- `item_holder_friend_component.ItemType : castable_concrete_subtype(entity) = entity` — 一緒に数えるアイテムの prefab の型。既定の entity のままだと、どのアイテムでも数えるので必ず選ぶ。
- `item_grant_component.PickMode : item_grant_pick_mode = item_grant_pick_mode.All` — `All` は子のアイテムをすべて、`Random` は `RandomCount` 個を配る人ごとに選び直して配る。
- `item_grant_component.RandomCount : int = 1` — `Random` のときに配る数（1〜100）。子の数より多ければ全部配る。
- `item_grant_component.Destination : item_grant_destination = item_grant_destination.Root` — `Root` はプレイヤーの根の inventory（`FindRootInventory`。種類に合った場所へ振り分け）、`WeaponHotbar` は武器のホットバー（`FindWeaponHotbar`。手に持てる場所）。
- `item_grant_component.RevokeOnDeactivate : logic = false` — オンなら停止の合図で配った物を回収する（回収できるよう、既にあるスタックとまとめずに入れる）。
- `item_grant_entry_component.Item : concrete_subtype(entity) = entity` — 配るアイテムの prefab。既定の entity のままだと何も配らない。
- `item_grant_entry_component.Count : int = 1` — 配る個数（1〜100）。同じものはまとめられることがある。
- `exclusive_item_component.ItemType : castable_concrete_subtype(entity) = entity` — 1 人 1 つまでにするアイテムの prefab の型。ふつうはこのアイテム自身の prefab。既定の entity のままだと、どのアイテムを持っていても入らなくなる。

## イベント
この System は scene_event を送りません。
- listenable（外から Signal はできない）
  - `item_holder_component.HolderAddedEvent : listenable(agent)` — 持ち手が付いたとき、その人で届く。
  - `item_holder_component.HolderRemovedEvent : listenable(agent)` — 持ち手が外れたとき（手放した・消えた・シミュレーションの終わりも）、外れた人で届く。
  - `item_equip_lock_component.ChangedEvent : listenable(logic)` — ロックの状態が変わったとき（回数が 0 と 1 のあいだで変わったとき）、新しい状態（true = ロック中）で届く。
- 受けるもの
  - `item_grant_component` は `activated_event`（全員に配る）と `deactivated_event`（`RevokeOnDeactivate` なら回収）。
  - `exclusive_item_component` は `add_item_query_event`（同じ種類をもう持っている人の inventory に入るのを、`item_exclusive_error` で断る）。
  - `item_equip_lock_component` は `unequip_item_query_event`（ロック中に装備を外すのを、`item_unequip_locked_error` で断る）。

## 持ち主
プレイヤーの slot の下（LoadoutSystem のロードアウトの中、CharacterSystem のキャラクターの中など。`Entity.FindOwningPlayer[]` が成功する場所）に置くと、全員ではなく持ち主に効きます。
- `item_grant_component`：起動の合図で、持ち主にだけ配る（ほかのプレイヤーには配らない）。`GrantToAgent` をコードから呼んだときは、渡した人に配る。

なお、アイテムの「持ち手」（`item_holder_component`）や `FindOwnerAgent` は、アイテムの entity から親をたどって最初の agent を探すもので、slot の持ち主（PlayerSystem の `FindOwningPlayer`）とは別です。

## 公開 API
```verse
# 持ち手
item_holder_rule<public> := enum:
    Owned
    Equipped

item_holder_component<public> := class<final_super>(component):
    Rule<public>:item_holder_rule
    var<private> Holder<public>:?agent                     # 今の持ち手。いなければ false
    HolderAddedEvent<public><final>:listenable(agent)
    HolderRemovedEvent<public><final>:listenable(agent)
    FindHolder<public>()<decides><transacts>:agent

item_holder_friend_component<public> := class<final_super>(component):
    ItemType<public>:castable_concrete_subtype(entity)

# inventory とアイテムの補助
(Agent:agent).GetRootInventories<public>()<transacts>:[]inventory_component   # 入れ子でない inventory すべて（並び順は決まっていない）
(Agent:agent).FindRootInventory<public>()<decides><transacts>:inventory_component   # 根の 1 つ目
(Agent:agent).GetAgentItems<public>()<transacts>:[]entity
(Agent:agent).GetAgentEquippedItems<public>():[]entity          # <decides> / <transacts> の中では呼べない
(Agent:agent).FindWeaponHotbar<public>()<decides><transacts>:inventory_component
(InEntity:entity).FindOwnerAgent<public>()<decides><reads>:agent # 親をたどって最初の agent
(Item:item_component).FindEquippedOwner<public>()<decides><reads>:agent
(Item:item_component).AwaitHolderChange<public>()<suspends>:void # 装備か inventory が変わるまで待つ
(Agent:agent).AwaitAnyEquipChange<public>()<suspends>:void       # inventory が無いとずっと戻らない
(Item:entity).RemoveFromInventory<public>():void                 # inventory から外して消す
(Item:entity).ConsumeOne<public>():void                          # スタックを 1 減らす。最後の 1 つなら外して消す
(InEntity:entity).BeginItemAbilities<public>(Agent:agent):[]ability_effect   # fort_item_ability_component の能力を使う
EndItemAbilities<public>(Effects:[]ability_effect):void

# GrantKit
item_grant_pick_mode<public> := enum:
    All
    Random

item_grant_destination<public> := enum:
    Root
    WeaponHotbar

item_grant_component<public> := class<final_super>(component):
    PickMode<public>:item_grant_pick_mode
    RandomCount<public>:int
    Destination<public>:item_grant_destination
    RevokeOnDeactivate<public>:logic
    GrantToAgent<public>(Agent:agent)<transacts>:void           # 1 人に配る（起動の合図は要らない。呼ぶたびに選び直す）
    RevokeAll<public>()<transacts>:void                         # RevokeOnDeactivate で配って覚えている物を全員から回収
    RevokeFrom<public>(Agent:agent)<transacts>:void

item_grant_entry_component<public> := class<final_super>(component):
    Item<public>:concrete_subtype(entity)
    Count<public>:int

# ExclusiveKit
item_exclusive_error<public> := class<computes>(add_item_error):

exclusive_item_component<public> := class<final_super>(component):
    ItemType<public>:castable_concrete_subtype(entity)

# RuleKit
item_unequip_locked_error<public> := class<computes>(unequip_item_error):

item_equip_lock_component<public> := class<final_super>(component):
    ChangedEvent<public><final>:listenable(logic)
    Lock<public>():void                                         # 回数を 1 増やす
    Unlock<public>():void                                       # 回数を 1 減らす。0 で外せるようになる
    IsLocked<public>()<decides><transacts>:void
```

## 前提・注意
- プレイヤーには inventory が複数あります（武器のホットバー・建築・素材・弾薬など）。`FindRootInventory` は根の 1 つ目を返し、根が複数あるときはどれが返るかは決まりません。特定の inventory が要るときは `GetRootInventories` から型で選ぶか、`FindWeaponHotbar` を使います。
- `FindOwnerAgent` は、inventory に入っているアイテムの entity が持ち主の子孫になる前提です。地面に落ちている・まだ配られていないアイテムでは失敗します。
- `AwaitAnyEquipChange` は `FindRootInventory` が返す 1 つの inventory だけを見ます。根が複数あると、別の根での装備の変化は届きません。
- `item_holder_component` は変化の知らせのあと 1 フレーム待ってから調べ直します（同じフレームに続けて来た変化の取りこぼし対策）。
- `item_grant_component` は区画ではなく、playspace のプレイヤー全員（`GetPlayers`）に配ります。途中参加の人には自動では配りません。配りたいときは参加の知らせ（`player_manager_component` の `PlayerAddedEvent` など）を受けて `GrantToAgent` を呼びます。入れ先が見つからない人には何もせず、`exclusive_item_component` などで入らなかったアイテムも失敗は返しません。
- `item_grant_component` が回収できるのは、`RevokeOnDeactivate` がオンのときに配った物だけです（もう持っていない物は飛ばします）。
- `item_equip_lock_component` は `Lock` / `Unlock` を対で呼びます。inventory から取り除く（`RemoveItem`・アイテムが消える）のは止めません。シミュレーションが終わるとロックは解けます。`jetpack_ability_component`（JetpackSystem）は、これが同じ entity にあればチャージと飛び出しのあいだロックします。

## 確かめ方
- テスト：`_Test/ItemSystemTest/` の `item_system_test_component`。置き方：
  - `player_manager_component` を付けた entity を 1 つ
  - テスト用の entity に `item_system_test_component` を付け、`TestItem` にテスト用のアイテムの prefab を選ぶ
  - テスト用のアイテムの prefab には `item_component`、`item_holder_component`（`Rule` = `Owned`）、`item_equip_lock_component` を付ける。重ねて持てない（stackable でない）もの（`TestItem` が既定の entity のままなら、アイテムを使う項目は飛ばす）

  `item_equip_lock_component` の回数の数え方と `ChangedEvent`、inventory の探し方（`GetRootInventories` / `FindRootInventory` / `GetAgentEquippedItems`）と入力の取り出し（InputSystem の `FindPlayerInput`）、`item_grant_component`（実行時に作って `GrantToAgent`）、`item_holder_component`（`Owned`）、ロック中に装備を外せないこと、`ConsumeOne` / `RemoveFromInventory` を確かめます。人の操作は要りません。数秒で終わります。結果は出力ログの `[TEST] ItemSystem`。
- 見本（`_Samples/`）は無い。
