# PlayerSystem

参加しているプレイヤーを扱う System です。`player_manager_component` が参加した人ごとに slot の entity を作り、ほかの System はその slot の下に 1 人分の view を作って（`player_view_set`）人ごとの処理をします。ほかに、プレイヤーの状態タグの基底と付け外し（PlayerTags）、「だれのものか」を entity の木から決める `FindOwningPlayer`（PlayerOwner）、体の entity とプレイヤーの行き来（PlayerBody）、プレイヤーの体に物を付ける `player_attach_component`、Fortnite キャラクターの動きへの反応（MotionKit）があります。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `player_manager_component` | 区画（または世界）に 1 つ。ほかの部品から `FindScopedComponent` で探される | 参加した人ごとに slot の entity を子に作り、退出で消す。参加と退出を区画全体へ知らせる |
| `player_slot_component` | 実行時に `player_manager_component` が作る（エディターでは置かない） | 参加中の 1 人を表す。view やロードアウトはこの entity の子に作られる |
| `player_attach_component` | 起動の合図が届く場所（`ActiveOnBegin` ならどこでもよい）。ロードアウトのプレハブの中に置くと持ち主だけに付ける | プレイヤーの体に `Prefab` を作って付け、体と一緒に動かす。リスポーンで体が変わったら付け直す |
| `player_group_component` | どこでもよい。排他にする組（1 人 1 つ）は、同じ親の下に兄弟として並べる | だれが起こしたか分かる起動の合図（選択メニューの `Targets` など）で、その人を組に入れる。入ったら `Targets` へその人の起動の合図を送る。「選んだ人」の置き場（UI を選んだ人にだけ出すのは WidgetSystem の `widget_show_in_group_component`） |
| `player_count_condition_component`（ConditionKit） | `game_transition_component` か `condition_all` / `condition_any` の entity の直下 | 参加人数が `MinPlayerCount` 以上なら満たす |
| `player_group_count_condition_component`（ConditionKit） | 同上。数える組は `Group` で選ぶ（空なら、この entity かその祖先の組） | 組（`player_group_component`）の人数が `MinMemberCount` 以上・`MaxMemberCount` 以下なら満たす（組の人がいる・そろった・だれもいない） |
| `player_motion_trigger_component`（MotionKit） | どこでもよい。ロードアウトのプレハブの中なら持ち主だけ、持ち主のいない場所なら区画の全員を見る | キャラクターの一瞬の動き（ジャンプ・着地など）が起きるたびに、`Targets` へ起動の合図（だれが起こしたか付き）を送り、`player_motion_event` を上へ送る |
| `player_state_trigger_component`（MotionKit） | ロードアウトのプレハブの中（持ち主のいる場所）。持ち主がいないと何もしない | 持ち主のキャラクターが `State` に入ったら `Targets` へ起動の合図、出たら停止の合図を送る |
| `player_state_condition_component`（MotionKit） | ロードアウトのプレハブの中で、`ability_grant_condition_component` / `game_transition_component` / `condition_all` / `condition_any` の entity の直下 | 持ち主のキャラクターが `State` にいるあいだ満たす |

`player_view_set` と `player_tag_holder` は component ではなく、component のフィールドに持つクラスです。

例：「2 人そろったら始める」と「ジャンプするたびに頭の上に目印を出す」
```
ゲーム（player_manager_component）
└ 待機（game_node_component）
  └ 次へ（game_transition_component）
    └ 2 人以上（player_count_condition_component、MinPlayerCount = 2）

ロードアウトのプレハブ（loadout_component の Prefab）
└ ジャンプ（player_motion_trigger_component、Motion = Jumped）
  └ 目印（player_attach_component、AttachToEveryone = オン）
```
実行時は `player_manager_component` の entity の下に slot（`player_slot_component`）が人数ぶん作られ、その下に各 System の view やロードアウトが作られます。

