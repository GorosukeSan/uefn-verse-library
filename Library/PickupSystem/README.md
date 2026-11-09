# PickupSystem

拾える物（オーブ）と、拾った人に付く「効果」の System です。オーブ（`pickup_component`）は触れた人に**効果のプレハブ**を作って与えるだけで、効果の中身は知りません。効果のプレハブは、根の「効果の土台」（`pickup_effect_component`：持ち主・寿命・重ねがけ）に、**起動の合図で動く部品を重ねるだけ**で作ります。コードを書かずに新しい効果を作れます（バフ・能力の付与・ステージへの影響・ほかの System の部品の組み合わせ）。拾ったことと続いている効果は、HudKit の `pickup_effect_hud_component` が持ち主の画面に出します（名前・説明・色は効果のプレハブの根の `card_info_component`）。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `pickup_component` | 拾える物の entity（見た目のメッシュ・触れたことを決める部品と同じ entity） | 触れた人に `Effect` のプレハブを作って与える（その人の slot の下）。見た目を消し、`RespawnSeconds` 秒で戻す |
| `pickup_filter_component` の派生 | `pickup_component` と同じ entity（1 つまで） | 拾える人をコードの条件で絞る（中身は `CanPick` だけ） |
| `pickup_effect_component` | 効果のプレハブの根 | 作られた次のフレームに、持ち主が起こした起動の合図を自分と子孫へ送り、`DurationSeconds` 秒で停止の合図を送って自分（プレハブ）を消す。同じ効果の重ねがけ（`StackMode`）。持ち主に `pickup_effect_tag` |
| 効果の中身（起動の合図で動く部品） | 効果のプレハブの根か子 | 起動の合図で効き、停止の合図か `OnEndSimulation` で元に戻す。持ち主は `FindOwningPlayer` か合図の Agent |
| `pickup_stage_signal_component`（StageKit） | 効果のプレハブの根か子 | 範囲（拾った物の最上位の entity・区画・世界）の、`Group` が同じ相手へ起動・停止の合図を送り、効果の終わりで元に戻す |
| `card_info_component`（WidgetSystem の CardKit） | 効果のプレハブの根 | 効果の見せ方（`Title`・`Description`・`Badge`・`Thumbnail`・`AccentColor`）。HudKit の HUD が読む（無ければ名前 = `EffectId`）。見せ方の持ち主はここだけ |
| `pickup_effect_hud_component`（HudKit） | 持ち主の slot の下（ロードアウトのプレハブ・独自キャラクターの体）。slot の祖先に置くと全員にそれぞれの効果を出す | 拾ったとき：画面の上の方に名前・説明・色の帯の板をポップして出し、消す（続けて拾えば順に、同じ効果なら弾ませる）。続いているあいだ：左に 1 行ずつ、色の四角・名前・重なった数・残り秒・残り時間の棒（毎フレーム縮む）。Instant と短い効果は板だけ |
| `pickup_stage_target_component`（StageKit） | 合図で動かしたい entity（隠れた足場・ハザード・仕掛け） | `Group` が同じ合図を受けたら、自分の entity と子孫へ起動・停止の合図を送る（重なった合図は数えて、全部終わってから戻す）。`pickup_stage_target_tag` を付ける |

効果の中身に使える Library の部品（どれも起動の合図で動き、持ち主のいる場所では持ち主だけに効く）:
- CharacterSystem / BuffKit：`character_buff_component`（速さ・ジャンプ・重力の倍率）、`character_move_grant_component`（空中ジャンプの回数・ダッシュの許可）。独自キャラクターの体に効く
- WidgetSystem：`text_hud_component` などの widget（効果のあいだだけ、持ち主の画面に出す。効果の名前を出すだけなら、根に `card_info_component` を置いて HudKit の HUD に任せる）
- AbilitySystem：能力（`ability_component` の派生）＋ `ability_grant_players_component`（`GrantOnBegin = false`。効果のあいだだけ持ち主に付与）
- ActivationSystem：`enable_on_activation_component`、SpawnSystem：`spawn_prefab_component`（拾った場所に物を出す。効果の entity の位置は拾った物の位置）など

