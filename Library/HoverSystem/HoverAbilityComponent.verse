using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Input }
using { AbilitySystem }
using { EnergySystem }
using { ItemSystem }
using { InputSystem }
using { MovementSystem }
using { PlayerSystem }
using { HoverSystem.TooltipKit }

# ホバーしている人（agent）に付くタグ。hover_ability_component が付け外しする（ほかの System は Agent.HasPlayerTag[hovering_tag] で確かめる）
hovering_tag<public> := class(player_state_tag):

# 方向：hover_ability_component の entity から上へ（SendUp）。ホバーを始めた・やめたときに送る
# 受け手：祖先（アイテムなら持ち主のプレイヤーまで）。演出や HUD。消費しない
hover_changed_event<public> := class(scene_event):
    # 送った能力
    Ability<public>:hover_ability_component
    # ホバーを始めた・やめた人
    Agent<public>:agent
    # true ならホバーを始めた、false ならやめた
    Active<public>:logic

# 役割：ホバーの能力。付与された人が空中で HoverAction（既定は Jump）を押し続けると、落ちる速さを MaxFallSpeedCmPerSecond までに抑えて浮く。
#   エネルギー（FindEnergyFor：この entity か子の energy_component、無ければプレイヤーに付いたもの）があれば、ホバーしているあいだ 1 秒に EnergyPerSecond 使い、0 になるとホバーできない（アイテムは無くならない）。
#   エネルギーの回復はこの能力では持たない（チェックポイントで満たすなら CheckpointSystem の EnergyKit、使って回復するなら EnergySystem の RestoreKit）。動きを操られている人（controlled_movement_tag が付いている。スイング中など）はホバーしない
# 付与の仕方は同じ entity に置く component で選ぶ：
#   - 全員に最初から／起動しているあいだ → ability_grant_players_component（エネルギーをこの entity に置くと全員で分け合う。1 人ずつにするならプレイヤーに付ける）
#   - アイテムとして（装備しているあいだ） → アイテムの entity に item_component・item_holder_component・ability_grant_item_component と一緒に置く（エネルギーはアイテムの entity に）
#   - 条件を満たしているあいだ → ability_grant_condition_component（子に条件）
#   - コードから → Grant / Revoke
# 知らせ：ホバーを始めた・やめたときに HoverChangedEvent と hover_changed_event
# タグ：ホバーしているあいだ、その人（agent）に hovering_tag を付ける
hover_ability_component<public> := class<final_super>(ability_component):

    # ホバーしているあいだの落ちる速さの上限（センチメートル毎秒。既定 100）。0 ならその高さで止まる
    @editable_number(float):
        ToolTip := HoverMaxFallSpeedToolTip
        Categories := array{HoverCategory}
        MinValue := option{0.0}
        MaxValue := option{3000.0}
    MaxFallSpeedCmPerSecond<public>:float = 100.0
    # ホバーしているあいだ 1 秒に使うエネルギー（既定 20）。エネルギーが無ければ減らさない
    @editable_number(float):
        ToolTip := HoverEnergyPerSecondToolTip
        Categories := array{HoverCategory}
        MinValue := option{0.0}
        MaxValue := option{1000.0}
    EnergyPerSecond<public>:float = 20.0
    # 空中で押し続けるとホバーする操作。既定は Jump
    @editable:
        ToolTip := HoverActionToolTip
        Categories := array{HoverCategory, HoverInputCategory}
    HoverAction<public>:input_action(logic) = Character.Jump
    # 付与しているあいだ有効にするキー割り当て。HoverAction を含むもの。既定は TraversalMapping
    @editable:
        ToolTip := HoverMappingToolTip
        Categories := array{HoverCategory, HoverInputCategory}
    HoverMapping<public>:input_mapping = Character.TraversalMapping
    # true なら剥奪したときに HoverMapping を外す（この能力専用の割り当てのときだけ。既定 false）
    @editable:
        ToolTip := HoverRemoveMappingToolTip
        Categories := array{HoverCategory, HoverInputCategory}
    RemoveMappingOnRevoke<public>:logic = false

    HoverChangedEventInternal<private><final>:event(tuple(agent, logic)) = event(tuple(agent, logic)){}

    # だれかがホバーを始めた・やめたときに、（その人, true = 始めた / false = やめた）で届く（Await / Subscribe する。外から Signal はできない）
    HoverChangedEvent<public><final>:listenable(tuple(agent, logic)) = MakeProxyListenable(HoverChangedEventInternal)

    var HoveringTags<private>:player_tag_holder = player_tag_holder{}

    # Agent が今ホバーしている（落ちる速さを抑えている）なら成功する
    IsHovering<public>(Agent:agent)<decides><transacts>:void =
        HoveringTags.Has[Agent]

    RunFor<override>(Agent:agent)<suspends>:void =
        MaybeInput := Agent.AwaitPlayerInput()
        if (PlayerInput := MaybeInput?):
            defer:
                SetHovering(Agent, false)
            race:
                PlayerInput.HoldInputMapping(HoverMapping, RemoveMappingOnRevoke)
                loop:
                    PlayerInput.AwaitPressed(HoverAction)
                    race:
                        PlayerInput.AwaitReleased(HoverAction)
                        HoverWhileHeld(Agent)
                    SetHovering(Agent, false)
        else if (not player[Agent]):
            Print("[hover_ability_component] プレイヤーでない agent に付与されました。入力が取れないので動きません")

    HoverWhileHeld<private>(Agent:agent)<suspends>:void =
        loop:
            DeltaTime := TickEvents.PrePhysics.Await()
            if (FortCharacter := Agent.GetFortCharacter[], CanHover[Agent, FortCharacter]):
                SetHovering(Agent, true)
                Velocity := FortCharacter.GetVelocityCmPerSecond()
                if (Velocity.Up < -MaxFallSpeedCmPerSecond):
                    FortCharacter.SetVelocityCmPerSecond(vector3{Forward := Velocity.Forward, Left := Velocity.Left, Up := -MaxFallSpeedCmPerSecond})
                if (Energy := Entity.FindEnergyFor[Agent]):
                    Energy.Consume(EnergyPerSecond * DeltaTime)
            else:
                SetHovering(Agent, false)

    CanHover<private>(Agent:agent, FortCharacter:fort_character)<decides><transacts>:void =
        FortCharacter.IsInAir[]
        not Agent.HasPlayerTag[controlled_movement_tag]
        if (Energy := Entity.FindEnergyFor[Agent]):
            not Energy.IsEmpty[]

    SetHovering<private>(Agent:agent, Value:logic):void =
        Was := logic{HoveringTags.Has[Agent]}
        if (Was <> Value):
            HoveringTags.Set(Agent, Value, hovering_tag{})
            HoverChangedEventInternal.Signal((Agent, Value))
            Entity.SendUp(hover_changed_event{Ability := Self, Agent := Agent, Active := Value})