## 設定（@editable）
- `player_count_condition_component.MinPlayerCount : int = 2` — この人数以上が参加していれば満たす（1〜100）。
- `player_group_count_condition_component.Group : ?entity = false` — 人数を数える組（`player_group_component` を付けた entity）。空なら、この entity かその祖先の組（`FindAncestorGroup`）。
- `player_group_count_condition_component.MinMemberCount : int = 1` — 組の人数がこの数以上なら満たす（0〜100）。
- `player_group_count_condition_component.MaxMemberCount : int = 100` — 組の人数がこの数以下なら満たす（0〜100。既定 100 は上限なし）。`Min 0・Max 0` で「組にだれもいない」。
- `player_attach_component.Prefab : concrete_subtype(entity) = entity` — 体に付ける entity（prefab）。既定のままなら中身の無い entity。
- `player_attach_component.OffsetCm : vector3 = vector3{Up := 200.0}` — 体の原点からのずらし（センチメートル。Forward・Left・Up）。
- `player_attach_component.Visibility : player_attach_visibility = Everyone` — だれに見せるか。`Everyone` は全員、`OwnerOnly` は付けた本人だけ、`OthersOnly` は本人以外。
- `player_attach_component.AttachToEveryone : logic = true` — オンなら起動で全員（途中参加も）に付ける。持ち主のいる場所では持ち主だけ。オフなら `AttachTo` で決めた人だけ。
- `player_attach_component.ActiveOnBegin : logic = false` — オンならゲームの開始から付ける。オフなら起動の合図から。
- `player_attach_component.RefreshSeconds : float = 1.0` — 体が変わっていないか（リスポーンなど）を見回る間隔（0.1〜10 秒）。
- `player_group_component.LeaveOthers : logic = true` — オンなら、組に入るとき同じ親の下のほかの組から出る（選び直すと前の選びが外れる）。
- `player_group_component.Targets : []entity = array{}` — 組に入った人の起動の合図（`activated_by_agent_event`）を送る entity。もう入っている人がまた選んだときも、合図だけ送り直す（ラウンドごとのワープなど）。
- `player_motion_trigger_component.Motion : player_motion = Jumped` — 見張る動き。
- `player_motion_trigger_component.Targets : []entity = array{}` — 起動の合図を送る entity（その entity と子孫に届く）。空なら、この entity とその子孫へ送る。
- `player_motion_trigger_component.CooldownSeconds : float = 0.0` — 同じ人の次の動きを無視する時間（0〜60 秒）。0 なら無視しない。
- `player_state_trigger_component.State : player_motion_state = InAir` — 見張る状態。
- `player_state_trigger_component.Targets : []entity = array{}` — 合図を送る entity。空なら、この entity の子の entity へ送る（自分の entity へは送らない）。
- `player_state_condition_component.State : player_motion_state = Crouching` — 満たす状態。

`player_motion` の値：`Jumped` / `Landed` / `LeftGround` / `CrouchStarted` / `CrouchEnded` / `SprintStarted` / `SprintEnded` / `Eliminated` / `Damaged`。
`player_motion_state` の値：`OnGround` / `InAir` / `Falling` / `Crouching` / `Sprinting` / `Gliding` / `InWater` / `Flying` / `Down`（倒れているが脱落していない）。

## イベント
- `player_added_event`（scene_event、SendScoped：区画全体。区画が無ければ世界全体）: `Manager : player_manager_component`、`Agent : agent`。`player_manager_component` が、参加して slot ができたあとに送る（受けた側で `FindSlot` が成功する）。消費しない。
- `player_removed_event`（scene_event、SendScoped）: `Manager : player_manager_component`、`Agent : agent`。退出して slot が消えたあとに送る（受けた側で `FindSlot` は失敗する）。消費しない。
- `player_event`（scene_event、SendDown）: `Sender : component`、`Event : scene_event`。同じ人の view どうしで知らせを渡す包み。`SendToPlayer` で slot の entity から下へ送る。受け手は同じ人の slot の下の view。消費しない。
- `player_view_source_event`（scene_event、SendDown）: `Event : scene_event`。view を作った component から view へ知らせを渡す包み。`player_view_set.SendToViews` で送る。消費しない。
- `player_motion_event`（scene_event、SendUp）: `Trigger : player_motion_trigger_component`、`Agent : agent`、`Motion : player_motion`。`player_motion_trigger_component` の entity から根へ。受け手は祖先の component。消費しない。
- listenable（外から Signal はできない）
  - `player_manager_component.PlayerAddedEvent : listenable(player)` — 参加して slot ができたあとに届く。
  - `player_manager_component.PlayerRemovedEvent : listenable(player)` — 退出して slot が消えたあとに届く。
  - `player_attach_component.AttachedEvent : listenable(tuple(agent, entity))` — 付けたときに（その人, 付けた entity）で届く。
  - `player_attach_component.DetachedEvent : listenable(agent)` — 外したときにその人で届く。
  - `player_group_component.JoinedEvent : listenable(agent)` / `LeftEvent : listenable(agent)` — 組に入った・出た（ほかの組を選んだ・`Leave`・`Clear`・退出）ときにその人で届く。
  - `player_motion_trigger_component.MotionEvent : listenable(tuple(agent, player_motion))` — `Motion` が起きるたびに（その人, 動き）で届く。