例：「速さ 1.5 倍を 8 秒、画面に名前を出す」効果と、それを配るオーブ
```
効果のプレハブ PF_Effect_SpeedUp
└ 根   pickup_effect_component（DurationSeconds = 8、EffectId = "SpeedUp"、StackMode = Extend）
       character_buff_component（CharacterSystem/BuffKit、SpeedMultiplier = 1.5）
       card_info_component（WidgetSystem/CardKit、Title = "スピードアップ"、Description = "8 秒間、走る速さが 1.5 倍"、AccentColor = 橙）

ロードアウトのプレハブ（持ち主の slot の下）
└ 体など pickup_effect_hud_component（HudKit。拾ったときの板と、続いている効果の一覧を持ち主に出す。効果ごとには置かない）

オーブ（レベル）
└ Orb  メッシュ（当たり判定なし）, character_surface_component（独自キャラクターが触れる）
       （Fortnite のキャラクターなら player_volume_component（VolumeSystem））,
       pickup_component（Effect = PF_Effect_SpeedUp、RespawnSeconds = 10）
```
「そのマップの隠れた足場を 10 秒出す」なら、効果の根に `pickup_stage_signal_component`（`Group = "reveal"`、`Signal = Activate`）を置き、足場に `pickup_stage_target_component`（`Group = "reveal"`）と、起動の合図で出る部品（`enable_on_activation_component` やゲームの部品）を置きます。

## 新しい効果を作る手順（コードなし）
1. コンテンツブラウザでプレハブを作り、根の entity に `pickup_effect_component` を付ける（`DurationSeconds`、同じ効果どうしの扱い `EffectId` / `StackMode`、1 回きりなら `Instant`）。
2. 根か子に、効果の中身の部品を重ねる（上の一覧。起動の合図で動く部品ならどれでもよい）。同じ型の部品を 2 つ使うなら子の entity に分ける。
3. 画面に名前を出すなら、根に `card_info_component`（`Title`・`Description`・`AccentColor`。`Thumbnail` と `Badge` は任意）を置き、持ち主の slot の下（ロードアウトなど）に `pickup_effect_hud_component`（HudKit）を 1 つ置く（効果ごとには置かない）。
4. オーブの `pickup_component.Effect` にプレハブを選ぶ。

## 設定（@editable）
`pickup_component`
- `Effect : concrete_subtype(entity) = entity` — 与える効果のプレハブ（根に `pickup_effect_component`）。根に無ければ出力ログに出して既定（10 秒）の土台を足す。
- `RespawnSeconds : float = 10.0` — 拾われてから戻るまで（0〜3600）。0 なら戻さない（`Restore`・起動の合図・ゲームのやり直しで戻す）。
- `Visual : concrete_subtype(entity) = entity` — 見た目のプレハブ。開始時にこの entity の子に作り、拾われたら一緒に消す。既定のままなら何も足さない（この entity のメッシュを差し替えてもよい）。
- `RequireGroupMember : logic = false` — オンなら祖先の一番近い `player_group_component`（PlayerSystem）の組の人だけ。
- `ActiveOnBegin : logic = true` — オフなら起動の合図まで隠す（合図で出るオーブ）。
- `DisplayName : string = ""` — 表示名（ログ・利用者の HUD 用）。

`pickup_effect_component`
- `DurationSeconds : float = 10.0` — 続く秒数（0〜3600）。0 ならずっと（`End`・`EndPickupEffectsFor`・退出まで）。
- `Instant : logic = false` — オンなら起動の合図を送った次のフレームで終える（1 回きりの効果）。
- `EffectId : string = ""` — 同じ効果の見分け。空なら毎回別の効果（いつも重ねる）。
- `StackMode : pickup_effect_stack_mode = Extend` — 同じ `EffectId` の効果を持っている人がまた拾ったとき。`Extend`（残りに足す）/ `Refresh`（残りを戻す）/ `Stack`（もう 1 つ重ねる）/ `Replace`（前のを終えて新しく）/ `Ignore`（何もしない）。
- `MaxStacks : int = 0` — `Stack` の上限（0 なら無し）。届いていたら一番早く終わるものを延ばす。

