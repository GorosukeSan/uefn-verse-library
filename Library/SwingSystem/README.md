# SwingSystem

スイングの能力（AbilitySystem の `ability_component` の派生）です。付与された人が射撃（`GrabAction`）を押すと、レティクルの先の物にロープをかけてつかみ、ジャンプ（`ReleaseAction`）を押して離すまで振り子で振ります。区画の台帳（`swing_registry_component`）、強さの倍率（`swing_modifier_component` と ModifierKit）、つかまれる物の振る舞い（`swing_target_component` と TargetKit）もここにあります。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `swing_ability_component` | 付与の component（AbilitySystem の GrantKit）と同じ entity。アイテムにするなら、アイテムの entity | 付与された人ごとにスイングを動かす。つかんでいるあいだ、その人に `swinging_tag` の派生（地面で待つ `swing_anchored_tag`・振っている `swing_pendulum_tag`）を付ける。知らせを slot の下と上へ送る |
| `swing_registry_component` | 区画（`game_scope_component` の配下。無ければ世界）に 1 つ | 各人のスイング・倍率の元を覚える。ロープを引く・倍率に要る（だれがスイング中かは持たない。タグで見る） |
| `swing_anchor_component` | 置かない（実行時に、つかんだ点の entity に付く） | `Break` で、その点をつかんでいるスイングを途切れさせる |
| `swing_target_component` | つかませたい物の entity（当たり判定のあるメッシュと同じ entity）。1 entity に 1 つ。無くてもつかめる | つかまれた・振り出された・外れたを知らせ、今かかっているロープの点を覚える。`Shatter` で壊れる |
| `swing_modifier_component` | 倍率を決めたい entity。1 entity に 1 つまで | スイングの強さを変える倍率（中身）。だれに掛けるかは ModifierKit かコードで決める |
| `swing_modifier_all_component`（ModifierKit） | `swing_modifier_component` と同じ entity | 全プレイヤー（途中参加も）に倍率を掛ける（開始から、または起動の合図から停止の合図まで） |
| `swing_modifier_grant_component`（ModifierKit） | `swing_modifier_component` と同じ entity | `swing_modifier_request_event` を受けた人に `DurationSeconds` のあいだ倍率を掛ける。停止の合図で全員から外す |
| `swing_modifier_condition_component`（ModifierKit） | `swing_modifier_component` と同じ entity。直下の子に条件 | 条件を満たしているあいだ、全プレイヤーに倍率を掛ける |
| `swing_life_component`（TargetKit） | `swing_target_component` と同じ entity | 最初につかまれてから `LifeSeconds` で壊す。残りと最後の点滅を知らせる |
| `swing_lift_component`（TargetKit） | `swing_target_component` と同じ entity（mover とは同じにしない） | 振り出されると `TravelCm` だけまっすぐ動き、着いたら壊す |

`swing_ability_component` の付与の仕方は、同じ entity に置く component で選びます。
- 全員に最初から／起動しているあいだ → `ability_grant_players_component`
- アイテムとして（装備しているあいだ） → `item_component`・`item_holder_component`・`ability_grant_item_component` と一緒に置く
- 条件を満たしているあいだ → `ability_grant_condition_component`（直下の子に条件）
- コードから → `Grant` / `Revoke`

例：全員がスイングでき、つかむと 5 秒で壊れるキューブがある
```
区画（または世界）
├ プレイヤー（player_manager_component）
├ スイングの台帳（swing_registry_component）
├ スイング（swing_ability_component + ability_grant_players_component）
└ 寿命のキューブ（メッシュ + swing_target_component + swing_life_component）
```

## 設定（@editable）
`swing_ability_component`（長さは cm、速さは cm/s、加速は cm/s²、時間は秒）：

