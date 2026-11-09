using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { SceneGraphSystem }
using { SwingSystem }
using { SwingSystem.TooltipKit }

# 役割：リフトの的。同じ entity の swing_target_component を起点に振り出されると（地面で待っているあいだは動かない）、TravelCm だけ SpeedCmPerSecond でまっすぐ動き、着いたら Shatter で壊す（つかんでいる人のスイングは途切れる）
# 知らせ：動き出すときに swing_lift_changed_event{Active := true} を自分の entity へ送る（見た目の切り替え用）
# 置き方：エディターで、swing_target_component と同じ entity に付ける（スイングでつかませたいキューブ）。mover と同じ entity には置かない（位置を取り合う）。実行時に作るときも同じ（swing_target_component と一緒に AddComponents する）
# 同じ entity：swing_target_component（必須）、当たり判定のあるメッシュ。見た目を変えるなら swing_lift_changed_event を受ける component
# 前提・注意：位置は毎フレーム（TickEvents.PrePhysics）SetGlobalTransform で動かす。経過時間は DeltaTime の足し合わせ
swing_lift_component<public> := class<final_super>(component):

    # 振り出されたときに動く向きと距離（センチメートル。既定は真上に 4000）
    @editable:
        ToolTip := SwingLiftTravelToolTip
        Categories := array{SwingCategory, SwingLiftCategory}
    TravelCm<public>:vector3 = vector3{Up := 4000.0}
    # 振り出されたあと動く速さ（センチメートル毎秒。既定 800）
    @editable_number(float):
        ToolTip := SwingLiftSpeedToolTip
        Categories := array{SwingCategory, SwingLiftCategory}
        MinValue := option{50.0}
        MaxValue := option{6000.0}
    SpeedCmPerSecond<public>:float = 800.0

    OnSimulate<override>()<suspends>:void =
        MaybeTarget := Entity.AwaitSwingTarget(TickEvents.PrePhysics)
        if (Target := MaybeTarget?):
            if (not Target.WasPulled[]):
                Target.PulledEvent.Await()
            Entity.SendDown(swing_lift_changed_event{Lift := Self, Active := true})
            Travel()
            Target.Shatter()

    Travel<private>()<suspends>:void =
        Start := Entity.GetGlobalTransform()
        Duration := Max(TravelCm.Length() / Max(SpeedCmPerSecond, 1.0), 0.01)
        var Elapsed:float = 0.0
        loop:
            DeltaTime := TickEvents.PrePhysics.Await()
            set Elapsed += DeltaTime
            Ratio := Min(Elapsed / Duration, 1.0)
            Entity.SetGlobalTransform(Start.WithTranslation(Start.Translation + TravelCm * Ratio))
            if (Ratio >= 1.0):
                break

# リフトの的（swing_lift_component）が動き出した（Active := true）
# 向き：swing_lift_component が自分の entity へ SendDown する。受け手：同じ entity・子孫の見た目の component。消費しない
swing_lift_changed_event<public> := class(scene_event):
    # 送り元
    Lift<public>:swing_lift_component
    # true なら動き出した
    Active<public>:logic
