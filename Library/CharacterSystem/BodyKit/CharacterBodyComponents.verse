using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Input }
using { /Verse.org/Assets }
using { /Fortnite.com/Characters }
using { InputSystem }
using { MovementSystem }
using { PlayerSystem }
using { CharacterSystem }
using { CharacterSystem.MoveKit }
using { CharacterSystem.TooltipKit }

# 役割：キャラクターの向き（体＝ character_motor_component の entity の水平の向き）を TurnSpeedDegreesPerSecond で回す。どこへ向けるかは、体の walk（character_walk_component。体の entity か子孫）の左右の入力のしかた（GetSideStyle）で決める
#   Turn：動いている方向へ（止まっているあいだは変えない）。walk が無いときもこれ
#     空中（AirFacesInput のとき）：walk の入力の向き（GetInputDirection）へ。入力が無ければ変えない（動く床から受け継いだ速さ・はじかれた向きへは回らない）
#   Strafe：walk の歩く向きの前（GetWalkFront。Space = View なら視点の向き）へ。止まっているあいだも回す。前の無い SideView では変えない
#   TankTurn：何もしない（walk が左右の入力で回す）
#   体の LockInput で入力を止めているあいだは回さない
# 置き方：エディターで、character_motor_component と同じ entity に付ける（見た目のメッシュは子に置くと一緒に回る）
# ⚠ 未検証：Yaw の正の向き（左回りか右回りか）。逆に向くなら見た目のメッシュを 180 度回して置く
character_face_movement_component<public> := class<final_super>(component):

    # 1 秒に回る角度（度）。0 ならすぐ向く。既定 720
    @editable_number(float):
        ToolTip := FaceTurnSpeedToolTip
        Categories := array{CharacterBodyCategory}
        MinValue := option{0.0}
        MaxValue := option{100000.0}
    TurnSpeedDegreesPerSecond<public>:float = 720.0
    # オンなら、Turn のとき空中では動いている方向ではなく入力の向きへ回す（入力が無ければ変えない）。オフなら空中でも動いている方向へ。既定オン
    @editable:
        ToolTip := FaceAirFacesInputToolTip
        Categories := array{CharacterBodyCategory}
    AirFacesInput<public>:logic = true

    # walk が見つからないとき、探し直す間隔（秒）
    WalkSearchIntervalSeconds<private>:float = 1.0

    var<private> Motor:?character_motor_component = false
    var<private> Subscription:?cancelable = false
    var<private> CachedWalk:?character_walk_component = false
    var<private> NextWalkSearchAt:float = -1000.0

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := Entity.FindCharacterMotorAbove[]):
            set Motor = option{Found}
            set Subscription = option{Found.PostMoveEvent.Subscribe(OnPostMove)}

    OnEndSimulation<override>():void =
        if (Current := Subscription?):
            Current.Cancel()
        set Subscription = false
        (super:)OnEndSimulation()

    OnPostMove<private>(DeltaTime:float):void =
        # 体の LockInput で入力を止めているあいだは回さない（ロビー・結果の画面で、視点や動きに合わせて向きが変わらないように）
        if (Found := Motor?, not Found.IsInputLocked[]):
            MaybeWalk := FindWalk(Found)
            Style := if (Walk := MaybeWalk?) then Walk.GetSideStyle() else character_side_style.Turn
            # character_side_style に値を足したら、ここに向け方を足す（_ を書かないので、足し忘れるとコンパイルが通らない）
            #   Turn：動いている方向へ。Strafe：walk の歩く向きの前へ。TankTurn：walk が左右の入力で回すので向けない（false）
            Target:?vector3 = case (Style):
                character_side_style.Turn => TurnDirection(Found, MaybeWalk)
                character_side_style.Strafe => WalkFrontDirection(MaybeWalk)
                character_side_style.TankTurn => false
            if (Direction := Target?):
                TurnToward(Found, Direction, DeltaTime)

    # Turn の向ける先：地面では動いている方向。空中（AirFacesInput で walk があるとき）では入力の向き（入力が無ければ false ＝変えない）
    TurnDirection<private>(Found:character_motor_component, MaybeWalk:?character_walk_component)<transacts>:?vector3 =
        if (AirFacesInput?, not Found.IsGrounded[], Walk := MaybeWalk?):
            Input := Walk.GetInputDirection()
            if (Input.Length() > 0.1) then option{Input} else false
        else:
            MovementDirection(Found)

    # 水平に動いている方向（止まっていれば false ＝変えない）
    MovementDirection<private>(Found:character_motor_component)<transacts>:?vector3 =
        Velocity := Found.GetVelocity()
        Horizontal := vector3{Forward := Velocity.Forward, Left := Velocity.Left}
        if (Horizontal.Length() > 1.0) then option{Horizontal} else false

    # Strafe の向ける先：walk の歩く向きの前（walk が無い・前の無い SideView なら false ＝変えない）
    WalkFrontDirection<private>(MaybeWalk:?character_walk_component)<transacts>:?vector3 =
        if (Walk := MaybeWalk?, Front := Walk.GetWalkFront(), Front.Length() > 0.5) then option{Front} else false

    # 体の walk（体の entity か、その子孫。FindCharacterWalk）。見つけたら覚えておき、見つからないあいだは WalkSearchIntervalSeconds ごとに探し直す
    FindWalk<private>(Found:character_motor_component):?character_walk_component =
        if (Cached := CachedWalk?, Cached.IsInScene[]):
            return option{Cached}
        set CachedWalk = false
        Now := GetSimulationElapsedTime()
        if (Now < NextWalkSearchAt):
            return false
        set NextWalkSearchAt = Now + WalkSearchIntervalSeconds
        if (Walk := Found.FindCharacterWalk[]):
            set CachedWalk = option{Walk}
        CachedWalk

    # 体の水平の向きを Direction（水平）へ、TurnSpeedDegreesPerSecond で回す（0 ならすぐ向く）
    TurnToward<private>(Found:character_motor_component, Direction:vector3, DeltaTime:float):void =
        # ArcTan は「左へ回ると正」。MakeRotationFromYawPitchRollDegrees のヨーの正の向きは、90 度で回した前の軸で確かめて合わせる（YawSign。CharacterSystem の直下）
        #   （v43.00 実機：そのまま渡すと左右に動いたときに逆を向いた＝ヨーの正は右回り）
        Target := ArcTan(Direction.Left, Direction.Forward) * 180.0 / PiFloat * YawSign()
        Current := Found.Entity.GetGlobalTransform()
        Yaw := Current.Rotation.GetYawPitchRollDegrees()(0)
        Next := if (TurnSpeedDegreesPerSecond <= 0.0) then Target else StepAngle(Yaw, Target, TurnSpeedDegreesPerSecond * DeltaTime)
        # もう向いていれば書き換えない（Strafe で止まっているあいだ、毎フレーム同じ向きを書かない）
        if (Abs(Next - Yaw) < 0.01):
            return
        Found.Entity.SetGlobalTransform(transform{Translation := Current.Translation, Rotation := MakeRotationFromYawPitchRollDegrees(Next, 0.0, 0.0), Scale := Current.Scale})

