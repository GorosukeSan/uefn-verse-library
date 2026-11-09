using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { SceneGraphSystem }
using { SwingSystem }

# 役割：条件（直下の子の condition_component の派生）を満たしているあいだ、同じ entity の swing_modifier_component の倍率を全プレイヤー（途中参加も）に掛ける。満たさなくなったら外す
# 置き方：エディターで、swing_modifier_component と同じ entity に付ける
# 子：condition_component の派生を付けた entity を直下に 1 つ（複数の条件は condition_all / condition_any でまとめる）
swing_modifier_condition_component<public> := class<final_super>(component):

    var<private> Active:logic = false
    var<private> Subscription:?cancelable = false

    # 掛けているあいだ（条件を満たしているあいだ）成功する
    IsApplying<public>()<decides><transacts>:void =
        Active?

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Condition := Entity.FindChildComponent[condition_component]):
            set Subscription = option{Condition.ChangedEvent.Subscribe(OnConditionChanged)}
            OnConditionChanged(if (Condition.IsSatisfied[]) then true else false)

    OnEndSimulation<override>():void =
        Subscription.CancelIfSet()
        set Subscription = false
        OnConditionChanged(false)
        (super:)OnEndSimulation()

    OnConditionChanged<private>(Satisfied:logic):void =
        if (Satisfied?):
            if (not Active?, Modifier := Entity.GetComponent[swing_modifier_component]):
                set Active = true
                Modifier.ApplyToAll()
        else if (Active?):
            set Active = false
            if (Modifier := Entity.GetComponent[swing_modifier_component]):
                Modifier.RemoveFromAll()