HudKit
- `pickup_effect_hud_component.ShowToasts : logic = true` — 拾ったとき（拾い直したときも）画面の上の方に名前と説明の板を出す。
- `pickup_effect_hud_component.ShowEffectList : logic = true` — 続いている効果を 1 行ずつ並べ、残り時間の棒と秒を出す（同じ `EffectId` は 1 行にまとめて重なった数を出す）。
- `pickup_effect_hud_component` は既定を `ActiveOnBegin = true`、`ZOrder = 100` にしている（`Audience`・`Mode` などは WidgetSystem の `player_widget_component` と同じ）。
- 見た目は `var Style : pickup_effect_hud_style`（コードで入れる。エディターには出ない。出し始めたときに写す）。主な項目：知らせの板 `ToastXRatio / ToastYRatio`（0.5 / 0.24）・`ToastWidthPx / ToastHeightPx`（560 / 110）・`ToastIconWidthPx`・`ToastLinePx`・`ToastBackColor / ToastBackOpacity`・`ToastTitleSize`（色は AccentColor）・`ToastDescriptionColor / Size`・`ToastBadgeColor / Size`・`ToastInSeconds`（0.2。大きくなりながら濃く）・`ToastHoldSeconds`（1.6）・`ToastOutSeconds`（0.3。上へずれながら薄く）・`ToastStartScale`（0.6）・`ToastOvershoot`（1.7）・`ToastOutSlidePx`・`ToastPulseScale / Seconds`（拾い直しで弾ませる）・`ToastQueuedHoldSeconds`（0.5。次が待っているとき）・`MaxQueuedToasts`（3）。一覧 `ListXRatio / ListYRatio`（0.015 / 0.2。左上）・`RowWidthPx / RowHeightPx / RowGapPx / RowPaddingPx`・`RowBackColor / Opacity`・`RowNameColor / Size`・`RowTimeColor / Size`・`StackPrefix`（"x"）・`RowBarHeightPx / RowBarBackColor / RowBarBackOpacity`・`RowInSeconds / RowOutSeconds / RowSlidePx`（横から出て横へ消える）・`RowMoveSpeed`（下の行が詰める速さ）・`RowWarnSeconds / RowWarnBlinkPerSecond`（残りが少ないと棒が点滅）・`RowFlashSeconds`（延びたら白く光る）・`MinRowSeconds`（2.0。これより短い効果は並べない）・`ShowEndlessRows`（true。ずっと続く効果は棒が満タンのまま）・`FallbackAccentColor`（`card_info_component` が無いときの色）。

StageKit
- `pickup_stage_target_component.Group : string = ""` — 合図のグループ。空なら受けない。
- `pickup_stage_signal_component.Group : string = ""`、`Signal : pickup_stage_signal = Activate`（`Activate` / `Deactivate`）、`Scope : pickup_stage_scope = SourceRoot`（`SourceRoot` = 拾った物の最上位の entity の中 / `SourceScope` = 拾った物の区画（無ければ世界）/ `World`）、`RevertOnEnd : logic = true`（効果の終わりに戻す）。

## イベント
- `pickup_picked_event`（scene_event、SendUp）: `Pickup : pickup_component`、`Agent : agent`、`Effect : ?entity`。拾われた物の entity から根へ。消費しない。
- `pickup_effect_changed_event`（scene_event、SendUp）: `Effect : pickup_effect_component`、`Agent : agent`、`Started : logic`。効果の entity（slot の下）から根へ。消費しない。
- `pickup_effect_owner_event`（scene_event、SendDown）: `Effect : pickup_effect_component`（続いている効果）、`Picked : pickup_effect_component`（拾った効果。見せ方はこちらから読む）、`Agent : agent`、`Notice : pickup_effect_notice`（`Started` / `Renewed` / `Ended`）。持ち主の slot の entity から下へ（ロードアウト・キャラクター・widget の view・効果のプレハブ）。消費しない。`Renewed` は、同じ効果を拾い直して新しい効果を始めなかったとき（`Extend` / `Refresh` / `Ignore`、`Stack` の上限）で、`Effect` は残り時間が延びた方。持ち主の退出で消えたときは `Ended` も届かない。HudKit の HUD はこれを受ける。
- `pickup_component.PickedEvent : listenable(agent)`、`RestoredEvent : listenable(tuple())`。
- `pickup_effect_component.StartedEvent / EndedEvent : listenable(agent)`。
- 送る合図：効果の土台は始まりに `activated_by_agent_event{Agent = 持ち主}`、終わりに `deactivated_event` を自分の entity と子孫へ（SendDown）。`pickup_stage_target_component` は自分の entity と子孫へ。
- 受ける合図：`pickup_effect_hud_component`（HudKit）は `pickup_effect_owner_event`（slot の下に置いたとき）と `pickup_effect_changed_event`（slot の祖先に置いたときだけ）、起動・停止の合図（WidgetSystem の基底）。`pickup_component` は `activated_event`（戻す）/ `deactivated_event`（隠す）、触れた知らせ `character_surface_contact_event`（SurfaceKit。自分の entity の面の `Touched`）、`player_volume_entered_event`（VolumeSystem。自分の entity のボリューム）。`pickup_stage_signal_component` は `activated_event` / `deactivated_event`。

## タグ
- `pickup_effect_tag`（`player_state_tag` の派生）— 効果のあいだ持ち主に付く（効果 1 つに 1 つ）。どの効果かは `GetActivePickupEffects(Agent)` の `EffectId`、何が変わっているかは中身の部品のタグ（BuffKit の `character_speed_modified_tag` など）。
- `pickup_stage_target_tag`（entity の役割）— `pickup_stage_target_component` が付ける。合図を送る側がこのタグで探す。

