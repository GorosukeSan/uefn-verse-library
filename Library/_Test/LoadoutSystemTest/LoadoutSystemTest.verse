using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { LoadoutSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { _Test }

# 役割：LoadoutSystem の動作確認。ApplyTo で slot の下にロードアウトができ（持ち主が決まる）、2 回目は増えない、同じ Group のほかのロードアウトは外れる、RemoveFrom で消えることを確かめる
# テストのレベル：player_manager_component を付けた entity を 1 つと、この component を付けた entity を 1 つ。プレイヤー 1 人以上で始める（参加を最大 10 秒待つ）
# 結果：出力ログの [TEST] LoadoutSystem
loadout_system_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "LoadoutSystem"}
        TickEvents.PrePhysics.Await()
        if (Manager := Entity.FindScopedComponent[player_manager_component]):
            if (Manager.GetPlayerCount() = 0):
                Arrived := AwaitWithin(Manager.PlayerAddedEvent, 10.0)
                if (not Arrived?):
                    Results.Fail("setup", "no player joined within 10 s")
            if (Slot := Manager.GetSlots()[0]):
                Run(Results, Slot.Player)
        else:
            Results.Fail("setup", "player_manager_component not found")
        if (Results.Finish[]) {}

    Run<private>(Results:test_log, Agent:agent):void =
        # 同じ型の component は 1 つの entity に 1 つまでなので、ロードアウトごとに entity を分ける
        Holder := entity{}
        FirstEntity := entity{}
        SecondEntity := entity{}
        First := loadout_component{Entity := FirstEntity, ApplyToEveryone := false, Group := "class"}
        Second := loadout_component{Entity := SecondEntity, ApplyToEveryone := false, Group := "class"}
        FirstEntity.AddComponents(array{First})
        SecondEntity.AddComponents(array{Second})
        Holder.AddEntities(array{FirstEntity, SecondEntity})
        Entity.AddEntities(array{Holder})

        Applied := First.ApplyTo(Agent)
        Results.Check("ApplyTo succeeds", Applied)
        Results.Check("IsAppliedTo", if (First.IsAppliedTo[Agent]) then true else false)
        if (Instance := First.FindInstance[Agent]):
            Results.Check("instance owner is the player", if (Owner := Instance.FindOwningPlayer[], Owner = Agent) then true else false)
            Results.Check("instance has loadout_instance_component", if (Instance.FindLoadoutInstance[].Source = First) then true else false)
        else:
            Results.Fail("FindInstance", "no instance")
        First.ApplyTo(Agent)
        Results.CheckInt("second ApplyTo does not duplicate", First.GetAppliedAgents().Length, 1)

        Second.ApplyTo(Agent)
        Results.Check("same group: second applied", if (Second.IsAppliedTo[Agent]) then true else false)
        Results.Check("same group: first removed", if (First.IsAppliedTo[Agent]) then false else true)

        Second.RemoveFrom(Agent)
        Results.Check("RemoveFrom removes", if (Second.IsAppliedTo[Agent]) then false else true)
        Holder.RemoveFromParent()