入力（キー割り当ては付与したときに足し、外さずに残す）：
- `GrabAction : input_action(logic) = Character.WeaponPrimary` — 押すとつかむ。振っているあいだは押し直すと縮める（空きがあれば次の点にもかける）。
- `GrabMapping : input_mapping = Character.RangedWeaponMapping` — `GrabAction` を含む割り当て。
- `ReleaseAction : input_action(logic) = Character.Jump` — 振っているあいだ押し続けると加速、離すとロープを外す。地面で待っているあいだは押すと振り出す。
- `ReleaseMapping : input_mapping = Character.TraversalMapping` — `ReleaseAction` を含む割り当て。
- `ReelOutAction : input_action(logic) = Character.WeaponSecondary` — 振っているあいだ押していると伸ばす。地面で待っているあいだは押すとロープを外す。
- `ReelOutMapping : input_mapping = Character.RangedWeaponMapping` — `ReelOutAction` を含む割り当て。

つかむ：
- `MaxRangeCm : float = 4000.0` — つかめる距離（100〜20000）。ロープを伸ばせる長さの上限にもなる。
- `GrabRadiusCm : float = 50.0` — つかむ判定の球の半径（0〜500）。0 なら点で判定する。
- `GrabGraceSeconds : float = 0.5` — レティクルが外れても、最後に見つけた点をつかめる時間（0〜3）。
- `GrabBufferSeconds : float = 0.3` — つかんでいるあいだの押下が、離す前この秒数以内なら、離した直後のつかみに使う（0〜1）。
- `GrabLiftHeightCm : float = 20.0` — 地面から振り出す前に、位置を直接動かして持ち上げる高さ（0〜300）。
- `GrabKickSpeedCmPerSecond : float = 300.0` — 振り出す瞬間に、動いている向きへ足す速さ（0〜3000）。
- `GroundLaunchMultiplier : float = 2.0` — 地面でつかんでジャンプで振り出したときの勢い（振り出しの速さと振り始めの速さ）の倍率（1〜10）。
- `LandingGraceSeconds : float = 1.0` — 振り出してから、地面に触れても着地とみなさない時間（0〜5）。

ロープ：
- `MinRopeLengthCm : float = 200.0` — ロープを縮められる一番短い長さ（50〜5000）。
- `ReelSpeedCmPerSecond : float = 500.0` — 押して縮める・伸ばす速さ（0〜5000）。
- `RopeCorrectionRate : float = 5.0` — はみ出した長さを毎秒引き戻す割合（0〜50。大きいほど硬い）。
- `AutoReelSeconds : float = 1.0` — 振り子が始まってから、ロープを自動で縮める時間（0〜5。0 なら縮めない）。
- `AutoReelRatio : float = 0.67` — 振り出したときの長さの、どこまで自動で縮めるか（0.1〜1。1 なら縮めない）。
- `MaxRopeCorrectionSpeedCmPerSecond : float = 1000.0` — はみ出しを引き戻す速さの上限（0〜5000）。

離す・加速：
- `ReleaseBoostCmPerSecond : float = 600.0` — 離したときに、動いている向きへ足す速さ（0〜5000）。
- `HoldAccelerationCmPerSecondSquared : float = 1000.0` — 振っているあいだ `ReleaseAction` を押し続けたときの加速（0〜10000）。
- `MaxHoldSpeedCmPerSecond : float = 4500.0` — 長押しで加速しているあいだの速さの上限（100〜15000。`MaxSwingSpeedCmPerSecond` より小さければそちらを使う）。

振り子：
- `SwingStartSpeedCmPerSecond : float = 400.0` — 振り出してから `SwingEaseSeconds` かけて足す速さの合計（0〜5000）。
- `SwingEaseSeconds : float = 0.3` — 振り始めの速さを足し終えるまでの時間（0.05〜3）。
- `SwingGravityCmPerSecondSquared : float = 980.0` — 振り子の計算で使う重力（0〜6000）。
- `SwingSteerAccelerationCmPerSecondSquared : float = 300.0` — 見ている向きへ足す加速（0〜5000）。
- `SwingDrag : float = 0.15` — 空気の抵抗（0〜5。毎秒、速さのこの割合が減る）。
- `MaxSwingSpeedCmPerSecond : float = 2500.0` — 振り子の速さの上限（100〜10000）。

