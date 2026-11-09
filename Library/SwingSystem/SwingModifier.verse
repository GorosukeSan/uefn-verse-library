using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SceneGraphSystem }
using { SwingSystem.TooltipKit }

# スイングの強さを変える倍率の組（値だけ。エディターでは swing_modifier_component に入れる）。いくつも重なるときは Apply で掛け合わせる
swing_modifier<public> := struct:
    # つかめる距離（ロープを伸ばせる長さの上限も）の倍率
    RangeMultiplier<public>:float = 1.0
    # 振り子の速さの上限の倍率
    SpeedMultiplier<public>:float = 1.0
    # 振り出し・見ている向き・長押しの加速の倍率
    AccelerationMultiplier<public>:float = 1.0
    # 離したときに足す速さの倍率
    BoostMultiplier<public>:float = 1.0
    # ロープを縮める・伸ばす速さの倍率
    ReelMultiplier<public>:float = 1.0
    # 同時にかけられるロープの本数に足す数
    ExtraRopes<public>:int = 0
    # false なら新しくつかめない
    AllowGrab<public>:logic = true

# 今かかっている倍率をまとめたもの。swing_registry_component.GetStats が、その人に掛かる swing_modifier_component をすべて重ねて作る
swing_stats<public> := struct:
    # つかめる距離（ロープを伸ばせる長さの上限も）に掛ける倍率
    RangeScale<public>:float = 1.0
    # 振り子の速さの上限に掛ける倍率
    SpeedScale<public>:float = 1.0
    # 振り出し・見ている向き・長押しの加速に掛ける倍率
    AccelerationScale<public>:float = 1.0
    # 離したときに足す速さに掛ける倍率
    BoostScale<public>:float = 1.0
    # ロープを縮める・伸ばす速さに掛ける倍率
    ReelScale<public>:float = 1.0
    # 同時にかけられるロープの本数に足す数
    ExtraRopes<public>:int = 0
    # false なら新しくつかめない
    CanGrab<public>:logic = true

# Modifier を重ねた結果を返す（倍率は掛け、ロープの本数は足し、つかめるかは両方 true のときだけ true）。Stats 自体は変えない
(Stats:swing_stats).Apply<public>(Modifier:swing_modifier)<transacts>:swing_stats =
    swing_stats:
        RangeScale := Stats.RangeScale * Modifier.RangeMultiplier
        SpeedScale := Stats.SpeedScale * Modifier.SpeedMultiplier
        AccelerationScale := Stats.AccelerationScale * Modifier.AccelerationMultiplier
        BoostScale := Stats.BoostScale * Modifier.BoostMultiplier
        ReelScale := Stats.ReelScale * Modifier.ReelMultiplier
        ExtraRopes := Stats.ExtraRopes + Modifier.ExtraRopes
        CanGrab := if (Stats.CanGrab?, Modifier.AllowGrab?) then true else false

# ある人に掛かる倍率（swing_stats）が変わった
# 向き：swing_ability_component が、その人の slot の下へ player_event に包んで SendDown し、能力の entity から SendUp する。受け手：HUD などの view。消費しない
swing_stats_changed_event<public> := class(scene_event):
    # 送り元の能力
    Ability<public>:swing_ability_component
    # 倍率が変わった人
    Agent<public>:agent
    # 今掛かっている倍率
    Stats<public>:swing_stats

# 依頼：Agent に倍率を掛けてほしい（期限付き）
# 向き：送り手（強化のアイテム・触れる物など）が、swing_modifier_grant_component の entity へ SendDown / SendUp する。受け手：その entity の swing_modifier_grant_component。消費しない
swing_modifier_request_event<public> := class(scene_event):
    # 依頼した物
    Sender<public>:entity
    # 倍率を掛ける人
    Agent<public>:agent