- 送るもの: `player_motion_trigger_component` は `Targets`（空なら自分の entity）へ `activated_by_agent_event`（`SendActivatedBy`）。`player_state_trigger_component` は `Targets`（空なら子の entity）へ `activated_event` / `deactivated_event`（だれかは付かない）。
- `player_group_joined_event` / `player_group_left_event`（scene_event、SendDown：組の entity から下へ）: `Group : player_group_component`、`Agent : agent`。組に人が入った・出たとき。消費しない。
- 受けるもの: `player_view_set.HandleActivation` と `player_attach_component` は `activated_event` / `deactivated_event`。`player_group_component` は、だれかの分かる `activated_event` でその人を入れ、`deactivated_event` でその人（だれか分からなければ全員）を出す。`player_count_condition_component` は `player_added_event` / `player_removed_event`。`player_group_count_condition_component` は scene_event ではなく、組の `JoinedEvent` / `LeftEvent` を購読する（組が祖先でなくても届く）。

## タグ
- `player_state_tag` — プレイヤーの状態を表すタグの抽象基底。状態を持つ System はこの派生を作る。派生で付けたタグは基底の型でも見つかる（`Agent.HasPlayerTag[player_state_tag]` は「何かの状態にある」）。
- `controlled_movement_tag` — 能力などがプレイヤーの動き（速度・位置）を直接操っているあいだ付くタグ（`player_state_tag` の派生）。ほかの力（引力・ホバーなど）は、これが付いている人の速度を書き換えない。自分で動きを操る能力を作るときもこの派生を付ける。
- `player_tag_holder` — 付け外しの部品。状態に入ったら `Tags.Add(Agent, xxx_tag{})`（または `Set`）、抜けたら `Tags.Remove(Agent)`、止まるとき（`OnEndSimulation`・能力の `defer`）に `Tags.RemoveAll()`。`AddTag` が返す `tag_key` を人ごとに覚え、自分が付けた分だけを外すので、ほかの部品が付けた同じ型のタグは消さない。同じ holder で同じ人にもう付けていれば `Add` は何もしない。
- タグはキャラクターの entity ではなく agent に付く（スポーン前・倒れているあいだ・リスポーンのあとも消えない）。
- 確かめる側は `Agent.HasPlayerTag[タグの型]`（中は `ContainsTag`）。PlayerSystem 自身はタグを付けない。

## 持ち主
- プレイヤーの slot（`player_slot_component` の entity）の下にある entity は、その人のもの（持ち主がいる）です。`InEntity.FindOwningPlayer[]` は、自分か祖先をたどって最初に見つかった slot のプレイヤーを返し、slot の下に無ければ失敗します。`FindOwningSlot[]` は slot の component を返します。
- slot の下に部品を置く一番の方法は、LoadoutSystem の `loadout_component`（プレハブを人ごとに作って slot の下に置く）です。`player_view_set` の view も slot の下に作られます。
- `FindOwningPlayer[]` が成功する場所では、全員ではなく持ち主だけに効く部品があります。能力の付与（AbilitySystem）、widget と標準 HUD を隠す部品（WidgetSystem）、`item_grant_component`（ItemSystem）、独自キャラクター（CharacterSystem）、デバイスの橋渡しの `Owner`（FNDeviceSystem）、そしてこの System の次の部品です。
  - `player_attach_component` — 持ち主のいる場所では、起動したとき（`AttachToEveryone` がオンなら）持ち主にだけ付ける。全員にも途中参加の人にも付けない。
  - `player_motion_trigger_component` — 持ち主のいる場所では持ち主だけを見る。持ち主がいなければ区画の全員（途中参加も）を見る。
  - `player_state_trigger_component` / `player_state_condition_component` — 持ち主がいないと動かない（出力ログに「持ち主がいません」と出る）。
