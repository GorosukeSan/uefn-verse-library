using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Input }
using { /Verse.org/Assets }
using { PlayerSystem }
using { SceneGraphSystem }

# Agent が今動かしている独自キャラクターの体（InEntity の区画の player_manager_component から、その人の slot の下を探す）。無ければ失敗する
# 能力の RunFor など、体の外から探すときに使う（Entity.FindCharacterMotorFor[Agent]）
(InEntity:entity).FindCharacterMotorFor<public>(Agent:agent)<decides><transacts>:character_motor_component =
    Manager := InEntity.FindScopedComponent[player_manager_component]
    Slot := Manager.FindSlot[player[Agent]]
    Found := for (Motor : Slot.Entity.FindDescendantComponents(character_motor_component), Owner := Motor.FindOwner[], Owner = Agent):
        Motor
    Found[0]

# InEntity か、その祖先の character_motor_component。独自キャラクターの中でなければ失敗する
(InEntity:entity).FindCharacterMotorAbove<public>()<decides><transacts>:character_motor_component =
    var Current:entity = InEntity
    var Found:?character_motor_component = false
    loop:
        if (Motor := Current.GetComponent[character_motor_component]):
            set Found = option{Motor}
            break
        if (Parent := Current.GetParent[]):
            set Current = Parent
        else:
            break
    Found?

# 役割：ボタンの入力（input_action(logic)）の今の状態を覚える。押した瞬間を秒で覚えるので、先行入力（少し早く押した入力を受け付ける）に使える
character_button_tracker<internal> := class<internal>:
    var<private> Down:logic = false
    var<private> PressedAt:float = -1000.0
    var<private> LastPressedAt:float = -1000.0
    var<private> ReleasedAt:float = -1000.0

    # 押しているあいだ成功する
    IsDown<internal>()<decides><transacts>:void =
        Down?

    # Seconds 秒以内に押されていて、まだ使っていなければ成功し、使ったことにする
    ConsumePress<internal>(WithinSeconds:float)<decides><transacts>:void =
        GetSimulationElapsedTime() - PressedAt <= WithinSeconds
        set LastPressedAt = PressedAt
        set PressedAt = -1000.0

    # ConsumePress で使った押しを、押した時刻のまま戻す（跳べなかった入力を先行入力として残す）
    Rebuffer<internal>():void =
        set PressedAt = LastPressedAt

    # 最後に離してからの秒数
    GetSecondsSinceRelease<internal>()<transacts>:float =
        GetSimulationElapsedTime() - ReleasedAt

    Listen<internal>(PlayerInput:player_input, Action:input_action(logic)):[]cancelable =
        Events := PlayerInput.GetInputEvents(Action)
        array:
            Events.BeginDetectEvent.Subscribe(OnBegin)
            Events.EndDetectEvent.Subscribe(OnEnd)

    OnBegin<private>(Payload:tuple(player, logic)):void =
        set Down = true
        set PressedAt = GetSimulationElapsedTime()

    OnEnd<private>(Payload:tuple(player, float)):void =
        set Down = false
        set ReleasedAt = GetSimulationElapsedTime()

# 役割：方向の入力（input_action(vector3)）の今の値を覚える（離したら 0）
character_axis_tracker<internal> := class<internal>:
    var<private> Value:vector3 = vector3{}

    # 今の値
    GetValue<internal>()<transacts>:vector3 =
        Value

    Listen<internal>(PlayerInput:player_input, Action:input_action(vector3)):[]cancelable =
        Events := PlayerInput.GetInputEvents(Action)
        array:
            Events.BeginDetectEvent.Subscribe(OnBegin)
            Events.DetectionOngoingEvent.Subscribe(OnOngoing)
            Events.EndDetectEvent.Subscribe(OnEnd)

    OnBegin<private>(Payload:tuple(player, vector3)):void =
        set Value = Payload(1)

    OnOngoing<private>(Payload:tuple(player, vector3, float)):void =
        set Value = Payload(1)

    OnEnd<private>(Payload:tuple(player, float)):void =
        set Value = vector3{}