マルチスイング・引っ張り：
- `MaxRopes : int = 1` — 同時にかけられるロープの本数（1〜5）。
- `PullerCorrectionRatio : float = 0.5` — 相手（ほかの agent）にロープをかけているあいだ、自分が引き戻される強さの倍率（0〜1）。
- `ReelPullSpeedCmPerSecond : float = 800.0` — 「ロープを引く」で引かれた人が引き寄せられる速さ（0〜6000）。
- `ReelPullLengthCm : float = 1000.0` — 「ロープを引く」で引き寄せる長さ（0〜20000）。
- `FollowDistanceRatio : float = 0.25` — 相手にかけて地面で待っているとき、`MaxRangeCm` のこの倍まで離れたらついていく（0.05〜1）。

`swing_modifier_component`（どれも既定は変えない値）：
- `RangeMultiplier` / `SpeedMultiplier` / `AccelerationMultiplier` / `BoostMultiplier` / `ReelMultiplier : float = 1.0` — つかめる距離・速さの上限（長押しの上限も）・加速（振り出し・見ている向き・長押し）・離す勢い・巻き取りの速さの倍率（0〜10）。
- `ExtraRopes : int = 0` — 同時にかけられるロープの本数に足す数（-4〜4。合計は 1 本より少なくならない）。
- `AllowGrab : logic = true` — false にすると新しくつかめない（つかんでいるロープは外さない）。

ModifierKit・TargetKit：
- `swing_modifier_all_component.ApplyOnBegin : logic = false` — true なら開始から全員に掛ける。false なら起動の合図から停止の合図まで。
- `swing_modifier_grant_component.DurationSeconds : float = 10.0` — 依頼を受けてから掛け続ける時間（秒。0〜600）。同じ人がまた受けると数え直す。0 なら停止の合図まで。
- `swing_life_component.LifeSeconds : float = 5.0` — 最初につかまれてから壊れるまで（秒。0.5〜120。放しても延びない。点滅の時間も含む）。
- `swing_life_component.BlinkCount : int = 3` / `BlinkSeconds : float = 0.9` — 壊れる直前の点滅の回数（1〜10）と時間（0.1〜10 秒）。
- `swing_lift_component.TravelCm : vector3 = vector3{Up := 4000.0}` — 振り出されたときに動く向きと距離（cm）。
- `swing_lift_component.SpeedCmPerSecond : float = 800.0` — 動く速さ（50〜6000）。スイングの引き戻す速さの上限より速いと、つかんでいる人が外れやすい。

## イベント
能力から（`swing_ability_component` が、その人の slot の下へ `player_event` に包んで SendDown し、能力の entity からも SendUp する。受け手は HUD などの view。消費しない）：
- `swing_target_changed_event`（scene_event）: `Ability : swing_ability_component`、`Agent : agent`、`CanGrab : logic` — 待機中、レティクルの先をつかめるかが変わった（0.1 秒ごとに確かめる）。
- `swing_state_changed_event`（scene_event）: `Ability`、`Agent`、`State : swing_state` — 状態が変わった。
- `swing_grabbed_event`（scene_event）: `Ability`、`Agent`、`Anchor : entity` — ロープを 1 本かけた（`Anchor` は `swing_anchor_component` 付きの点）。
- `swing_rope_detached_event`（scene_event）: `Ability`、`Agent`、`Anchor : entity` — ロープが 1 本外れた（点が壊れた・離れすぎた・つかんだ物が消えた）。
- `swing_released_event`（scene_event）: `Ability`、`Agent` — ロープをすべて外して離した（自分で離した・点が壊れた・`Release`）。
- `swing_reel_hint_event`（scene_event）: `Ability`、`Agent`、`Holder : ?agent` — 地面で、自分にロープをかけている人を見ている／見なくなった（`false`）。「ロープを引く」の案内用。
- `swing_stats_changed_event`（scene_event）: `Ability`、`Agent`、`Stats : swing_stats` — その人に掛かる倍率が変わった。