- 新しく作る部品も、`FindOwningPlayer[]` が成功したら持ち主だけに効くようにそろえます。

## 公開 API
```verse
# PlayerManagerComponent / PlayerSlotComponent
player_added_event<public> := class(scene_event):
    Manager<public>:player_manager_component
    Agent<public>:agent

player_removed_event<public> := class(scene_event):
    Manager<public>:player_manager_component
    Agent<public>:agent

player_manager_component<public> := class<final_super>(component):
    PlayerAddedEvent<public><final>:listenable(player)
    PlayerRemovedEvent<public><final>:listenable(player)
    GetPlayerCount<public>()<reads>:int                                   # 直下の slot の数
    GetSlots<public>()<reads>:[]player_slot_component                     # 並び順は決まっていない
    FindSlot<public>(Player:player)<decides><reads>:player_slot_component # 参加の処理より前と退出のあとは失敗

player_slot_component<public> := class<final_super>(component):
    Player<public>:player

# PlayerViewSet
player_event<public> := class(scene_event):
    Sender<public>:component
    Event<public>:scene_event

player_view_source_event<public> := class(scene_event):
    Event<public>:scene_event

player_view_set<public> := class<unique>:
    IsActive<public>()<decides><transacts>:void
    GetViews<public>()<transacts>:[]entity                                # 世界に入っている view だけ（退出した人・HideFor の分は含まない）
    Activate<public>(Owner:entity, MakeView:type{_(:entity, :player_slot_component):component}, ?Everyone:logic = true, ?ViewFilter:?player_view_filter = false):void   # Everyone = false なら ShowFor で決めた人だけ。ViewFilter が許す人にだけ作る
    Deactivate<public>():void
    HandleActivation<public>(SceneEvent:scene_event, Owner:entity, MakeView:type{_(:entity, :player_slot_component):component}):void
    FindViewFor<public>(Agent:agent)<decides><transacts>:entity
    HideFor<public>(Agent:agent):void
    ShowFor<public>(Agent:agent):void                                     # 起動中で、view が無ければ作る
    SendToViews<public>(SceneEvent:scene_event):void                      # player_view_source_event で包んで送る

(View:component).SendToPlayer<public>(SceneEvent:scene_event):void        # player_event で包んで同じ人の slot の下へ
(View:component).FindViewSlot<public>()<decides><transacts>:player_slot_component

# PlayerSubscription
(InEntity:entity).SubscribePlayers<public>(OnAdded:type{_(:player):void}, OnRemoved:type{_(:player):void}):?cancelable

# PlayerOwner
(InEntity:entity).FindOwningPlayer<public>()<decides><transacts>:player              # 自分か祖先の slot のプレイヤー
(InEntity:entity).FindOwningSlot<public>()<decides><transacts>:player_slot_component

# PlayerBody
(Agent:agent).FindPlayerEntity<public>()<decides><transacts>:entity       # キャラクターがいないと失敗
(Body:entity).FindPossessingAgent<public>()<decides><transacts>:agent     # possessable_component の Agent
(Body:entity).FindPlayer<public>()<decides><transacts>:player             # 操っているのがプレイヤーでなければ失敗
(Body:entity).FindFortCharacter<public>()<decides><transacts>:fort_character

# PlayerTags
player_state_tag<public> := class<abstract>(tag):
controlled_movement_tag<public> := class(player_state_tag):
(Agent:agent).HasPlayerTag<public>(TagType:castable_subtype(tag))<decides><reads>:void

player_tag_holder<public> := class:
    Add<public>(Agent:agent, Tag:tag)<transacts>:void
    Remove<public>(Agent:agent)<transacts>:void
    Set<public>(Agent:agent, On:logic, Tag:tag)<transacts>:void
    Has<public>(Agent:agent)<decides><reads>:void
    RemoveAll<public>()<transacts>:void

# PlayerAttachComponent
player_attach_visibility<public> := enum:
    Everyone
    OwnerOnly
    OthersOnly

player_attach_component<public> := class<final_super>(component):
    Prefab<public>:concrete_subtype(entity)
    OffsetCm<public>:vector3
    Visibility<public>:player_attach_visibility
    AttachToEveryone<public>:logic
    ActiveOnBegin<public>:logic
    RefreshSeconds<public>:float
    AttachedEvent<public><final>:listenable(tuple(agent, entity))
    DetachedEvent<public><final>:listenable(agent)
    Activate<public>():void                                     # もう起動していれば何もしない
    Deactivate<public>():void                                   # 全員から外す
    AttachTo<public>(Agent:agent):entity                        # 付いていればその entity を返す。起動していなければ起動する
    DetachFrom<public>(Agent:agent):void
    DetachAll<public>():void
    FindAttached<public>(Agent:agent)<decides><transacts>:entity
    IsAttachedTo<public>(Agent:agent)<decides><transacts>:void

# ConditionKit
player_count_condition_component<public> := class<final_super>(condition_component):
    MinPlayerCount<public>:int

player_group_count_condition_component<public> := class<final_super>(condition_component):
    Group<public>:?entity                                       # 空なら、この entity かその祖先の組
    MinMemberCount<public>:int
    MaxMemberCount<public>:int
    FindTargetGroup<public>()<decides><transacts>:player_group_component   # 数えている組。開始前・見つからないときは失敗

# MotionKit
player_motion<public> := enum:
    Jumped
    Landed
    LeftGround
    CrouchStarted
    CrouchEnded
    SprintStarted
    SprintEnded
    Eliminated
    Damaged

player_motion_state<public> := enum:
    OnGround
    InAir
    Falling
    Crouching
    Sprinting
    Gliding
    InWater
    Flying
    Down

player_motion_event<public> := class(scene_event):
    Trigger<public>:player_motion_trigger_component
    Agent<public>:agent
    Motion<public>:player_motion

player_motion_trigger_component<public> := class<final_super>(component):
    Motion<public>:player_motion
    Targets<public>:[]entity
    CooldownSeconds<public>:float
    MotionEvent<public><final>:listenable(tuple(agent, player_motion))

player_view_filter<public> := interface:                       # player_view_set がだれに view を作ってよいか
    AllowsView<public>(Agent:agent)<decides><transacts>:void

player_group_joined_event<public> := class(scene_event):
    Group<public>:player_group_component
    Agent<public>:agent
player_group_left_event<public> := class(scene_event):
    Group<public>:player_group_component
    Agent<public>:agent

player_group_component<public> := class<final_super>(component):
    LeaveOthers<public>:logic
    Targets<public>:[]entity
    JoinedEvent<public><final>:listenable(agent)
    LeftEvent<public><final>:listenable(agent)
    Join<public>(Agent:agent):void                               # 兄弟の組から出してから入れ、Targets へ合図。もう入っていれば合図だけ
    Leave<public>(Agent:agent):void
    Clear<public>():void
    IsMember<public>(Agent:agent)<decides><transacts>:void
    GetMembers<public>()<transacts>:[]agent                      # 入った順
    GetMemberCount<public>()<transacts>:int
    GetMemberPlayerEntities<public>()<transacts>:[]entity       # 今キャラクターがいる人の体（FindPlayerEntity）。体の無い人は含まない

(InEntity:entity).FindAncestorGroup<public>()<decides><transacts>:player_group_component   # InEntity かその祖先のいちばん近い組

player_state_trigger_component<public> := class<final_super>(component):
    State<public>:player_motion_state
    Targets<public>:[]entity
    IsActive<public>()<decides><transacts>:void                 # 持ち主が今 State にいるなら成功

player_state_condition_component<public> := class<final_super>(condition_component):
    State<public>:player_motion_state
```