# From から To へ、MaxStep 度まで近い向きに回した角度（度）
StepAngle<internal>(From:float, To:float, MaxStep:float)<transacts>:float =
    var Delta:float = To - From
    loop:
        if (Delta <= 180.0):
            break
        set Delta -= 360.0
    loop:
        if (Delta >= -180.0):
            break
        set Delta += 360.0
    if (Abs(Delta) <= MaxStep) then To else From + (if (Delta > 0.0) then MaxStep else -MaxStep)

# 役割：独自キャラクターが動いているあいだ、持ち主の Fortnite のキャラクターを PutInStasis でその場に固定し、見えなくする。止まると元に戻す
#   独自キャラクターは物理・当たり・動きをすべて自前で持ち、Fortnite のキャラクターとは独立して動く。Fortnite のキャラクターは動かさない・付いていかせない（そのための設定も持たない）
# 置き方：エディターで、character_motor_component と同じ entity に付ける
# 前提・注意：持ち主の Fortnite のキャラクターは、独自キャラクターの当たりから除かれる。固定中は Fortnite のキャラクターの移動・視点の入力は効かない（独自キャラクターの入力は input_action で別に受ける）。視点は CameraExperimentalKit の character_camera_component などで独自キャラクターに向ける
character_owner_stasis_component<public> := class<final_super>(component):

    # 固定した位置からこれ以上離れたら固定し直す（cm）
    ReparkDistanceCm<private>:float = 50.0

    var<private> Motor:?character_motor_component = false
    var<private> Subscription:?cancelable = false
    var<private> Parked:?fort_character = false
    # 固定したときの Fortnite のキャラクターの位置。ここから離れたら（出現の途中で固定して、そのあとスポーンパッドへ移されたときなど）固定し直す
    var<private> ParkedAt:vector3 = vector3{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := Entity.FindCharacterMotorAbove[]):
            set Motor = option{Found}
            set Subscription = option{Found.PostMoveEvent.Subscribe(OnPostMove)}
        else:
            Print("[character_owner_stasis_component] character_motor_component が見つかりません（同じ entity か祖先に置いてください）")

    OnEndSimulation<override>():void =
        if (Current := Subscription?):
            Current.Cancel()
        set Subscription = false
        Release()
        (super:)OnEndSimulation()

    # 今固定している Fortnite のキャラクター（無ければ失敗）
    FindParkedCharacter<public>()<decides><transacts>:fort_character = Parked?

    # 持ち主の Fortnite のキャラクターが変わったら（リスポーンなど）固定し直す。毎フレーム見るのは「同じキャラクターか」だけ
    OnPostMove<private>(DeltaTime:float):void =
        if (Found := Motor?, Owner := Found.FindOwner[], OwnerCharacter := Owner.GetFortCharacter[]):
            if (Current := Parked?, Current = OwnerCharacter):
                # 同じキャラクターでも、固定した位置から離れていたら固定が外れている（v43.00 実機：出現の途中で固定すると、スポーンパッドへ移された後は歩けた）
                if (Body := OwnerCharacter.GetEntity[], Distance(Body.GetGlobalTransform().Translation, ParkedAt) > ReparkDistanceCm):
                    Park(OwnerCharacter)
            else:
                Release()
                Park(OwnerCharacter)

    # AllowTurning は視点の入力（Orbit のカメラ・Space = View の歩く向き）を生かすため。体は隠れているので向きが変わっても見えない
    Park<private>(OwnerCharacter:fort_character):void =
        OwnerCharacter.PutInStasis(stasis_args{AllowTurning := true, AllowFalling := false, AllowEmotes := false})
        OwnerCharacter.Hide()
        set Parked = option{OwnerCharacter}
        if (Body := OwnerCharacter.GetEntity[]):
            set ParkedAt = Body.GetGlobalTransform().Translation

    Release<private>():void =
        if (Current := Parked?):
            Current.ReleaseFromStasis()
            Current.Show()
        set Parked = false

