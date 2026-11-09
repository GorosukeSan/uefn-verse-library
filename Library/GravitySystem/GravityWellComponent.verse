using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { MovementSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { GravitySystem.TooltipKit }

# 役割：引力を持つ点。毎フレーム（TickEvents.PrePhysics）、この entity から RadiusCm 以内のプレイヤーを、中心へ向けて StrengthCmPerSecondSquared（中心で最大、RadiusCm で 0）で引く（速度に足す）。動きを操られている人（体に controlled_movement_tag が付いている。スイング中など）は引かない（その動きを優先する）
# 置き方：エディターで entity に付ける（実行時に gravity_point_ability_component が作ることもある）
# 同じ entity：見た目のメッシュ（当たり判定があれば、スイングでもつかめる）
# 前提：区画（または世界）に player_manager_component が 1 つ（引く相手）。最初に 1 度だけ探して覚える（見つかるまでは 1 秒ごとに探し直す）
gravity_well_component<public> := class<final_super>(component):

    # 引力が届く半径（センチメートル。既定 1500）。中心で一番強く、この距離で 0
    @editable_number(float):
        ToolTip := GravityRadiusToolTip
        Categories := array{GravityCategory}
        MinValue := option{100.0}
        MaxValue := option{20000.0}
    RadiusCm<public>:float = 1500.0
    # 中心での引く強さ（センチメートル毎秒毎秒。既定 1200）。毎秒この速さずつ中心へ向かう速さが増える
    @editable_number(float):
        ToolTip := GravityStrengthToolTip
        Categories := array{GravityCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    StrengthCmPerSecondSquared<public>:float = 1200.0

    OnSimulate<override>()<suspends>:void =
        # player_manager_component が見つかるまで、1 秒ごとに探し直す（見つけたら覚えて、二度と探さない）
        Found := Entity.AwaitScopedComponent(player_manager_component)
        loop:
            DeltaTime := TickEvents.PrePhysics.Await()
            PullPlayers(Found, DeltaTime)

    PullPlayers<private>(Found:player_manager_component, DeltaTime:float):void =
        Center := Entity.GetGlobalTranslation()
        for (Slot : Found.GetSlots(), not Slot.Player.HasPlayerTag[controlled_movement_tag]):
            Pull(Slot.Player, Center, DeltaTime)

    Pull<private>(Agent:agent, Center:vector3, DeltaTime:float):void =
        if:
            FortCharacter := Agent.GetFortCharacter[]
            Position := FortCharacter.FindGlobalTranslation[]
            Offset := Center - Position
            Gap := Offset.Length()
            Gap > 1.0
            Gap < RadiusCm
        then:
            Falloff := 1.0 - Gap / RadiusCm
            # GetLinearVelocity / SetLinearVelocity はメートル毎秒なので、センチメートルから直す
            Push := Offset.MakeUnitVector() * (StrengthCmPerSecondSquared / 100.0 * Falloff * DeltaTime)
            FortCharacter.SetLinearVelocity(FortCharacter.GetLinearVelocity() + Push)