## 前提・注意
- `player_view_set`・`player_count_condition_component`・`player_attach_component`（`AttachToEveryone` で持ち主がいないとき）・`player_motion_trigger_component`（持ち主がいないとき）と、それを使うほかの System は、区画（または世界）に `player_manager_component` が 1 つ要る。見つからないと `player_view_set.Activate` は起動した扱いになるが view は作らない（参加も待たない。出力ログに `[player_view_set] player_manager_component が…見つかりません` と 1 回出る）。
- 退出すると `player_manager_component` が slot の entity を外し、その下の view も世界から外れる（view の component は `OnEndSimulation` を通る）。`player_view_set` は `GetViews` / `FindViewFor` / `SendToViews` で世界に入っている view だけを見て、manager の `PlayerRemovedEvent` で退出した人の view を一覧から除く。view の component は、止まるとき（`OnEndSimulation`）に人ごとの状態を戻す（`player_ready_view_component` の「準備 OK」など）。⚠ 未検証：外した slot の下の view で `GetSimulationEntity` が失敗すること（digest の説明では「シーンに無いと失敗」）。
- シミュレーション開始の時点でいる人の slot は `player_manager_component` の `OnBeginSimulation` の中で作られ、そのときの知らせ（scene event・event とも）はまだ購読していない相手には届かない。あとから購読するコードは、先に `GetSlots` で今いる人を見てから `PlayerAddedEvent` を待つ。
- `SubscribePlayers` は、すでにいるプレイヤーにはこの関数の中で（返る前に）`OnAdded` を呼ぶ。playspace が取れない entity では false を返し、何も呼ばない。返り値は `OnEndSimulation` で Cancel する。世界に 1 つの slot が欲しいだけなら `player_manager_component` を使う。
- `player_attach_component` は体の entity と親子にせず、自分の entity の子に作った entity を `SetOrigin(entity_origin{Entity := 体})` で体を基準にする（体の中身には触らない）。同じ人には 1 つだけ付ける。体がいないあいだは隠し、`RefreshSeconds` ごとの見回りで付け直す。`OthersOnly` は区画の `player_manager_component` の参加者から本人を除いた人に見せる。
- 区画の `player_manager_component` は、`player_count_condition_component`・`player_attach_component`・`player_view_set` とも、最初に見つけたものを覚えて使う（SceneGraphSystem の `ResolveScopedComponent`）。`player_attach_component` は止まるとき、`player_view_set` は `Deactivate` で忘れる。
- `player_group_count_condition_component` は開始時に組を探して購読する。組が見つからなければ出力ログに「player_group_component が見つかりません」と出て、満たさない。実行時に作った組を数えるときは、組を先に作ってから条件を足す。
- MotionKit の部品は毎フレーム（`TickEvents.PrePhysics`）キャラクターを調べる。リスポーンでキャラクターが変わると購読し直す。`Landed` / `LeftGround` は地面にいるかの変化で決め、`Sprinting` の状態は `SprintedEvent` の知らせで覚える。`player_state_trigger_component` は開始時にすでに `State` にいれば、すぐ起動の合図を送り、止まるときに `State` にいれば停止の合図を送る。
- ⚠ 未検証（PlayerTags.verse）：agent に付けたタグの付け外し・`ContainsTag` が UEFN 43.00 の実機で動くか（digest では agent は entity の派生で、entity は has_tags）。`_Test/PlayerSystemTest` で確かめる。
- ⚠ 未検証（PlayerAttachComponent.verse）：`entity_origin` で体に付けた entity が、体の向き・しゃがみに合わせて動くか。