# 役割：スイングの強さを変える倍率（中身）。だれに掛けるかは、この component では決めない
# だれに・いつは、同じ entity に置く ModifierKit の component で選ぶ：
#   - 起動しているあいだ全員 → swing_modifier_all_component
#   - 依頼（swing_modifier_request_event）を受けた人に期限付き → swing_modifier_grant_component
#   - 条件を満たしているあいだ全員 → swing_modifier_condition_component（子に条件）
#   - コードから → ApplyTo / RemoveFrom / ApplyToAll / RemoveFromAll
# 置き方：エディターで entity に付ける（実行時に作ってもよい）。1 entity に 1 つまで
# 知らせ：掛ける相手が変わると ChangedEvent。区画の swing_registry_component に自分を登録し、変わるたびに知らせる（スイング側はそれを受けて倍率を作り直す。毎回探さない）
# 前提：区画（または世界）に swing_registry_component が 1 つ（無いと倍率は効かない）
swing_modifier_component<public> := class<final_super>(component):

    # つかめる距離（ロープを伸ばせる長さの上限も）の倍率（既定 1 = 変えない）
    @editable_number(float):
        ToolTip := SwingModifierRangeToolTip
        Categories := array{SwingCategory, SwingModifierCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    RangeMultiplier<public>:float = 1.0
    # 振り子の速さの上限（長押しの上限も）の倍率（既定 1 = 変えない）
    @editable_number(float):
        ToolTip := SwingModifierSpeedToolTip
        Categories := array{SwingCategory, SwingModifierCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    SpeedMultiplier<public>:float = 1.0
    # 振り出しの勢い・見ている向きへの加速・長押しの加速の倍率（既定 1 = 変えない）
    @editable_number(float):
        ToolTip := SwingModifierAccelerationToolTip
        Categories := array{SwingCategory, SwingModifierCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    AccelerationMultiplier<public>:float = 1.0
    # 離したときに足す速さの倍率（既定 1 = 変えない）
    @editable_number(float):
        ToolTip := SwingModifierBoostToolTip
        Categories := array{SwingCategory, SwingModifierCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    BoostMultiplier<public>:float = 1.0
    # ロープを縮める・伸ばす速さの倍率（既定 1 = 変えない）
    @editable_number(float):
        ToolTip := SwingModifierReelToolTip
        Categories := array{SwingCategory, SwingModifierCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    ReelMultiplier<public>:float = 1.0
    # 同時にかけられるロープの本数に足す数（マイナスで減らす。1 本より少なくはならない。既定 0）
    @editable_number(int):
        ToolTip := SwingModifierExtraRopesToolTip
        Categories := array{SwingCategory, SwingModifierCategory}
        MinValue := option{-4}
        MaxValue := option{4}
    ExtraRopes<public>:int = 0
    # false にすると新しくつかめない（つかんでいるロープは外さない。既定 true）
    @editable:
        ToolTip := SwingModifierAllowGrabToolTip
        Categories := array{SwingCategory, SwingModifierCategory}
    AllowGrab<public>:logic = true

    var<private> AllCount:int = 0
    var<private> AgentCounts:[agent]int = map{}
    var<private> Registry:?swing_registry_component = false

    ChangedEventInternal<private><final>:event() = event(){}

    # 掛ける相手が変わったときに届く（Await / Subscribe する。外から Signal はできない）
    ChangedEvent<public><final>:listenable(tuple()) = MakeProxyListenable(ChangedEventInternal)

    # この component の倍率（値の組）
    GetModifier<public>()<transacts>:swing_modifier =
        swing_modifier:
            RangeMultiplier := RangeMultiplier
            SpeedMultiplier := SpeedMultiplier
            AccelerationMultiplier := AccelerationMultiplier
            BoostMultiplier := BoostMultiplier
            ReelMultiplier := ReelMultiplier
            ExtraRopes := ExtraRopes
            AllowGrab := AllowGrab

    # Agent に掛かっているなら成功する（全員に掛けている・その人に掛けている、のどちらか）
    IsAppliedTo<public>(Agent:agent)<decides><transacts>:void =
        AllCount > 0 or AgentCounts[Agent] > 0

    # 全員に掛ける（回数を 1 増やす。RemoveFromAll と同じ回数呼ぶと外れる。ほかの付け元の分には触らない）
    ApplyToAll<public>():void =
        set AllCount += 1
        if (AllCount = 1):
            NotifyChanged()

    # ApplyToAll を 1 回取り消す。0 になったら全員分を外す（ApplyTo で掛けた人には掛かったまま）
    RemoveFromAll<public>():void =
        if (AllCount > 0):
            set AllCount -= 1
            if (AllCount = 0):
                NotifyChanged()

    # Agent に掛ける（回数を 1 増やす。RemoveFrom と同じ回数呼ぶと外れる）
    ApplyTo<public>(Agent:agent):void =
        Count := GetAgentCount(Agent)
        if (set AgentCounts[Agent] = Count + 1) {}
        if (Count = 0):
            NotifyChanged()

    # ApplyTo を 1 回取り消す。掛けていなければ何もしない
    RemoveFrom<public>(Agent:agent):void =
        Count := GetAgentCount(Agent)
        if (Count > 0):
            if (set AgentCounts[Agent] = Count - 1) {}
            if (Count = 1):
                NotifyChanged()

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Register()

    OnEndSimulation<override>():void =
        set AllCount = 0
        set AgentCounts = map{}
        if (Current := Registry?):
            Current.RemoveModifier(Self)
        set Registry = false
        (super:)OnEndSimulation()

    GetAgentCount<private>(Agent:agent)<transacts>:int =
        if (Count := AgentCounts[Agent]) then Count else 0

    # 区画の registry を 1 回だけ探して登録する（見つからなければ、次に変わったときにもう一度探す）
    Register<private>():void =
        if (not Registry?, Found := Entity.ResolveScopedComponent(Registry, swing_registry_component)?):
            set Registry = option{Found}
            Found.AddModifier(Self)

    NotifyChanged<private>():void =
        Register()
        ChangedEventInternal.Signal()
        if (Current := Registry?):
            Current.NotifyModifiersChanged()
