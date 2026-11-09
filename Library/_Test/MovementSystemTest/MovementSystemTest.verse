using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { MovementSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { _Test }

# 役割：MovementSystem の動作確認。最初に参加したプレイヤーで、FindGlobalTranslation が取れること、LiftBy で真上へ指定のセンチメートルだけ動くこと、GetViewDirection が長さ 1 であること、GetViewOrigin がキャラクターの近く（3 メートル以内）にあることを確かめる（Verse の座標への変換の向きが逆だと、視点がキャラクターから離れる）
# テストのレベル：
#   - player_manager_component を付けた entity を 1 つ
#   - このテストの component を、どこかの entity に付ける。プレイヤーの頭の上 3 メートルは空けておく
# 結果：出力ログの [TEST] MovementSystem
movement_system_test_component<public> := class<final_super>(component):

    LiftCm<private>:float = 200.0

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "MovementSystem"}
        MaybeAgent := AwaitFirstPlayer()
        if (Agent := MaybeAgent?, FortCharacter := Agent.GetFortCharacter[]):
            TestCharacter(Results, FortCharacter)
        else:
            Results.Fail("setup", "no player_manager_component, no player or no character")
        if (Results.Finish[]) {}

    TestCharacter<private>(Results:test_log, FortCharacter:fort_character)<suspends>:void =
        TickEvents.PrePhysics.Await()
        if (Before := FortCharacter.FindGlobalTranslation[]):
            Results.Pass("FindGlobalTranslation")
            FortCharacter.LiftBy(LiftCm)
            if (After := FortCharacter.FindGlobalTranslation[]):
                Results.CheckFloat("LiftBy moves straight up by HeightCm", After.Up - Before.Up, LiftCm, 1.0)
                Results.CheckFloat("LiftBy keeps the horizontal position", Distance(vector3{Forward := After.Forward, Left := After.Left}, vector3{Forward := Before.Forward, Left := Before.Left}), 0.0, 1.0)
            else:
                Results.Fail("LiftBy moves straight up by HeightCm", "position not available")
            TickEvents.PrePhysics.Await()
            Direction := FortCharacter.GetViewDirection()
            Results.CheckFloat("GetViewDirection has length 1", Direction.Length(), 1.0, 0.01)
            if (Now := FortCharacter.FindGlobalTranslation[]):
                Results.Check("GetViewOrigin is within 3 m of the character (Verse coordinates)", if (Distance(FortCharacter.GetViewOrigin(), Now) < 300.0) then true else false)
        else:
            Results.Fail("FindGlobalTranslation", "failed")

    AwaitFirstPlayer<private>()<suspends>:?agent =
        if (Manager := Entity.FindScopedComponent[player_manager_component]):
            if (Slot := Manager.GetSlots()[0]):
                option{Slot.Player}
            else:
                Player := Manager.PlayerAddedEvent.Await()
                option{Player}
        else:
            false