# 役割：持ち主に入力の割り当て（input_mapping。独自キャラクターのボタン・方向の入力を入れたもの）を足し、止まると外す
# 置き方：エディターで、独自キャラクターの entity（character_motor_component と同じ entity か子孫）に付ける。持ち主のいる場所（ロードアウトの中）に置く
# 前提・注意：割り当ては 2 つまで（アセットの配列は MCP で書けないため、1 つずつのフィールド）。3 つ以上なら子の entity にこの部品をもう 1 つ置く。RemoveOnEnd は、独自キャラクター専用の割り当てのときだけオンにする（TraversalMapping など Fortnite の割り当てを外すと、ほかの操作もできなくなる）
character_input_mapping_component<public> := class<final_super>(component):

    # 足す入力の割り当て（使わなければ空）
    @editable:
        ToolTip := InputMappingsToolTip
        Categories := array{CharacterBodyCategory}
    Mapping<public>:?input_mapping = false
    # 2 つ目に足す入力の割り当て（使わなければ空）
    @editable:
        ToolTip := InputMappingsToolTip
        Categories := array{CharacterBodyCategory}
    SecondMapping<public>:?input_mapping = false
    # オンなら、止まるときに外す。既定オン
    @editable:
        ToolTip := InputMappingsRemoveToolTip
        Categories := array{CharacterBodyCategory}
    RemoveOnEnd<public>:logic = true

    OnSimulate<override>()<suspends>:void =
        if (Owner := Entity.FindOwningPlayer[]):
            MaybeInput := Owner.AwaitPlayerInput()
            if (PlayerInput := MaybeInput?):
                Mappings := GetMappings()
                for (Each : Mappings):
                    PlayerInput.AddInputMapping(Each)
                defer:
                    if (RemoveOnEnd?):
                        for (Each : Mappings):
                            PlayerInput.RemoveInputMapping(Each)
                Sleep(Inf)
        else:
            Print("[character_input_mapping_component] 持ち主がいません（ロードアウトの中など、持ち主のいる場所に置いてください）")

    GetMappings<private>()<transacts>:[]input_mapping =
        var Result:[]input_mapping = array{}
        if (First := Mapping?):
            set Result += array{First}
        if (Second := SecondMapping?):
            set Result += array{Second}
        Result