つかまれた物へ（スイングが、当たった entity へ SendDown する。受け手はその entity の `swing_target_component` と子孫の見た目。消費しない）：
- `swing_attached_event`（ロープをかけられた）、`swing_pulled_event`（その点を起点に振り出された。振り出すたびに届く。地面で待っているあいだは届かない）、`swing_detached_event`（その点のロープが外れた）。どれも `Ability : swing_ability_component`、`Agent : agent`、`Anchor : entity`。

TargetKit から（自分の entity へ SendDown。受け手は同じ entity・子孫の見た目。消費しない）：
- `swing_life_changed_event`（scene_event）: `Life : swing_life_component`、`RemainingRatio : float`（1 → 0）、`Visible : logic`（点滅中に false）。0.1 秒ごとと、最後の点滅で届く。
- `swing_lift_changed_event`（scene_event）: `Lift : swing_lift_component`、`Active : logic` — 動き出したとき（`Active := true`）。

listenable（外から Signal はできない）：
- `swing_ability_component.StateChangedEvent : listenable(tuple(agent, swing_state))` — だれかの状態が変わるたび。
- `swing_ability_component.GrabbedEvent : listenable(tuple(agent, entity))` — ロープを 1 本かけるたび（つかんだ点の entity）。
- `swing_ability_component.RopeDetachedEvent : listenable(tuple(agent, entity))` — ロープが 1 本外れるたび。
- `swing_ability_component.ReleasedEvent : listenable(agent)` — すべて外して離したとき。
- `swing_target_component.AttachedEvent` / `PulledEvent` / `DetachedEvent : listenable(agent)`、`ShatteredEvent : listenable(tuple())`（`Shatter` で 1 回だけ）。
- `swing_anchor_component.BrokenEvent : listenable(tuple())`（`Break` で 1 回だけ）。
- `swing_modifier_component.ChangedEvent : listenable(tuple())` — 掛ける相手が変わったとき。

受けるもの：
- `swing_modifier_request_event`（scene_event）: `Sender : entity`、`Agent : agent` — 送り手（強化のアイテム・触れる物など）が `swing_modifier_grant_component` の entity へ SendDown / SendUp すると、その人に期限付きで倍率を掛ける。消費しない。
- `swing_modifier_all_component` は `activated_event` / `deactivated_event`。`swing_modifier_grant_component` は `deactivated_event`（全員から外す）。
- `swing_target_component` は `swing_attached_event` / `swing_pulled_event` / `swing_detached_event`。

## 状態の問い合わせ（タグ）
スイングの今の状態を確かめる入口は、その人（`agent`）に付くタグだけです（能力・台帳には問い合わせの関数がありません）。
- `swinging_tag`（`controlled_movement_tag` の派生）：つかんでいるあいだ（地面で待つ・振っている。状態が `Idle` 以外）付いています。実際に付くのは派生の `swing_anchored_tag`（`Anchored`：地面でロープだけかけて待っている）か `swing_pendulum_tag`（`Swinging`：振り子で振っている）で、どちらも `swinging_tag` の型で見つかります。状態が変わると付け替え、`Idle` に戻ったとき・剥奪されたときに外します。付け外しは能力が `player_tag_holder`（PlayerSystem）で行います。
- コードからは `Agent.IsSwinging[]`（スイング中なら成功）か `Agent.GetSwingState()`（`swing_state`）で読みます。どちらもタグを見るだけです。
- SwingSystem を知らないほかの System は `Agent.HasPlayerTag[swinging_tag]`（動きを操られているかなら `controlled_movement_tag`）で確かめます。引力（GravitySystem）やホバー（HoverSystem）は、このタグが付いた人の速度を書き換えません。
- 状態が変わったときに知りたいなら、`swing_ability_component.StateChangedEvent` か `swing_state_changed_event`（slot の下と能力の entity から上へ届く）を使います。

