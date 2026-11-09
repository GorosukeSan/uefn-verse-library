using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Fortnite.com/Input }
using { InputSystem }
using { CharacterSystem }
using { CharacterSystem.TooltipKit }

# 役割：入力でジャンプする。JumpAction を押すと、上向きの速さを JumpSpeedCmPerSecond にする
#   コヨーテタイム：歩いて地面を離れてから CoyoteSeconds 秒は、地面にいるのと同じようにジャンプできる（自分のジャンプで離れたときは使えない）
#   先行入力：着地の BufferSeconds 秒前までに押したジャンプは、着地した瞬間に跳ぶ（0 でも、前のフレームから今までの押しは使う）
#   空中ジャンプ：空中で AirJumps 回まで跳べる（地面に降りると戻る）。体に重ねた変更の ExtraAirJumps を足す（空中で増えたら、その分をすぐ使える）
#     押したときに使う順：地面（コヨーテタイムを含む）→ 空中ジャンプの残り → どちらも無ければ先行入力として覚える。1 フレームに跳ぶのは 1 回まで（同じ押しで 2 回使わない）
#   高さの調整：跳んでから上がっている途中で離すと、上向きの速さに ReleaseCutRatio を掛ける（短く押すと低く跳ぶ。1 なら変えない。1 回のジャンプに 1 回、下がり始めたら掛けない）
#   頂点の浮き：跳んでから押したまま、上下の速さが ApexSpeedThresholdCmPerSecond より遅いあいだ、重力を ApexGravityMultiplier 倍にする（体の ScaleGravityThisFrame。体の FallGravityMultiplier より優先）
#   跳ぶ速さには、体に重ねた変更の JumpMultiplier を掛ける（BuffKit）
#   体の LockInput で入力を止めているあいだは跳ばない（押しは捨てる。押しているとはみなさない）
# 置き方：エディターで、character_motor_component と同じ entity に付ける
# 知らせ：跳んだら character_motor_component の ActionEvent に Jumped（空中なら AirJumped）
# 外から：Jump（入力なしで跳ばせる。跳べたら true。ReleaseJump を呼ぶか着地するまで押しているとみなす）、ReleaseJump（コードの入力で離したことにする）
# 前提・注意：先行入力で着地の瞬間に跳んだとき、もうボタンを離していれば、すぐに高さの調整が掛かる（短く押した＝低いジャンプ）
character_jump_component<public> := class<final_super>(component):

    # ジャンプのボタン。既定 Character.Jump（Fortnite の移動の割り当て TraversalMapping に入っている）
    @editable:
        ToolTip := JumpActionToolTip
        Categories := array{CharacterJumpCategory}
    JumpAction<public>:input_action(logic) = Character.Jump
    # 跳んだ瞬間の上向きの速さ（cm/s）。既定 900
    @editable_number(float):
        ToolTip := JumpSpeedToolTip
        Categories := array{CharacterJumpCategory}
        MinValue := option{0.0}
        MaxValue := option{20000.0}
    JumpSpeedCmPerSecond<public>:float = 900.0
    # 空中で跳べる回数（2 段ジャンプなら 1）。既定 0
    @editable_number(int):
        ToolTip := JumpAirJumpsToolTip
        Categories := array{CharacterJumpCategory}
        MinValue := option{0}
        MaxValue := option{10}
    AirJumps<public>:int = 0
    # 歩いて地面を離れてからも地面のジャンプとして扱う時間（秒）。0 で使わない。既定 0.12
    @editable_number(float):
        ToolTip := JumpCoyoteToolTip
        Categories := array{CharacterJumpCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    CoyoteSeconds<public>:float = 0.12
    # 着地より前に押したジャンプを覚えておく時間（秒）。0 で使わない。既定 0.12
    @editable_number(float):
        ToolTip := JumpBufferToolTip
        Categories := array{CharacterJumpCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    BufferSeconds<public>:float = 0.12
    # 上がっている途中で離したときに、上向きの速さに掛ける倍率（1 なら変えない）。既定 0.5
    @editable_number(float):
        ToolTip := JumpReleaseCutToolTip
        Categories := array{CharacterJumpCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    ReleaseCutRatio<public>:float = 0.5
    # 頂点の浮き：跳んでから押したまま、上下の速さ（絶対値）がこれより遅いあいだ重力を弱める（cm/s）。0 で使わない。既定 150
    @editable_number(float):
        ToolTip := JumpApexSpeedToolTip
        Categories := array{CharacterJumpCategory}
        MinValue := option{0.0}
        MaxValue := option{5000.0}
    ApexSpeedThresholdCmPerSecond<public>:float = 150.0
    # 頂点の浮きのあいだ、重力に掛ける倍率（体の FallGravityMultiplier の代わり）。1 なら弱めない。既定 0.5
    @editable_number(float):
        ToolTip := JumpApexGravityToolTip
        Categories := array{CharacterJumpCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    ApexGravityMultiplier<public>:float = 0.5

    var<private> Motor:?character_motor_component = false
    var<private> Subscriptions:[]cancelable = array{}
    Button<private>:character_button_tracker = character_button_tracker{}
    var<private> AirJumpsLeft:int = 0
    var<private> SecondsSinceGrounded:float = 1000.0
    # 高さの調整を、このジャンプでもう掛けたか（掛けない状態にしたか）。跳んだ瞬間だけ false にする
    var<private> CutApplied:logic = true
    # 前のフレームに体から読んだ、空中ジャンプに足す回数
    var<private> LastExtraAirJumps:int = 0
    # 跳んでから地面に降りるまで true（頂点の浮きはこのあいだだけ）
    var<private> InJump:logic = false
    # コードの Jump で跳んで、まだ ReleaseJump も着地もしていない（押しているとみなす）
    var<private> HeldByCode:logic = false
    # OnPreMove のたびに 1 増やす番号と、最後に跳んだときの番号（1 フレームに 2 回跳ばない）
    var<private> FrameIndex:int = 0
    var<private> LaunchFrame:int = -1

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := Entity.FindCharacterMotorAbove[]):
            set Motor = option{Found}
            set Subscriptions += array{Found.PreMoveEvent.Subscribe(OnPreMove)}
        else:
            Print("[character_jump_component] character_motor_component が見つかりません（同じ entity か祖先に置いてください）")

    OnSimulate<override>()<suspends>:void =
        if (Found := Motor?, Owner := Found.FindOwner[]):
            MaybeInput := Owner.AwaitPlayerInput()
            if (PlayerInput := MaybeInput?):
                set Subscriptions += Button.Listen(PlayerInput, JumpAction)

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        (super:)OnEndSimulation()

    # 入力なしで跳ばせる（地面・コヨーテタイム・空中ジャンプの残りの順に使う）。跳べなければ false（体の LockInput で止めているあいだ・このフレームにもう跳んだときも false）
    #   跳んだら、ReleaseJump を呼ぶか着地するまで押しているとみなす（高さの調整は掛からず、頂点の浮きは効く）。タッチの UI などは、押したら Jump、離したら ReleaseJump を呼ぶ
    Jump<public>():logic =
        Jumped := TryJump()
        if (Jumped?):
            set HeldByCode = true
        Jumped

    # コードの入力でジャンプを離したことにする（Jump で跳んだときだけ意味がある）。次のフレームの動きの前に、上がっている途中なら高さの調整を掛ける
    ReleaseJump<public>():void =
        set HeldByCode = false

    TryJump<private>():logic =
        if (Found := Motor?, not Found.IsInputLocked[], LaunchFrame <> FrameIndex):
            if (IsOnGround[Found] or SecondsSinceGrounded <= CoyoteSeconds):
                # 地面のジャンプ（コヨーテタイムを含む）。空中ジャンプの残りは使わない。コヨーテタイムは、このジャンプで使い切る
                set SecondsSinceGrounded = 1000.0
                Launch(Found, character_action.Jumped)
                return true
            if (AirJumpsLeft > 0):
                set AirJumpsLeft -= 1
                Launch(Found, character_action.AirJumped)
                return true
        false

    OnPreMove<private>(DeltaTime:float):void =
        set FrameIndex += 1
        if (Found := Motor?):
            Locked := if (Found.IsInputLocked[]) then true else false
            Extra := Found.GetExtraAirJumps()
            if (IsOnGround[Found]):
                set SecondsSinceGrounded = 0.0
                set AirJumpsLeft = AirJumps + Extra
                set InJump = false
                set HeldByCode = false
                set CutApplied = true
            else:
                set SecondsSinceGrounded += DeltaTime
                # 空中で回数が増えたら、増えた分をすぐ使える。減ったら残りを上限までにする
                if (Extra > LastExtraAirJumps):
                    set AirJumpsLeft += Extra - LastExtraAirJumps
                set AirJumpsLeft = Min(AirJumpsLeft, Max(AirJumps + Extra, 0))
            set LastExtraAirJumps = Extra
            if (Locked?):
                set HeldByCode = false
            # 前のフレームから今までの押し（DeltaTime）と、それより BufferSeconds 秒前までの押し（先行入力）。入力を止めているあいだの押しは捨てる
            if (Button.ConsumePress[BufferSeconds + DeltaTime]):
                if (not Locked?):
                    set HeldByCode = false
                    Jumped := TryJump()
                    if (not Jumped?):
                        # 跳べなかった押しは、先行入力として残す（着地までの BufferSeconds 秒）
                        Button.Rebuffer()
            Held := if (not Locked?, (Button.IsDown[] or HeldByCode?)) then true else false
            Velocity := Found.GetVelocity()
            if (not CutApplied?):
                if (Velocity.Up <= 0.0):
                    # 下がり始めた（か止められた）ので、このジャンプではもう掛けない
                    set CutApplied = true
                else if (not Held?):
                    set CutApplied = true
                    Found.SetVelocity(vector3{Forward := Velocity.Forward, Left := Velocity.Left, Up := Velocity.Up * ReleaseCutRatio})
            ApplyApexHang(Found, Held)

    # 頂点の浮き：跳んでから押したまま、空中で上下の速さが ApexSpeedThresholdCmPerSecond より遅いあいだ、このフレームの重力を ApexGravityMultiplier 倍にする
    #   体は下がっているときに FallGravityMultiplier を掛けるので、その分を割って、頂点の前後どちらでも ApexGravityMultiplier 倍にそろえる
    ApplyApexHang<private>(Found:character_motor_component, Held:logic):void =
        Velocity := Found.GetVelocity()
        if (InJump?, Held?, ApexSpeedThresholdCmPerSecond > 0.0, not Found.IsGrounded[], Abs(Velocity.Up) < ApexSpeedThresholdCmPerSecond):
            Multiplier := if (Velocity.Up < 0.0 and Found.FallGravityMultiplier > 0.0) then ApexGravityMultiplier / Found.FallGravityMultiplier else ApexGravityMultiplier
            Found.ScaleGravityThisFrame(Multiplier)

    # 地面にいるとみなすなら成功する。体の IsGrounded は前のフレームの結果なので、フレームの外（コードの Jump）で跳んだ直後のフレームは、上がっていれば地面にいないとする（跳んだ直後に地面のジャンプ・回数の戻しをしない）
    IsOnGround<private>(Found:character_motor_component)<decides><transacts>:void =
        Found.IsGrounded[]
        not (LaunchFrame >= FrameIndex - 1 and Found.GetVelocity().Up > 0.0)

    Launch<private>(Found:character_motor_component, Action:character_action):void =
        Velocity := Found.GetVelocity()
        Found.SetVelocity(vector3{Forward := Velocity.Forward, Left := Velocity.Left, Up := JumpSpeedCmPerSecond * Found.GetJumpMultiplier()})
        set CutApplied = false
        set InJump = true
        set LaunchFrame = FrameIndex
        Found.ReportAction(Action)
