using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { PlayerSystem }

# スイングの状態。Idle = ロープをかけていない、Anchored = 地面でロープだけかけて待っている、Swinging = 振り子で振っている
swing_state<public> := enum:
    Idle
    Anchored
    Swinging

# スイング中（ロープをかけている：地面で待つ・振っている）の人（agent）に付くタグ。スイングの状態を確かめる入口はこのタグ（と、それを読む下の IsSwinging / GetSwingState）だけ
# 実際に付くのは派生の swing_anchored_tag（地面で待つ）か swing_pendulum_tag（振っている）。どちらも swinging_tag の型で見つかる。swing_ability_component が付け外しする（直接は付けない）
# controlled_movement_tag の派生なので、引力（GravitySystem）やホバー（HoverSystem）はこの人の速度を書き換えない
swinging_tag<public> := class(controlled_movement_tag):

# 地面でロープだけかけて待っている人（swing_state.Anchored）に付くタグ。swinging_tag の派生
swing_anchored_tag<public> := class(swinging_tag):

# 振り子で振っている人（swing_state.Swinging）に付くタグ。swinging_tag の派生
swing_pendulum_tag<public> := class(swinging_tag):

# Agent がスイング中（ロープをかけている：地面で待つ・振っている）なら成功する。swinging_tag を見る（能力・区画の台帳を探さない）
(Agent:agent).IsSwinging<public>()<decides><reads>:void =
    Agent.HasPlayerTag[swinging_tag]

# Agent のスイングの状態。タグから読む（swing_pendulum_tag なら Swinging、ほかの swinging_tag なら Anchored、無ければ Idle）
(Agent:agent).GetSwingState<public>()<reads>:swing_state =
    if (Agent.HasPlayerTag[swing_pendulum_tag]):
        swing_state.Swinging
    else if (Agent.HasPlayerTag[swinging_tag]):
        swing_state.Anchored
    else:
        swing_state.Idle

# State のときに付けるタグを作る（Idle なら false）
MakeSwingStateTag<internal>(State:swing_state)<transacts>:?swinging_tag =
    case (State):
        swing_state.Anchored => option{swing_anchored_tag{}}
        swing_state.Swinging => option{swing_pendulum_tag{}}
        _ => false

# 待機中、レティクルの先をつかめるかが変わった（HUD の照準の色など）
# 向き：swing_ability_component が、その人の slot の下へ player_event に包んで SendDown し、能力の entity から SendUp する。受け手：HUD などの view。消費しない
swing_target_changed_event<public> := class(scene_event):
    # 送り元の能力
    Ability<public>:swing_ability_component
    # 照準を見ている人
    Agent<public>:agent
    # true ならつかめる
    CanGrab<public>:logic

# スイングの状態（swing_state）が変わった。swing_ability_component.StateChangedEvent にも同じ中身が届く（今の状態を問い合わせるなら Agent.GetSwingState()）
# 向き：swing_target_changed_event と同じ（slot の下へ player_event で SendDown ＋ 能力の entity から SendUp）。消費しない
swing_state_changed_event<public> := class(scene_event):
    # 送り元の能力
    Ability<public>:swing_ability_component
    # 状態が変わった人
    Agent<public>:agent
    # 新しい状態
    State<public>:swing_state

# ロープを 1 本かけた（つかんだ）。Anchor はつかんだ点の entity（swing_anchor_component 付き）。swing_ability_component.GrabbedEvent にも届く
# 向き：swing_target_changed_event と同じ。消費しない
swing_grabbed_event<public> := class(scene_event):
    # 送り元の能力
    Ability<public>:swing_ability_component
    # ロープをかけた人
    Agent<public>:agent
    # つかんだ点の entity（swing_anchor_component 付き）
    Anchor<public>:entity

# ロープをすべて外して離した（自分で離した・点が壊れた・Release で離させた）。swing_ability_component.ReleasedEvent にも届く
# 向き：swing_target_changed_event と同じ。消費しない
swing_released_event<public> := class(scene_event):
    # 送り元の能力
    Ability<public>:swing_ability_component
    # 離した人
    Agent<public>:agent

# 地面にいて、自分にロープをかけている人（Holder）をレティクルで見ている／見なくなった（Holder := false）。「ロープを引く」の案内用
# 向き：swing_target_changed_event と同じ。消費しない
swing_reel_hint_event<public> := class(scene_event):
    # 送り元の能力
    Ability<public>:swing_ability_component
    # 案内を出す人
    Agent<public>:agent
    # 引ける相手。見なくなったら false
    Holder<public>:?agent

# 複数かけたロープのうち 1 本だけが外れた（点が壊れた・離れすぎた・つかんだ物が消えた）。swing_ability_component.RopeDetachedEvent にも届く
# 向き：swing_target_changed_event と同じ。消費しない
swing_rope_detached_event<public> := class(scene_event):
    # 送り元の能力
    Ability<public>:swing_ability_component
    # ロープをかけた人
    Agent<public>:agent
    # つかんだ点の entity（swing_anchor_component 付き）
    Anchor<public>:entity

# つかまれた物（レティクルの球が当たった entity）に、ロープをかけられたことを知らせる
# 向き：swing_runner が、当たった entity へ SendDown する。受け手：その entity の swing_target_component（と、その子孫の見た目など）。消費しない
swing_attached_event<public> := class(scene_event):
    # 送り元の能力
    Ability<public>:swing_ability_component
    # ロープをかけた人
    Agent<public>:agent
    # つかんだ点の entity（swing_anchor_component 付き）
    Anchor<public>:entity

# つかまれた物に、その点を起点に振り出した（振り子が始まった）ことを知らせる。振り出すたびに届く
# 向き：swing_attached_event と同じ。消費しない
swing_pulled_event<public> := class(scene_event):
    # 送り元の能力
    Ability<public>:swing_ability_component
    # ロープをかけた人
    Agent<public>:agent
    # つかんだ点の entity（swing_anchor_component 付き）
    Anchor<public>:entity

# つかまれた物に、その点のロープが外れたことを知らせる
# 向き：swing_attached_event と同じ。消費しない
swing_detached_event<public> := class(scene_event):
    # 送り元の能力
    Ability<public>:swing_ability_component
    # ロープをかけた人
    Agent<public>:agent
    # つかんだ点の entity（swing_anchor_component 付き）
    Anchor<public>:entity