## 持ち主
- 効果のプレハブは拾った人の slot の下に作られるので、中の部品は `FindOwningPlayer` で持ち主（拾った人）を知り、持ち主だけに効く（Library の決まり）。起動の合図の Agent も持ち主。
- 効果の土台は持ち主のいない場所では始まらない（出力ログに出して消える）。持ち主のいる場所（ロードアウトの中など）にエディターで置いた効果は、開始の次のフレームから始まる。

## 公開 API
```verse
pickup_effect_stack_mode<public> := enum:
    Extend
    Refresh
    Stack
    Replace
    Ignore

pickup_effect_tag<public> := class(player_state_tag):

pickup_picked_event<public> := class(scene_event):
    Pickup<public>:pickup_component
    Agent<public>:agent
    Effect<public>:?entity

pickup_effect_changed_event<public> := class(scene_event):
    Effect<public>:pickup_effect_component
    Agent<public>:agent
    Started<public>:logic

pickup_effect_notice<public> := enum:
    Started
    Renewed                                  # 拾い直したが始めなかった（続いている効果が延びた・そのまま）
    Ended

pickup_effect_owner_event<public> := class(scene_event):    # 持ち主の slot から SendDown
    Effect<public>:pickup_effect_component   # 続いている効果（Renewed なら延びた方）
    Picked<public>:pickup_effect_component   # 拾った効果
    Agent<public>:agent
    Notice<public>:pickup_effect_notice

pickup_filter_component<public> := class<abstract><final_super>(component):
    CanPick<public>(Pickup:pickup_component, Agent:agent)<decides><transacts>:void

pickup_component<public> := class<final_super>(component):
    Effect<public>:concrete_subtype(entity)
    RespawnSeconds<public>:float
    Visual<public>:concrete_subtype(entity)
    RequireGroupMember<public>:logic
    ActiveOnBegin<public>:logic
    DisplayName<public>:string
    PickedEvent<public><final>:listenable(agent)
    RestoredEvent<public><final>:listenable(tuple())
    TryPickup<public>(Agent:agent):logic                 # 拾わせた（効果を与えた）なら true
    Restore<public>():void
    Hide<public>():void
    IsAvailable<public>()<decides><transacts>:void
    CanPick<public>(Agent:agent)<decides><transacts>:void

pickup_effect_component<public> := class<final_super>(component):
    DurationSeconds<public>:float
    Instant<public>:logic
    EffectId<public>:string
    StackMode<public>:pickup_effect_stack_mode
    MaxStacks<public>:int
    StartedEvent<public><final>:listenable(agent)
    EndedEvent<public><final>:listenable(agent)
    End<public>():void
    AddSeconds<public>(Seconds:float):void
    SetRemainingSeconds<public>(Seconds:float):void
    GetRemainingSeconds<public>()<transacts>:float     # ずっと続く効果は -1
    IsActive<public>()<decides><transacts>:void
    FindOwner<public>()<decides><transacts>:agent
    FindSource<public>()<decides><transacts>:entity     # 拾った物（オーブ）の entity
    GetOriginTransform<public>()<transacts>:transform

(InEntity:entity).GrantPickupEffect<public>(Agent:agent, Prefab:concrete_subtype(entity), Origin:transform, Source:?entity):?entity
(InEntity:entity).GrantPickupEffectEntity<public>(Agent:agent, Effect:entity, Origin:transform, Source:?entity):?entity
(InEntity:entity).FindPickupEffect<public>()<decides><transacts>:pickup_effect_component        # InEntity か祖先
(InEntity:entity).GetActivePickupEffects<public>(Agent:agent)<transacts>:[]pickup_effect_component
(InEntity:entity).EndPickupEffectsFor<public>(Agent:agent):int                                   # 終えた数

# StageKit
pickup_stage_signal<public> := enum:
    Activate
    Deactivate

pickup_stage_scope<public> := enum:
    SourceRoot
    SourceScope
    World

pickup_stage_target_tag<public> := class(tag):

pickup_stage_target_component<public> := class<final_super>(component):
    Group<public>:string
    Hold<public>(Signal:pickup_stage_signal, Activator:?agent):void
    Release<public>(Signal:pickup_stage_signal):void
    Pulse<public>(Signal:pickup_stage_signal, Activator:?agent):void
    IsHeld<public>(Signal:pickup_stage_signal)<decides><transacts>:void

pickup_stage_signal_component<public> := class<final_super>(component):
    Group<public>:string
    Signal<public>:pickup_stage_signal
    Scope<public>:pickup_stage_scope
    RevertOnEnd<public>:logic
    Apply<public>(Activator:?agent):void
    Revert<public>():void
    GetTargetCount<public>()<transacts>:int

(InEntity:entity).FindTopEntity<public>()<transacts>:entity   # simulation entity のすぐ下の祖先（最上位の entity）

# HudKit（WidgetSystem と WidgetSystem.CardKit を使う。WidgetSystem は PickupSystem を知らない）
pickup_effect_hud_style<public> := struct:                    # 見た目と動き（上の「設定」の HudKit）
pickup_effect_hud_component<public> := class<final_super>(player_widget_component):
    ShowToasts<public>:logic
    ShowEffectList<public>:logic
    var Style<public>:pickup_effect_hud_style
    ShowToastFor<public>(Agent:agent, Card:widget_card):void                         # コードから板を出す
    TrackEffectFor<public>(Agent:agent, Effect:pickup_effect_component):void        # 知らせの届かない効果を一覧に並べる
(Effect:pickup_effect_component).GetPickupEffectCard<public>(?FallbackColor:color = NamedColors.SkyBlue)<transacts>:widget_card   # 根の card_info_component（無ければ名前 = EffectId）
```

