using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SwingSystem }
using { SwingSystem.TooltipKit }

# 役割：寿命の的。同じ entity の swing_target_component が最初につかまれた時点から LifeSeconds 経つと、Shatter で壊す（放しても延びない。つかんでいる人のスイングは途切れる）
# 知らせ：0.1 秒ごとに残りの割合（1 → 0）を swing_life_changed_event で自分の entity へ送り、最後の BlinkSeconds は BlinkCount 回、Visible を切り替えて点滅を知らせる（見た目の切り替え用）
# 置き方：エディターで、swing_target_component と同じ entity に付ける（スイングでつかませたいキューブ）。mover と同じ entity にも置ける。実行時に作るときも同じ（swing_target_component{Entity := E} と swing_life_component{Entity := E, LifeSeconds := 5.0} を一緒に AddComponents する）
# 同じ entity：swing_target_component（必須）、当たり判定のあるメッシュ。見た目を変えるなら swing_life_changed_event を受ける component
swing_life_component<public> := class<final_super>(component):

    # 最初につかまれてから壊れるまでの時間（秒。既定 5）。最後の点滅の時間も含む
    @editable_number(float):
        ToolTip := SwingLifeSecondsToolTip
        Categories := array{SwingCategory, SwingLifeCategory}
        MinValue := option{0.5}
        MaxValue := option{120.0}
    LifeSeconds<public>:float = 5.0
    # 壊れる直前に点滅する回数（既定 3）
    @editable_number(int):
        ToolTip := SwingLifeBlinkCountToolTip
        Categories := array{SwingCategory, SwingLifeCategory}
        MinValue := option{1}
        MaxValue := option{10}
    BlinkCount<public>:int = 3
    # 壊れる直前に点滅する時間（秒。既定 0.9）
    @editable_number(float):
        ToolTip := SwingLifeBlinkSecondsToolTip
        Categories := array{SwingCategory, SwingLifeCategory}
        MinValue := option{0.1}
        MaxValue := option{10.0}
    BlinkSeconds<public>:float = 0.9

    # 残りを知らせる間隔（秒）。見た目の更新用なので毎フレームにはしない
    NotifyIntervalSeconds<private>:float = 0.1

    OnSimulate<override>()<suspends>:void =
        MaybeTarget := Entity.AwaitSwingTarget(TickEvents.PrePhysics)
        if (Target := MaybeTarget?):
            if (not Target.WasAttached[]):
                Target.AttachedEvent.Await()
            RunCountdown()
            Target.Shatter()

    RunCountdown<private>()<suspends>:void =
        Life := Max(LifeSeconds, 0.01)
        StartTime := GetSimulationElapsedTime()
        SteadySeconds := Max(Life - BlinkSeconds, 0.0)
        loop:
            Elapsed := GetSimulationElapsedTime() - StartTime
            if (Elapsed >= SteadySeconds):
                break
            Entity.SendDown(swing_life_changed_event{Life := Self, RemainingRatio := 1.0 - Elapsed / Life, Visible := true})
            Sleep(NotifyIntervalSeconds)
        Remaining := Min(BlinkSeconds, Life) / Life
        HalfSeconds := BlinkSeconds / (2.0 * (Max(BlinkCount, 1) * 1.0))
        var Count:int = 0
        loop:
            if (Count >= BlinkCount):
                break
            Entity.SendDown(swing_life_changed_event{Life := Self, RemainingRatio := Remaining, Visible := false})
            Sleep(HalfSeconds)
            Entity.SendDown(swing_life_changed_event{Life := Self, RemainingRatio := Remaining, Visible := true})
            Sleep(HalfSeconds)
            set Count += 1

# 寿命の的（swing_life_component）の残り。0.1 秒ごとと、最後の点滅で届く
# 向き：swing_life_component が自分の entity へ SendDown する。受け手：同じ entity・子孫の見た目の component。消費しない
swing_life_changed_event<public> := class(scene_event):
    # 送り元
    Life<public>:swing_life_component
    # 残りの割合（1 → 0）
    RemainingRatio<public>:float
    # 点滅中に false になる（見た目を隠す）
    Visible<public>:logic