## 確かめ方
- テスト：`_Test/PlayerSystemTest/` の `player_system_test_component`。`player_manager_component` を付けた entity を 1 つと、この component を付けた entity を 1 つ置き、プレイヤー 1 人以上で始める（参加を最大 10 秒待つ。そろっていれば次のフレームで終わる）。slot（`GetPlayerCount` / `GetSlots` / `FindSlot`）、`player_count_condition_component`、`player_view_set`（`Activate` / `Deactivate` / `GetViews` / `FindViewSlot`）、`SubscribePlayers`、タグ（`player_tag_holder` / `HasPlayerTag`。派生のタグを基底の型で探す、ほかの holder の分は残る）、組（`Join` / `Leave` / `GetMemberCount` / `GetMemberPlayerEntities` / `FindAncestorGroup`）と `player_group_count_condition_component`（祖先の組を数える、1 人以上・だれもいない、`ChangedEvent` の回数）を確かめます。結果は出力ログの `[TEST] PlayerSystem`。
- `player_attach_component`・MotionKit・`FindOwningPlayer`・PlayerBody・`player_group_component` の合図（`Targets`・`LeaveOthers`）は、このテストでは確かめない。`FindOwningPlayer` は `_Test/LoadoutSystemTest/` が使う。
- 見本：`_Samples/ScopeSample/`（`FindScopedComponent[player_manager_component]` がどこを見つけるか）。`player_view_set` の使い方は `_Samples/AbilitySample/`・`_Samples/WidgetSample/`（`SendToPlayer` も）・`_Samples/InputSampleExperimentalKit/`・`_Samples/VirtualPointerSampleExperimentalKit/`。名前が `ExperimentalKit` で終わる見本は、VerseShare で「実験的を含む」をオンにしたプロジェクトにだけ配られる。