## 前提・注意
- 区画か世界に `player_manager_component` が 1 つ要ります（効果をその人の slot の下に作るため）。
- 効果の中身の部品は、停止の合図と `OnEndSimulation` の両方で元に戻すこと（効果は持ち主の退出・`EndPickupEffectsFor` で、停止の合図なしに消えることもある）。BuffKit・StageKit の部品はそうなっています。
- ゲームの流れでやり直すとき（マップを始める・クリア・ロビーへ戻る）は、`EndPickupEffectsFor(Agent)` でその人の効果を全部終え、オーブは `Restore` で戻します（作者のゲームでは、ゲームの状態を切り替える component がこれを呼び、オーブ側は戻せる interface を実装しています）。
- ステージへの合図は共有のステージに効きます（同じマップのほかの人にも隠れた足場が見える）。相手は合図を送るときに 1 回だけ探します。
- 同じ型の部品は 1 つの entity に 1 つまで（エディターの決まり）。同じ効果に同じ部品を 2 つ使うなら子の entity に分けます。
- ⚠ 未検証（UEFN の実機）：
  - プレハブを `Prefab{}` で作って slot の下に足したとき、次のフレームに根の `pickup_effect_component` が印（`pickup_effect_grant_component`）を読めるか（PickupEffectComponent.verse）。
  - 効果の entity の中の `text_hud_component` が、持ち主だけに出るか（WidgetSystem の「持ち主のいる場所では Everyone = 持ち主」）。
  - HudKit：毎フレームの `SetDesiredSize` / `SetTextSize` / 不透明度と canvas_slot の置き直しで、板のポップ・行の出入りがちらつかずに動くか。`canvas_slot` の `Offsets`（点のアンカーで `Left` / `Top` を位置のずれとして使う）が想定どおりか。`texture_block` は薄くできないので、半分より薄いあいだは隠している。
  - HudKit：`pickup_effect_owner_event` が、slot の下のロードアウトの中の HUD に届くか（slot の entity からの SendDown）。
  - オーブの見た目を `mesh_component.Disable` で消したときに、全員から見えなくなるか。

## 確かめ方
- テスト：`_Test/PickupSystemTest/` の `pickup_system_test_component`。`player_manager_component` を付けた entity と、この component を付けた entity を 1 つずつ（どちらも最上位）置き、プレイヤー 1 人で始めます。効果の寿命（次のフレームの起動の合図・持ち主・タグ・時間で停止の合図と消える・Instant）、重ねがけ（Extend・Stack と MaxStacks・Replace・`EndPickupEffectsFor`）、オーブ（`TryPickup`・戻る・戻らない・`Restore`・合図・`RequireGroupMember`）、StageKit（Group の相手だけ・2 つの効果が重なったら両方終わってから戻す）を確かめます。約 4 秒。結果は出力ログの `[TEST] PickupSystem`。
- HudKit の HUD は自動テストしていません（画面の見た目）。MCPSystem の PickupKit（`pickup.pick` / `pickup.grant` / `pickup.effects` / `pickup.end_effects`）で拾わせて、画面を見て確かめます。
- 独自キャラクターのバフは `_Test/CharacterSystemTest/CharacterBuffTest.verse`（`character_buff_test_component`）。
