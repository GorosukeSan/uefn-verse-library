using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { CharacterSystem }
using { CharacterSystem.TooltipKit }

# 役割：独自キャラクターが State（地面・空中・上昇・落下・動いている・止まっている）のあいだ満たす条件
#   ability_grant_condition_component の子に置くと「空中にいるあいだだけ使える能力」、enable の部品と組むと「動いているあいだだけ光る」などをコードなしで作れる
#   毎フレーム（体が動いたあと）状態を見て、変わったときだけ知らせる
# 置き方：エディターで、独自キャラクターの entity（character_motor_component と同じ entity）の子孫に付ける
# 親：ability_grant_condition_component / game_transition_component / condition_all / condition_any の entity の直下
character_motor_condition_component<public> := class<final_super>(condition_component):

    # 満たす状態。既定 Airborne
    @editable:
        ToolTip := MotorConditionStateToolTip
        Categories := array{CharacterEventCategory}
    State<public>:character_motor_state = character_motor_state.Airborne

    var<private> Satisfied:logic = false
    var<private> Motor:?character_motor_component = false
    var<private> Subscription:?cancelable = false

    IsSatisfied<override>()<decides><transacts>:void =
        Satisfied?

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := Entity.FindCharacterMotorAbove[]):
            set Motor = option{Found}
            set Subscription = option{Found.PostMoveEvent.Subscribe(OnPostMove)}
        else:
            Print("[character_motor_condition_component] character_motor_component が見つかりません（独自キャラクターの entity の子孫に置いてください）")

    OnEndSimulation<override>():void =
        if (Current := Subscription?):
            Current.Cancel()
        set Subscription = false
        (super:)OnEndSimulation()

    OnPostMove<private>(DeltaTime:float):void =
        if (Found := Motor?):
            Now := logic{Found.IsInState[State]}
            if (Now <> Satisfied):
                set Satisfied = Now
                NotifyChanged()
