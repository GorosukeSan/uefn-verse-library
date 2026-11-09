using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Input }
using { InputSystem }
using { MovementSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { CharacterSystem }
using { CharacterSystem.TooltipKit }

# 歩く向きを何に合わせるか
character_walk_space<public> := enum:
    # 持ち主の視点（カメラ）の水平の向きを前にする（3D のアクション）
    View
    # 世界の向き（前 = Forward、左 = Left）。横スクロールや見下ろし型
    World
    # キャラクターの向き（この entity の前）
    Facing
    # 横から見る 2D（横スクロール）。入力の左右で世界の前後（右 = 前）に動き、入力の前後は使わない。体の AxisLock を Left にして使う
    SideView

# 役割：入力で水平に歩く・走る。地面では、入力の向き（前後・左右）に、MaxSpeedCmPerSecond まで AccelerationCmPerSecondSquared で加速し、入力が無ければ BrakingCmPerSecondSquared で止まる
#   入力は 3 通り（足し合わせる）：MoveAction（方向の入力。input_action(vector3)）、ForwardAction / BackAction / LeftAction / RightAction（ボタン 4 つ）、コードからの SetMoveInput（タッチ UI・AI・実験的な Character.Move など）
#   SprintAction を押しているあいだは SprintMultiplier 倍。体に重ねた変更（character_modifier の SpeedMultiplier。BuffKit）も掛ける
#   切り返し（地面）：入力の向きが今の動きと逆向きなら、加速に TurnAroundMultiplier を掛ける
#   空中：加速は AccelerationCmPerSecondSquared × AirControlRatio、切り返しは逆向きの度合いに応じてさらに最大 × AirTurnAroundMultiplier（TurnAroundMultiplier の代わり）、入力が無いときの減速は BrakingCmPerSecondSquared × AirBrakingRatio（小さいので勢いが残る）
#     KeepAirMomentum なら、上限より速い分（はじき・打ち上げで得た速さ）は、入力の向きへ曲げるだけで減らさない（逆向きに入れたときだけ減らす）。入力で上限より速くはならない。dash の突進の速さは、dash が終わるときに上限までに切るので残らない
#     動く床から受け継いだ速度（体の GetInheritedVelocity。SurfaceKit の character_ride_component）の分は、入力が無くても減速しない（跳んでも床と一緒に進む）。逆向きに入れる・壁に当たると減り、減った分は戻らない
#   ほかの部品（dash の突進）が速度を決めているあいだ（体の IsMoveOverridden）は、速度を変えない
#   体の LockInput で入力を止めているあいだは、どの入力も 0 として扱う（減速だけ続く。空中では AirBrakingRatio の弱い減速。TankTurn でも回さない）
#   左右の入力のしかた（character_side_style）はここが持つ：Turn（左右へ動き、体は動く向きへ回る）・Strafe（左右へ動くが体は前を向いたまま）・TankTurn（左右でその場で回り、前後は体の向きへ動く）
#   今のしかた = 体に重ねた変更（character_modifier の SideStyle）があればそれ、無ければ基本（SideStyle。SetSideStyle・SideStyleToggleAction で変わる）。変わると SideStyleChangedEvent に届く
#   体の向きは、Turn / Strafe なら BodyKit の character_face_movement_component が回す（このしかたを読む）。TankTurn ならこの部品が回す
# 置き方：エディターで、character_motor_component と同じ entity に付ける
# 前提：持ち主（ロードアウトの中など）がいて、入力の割り当て（input_mapping）がその人に足されていること（BodyKit の character_input_mapping_component で足せる）
# 前提・注意：体に重ねた変更で左右の入力のしかたが変わったときは、次のフレームの動きの前に SideStyleChangedEvent に届く（変更を足す処理からは知らせを出せないため、毎フレーム見比べる）
# ⚠ 未検証：MoveAction の値の向き（Forward = 前、Left = 左として読む）
character_walk_component<public> := class<final_super>(component):

    # 方向の入力（前後・左右）。使わなければ空
    @editable:
        ToolTip := WalkMoveActionToolTip
        Categories := array{CharacterWalkCategory}
    MoveAction<public>:?input_action(vector3) = false
    # 前へ進むボタン。使わなければ空
    @editable:
        ToolTip := WalkButtonToolTip
        Categories := array{CharacterWalkCategory}
    ForwardAction<public>:?input_action(logic) = false
    # 後ろへ進むボタン
    @editable:
        ToolTip := WalkButtonToolTip
        Categories := array{CharacterWalkCategory}
    BackAction<public>:?input_action(logic) = false
    # 左へ進むボタン
    @editable:
        ToolTip := WalkButtonToolTip
        Categories := array{CharacterWalkCategory}
    LeftAction<public>:?input_action(logic) = false
    # 右へ進むボタン
    @editable:
        ToolTip := WalkButtonToolTip
        Categories := array{CharacterWalkCategory}
    RightAction<public>:?input_action(logic) = false
    # 押しているあいだ走るボタン。使わなければ空
    @editable:
        ToolTip := WalkSprintActionToolTip
        Categories := array{CharacterWalkCategory}
    SprintAction<public>:?input_action(logic) = false
    # 歩く向きを何に合わせるか。既定 View
    @editable:
        ToolTip := WalkSpaceToolTip
        Categories := array{CharacterWalkCategory}
    Space<public>:character_walk_space = character_walk_space.View
    # 歩く速さの上限（cm/s）。既定 600
    @editable_number(float):
        ToolTip := WalkMaxSpeedToolTip
        Categories := array{CharacterWalkCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    MaxSpeedCmPerSecond<public>:float = 600.0
    # 加速（cm/s²）。既定 4000
    @editable_number(float):
        ToolTip := WalkAccelerationToolTip
        Categories := array{CharacterWalkCategory}
        MinValue := option{0.0}
        MaxValue := option{100000.0}
    AccelerationCmPerSecondSquared<public>:float = 4000.0
    # 入力が無いときの減速（cm/s²）。既定 5000
    @editable_number(float):
        ToolTip := WalkBrakingToolTip
        Categories := array{CharacterWalkCategory}
        MinValue := option{0.0}
        MaxValue := option{100000.0}
    BrakingCmPerSecondSquared<public>:float = 5000.0
    # 空中で入力の向きへ加速するときの、加速（AccelerationCmPerSecondSquared）に掛ける倍率（0 で空中では操作できない、1 で地上と同じ）。入力が無いときの減速は AirBrakingRatio。既定 0.6
    @editable_number(float):
        ToolTip := WalkAirControlToolTip
        Categories := array{CharacterWalkCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    AirControlRatio<public>:float = 0.6
    # 空中で入力が無いときの、減速（BrakingCmPerSecondSquared）に掛ける倍率（0 で減速しない、1 で地上と同じ）。小さいほど勢いが残る。既定 0.2
    #   既定で 1000 cm/s²（600 cm/s が 0 になるまで約 0.6 秒。短いジャンプでは勢いが残り、長いジャンプの終わりにはほぼ止まる。0.1 では氷の上のように流れ続けた）
    @editable_number(float):
        ToolTip := WalkAirBrakingToolTip
        Categories := array{CharacterWalkCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    AirBrakingRatio<public>:float = 0.2
    # 空中の切り返しのとき、空中の加速に掛ける倍率の上限（地上の TurnAroundMultiplier の代わり）。入力の向きが今の水平の動きと逆向きなほど大きく掛かる（真横で 1 倍、真逆でこの倍率）。既定 2
    #   既定で真逆なら 4800 cm/s²（600 cm/s から逆向きの 600 cm/s まで約 0.25 秒。地上の切り返し 8000 cm/s² の 0.6 倍＝ AirControlRatio とそろう）
    @editable_number(float):
        ToolTip := WalkAirTurnAroundToolTip
        Categories := array{CharacterWalkCategory}
        MinValue := option{1.0}
        MaxValue := option{10.0}
    AirTurnAroundMultiplier<public>:float = 2.0
    # オンなら、空中で上限より速い分（はじき・打ち上げで得た速さ）を、入力の向きへ曲げるだけで減らさない（逆向きに入れたときだけ減らす）。オフなら空中でも入力の速さへ近づける（上限まで減らす）。既定オン
    #   dash の突進の速さは、dash が終わるときに上限までに切るので、ここでは残らない
    @editable:
        ToolTip := WalkKeepAirMomentumToolTip
        Categories := array{CharacterWalkCategory}
    KeepAirMomentum<public>:logic = true
    # 走るときの速さの倍率。既定 1.6
    @editable_number(float):
        ToolTip := WalkSprintMultiplierToolTip
        Categories := array{CharacterWalkCategory}
        MinValue := option{1.0}
        MaxValue := option{10.0}
    SprintMultiplier<public>:float = 1.6
    # 地面の切り返し（入力の向きが今の水平の動きと 90 度より大きく違う）のとき、加速に掛ける倍率。1 なら普通の加速と同じ。空中は AirTurnAroundMultiplier。既定 2
    @editable_number(float):
        ToolTip := WalkTurnAroundToolTip
        Categories := array{CharacterWalkCategory}
        MinValue := option{1.0}
        MaxValue := option{10.0}
    TurnAroundMultiplier<public>:float = 2.0
    # 左右の入力でどうするか（基本の値）。Turn = 左右へ動き体は動く向きへ回る、Strafe = 左右へ動くが体は前を向いたまま（カニ歩き）、TankTurn = 左右ではその場で回り前後は体の向きへ動く。既定 Turn
    @editable:
        ToolTip := WalkSideStyleToolTip
        Categories := array{CharacterWalkCategory}
    SideStyle<public>:character_side_style = character_side_style.Turn
    # TankTurn のとき、左右の入力で 1 秒に回る角度（度）。既定 180
    @editable_number(float):
        ToolTip := WalkTankTurnSpeedToolTip
        Categories := array{CharacterWalkCategory}
        MinValue := option{0.0}
        MaxValue := option{3600.0}
    TankTurnDegreesPerSecond<public>:float = 180.0
    # 押すたびに、左右の入力のしかた（基本）を SideStyle と ToggleSideStyle で切り替えるボタン。使わなければ空
    @editable:
        ToolTip := WalkSideStyleToggleActionToolTip
        Categories := array{CharacterWalkCategory}
    SideStyleToggleAction<public>:?input_action(logic) = false
    # SideStyleToggleAction で切り替える先。既定 Strafe
    @editable:
        ToolTip := WalkToggleSideStyleToolTip
        Categories := array{CharacterWalkCategory}
    ToggleSideStyle<public>:character_side_style = character_side_style.Strafe

    # 切り替えのボタンの押しを、この秒数以内なら受け付ける（毎フレーム見るので 1 フレームより長ければよい）
    ToggleBufferSeconds<private>:float = 0.25

    var<private> Motor:?character_motor_component = false
    var<private> ExternalInput:vector3 = vector3{}
    var<private> Subscriptions:[]cancelable = array{}
    # SetSideStyle・切り替えで変えた基本の左右の入力のしかた（false なら SideStyle のまま）
    var<private> BaseSideStyle:?character_side_style = false
    # 最後に SideStyleChangedEvent で知らせた（か開始時の）今のしかた
    var<private> NotifiedSideStyle:?character_side_style = false
    # 最後のフレームの入力の向き（世界の水平。長さ 0〜1。GetInputDirection）
    var<private> InputDirection:vector3 = vector3{}
    Axis<private>:character_axis_tracker = character_axis_tracker{}
    Forward<private>:character_button_tracker = character_button_tracker{}
    Back<private>:character_button_tracker = character_button_tracker{}
    Left<private>:character_button_tracker = character_button_tracker{}
    Right<private>:character_button_tracker = character_button_tracker{}
    Sprint<private>:character_button_tracker = character_button_tracker{}
    SideToggle<private>:character_button_tracker = character_button_tracker{}

    SideStyleChangedEventInternal<private><final>:event(character_side_style) = event(character_side_style){}

    # 今の左右の入力のしかた（GetSideStyle）が変わるたびに、新しいしかたで届く（SetSideStyle・切り替えのボタン・体に重ねた変更のどれで変わっても）
    SideStyleChangedEvent<public><final>:listenable(character_side_style) = MakeProxyListenable(SideStyleChangedEventInternal)

    # コードから歩く入力を入れる（Forward = 前、Left = 左。長さ 1 まで）。入れた値は次に入れるまで残る（止めるなら vector3{}）
    SetMoveInput<public>(Input:vector3):void =
        set ExternalInput = Input

    # 今の左右の入力のしかた。体に重ねた変更（character_modifier の SideStyle）があればそれ、無ければ基本（GetBaseSideStyle）
    GetSideStyle<public>()<transacts>:character_side_style =
        if (Found := Motor?, Override := Found.GetSideStyleOverride[]) then Override else GetBaseSideStyle()

    # 基本の左右の入力のしかた（SetSideStyle・切り替えで変えたもの。変えていなければ SideStyle）
    GetBaseSideStyle<public>()<transacts>:character_side_style =
        if (Base := BaseSideStyle?) then Base else SideStyle

    # 基本の左右の入力のしかたを Style にする。体に重ねた変更が SideStyle を決めているあいだは、その変更が外れてから効く。今のしかたが変わったら SideStyleChangedEvent に届く
    SetSideStyle<public>(Style:character_side_style):void =
        set BaseSideStyle = option{Style}
        NotifySideStyle()

    # 基本を SideStyle と ToggleSideStyle で切り替える（SideStyleToggleAction を押したのと同じ。基本が ToggleSideStyle なら SideStyle へ、ほかなら ToggleSideStyle へ）
    SwitchSideStyle<public>():void =
        SetSideStyle(if (GetBaseSideStyle() = ToggleSideStyle) then SideStyle else ToggleSideStyle)

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := Entity.FindCharacterMotorAbove[]):
            set Motor = option{Found}
            set Subscriptions += array{Found.PreMoveEvent.Subscribe(OnPreMove)}
        else:
            Print("[character_walk_component] character_motor_component が見つかりません（同じ entity か祖先に置いてください）")
        # 開始時のしかたは知らせない（変わったときだけ知らせる）
        set NotifiedSideStyle = option{GetSideStyle()}

    OnSimulate<override>()<suspends>:void =
        if (Found := Motor?, Owner := Found.FindOwner[]):
            MaybeInput := Owner.AwaitPlayerInput()
            if (PlayerInput := MaybeInput?):
                if (Action := MoveAction?):
                    set Subscriptions += Axis.Listen(PlayerInput, Action)
                if (Action := ForwardAction?):
                    set Subscriptions += Forward.Listen(PlayerInput, Action)
                if (Action := BackAction?):
                    set Subscriptions += Back.Listen(PlayerInput, Action)
                if (Action := LeftAction?):
                    set Subscriptions += Left.Listen(PlayerInput, Action)
                if (Action := RightAction?):
                    set Subscriptions += Right.Listen(PlayerInput, Action)
                if (Action := SprintAction?):
                    set Subscriptions += Sprint.Listen(PlayerInput, Action)
                if (Action := SideStyleToggleAction?):
                    set Subscriptions += SideToggle.Listen(PlayerInput, Action)

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        (super:)OnEndSimulation()

    OnPreMove<private>(DeltaTime:float):void =
        # 体の LockInput で入力を止めているあいだは、入力を 0 として扱う（切り替えのボタンの押しは捨てる。止まるまでの減速だけ続く）
        Locked := if (Found := Motor?, Found.IsInputLocked[]) then true else false
        if (SideToggle.ConsumePress[ToggleBufferSeconds]):
            if (not Locked?):
                SwitchSideStyle()
        # 体に重ねた変更が付いた・外れたことも、ここで見比べて知らせる
        NotifySideStyle()
        if (Found := Motor?):
            Raw := if (Locked?) then vector3{} else GetRawInput()
            TurnsBody := SideInputTurnsBody(GetSideStyle())
            # TankTurn：左右の入力は体を回すだけ（先に回して、前後はその向きへ動く）。入力を止めているあいだは Raw が 0 なので回らない
            if (TurnsBody?):
                TurnBody(Found, Clamp(Raw.Left, -1.0, 1.0), DeltaTime)
            Input := if (TurnsBody?) then vector3{Forward := Clamp(Raw.Forward, -1.0, 1.0)} else LimitLength(Raw)
            Basis := GetBasis(Found)
            Direction := Basis(0) * Input.Forward + Basis(1) * Input.Left
            set InputDirection = Direction
            # ほかの部品（dash の突進）が速度を決めているあいだは、速度を変えない（入力の向きだけ覚える。どの順に動いても突進の距離が変わらない）
            if (Found.IsMoveOverridden[]):
                return
            BaseSpeed := if (Sprint.IsDown[]) then MaxSpeedCmPerSecond * SprintMultiplier else MaxSpeedCmPerSecond
            # 体に重ねた変更（バフ）の倍率を掛ける
            Speed := BaseSpeed * Found.GetSpeedMultiplier()
            Desired := Direction * Speed
            Velocity := Found.GetVelocity()
            Horizontal := vector3{Forward := Velocity.Forward, Left := Velocity.Left}
            HasInput := if (Input.LengthSquared() > 0.0001) then true else false
            Next := if (Found.IsGrounded[]) then GroundStep(Horizontal, Desired, HasInput, DeltaTime) else AirStep(Found, Horizontal, Desired, HasInput, DeltaTime)
            Found.SetVelocity(vector3{Forward := Next.Forward, Left := Next.Left, Up := Velocity.Up})

    # 地面：入力の向きへ加速（切り返しは TurnAroundMultiplier 倍）、入力が無ければ BrakingCmPerSecondSquared で止まる。上限より速ければ入力の速さまで減らす
    GroundStep<private>(Horizontal:vector3, Desired:vector3, HasInput:logic, DeltaTime:float)<transacts>:vector3 =
        # 切り返し：入力の向きが今の水平の動きと逆（90 度より大きく違う）なら、加速に TurnAroundMultiplier を掛ける（止まってから動き直すより早く向きを変えられる）
        Acceleration := if (DotProduct(Desired, Horizontal) < 0.0) then AccelerationCmPerSecondSquared * TurnAroundMultiplier else AccelerationCmPerSecondSquared
        Rate := if (HasInput?) then Acceleration else BrakingCmPerSecondSquared
        MoveToward(Horizontal, Desired, Rate * DeltaTime)

    # 空中：Horizontal を、動く床から受け継いだ分（体の GetInheritedVelocity の向きに、その長さまで）と自分の分に分け、自分の分だけを入力で変える
    #   受け継いだ分が入力（逆向き）・壁で減ったら、体の受け継いだ速度もそこまで縮める（減った分は戻らない。前は、あとで同じ向きに入れると減速しない分として戻っていた）
    #   入力が無い：自分の分を BrakingCmPerSecondSquared × AirBrakingRatio で 0 へ（受け継いだ分は減らさない）
    #   切り返し：入力の向きが自分の分と逆向きなほど、加速に AirTurnAroundMultiplier を掛ける（真横なら 1 倍、真逆で AirTurnAroundMultiplier 倍。前は 90 度を境に急に変わった）
    #   上限より速い（KeepAirMomentum のとき）：入力の向きへ曲げるだけ（速さは変えない）。それ以外：AccelerationCmPerSecondSquared × AirControlRatio で入力の速さへ（入力で上限を超えない）
    #   dash の突進の速さはここに残らない（dash が終わるときに歩く速さの上限までに切る）。上限より速い分として残るのは、はじき・打ち上げなど外から足された速さ
    AirStep<private>(Found:character_motor_component, Horizontal:vector3, Desired:vector3, HasInput:logic, DeltaTime:float)<transacts>:vector3 =
        Inherited := Found.GetInheritedVelocity()
        InheritedCm := Inherited.Length()
        Carried := if (InheritedCm > 0.01) then Inherited * (Clamp(DotProduct(Horizontal, Inherited) / InheritedCm, 0.0, InheritedCm) / InheritedCm) else vector3{}
        if (InheritedCm > 0.01):
            Found.SetInheritedVelocity(Carried)
        Own := Horizontal - Carried
        if (not HasInput?):
            return Carried + MoveToward(Own, vector3{}, BrakingCmPerSecondSquared * AirBrakingRatio * DeltaTime)
        Cap := Desired.Length()
        OwnCm := Own.Length()
        # 逆向きの度合い（0 = 真横か同じ向き、1 = 真逆）
        Opposition := if (OwnCm > 0.01 and Cap > 0.0001) then Max(-DotProduct(Desired, Own) / (Cap * OwnCm), 0.0) else 0.0
        Reversing := if (Opposition > 0.0) then true else false
        Rate := AccelerationCmPerSecondSquared * AirControlRatio * (1.0 + (AirTurnAroundMultiplier - 1.0) * Opposition)
        Step := Rate * DeltaTime
        if (Reversing? or not KeepAirMomentum? or OwnCm <= Cap or Cap <= 0.0001):
            return Carried + MoveToward(Own, Desired, Step)
        # 上限より速い：入力の向きへ Step だけ押してから、もとの速さに戻す（曲がるが、速くも遅くもならない）
        Bent := Own + Desired * (Step / Cap)
        BentCm := Bent.Length()
        Carried + (if (BentCm > 0.0001) then Bent * (OwnCm / BentCm) else Own)

    # 最後のフレームの入力の向き（世界の水平の向き × 入力の強さ。長さ 0〜1）。入力が無い・LockInput で止めているときは vector3{}。TankTurn なら前後の入力だけ（体の向き）
    #   BodyKit の character_face_movement_component が、空中で体を入力の向きへ向けるのに使う
    GetInputDirection<public>()<transacts>:vector3 = InputDirection

    # 診断用：入力の割り当て（MoveAction）から今読めている生の値（変換前。左右の符号は逆のまま＝ Left が正なら右）
    GetRawMoveAxis<public>()<transacts>:vector3 = Axis.GetValue()

    # 今の歩く向きの（前, 左）の単位ベクトル（水平）。入力の（前, 左）をこれで世界の向きに直す。TankTurn なら体の向き（Space は使わない）。SideView なら前は vector3{}
    GetWalkBasis<public>()<transacts>:tuple(vector3, vector3) =
        if (Found := Motor?) then GetBasis(Found) else (vector3{Forward := 1.0}, vector3{Left := 1.0})

    # 今の歩く向きの前（水平の単位ベクトル。GetWalkBasis の前）。Strafe のとき、character_face_movement_component はこの向きへ体を回す。SideView なら vector3{}（前が無い）
    GetWalkFront<public>()<transacts>:vector3 =
        GetWalkBasis()(0)

    # 今のしかた（GetSideStyle）が最後に知らせたものと違えば、SideStyleChangedEvent に届ける
    NotifySideStyle<private>():void =
        Current := GetSideStyle()
        if (Previous := NotifiedSideStyle?, Previous = Current):
            return
        set NotifiedSideStyle = option{Current}
        SideStyleChangedEventInternal.Signal(Current)

    # TankTurn：Turn（-1〜1。正で左回り）× TankTurnDegreesPerSecond で、体（motor の entity）の水平の向きを回す
    TurnBody<private>(Found:character_motor_component, Turn:float, DeltaTime:float):void =
        if (Turn = 0.0 or TankTurnDegreesPerSecond <= 0.0):
            return
        Current := Found.Entity.GetGlobalTransform()
        Yaw := Current.Rotation.GetYawPitchRollDegrees()(0)
        # 「左へ回ると正」の角度をヨーの向きに合わせる（YawSign。CharacterSystem の直下）
        Next := Yaw + Turn * TankTurnDegreesPerSecond * DeltaTime * YawSign()
        Found.Entity.SetGlobalTransform(transform{Translation := Current.Translation, Rotation := MakeRotationFromYawPitchRollDegrees(Next, 0.0, 0.0), Scale := Current.Scale})

    # 入力（Forward = 前、Left = 左）を足し合わせたもの。長さは縮めない
    GetRawInput<private>()<transacts>:vector3 =
        Axis2 := Axis.GetValue()
        # MoveAction（Character.Move）の値は左右の符号が逆（実機 v43.00：A で Left = -1、D で Left = +1。UE の「右が正」のまま入る）なので反転する
        var Sum:vector3 = vector3{Forward := Axis2.Forward + ExternalInput.Forward, Left := -Axis2.Left + ExternalInput.Left}
        if (Forward.IsDown[]):
            set Sum = Sum + vector3{Forward := 1.0}
        if (Back.IsDown[]):
            set Sum = Sum + vector3{Forward := -1.0}
        if (Left.IsDown[]):
            set Sum = Sum + vector3{Left := 1.0}
        if (Right.IsDown[]):
            set Sum = Sum + vector3{Left := -1.0}
        Sum

    # 歩く向きの（前, 左）の単位ベクトル（水平）
    GetBasis<private>(Found:character_motor_component)<transacts>:tuple(vector3, vector3) =
        # TankTurn（左右で体を回すしかた）：前後は体の向きへ（Space は使わない）
        if (SideInputTurnsBody(GetSideStyle())?):
            Facing := Flatten(Found.Entity.GetGlobalTransform().Rotation.GetForwardAxis())
            return (Facing, CrossProduct(vector3{Up := 1.0}, Facing))
        if (Space = character_walk_space.SideView):
            return (vector3{}, vector3{Forward := -1.0})
        Front := case (Space):
            character_walk_space.SideView => vector3{Forward := 1.0}
            character_walk_space.World => vector3{Forward := 1.0}
            character_walk_space.Facing => Flatten(Found.Entity.GetGlobalTransform().Rotation.GetForwardAxis())
            character_walk_space.View =>
                if (Owner := Found.FindOwner[], OwnerCharacter := Owner.GetFortCharacter[]):
                    Flatten(OwnerCharacter.GetViewDirection())
                else:
                    vector3{Forward := 1.0}
        (Front, CrossProduct(vector3{Up := 1.0}, Front))

# Motor が使う walk。まず体（Motor の entity）に付いたもの、無ければその子孫に付いたもの（どれか 1 つ。子孫のどれになるかは決まっていない）。無ければ失敗する
#   BodyKit の character_face_movement_component がこれで探す（自分で作る部品・MCP からも使える）
(Motor:character_motor_component).FindCharacterWalk<public>()<decides><transacts>:character_walk_component =
    Candidates := for (Each : Motor.Entity.FindDescendantComponents(character_walk_component)):
        Each
    OnBody := for (Each : Candidates, Each.Entity = Motor.Entity):
        Each
    (OnBody + Candidates)[0]

# V の上下の成分を消して長さ 1 にする（ほぼ真上・真下なら前）
Flatten<internal>(V:vector3)<transacts>:vector3 =
    Horizontal := vector3{Forward := V.Forward, Left := V.Left}
    Length := Horizontal.Length()
    if (Length > 0.0001) then Horizontal / Length else vector3{Forward := 1.0}

# V の長さを 1 までに縮める
LimitLength<internal>(V:vector3)<transacts>:vector3 =
    Magnitude := V.Length()
    if (Magnitude > 1.0) then V / Magnitude else V

# Current から Target へ、長さ MaxStep まで近づけたベクトル
MoveToward<internal>(Current:vector3, Target:vector3, MaxStep:float)<transacts>:vector3 =
    Gap := Target - Current
    Length := Gap.Length()
    if (Length <= MaxStep or Length <= 0.0001) then Target else Current + Gap * (MaxStep / Length)
