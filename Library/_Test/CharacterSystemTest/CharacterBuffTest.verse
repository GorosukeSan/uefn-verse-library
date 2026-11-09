using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { ActivationSystem }
using { CharacterSystem }
using { CharacterSystem.BuffKit }
using { SceneGraphSystem }
using { _Test }

# 役割：CharacterSystem の変更（character_motor_component.AddModifier）と BuffKit（character_buff_component・character_move_grant_component）の動作確認
#   持ち主のいない体を作り、AddModifier の倍率が掛け合わせになること・Cancel で元に戻ること（2 回目の Cancel は何もしない）、
#   体の子に置いた character_buff_component / character_move_grant_component が起動の合図で重ね、停止の合図と entity を消したときに外すことを見る
# テストのレベル：この component を付けた entity を 1 つ（プレイヤーは要らない。体は宙に作って重力を 0 にする）
# 結果：出力ログの [TEST] CharacterBuff。約 1 秒
character_buff_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "CharacterBuff"}
        Sleep(0.0)
        Pawn := entity{}
        Pawn.SetGlobalTransform(MakeTranslationTransform(Entity.GetGlobalTranslation() + vector3{Up := 2000.0}))
        Motor := character_motor_component{Entity := Pawn, SpawnAtOwner := false, ResetOnRoundStart := false}
        Pawn.AddComponents(array{Motor})
        Entity.AddEntities(array{Pawn})
        Sleep(0.0)
        Motor.SetGravityScale(0.0)

        # AddModifier：掛け合わせと Cancel
        First := Motor.AddModifier(character_modifier{SpeedMultiplier := 1.5, ExtraAirJumps := 1})
        Second := Motor.AddModifier(character_modifier{SpeedMultiplier := 2.0, GravityMultiplier := 0.5, GrantsDash := true})
        Results.CheckFloat("speed multiplies", Motor.GetSpeedMultiplier(), 3.0, 0.001)
        Results.CheckFloat("gravity", Motor.GetGravityMultiplier(), 0.5, 0.001)
        Results.CheckInt("extra air jumps add", Motor.GetExtraAirJumps(), 1)
        Results.Check("dash granted", if (Motor.IsDashGranted[]) then true else false)
        Second.Cancel()
        Second.Cancel()
        Results.CheckFloat("cancel restores speed", Motor.GetSpeedMultiplier(), 1.5, 0.001)
        Results.Check("cancel removes dash grant", if (Motor.IsDashGranted[]) then false else true)
        First.Cancel()
        Results.CheckInt("all canceled", Motor.GetModifierCount(), 0)
        Results.CheckFloat("back to 1", Motor.GetSpeedMultiplier(), 1.0, 0.001)

        # BuffKit：体の子に置いて、起動・停止の合図で重ねる・外す
        Holder := entity{}
        Buff := character_buff_component{Entity := Holder, SpeedMultiplier := 1.5, JumpMultiplier := 1.4}
        Grant := character_move_grant_component{Entity := Holder, ExtraAirJumps := 2, GrantDash := true}
        Holder.AddComponents(array{Buff, Grant})
        Pawn.AddEntities(array{Holder})
        Sleep(0.0)
        Results.CheckInt("nothing before activation", Motor.GetModifierCount(), 0)
        Holder.SendActivated()
        Results.CheckFloat("buff speed", Motor.GetSpeedMultiplier(), 1.5, 0.001)
        Results.CheckFloat("buff jump", Motor.GetJumpMultiplier(), 1.4, 0.001)
        Results.CheckInt("grant air jumps", Motor.GetExtraAirJumps(), 2)
        Results.Check("grant dash", if (Motor.IsDashGranted[]) then true else false)
        Holder.SendActivated()
        Results.CheckInt("second activation does not stack", Motor.GetModifierCount(), 2)
        Holder.SendDeactivated()
        Results.CheckInt("deactivation removes", Motor.GetModifierCount(), 0)
        Holder.SendActivated()
        Results.CheckInt("reactivation applies", Motor.GetModifierCount(), 2)
        Holder.RemoveFromParent()
        Sleep(0.0)
        Results.CheckInt("removing the entity removes", Motor.GetModifierCount(), 0)
        Results.CheckFloat("speed back to 1", Motor.GetSpeedMultiplier(), 1.0, 0.001)
        Pawn.RemoveFromParent()
        if (Results.Finish[]) {}