## 公開 API
```verse
swing_state<public> := enum:
    Idle         # ロープをかけていない
    Anchored     # 地面でロープだけかけて待っている
    Swinging     # 振り子で振っている

swinging_tag<public> := class(controlled_movement_tag):
swing_anchored_tag<public> := class(swinging_tag):         # Anchored のあいだ
swing_pendulum_tag<public> := class(swinging_tag):         # Swinging のあいだ
(Agent:agent).IsSwinging<public>()<decides><reads>:void    # swinging_tag が付いていれば成功
(Agent:agent).GetSwingState<public>()<reads>:swing_state   # タグから読む。無ければ Idle

swing_ability_component<public> := class<final_super>(ability_component):
    # @editable は「設定」の項を参照（Name<public>:type）
    StateChangedEvent<public><final>:listenable(tuple(agent, swing_state))
    GrabbedEvent<public><final>:listenable(tuple(agent, entity))
    RopeDetachedEvent<public><final>:listenable(tuple(agent, entity))
    ReleasedEvent<public><final>:listenable(agent)
    Release<public>(Agent:agent):void                       # つかんでいれば離させる（加速は足さない）
    # Grant / Revoke / RevokeAll / IsGranted / GetGrantedAgents / GrantedEvent / RevokedEvent は ability_component から

swing_registry_component<public> := class<final_super>(component):
    GetStats<public>(Agent:agent)<transacts>:swing_stats     # 掛かっている倍率をすべて重ねた結果

swing_anchor_component<public> := class<final_super>(component):
    var<private> Broken<public>:logic = false
    BrokenEvent<public><final>:listenable(tuple())
    Break<public>():void                                     # 2 回目以降は何もしない

swing_target_component<public> := class<final_super>(component):
    AttachedEvent<public><final>:listenable(agent)
    PulledEvent<public><final>:listenable(agent)
    DetachedEvent<public><final>:listenable(agent)
    ShatteredEvent<public><final>:listenable(tuple())
    WasAttached<public>()<decides><transacts>:void
    WasPulled<public>()<decides><transacts>:void
    IsShattered<public>()<decides><transacts>:void
    GetAnchorCount<public>()<transacts>:int
    Shatter<public>()<suspends>:void                         # ロープを途切れさせ、1 フレーム後に entity を消す

swing_modifier<public> := struct:
    RangeMultiplier<public>:float = 1.0
    SpeedMultiplier<public>:float = 1.0
    AccelerationMultiplier<public>:float = 1.0
    BoostMultiplier<public>:float = 1.0
    ReelMultiplier<public>:float = 1.0
    ExtraRopes<public>:int = 0
    AllowGrab<public>:logic = true

swing_stats<public> := struct:
    RangeScale<public>:float = 1.0
    SpeedScale<public>:float = 1.0
    AccelerationScale<public>:float = 1.0
    BoostScale<public>:float = 1.0
    ReelScale<public>:float = 1.0
    ExtraRopes<public>:int = 0
    CanGrab<public>:logic = true

(Stats:swing_stats).Apply<public>(Modifier:swing_modifier)<transacts>:swing_stats   # 倍率は掛け、本数は足し、つかめるかは両方 true のときだけ

swing_modifier_component<public> := class<final_super>(component):
    RangeMultiplier<public>:float
    SpeedMultiplier<public>:float
    AccelerationMultiplier<public>:float
    BoostMultiplier<public>:float
    ReelMultiplier<public>:float
    ExtraRopes<public>:int
    AllowGrab<public>:logic
    ChangedEvent<public><final>:listenable(tuple())
    GetModifier<public>()<transacts>:swing_modifier
    IsAppliedTo<public>(Agent:agent)<decides><transacts>:void
    ApplyToAll<public>():void           # 回数を数える。RemoveFromAll と同じ回数で外れる
    RemoveFromAll<public>():void
    ApplyTo<public>(Agent:agent):void   # 回数を数える。RemoveFrom と同じ回数で外れる
    RemoveFrom<public>(Agent:agent):void

swing_target_changed_event<public> := class(scene_event):
    Ability<public>:swing_ability_component
    Agent<public>:agent
    CanGrab<public>:logic
swing_state_changed_event<public> := class(scene_event):
    Ability<public>:swing_ability_component
    Agent<public>:agent
    State<public>:swing_state
swing_grabbed_event<public> := class(scene_event):     # swing_rope_detached_event・swing_attached_event・swing_pulled_event・swing_detached_event も同じ形
    Ability<public>:swing_ability_component
    Agent<public>:agent
    Anchor<public>:entity
swing_released_event<public> := class(scene_event):
    Ability<public>:swing_ability_component
    Agent<public>:agent
swing_reel_hint_event<public> := class(scene_event):
    Ability<public>:swing_ability_component
    Agent<public>:agent
    Holder<public>:?agent
swing_stats_changed_event<public> := class(scene_event):
    Ability<public>:swing_ability_component
    Agent<public>:agent
    Stats<public>:swing_stats
swing_modifier_request_event<public> := class(scene_event):
    Sender<public>:entity
    Agent<public>:agent

# ModifierKit
swing_modifier_all_component<public> := class<final_super>(component):
    ApplyOnBegin<public>:logic
    IsApplying<public>()<decides><transacts>:void
swing_modifier_grant_component<public> := class<final_super>(component):
    DurationSeconds<public>:float
    IsApplyingTo<public>(Agent:agent)<decides><transacts>:void
    Request<public>(Agent:agent):void   # swing_modifier_request_event を受けたのと同じ
swing_modifier_condition_component<public> := class<final_super>(component):
    IsApplying<public>()<decides><transacts>:void

# TargetKit
swing_life_component<public> := class<final_super>(component):
    LifeSeconds<public>:float
    BlinkCount<public>:int
    BlinkSeconds<public>:float
swing_life_changed_event<public> := class(scene_event):
    Life<public>:swing_life_component
    RemainingRatio<public>:float
    Visible<public>:logic
swing_lift_component<public> := class<final_super>(component):
    TravelCm<public>:vector3
    SpeedCmPerSecond<public>:float
swing_lift_changed_event<public> := class(scene_event):
    Lift<public>:swing_lift_component
    Active<public>:logic
```

