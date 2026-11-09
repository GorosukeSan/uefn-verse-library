using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { EnergySystem }
using { InputSystem }
using { CharacterSystem }
using { CharacterSystem.TooltipKit }

# 役割：入力で、短く鋭く突進する（ブーストではなくダッシュ）。決まった時間・距離だけ速く動き、終わると歩く速さまですぐ落とす
#   1 回の流れ（既定値）：
#     0 秒：向きを決める（walk の入力の向き → 今の水平の動き → 体の向きの順）。水平の速度をその向き × DashSpeedCmPerSecond（2200 cm/s）にする。空中なら上下の速さを 0 にする（水平に出る）
#     0〜DurationSeconds（0.18 秒）：毎フレーム同じ速さで突進する。重力は DashGravityScale 倍（0 = 空中のダッシュは高さが変わらない）。walk は速度を変えない（体の SetMoveOverride）
#       最後のフレームは残りの秒数の分だけ突進の速さで動くので、距離はフレームの長さによらず DashSpeedCmPerSecond × DurationSeconds（396 cm）
#     終わり：ダッシュの向きの速さを「walk の歩く速さの上限（MaxSpeedCmPerSecond × 変更の速さの倍率。走るボタンは含めない）× DashEndSpeedRatio（1.0）」までに切り、横の速さは消す（突進の速さを残さない）
#     CooldownSeconds（0.8 秒。出した瞬間から数える）が過ぎるまで次は出せない
#   突進の途中でジャンプした（jump の Jumped / AirJumped）・入力を止めた（LockInput）ら、その場で終える（速さは同じように切る。ダッシュの速さのまま跳ばない）
#   突進は勢いを置き換える：動く床から受け継いだ速度（体の GetInheritedVelocity）は出した瞬間に消す
#   空中では AirDashes 回まで（地面に降りると戻る）。エネルギー（EnergySystem。この entity か祖先・持ち主に付いた energy_component）があれば EnergyCost を使い、足りなければ出せない
# 置き方：エディターで、character_motor_component と同じ entity に付ける
# 知らせ：出したら character_motor_component の ActionEvent に Dashed
# 外から：Dash（入力なしで出させる。出せたら true）、IsDashing
#   RequiresGrant なら、体に GrantsDash の変更（BuffKit の character_move_grant_component など）があるあいだだけ出せる
#   体の LockInput で入力を止めているあいだは出さない（ボタン・Dash とも。押しは捨てる）。突進の途中で止められたら、その場で終える
# 前提・注意：重力は体の ScaleGravityThisFrame で毎フレーム弱める（SetGravityScale は変えない。ほかの部品が決めた倍率を上書きしない）
character_dash_component<public> := class<final_super>(component):

    # ダッシュのボタン。使わなければ空（コードの Dash で出す）
    @editable:
        ToolTip := DashActionToolTip
        Categories := array{CharacterDashCategory}
    DashAction<public>:?input_action(logic) = false
    # 突進の速さ（cm/s）。既定 2200（DurationSeconds と掛けた距離 396 cm だけ進む）
    @editable_number(float):
        ToolTip := DashSpeedToolTip
        Categories := array{CharacterDashCategory}
        MinValue := option{0.0}
        MaxValue := option{50000.0}
    DashSpeedCmPerSecond<public>:float = 2200.0
    # 突進の時間（秒）。既定 0.18
    @editable_number(float):
        ToolTip := DashDurationToolTip
        Categories := array{CharacterDashCategory}
        MinValue := option{0.01}
        MaxValue := option{5.0}
    DurationSeconds<public>:float = 0.18
    # 突進が終わったときに、ダッシュの向きの速さを落とす先の、walk の歩く速さの上限に掛ける倍率（1 なら歩く速さの上限まで、0 ならその場で止まる）。既定 1
    @editable_number(float):
        ToolTip := DashEndSpeedRatioToolTip
        Categories := array{CharacterDashCategory}
        MinValue := option{0.0}
        MaxValue := option{2.0}
    DashEndSpeedRatio<public>:float = 1.0
    # 突進のあいだ、重力に掛ける倍率（0 なら空中のダッシュは高さが変わらない、1 なら普段どおり落ちる）。既定 0
    @editable_number(float):
        ToolTip := DashGravityScaleToolTip
        Categories := array{CharacterDashCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    DashGravityScale<public>:float = 0.0
    # 次に出せるまでの時間（秒。出した瞬間から数える）。既定 0.8
    @editable_number(float):
        ToolTip := DashCooldownToolTip
        Categories := array{CharacterDashCategory}
        MinValue := option{0.0}
        MaxValue := option{60.0}
    CooldownSeconds<public>:float = 0.8
    # 空中で出せる回数。既定 1
    @editable_number(int):
        ToolTip := DashAirDashesToolTip
        Categories := array{CharacterDashCategory}
        MinValue := option{0}
        MaxValue := option{10}
    AirDashes<public>:int = 1
    # 1 回に使うエネルギー（0 なら使わない）。既定 0
    @editable_number(float):
        ToolTip := DashEnergyCostToolTip
        Categories := array{CharacterDashCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    EnergyCost<public>:float = 0.0
    # オンなら、体に「ダッシュを許す変更」（character_modifier の GrantsDash。BuffKit の character_move_grant_component など）が重なっているあいだだけ出せる（拾ったら使える能力にする）。既定オフ
    @editable:
        ToolTip := DashRequiresGrantToolTip
        Categories := array{CharacterDashCategory}
    RequiresGrant<public>:logic = false

    # walk が見つからないときの、歩く速さの上限（cm/s。終わりの速さを決めるのに使う）
    FallbackWalkSpeedCmPerSecond<private>:float = 600.0

    var<private> Motor:?character_motor_component = false
    var<private> Subscriptions:[]cancelable = array{}
    Button<private>:character_button_tracker = character_button_tracker{}
    var<private> DashLeftSeconds:float = 0.0
    var<private> CooldownLeftSeconds:float = 0.0
    var<private> AirDashesLeft:int = 0
    var<private> Direction:vector3 = vector3{Forward := 1.0}
    # 最後のフレームを突進の速さで動いたので、次のフレームの動きの前に速さを切る
    var<private> CutPending:logic = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := Entity.FindCharacterMotorAbove[]):
            set Motor = option{Found}
            set Subscriptions += array{Found.PreMoveEvent.Subscribe(OnPreMove), Found.ActionEvent.Subscribe(OnAction)}
        else:
            Print("[character_dash_component] character_motor_component が見つかりません（同じ entity か祖先に置いてください）")

    OnSimulate<override>()<suspends>:void =
        if (Found := Motor?, Owner := Found.FindOwner[], Action := DashAction?):
            MaybeInput := Owner.AwaitPlayerInput()
            if (PlayerInput := MaybeInput?):
                set Subscriptions += Button.Listen(PlayerInput, Action)

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        if (Found := Motor?, (IsDashing[] or CutPending?)):
            Found.SetMoveOverride(false)
        set DashLeftSeconds = 0.0
        set CutPending = false
        (super:)OnEndSimulation()

    # 突進しているあいだ成功する
    IsDashing<public>()<decides><transacts>:void =
        DashLeftSeconds > 0.0

    # 入力なしで出させる。待ち時間・空中の回数・エネルギーが足りない、RequiresGrant で許されていない、体の LockInput で止めているなら false
    Dash<public>():logic =
        if (Found := Motor?, not Found.IsInputLocked[], CooldownLeftSeconds <= 0.0, not IsDashing[], (not RequiresGrant? or Found.IsDashGranted[])):
            Grounded := logic{Found.IsGrounded[]}
            if (not Grounded? and AirDashesLeft <= 0):
                return false
            if (EnergyCost > 0.0):
                if (Energy := Entity.FindEnergyAbove[]):
                    if (not Energy.Spend[EnergyCost]):
                        return false
            if (not Grounded?):
                set AirDashesLeft -= 1
            set Direction = PickDirection(Found)
            set DashLeftSeconds = DurationSeconds
            set CooldownLeftSeconds = CooldownSeconds
            set CutPending = false
            Velocity := Found.GetVelocity()
            # 空中のダッシュは上下の速さを 0 にして水平に出る（地面では地面に沿う上下の速さのまま）
            StartUp := if (Grounded?) then Velocity.Up else 0.0
            Found.SetVelocity(Direction * DashSpeedCmPerSecond + vector3{Up := StartUp})
            # 突進は勢いを置き換える（動く床から受け継いだ分も消す。walk が空中で減速しない分として残さない）
            Found.SetInheritedVelocity(vector3{})
            Found.SetMoveOverride(true)
            Found.ReportAction(character_action.Dashed)
            return true
        false

    OnPreMove<private>(DeltaTime:float):void =
        if (Found := Motor?):
            if (Found.IsGrounded[]):
                set AirDashesLeft = AirDashes
            if (CooldownLeftSeconds > 0.0):
                set CooldownLeftSeconds -= DeltaTime
            if (CutPending?):
                # 前のフレームで突進を終えた：速さを切って、walk に速度を返す
                CutSpeed(Found)
            Locked := if (Found.IsInputLocked[]) then true else false
            # 入力を止めているあいだの押しは捨てる
            if (Button.ConsumePress[0.1]):
                if (not Locked?):
                    Dash()
            if (IsDashing[]):
                if (Locked?):
                    # 入力を止めたら、その場で突進を終える
                    EndDash(Found)
                else:
                    RunDash(Found, DeltaTime)

    # 体の知らせ：突進の途中で跳んだら、その場で終える（ダッシュの速さのまま跳ばない）
    OnAction<private>(Action:character_action):void =
        if (Found := Motor?, IsDashing[], (Action = character_action.Jumped or Action = character_action.AirJumped)):
            EndDash(Found)

    # 突進の 1 フレーム：重力を DashGravityScale 倍にし、水平の速度をダッシュの向き × DashSpeedCmPerSecond にする（上下の速さは変えない）
    #   最後のフレーム（残りが DeltaTime 以下）は、残りの秒数の分だけ突進の速さ、あとは終わりの速さで動くように速さを混ぜる（距離が DashSpeedCmPerSecond × DurationSeconds ちょうどになる）。次のフレームの動きの前に速さを切る
    RunDash<private>(Found:character_motor_component, DeltaTime:float):void =
        Found.ScaleGravityThisFrame(DashGravityScale)
        Velocity := Found.GetVelocity()
        if (DashLeftSeconds > DeltaTime):
            set DashLeftSeconds -= DeltaTime
            Found.SetVelocity(Direction * DashSpeedCmPerSecond + vector3{Up := Velocity.Up})
        else:
            Share := Clamp(DashLeftSeconds / DeltaTime, 0.0, 1.0)
            Speed := DashSpeedCmPerSecond * Share + GetEndSpeed(Found) * (1.0 - Share)
            set DashLeftSeconds = 0.0
            set CutPending = true
            Found.SetVelocity(Direction * Speed + vector3{Up := Velocity.Up})

    # 突進をその場で終える（跳んだ・入力を止めた）。速さを切って、walk に速度を返す
    EndDash<private>(Found:character_motor_component):void =
        set DashLeftSeconds = 0.0
        CutSpeed(Found)

    # ダッシュの向きの速さを終わりの速さ（GetEndSpeed）までに切り、横の速さを消す（上下の速さは変えない。壁で止まっていれば 0 のまま）。walk に速度を返す
    CutSpeed<private>(Found:character_motor_component):void =
        set CutPending = false
        Velocity := Found.GetVelocity()
        Along := Clamp(DotProduct(Velocity, Direction), 0.0, GetEndSpeed(Found))
        Found.SetVelocity(Direction * Along + vector3{Up := Velocity.Up})
        Found.SetMoveOverride(false)

    # 終わりの速さ（cm/s）：walk の歩く速さの上限 × 体に重ねた変更の速さの倍率 × DashEndSpeedRatio（突進の速さより速くはしない）。walk が無ければ 600 cm/s を上限とする
    GetEndSpeed<private>(Found:character_motor_component)<transacts>:float =
        WalkSpeed := if (Walk := Found.FindCharacterWalk[]) then Walk.MaxSpeedCmPerSecond else FallbackWalkSpeedCmPerSecond
        Min(DashSpeedCmPerSecond, WalkSpeed * Found.GetSpeedMultiplier() * DashEndSpeedRatio)

    # ダッシュの向き（水平の単位ベクトル）：walk の入力の向き → 今の水平の動き → 体の向き の順。体の AxisLock で縛った軸の分は除く（除いて 0 なら前の向きのまま）
    PickDirection<private>(Found:character_motor_component)<transacts>:vector3 =
        Input := if (Walk := Found.FindCharacterWalk[]) then Walk.GetInputDirection() else vector3{}
        Velocity := Found.GetVelocity()
        Moving := vector3{Forward := Velocity.Forward, Left := Velocity.Left}
        Raw := if (Input.Length() > 0.1) then Input else if (Moving.Length() > 1.0) then Moving else Flatten(Found.Entity.GetGlobalTransform().Rotation.GetForwardAxis())
        Free := case (Found.AxisLock):
            character_axis_lock.Left => vector3{Forward := Raw.Forward}
            character_axis_lock.Forward => vector3{Left := Raw.Left}
            character_axis_lock.None => vector3{Forward := Raw.Forward, Left := Raw.Left}
        FreeCm := Free.Length()
        if (FreeCm > 0.001) then Free / FreeCm else Direction
