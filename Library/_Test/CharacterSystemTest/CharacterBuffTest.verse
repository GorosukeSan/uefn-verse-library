using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { ActivationSystem }
using { CharacterSystem }
using { CharacterSystem.BuffKit }
using { SceneGraphSystem }
using { _Test }

# Role: verification of CharacterSystem modifiers (character_motor_component.AddModifier) and BuffKit (character_buff_component / character_move_grant_component)
#   Creates an ownerless body and checks that AddModifier multipliers multiply together and that Cancel restores them (a second Cancel does nothing),
#   and that character_buff_component / character_move_grant_component placed under the body stack on the activate signal and are removed on the deactivate signal and when the entity is disposed
# Test level: one entity with this component (no player needed; the body is created in the air with gravity 0)
# Result: [TEST] CharacterBuff in the output log. About 1 second
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

        # AddModifier: multiplication and Cancel
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

        # BuffKit: placed under the body; stacked / removed by the activate / deactivate signals
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