## 前提・注意
- 区画（または世界）に `player_manager_component`（slot へ送るため）と `swing_registry_component`（任意）を置きます。能力はどちらも、見つかるまで探し、見つけたら覚えます。
- `swing_registry_component` が無くてもスイングは動きますが、ロープを引く・倍率（`swing_modifier_component`）は使えません。状態の問い合わせ（タグ）は台帳が無くても使えます。
- つかむ判定は、レティクルの向きへ半径 `GrabRadiusCm` の球を飛ばして当たった点です。当たり判定のある物ならつかめ、`swing_target_component` は要りません（壊れる・動くなどの振る舞いが要るときだけ付ける）。カメラとキャラクターのあいだの物と、自分の持ち物は除きます。
- ほかの agent（参加者のキャラクターか、その持ち物）にもロープをかけられます。そのときは相手が離れるとついていき（`FollowDistanceRatio`）、相手が地面からレティクルで自分を見て射撃を押すと「ロープを引く」で引き寄せられます。相手にかけたロープは `MaxRangeCm` より離れても外れません。
- 振り子は自分で計算し、毎フレーム（`TickEvents.PrePhysics`）`SetLinearVelocity` で入れます。地面から振り出すときは `GrabLiftHeightCm` だけ位置を直接持ち上げます（MovementSystem の `LiftBy`）。
- 地面・着地・相手との距離・レティクルの先は知らせ（イベント）が無いので、0.1 秒ごとに確かめます。倍率は、台帳が変化を知らせたときだけ読み直します。
- キー割り当て（`GrabMapping` / `ReleaseMapping` / `ReelOutMapping`）は付与したときに足し、剥奪しても外しません。
- 演出：能力の entity に `fort_item_ability_component` があれば、振っているあいだ `ItemEquippedAbilities` をその人に使います。
- `RunFor` の頭で `AwaitPlayerInput` を使い、入力が取れるまで待ちます。プレイヤーでない agent では動きません（出力ログに `[swing_ability_component] プレイヤーでない agent に付与されました…` と出ます）。
- 能力の側は持ち主を見ません。ロードアウトなど slot の下に置いたときに持ち主だけに付与されるのは、付与の component（`ability_grant_players_component` / `ability_grant_condition_component`）の働きです（AbilitySystem）。
- `swing_lift_component` は位置を毎フレーム `SetGlobalTransform` で動かすので、mover と同じ entity には置きません。`swing_life_component` は mover と同じ entity にも置けます。
- タグを agent に付けることは、PlayerSystem の `⚠ 未検証`（`PlayerTags.verse`：agent に付けたタグの付け外し・`ContainsTag` が実機で動くか）に頼っています。
- このフォルダのコードに `⚠ 未検証` と `@experimental` の API はありません。動きの詳しいことは `SwingRunner.verse` 先頭の説明にあります。

## 確かめ方
- テスト：`_Test/SwingSystemTest/` の `swing_system_test_component`。`player_manager_component` を付けた entity と `swing_registry_component` を付けた entity を 1 つずつ（同じ区画に）置き、テスト用の entity に `swing_system_test_component` と `swing_ability_component` を付けます（付与の component は付けない。テストがコードから `Grant` / `Revoke` する）。倍率の重ね方、`Grant` と待機中の状態、状態のタグ（`swing_anchored_tag` / `swing_pendulum_tag` と `IsSwinging` / `GetSwingState`。テストがタグを付け外しする）、倍率の登録と `swing_modifier_grant_component` の期限、寿命の的・リフトの的（テストが実行時に作り、`swing_attached_event` / `swing_pulled_event` を送る）、`Revoke` を確かめます。`RunHumanTests`（既定 true）なら、ログの案内に従ってレティクルを `MaxRangeCm` 以内のメッシュに向けて射撃を押します（`HumanTimeoutSeconds` 既定 30 秒。届かなければ `[SKIP]`）。人の操作の確認のため、プレイヤーから見える位置に当たり判定のあるメッシュを置きます。人の操作を除いて約 6 秒です。結果は出力ログの `[TEST] SwingSystem`。
- 見本：`_Samples/AbilitySample/` の `ability_sample_component`。`swing_ability_component` を付けた entity に一緒に付けると、各プレイヤーが `ToggleAction`（既定 E / RB）で自分への付与を切り替えられます。ログは `[ability_sample]`。

## 移行が要るもの（2026-11-08）
状態の問い合わせをタグ（`swinging_tag`）に一本化しました。
- `swing_ability_component.GetState(Agent)` → `Agent.GetSwingState()`、`swing_ability_component.IsSwinging[Agent]` → `Agent.IsSwinging[]`。
- `swing_registry_component.GetState(Agent)` / `IsSwinging[Agent]` → 同上。`GetSwingingAgents()` は無くなった（参加者を回して `Agent.IsSwinging[]` で絞る）。
- `swing_registry_component.StateChangedEvent` は無くなった → `swing_ability_component.StateChangedEvent` か `swing_state_changed_event`（能力の entity から上へ・slot の下へ）。
- タグは `swinging_tag` そのものではなく派生の `swing_anchored_tag` / `swing_pendulum_tag` が付く。`HasPlayerTag[swinging_tag]` は前と同じに成功する（派生も見つかる）。
