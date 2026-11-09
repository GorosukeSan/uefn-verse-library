using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { CharacterSystem.TooltipKit }

# キャラクターに起きたこと（character_motor_component.ActionEvent で届く。EventKit の character_action_trigger_component が見る）
character_action<public> := enum:
    # 地面からジャンプした（jump の部品が知らせる）
    Jumped
    # 空中でジャンプした（2 段目以降。jump の部品が知らせる）
    AirJumped
    # ダッシュした（dash の部品が知らせる）
    Dashed
    # 空中から地面に降りた
    Landed
    # 地面から離れた（ジャンプ・落下）
    LeftGround
    # 水平に動き始めた（MovingSpeedCmPerSecond を超えた）
    StartedMoving
    # 水平に止まった（MovingSpeedCmPerSecond を下回った）
    StoppedMoving
    # 壁・天井にぶつかった（動きの向きが変わるほど当たった）
    HitWall

# キャラクターの続いている状態（ConditionKit の character_motor_condition_component が見る）
character_motor_state<public> := enum:
    # 地面にいる
    Grounded
    # 空中にいる
    Airborne
    # 空中で上がっている
    Rising
    # 空中で下がっている
    Falling
    # 水平に動いている
    Moving
    # 水平に止まっている
    Still

# 動ける向きを平面に縛る（横スクロールの 2D など）
character_axis_lock<public> := enum:
    # 縛らない（3D）
    None
    # 左右（Left）を縛る。前後（Forward）と上下だけで動く（横スクロール）
    Left
    # 前後（Forward）を縛る。左右（Left）と上下だけで動く
    Forward

# 左右の入力でどうするか（MoveKit の character_walk_component が持つ。BodyKit の character_face_movement_component が読む）
#   値を足すときに直す場所（どれも case に _ を書いていないので、直し忘れるとコンパイルが通らない）：
#     この下の SideInputTurnsBody（walk が使う）、BodyKit の character_face_movement_component.OnPostMove（体をどこへ向けるか）、
#     MCPSystem の CharacterKit（SideStyleName / SideStyleTitle と、名前から探す一覧）、TooltipKit の WalkSideStyleToolTip・README
#   体に重ねた変更（character_modifier.SideStyle）がいくつもあるときは、最後に足したものが勝つ（決まり。character_motor_component.GetSideStyleOverride）
character_side_style<public> := enum:
    # 左右へ動き、体は動く向きへ回る（既定）
    Turn
    # 左右へ動くが、体は歩く向きの前（Space = View なら視点の向き）を向いたまま（カニ歩き）
    Strafe
    # 左右では動かず、その場で体を回す。前後は体の向きへ動く（walk の Space は使わない）
    TankTurn

# Style のとき、左右の入力が体を回すだけ（左右へは動かず、前後は体の向きへ動く）なら true（walk が使う）
SideInputTurnsBody<internal>(Style:character_side_style)<computes>:logic =
    case (Style):
        character_side_style.Turn => false
        character_side_style.Strafe => false
        character_side_style.TankTurn => true

# プレイヤーが独自キャラクターを動かしているあいだ、その人（agent）に付くタグ。character_motor_component が付け外しする
custom_character_tag<public> := class(player_state_tag):

# 体の動きに重ねる変更（バフ・能力の付与）。character_motor_component.AddModifier で足し、返った cancelable の Cancel で外す
#   いくつ重ねてもよい。倍率は掛け合わせ、回数は足し合わせ、ダッシュの許可は 1 つでもあれば許可、左右の入力のしかた（SideStyle）は最後に足したものが勝つ。全部外すと元どおり（各部品の @editable の値）に戻る
#   BuffKit の character_buff_component / character_move_grant_component がこれを使う（自分で作る部品からも使える）
character_modifier<public> := struct:
    # 歩く・走る速さの上限に掛ける倍率（walk の MaxSpeedCmPerSecond）。既定 1
    SpeedMultiplier<public>:float = 1.0
    # 跳ぶ瞬間の上向きの速さに掛ける倍率（jump の JumpSpeedCmPerSecond。高さはおよそ 2 乗で変わる）。既定 1
    JumpMultiplier<public>:float = 1.0
    # 重力に掛ける倍率（0.5 でふんわり落ちる）。SetGravityScale とは別に掛かる。既定 1
    GravityMultiplier<public>:float = 1.0
    # 空中ジャンプの回数に足す数（jump の AirJumps）。既定 0
    ExtraAirJumps<public>:int = 0
    # true なら、dash の RequiresGrant がオンでもダッシュできる。既定 false
    GrantsDash<public>:logic = false
    # 重ねているあいだ、walk の左右の入力のしかたをこれにする（walk の基本の SideStyle より優先。いくつもあれば最後に足したもの）。false なら変えない。既定 false
    SideStyle<public>:?character_side_style = false

# 役割：独自キャラクターの体と物理。Fortnite のキャラクターの動きを使わず、この entity を Verse で動かす（キネマティック：速度を自分で積分し、カプセルを掃引して当たりを決める）
#   毎フレーム（TickEvents.PrePhysics）：PreMoveEvent（同じ entity の動きの部品が速度を決める）→ 重力 → 掃引して当たったら面に沿って滑る（最大 4 回）→ 地面を下へ探して接地を決める → PostMoveEvent
#   重力：GravityCmPerSecondSquared × SetGravityScale の倍率 × 重ねた変更の GravityMultiplier × このフレームだけの倍率（ScaleGravityThisFrame）× 下がっているときは FallGravityMultiplier。SetGravityScale(0) なら必ず 0（止めておける）
#   当たったら：面の法線の向きに SkinCm 離れたところで止まり（掃引の向きに SkinCm 戻すのではない）、残りを面に沿わせる
#     床・坂（歩ける面）と天井：面に沿わせる（着地・頭をぶつけると上下の動きが止まる）
#     壁（歩けない面で、天井でないもの）：上下の動きは変えず、水平の壁に向かう分だけを消す（壁沿いに落ちる・跳ぶ動きを壁が止めない）
#     掃引の始めから触れている当たり（距離 0。めり込みかけ）：返る法線を当てにせず（掃引の逆向きになり、落ちていれば床に見える）、押し出してから掃引し直す。押し出せなければ、そのフレームはその物を無視して動く
#   当たったときの補正（掃引で当たるたびに、面に沿って滑る前に試す）：
#     角の補正：上がっている途中で頭が天井（下向きの面）の角にかすっただけなら、横へ CornerCorrectionCm までずらして上がり続ける（速度は変えない）
#     段の補正：地面にいて水平に動いているときに、足元が段の角に当たっただけ（StepUpCm 以下）なら、段の上へ乗り上げる（階段）。空中で下がっているときは LedgeAssistCm 以下の縁だけ（既定 0 で使わない）
#   接地：地面にいた体は、地面に沿って動いているあいだ（ジャンプ・打ち上げで離れていないあいだ）GroundSnapCm まで下を探して吸い付き、速度を地面に沿わせる（坂を上り下りしても浮かない）
#   体の形は、この entity の位置を足元（底の中心）にした縦のカプセル（直径 RadiusCm × 2、高さ HeightCm）。当たりは FindSweepHits（自分の entity とその子孫、持ち主の Fortnite キャラクターには当たらない）
#   動き方（歩く・ジャンプ・ダッシュ・向き・Fortnite キャラクターを合わせる）は、同じ entity に置く MoveKit / BodyKit の部品で足す（この component は入力を知らない）。自分で部品を作るときは PreMoveEvent を購読して AddVelocity / SetVelocity を呼ぶ
# 置き方：エディターで、独自キャラクターの entity（見た目のメッシュの親）に付ける。プレイヤーごとに動かすなら、この entity をプレハブにして LoadoutSystem の loadout_component の Prefab に入れる（持ち主が決まる）
# 同じ entity：MoveKit の部品（character_walk_component・character_jump_component など）、BodyKit の部品（character_owner_stasis_component・character_face_movement_component）
# いつ：シミュレーション開始から動く。SpawnAtOwner なら、開始の 1 フレーム後に持ち主の Fortnite キャラクターの位置へ移る（子の見た目が付いてくるように）。ResetOnRoundStart なら、Fortnite のラウンドが始まるたびに速度を消して持ち主の位置へ移る（fort_round_manager）
# 知らせ：ActionEvent（character_action）、PreMoveEvent / PostMoveEvent（前のフレームからの秒数）、LandedEvent（着地した瞬間の下向きの速さ）
# タグ：持ち主に custom_character_tag を付ける（動かしているあいだ）
# 外から：Entity.FindCharacterMotorFor[Agent] で、その人が動かしている体を探せる。GetVelocity / SetVelocity / AddVelocity / IsGrounded / IsInState / GetGroundNormal / GetGroundEntity / GetGroundVelocity / GetInheritedVelocity / SetGravityScale / ScaleGravityThisFrame / GetLastLandingSpeed / TeleportTo / ReportAction / FindOwner
#   変更（バフ・能力の付与）：AddModifier（character_modifier を重ね、返った cancelable で外す）、GetSpeedMultiplier / GetJumpMultiplier / GetGravityMultiplier / GetExtraAirJumps / IsDashGranted / GetSideStyleOverride（walk / jump / dash が読む）
# 前提・注意：登れる段は StepUpCm まで（それより高い段は坂にする）。体だけでは動く床に乗っても一緒には動かない（SurfaceKit の character_ride_component を足すと運ばれる。立っている物は接地の掃引で当たった entity＝GetGroundEntity）
#   地面にいるとき、地面から離れる向きの速さが GroundStickSpeedCmPerSecond（200 cm/s）以下の上向きの速度は、地面に沿わせて消す（それより速いジャンプ・打ち上げで離れる）
# ⚠ 未検証：FindSweepHits にカプセルを渡したときの当たり・法線・距離・ContactPosition（角・段の補正が使う）が、説明どおりに返るか（UEFN 43.00 の実機）
character_motor_component<public> := class<final_super>(component):

    # カプセルの半径（cm）。既定 40
    @editable_number(float):
        ToolTip := MotorRadiusToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{5.0}
        MaxValue := option{1000.0}
    RadiusCm<public>:float = 40.0
    # カプセルの高さ（cm。足元から頭まで）。既定 180
    @editable_number(float):
        ToolTip := MotorHeightToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{10.0}
        MaxValue := option{2000.0}
    HeightCm<public>:float = 180.0
    # 重力の加速度（cm/s²）。既定 1960
    @editable_number(float):
        ToolTip := MotorGravityToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.0}
        MaxValue := option{20000.0}
    GravityCmPerSecondSquared<public>:float = 1960.0
    # 落ちる速さの上限（cm/s）。既定 4000
    @editable_number(float):
        ToolTip := MotorMaxFallToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.0}
        MaxValue := option{50000.0}
    MaxFallSpeedCmPerSecond<public>:float = 4000.0
    # 下がっているとき（上下の速さが負）の重力に掛ける倍率。上がるときより速く落ちて、ふわっとしない。1 なら上がるときと同じ。既定 1.6
    #   ジャンプしたときだけでなく、縁から歩いて落ちたとき・打ち上げられて落ちるときも掛かる（SetGravityScale(0) なら 0 のまま）
    @editable_number(float):
        ToolTip := MotorFallGravityToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.1}
        MaxValue := option{10.0}
    FallGravityMultiplier<public>:float = 1.6
    # 立っていられる坂の角度の上限（度）。これより急な面は壁として滑る。既定 50
    @editable_number(float):
        ToolTip := MotorMaxSlopeToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.0}
        MaxValue := option{89.0}
    MaxSlopeDegrees<public>:float = 50.0
    # 地面を探す距離（cm）。足元からこの距離までに地面があれば吸い付く。既定 10
    @editable_number(float):
        ToolTip := MotorGroundProbeToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.0}
        MaxValue := option{200.0}
    GroundProbeCm<public>:float = 10.0
    # 地面にいた体が、地面に沿って動いているとき（ジャンプで離れていないとき）に下へ探す距離（cm）。坂を下る・低い段を降りるときに浮かずに吸い付く。GroundProbeCm より小さければ GroundProbeCm。0 で使わない。既定 20
    @editable_number(float):
        ToolTip := MotorGroundSnapToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.0}
        MaxValue := option{200.0}
    GroundSnapCm<public>:float = 20.0
    # 地面にいて水平に動いているときに、足元が段の角に当たったら乗り上げる高さの上限（cm）。階段で使う。0 で使わない。既定 15
    #   空中では使わない（壁沿いに落ちる・跳ぶときに壁へ乗り上げようとしない）。空中の縁の補助は LedgeAssistCm
    @editable_number(float):
        ToolTip := MotorStepUpToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.0}
        MaxValue := option{200.0}
    StepUpCm<public>:float = 15.0
    # 空中で下がっているときに、足元が縁の角に当たったら乗り上げる高さの上限（cm。ジャンプが少し届かなかった縁の補助）。0 で使わない。既定 0
    @editable_number(float):
        ToolTip := MotorLedgeAssistToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.0}
        MaxValue := option{200.0}
    LedgeAssistCm<public>:float = 0.0
    # 上がっている途中で頭が天井の角にかすったとき、横へずらして上がり続ける距離の上限（cm）。0 で使わない。既定 12
    @editable_number(float):
        ToolTip := MotorCornerCorrectionToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.0}
        MaxValue := option{100.0}
    CornerCorrectionCm<public>:float = 12.0
    # 水平の速さがこれを超えたら「動いている」（StartedMoving / Moving）。既定 10
    @editable_number(float):
        ToolTip := MotorMovingSpeedToolTip
        Categories := array{CharacterMotorCategory}
        MinValue := option{0.0}
        MaxValue := option{1000.0}
    MovingSpeedCmPerSecond<public>:float = 10.0
    # 動ける向きを平面に縛る。Left なら左右の位置を開始時（か TeleportTo した位置）のまま保つ（横スクロール）。既定 None
    @editable:
        ToolTip := MotorAxisLockToolTip
        Categories := array{CharacterMotorCategory}
    AxisLock<public>:character_axis_lock = character_axis_lock.None
    # オンなら、開始時に持ち主の Fortnite キャラクターの位置へ移る。既定オン
    @editable:
        ToolTip := MotorSpawnAtOwnerToolTip
        Categories := array{CharacterMotorCategory}
    SpawnAtOwner<public>:logic = true
    # オンなら、Fortnite のラウンドが始まるたびに、速度を消して持ち主の Fortnite キャラクターの位置へ移る（ラウンドごとにスタートからやり直す）。既定オン
    @editable:
        ToolTip := MotorResetOnRoundToolTip
        Categories := array{CharacterMotorCategory}
    ResetOnRoundStart<public>:logic = true

    # 面から離しておく距離（cm）。当たった面にめり込まないように少し手前で止める
    SkinCm<private>:float = 2.0
    MaxSlideIterations<private>:int = 4
    # 地面にいるとき、地面から離れる向きの速さがこれ以下なら地面に沿って動いているとみなす（cm/s）。坂を上り下りする・加速するくらいの揺れは吸収し、ジャンプ・打ち上げ（これより速い）では離れる
    GroundStickSpeedCmPerSecond<private>:float = 200.0
    # 角の補正で、ずれの向きが分からない（平らな天井に当たった）ときに試す段数（CornerCorrectionCm を等分して近い順に）
    CornerCorrectionSteps<private>:int = 3
    # 当たりの距離がこれ（cm）以下なら「掃引の始めから触れている（めり込みかけ）」とみなす。このとき返る法線は当てにならない
    StartHitCm<private>:float = 0.01
    # 面の法線の上下の成分がこれより小さい（下を向いた）面は天井。歩けない面でそれ以外は壁（上下の動きを減らさない）
    CeilingNormalUp<private>:float = -0.3
    # 壁に触れた向きを、めり込みからの押し出しに使うために覚えておくフレーム数
    WallMemoryFrames<private>:int = 30

    PreMoveEventInternal<private><final>:event(float) = event(float){}
    PostMoveEventInternal<private><final>:event(float) = event(float){}
    ActionEventInternal<private><final>:event(character_action) = event(character_action){}
    LandedEventInternal<private><final>:event(float) = event(float){}

    # 毎フレーム、動かす前に（前のフレームからの秒数）で届く。動きの部品はここで AddVelocity / SetVelocity する
    PreMoveEvent<public><final>:listenable(float) = MakeProxyListenable(PreMoveEventInternal)

    # 毎フレーム、動かしたあとに（前のフレームからの秒数）で届く。位置を読んで合わせる部品（Fortnite キャラクター・カメラ）はここで動かす
    PostMoveEvent<public><final>:listenable(float) = MakeProxyListenable(PostMoveEventInternal)

    # 何かが起きるたびに届く（着地・ジャンプ・ダッシュ・動き始めなど）
    ActionEvent<public><final>:listenable(character_action) = MakeProxyListenable(ActionEventInternal)

    # 空中から地面に降りるたびに、降りた瞬間の下向きの速さ（cm/s。0 以上）で届く。ActionEvent の Landed のすぐあと。着地のつぶれ・土煙・音の大きさなどに使う
    LandedEvent<public><final>:listenable(float) = MakeProxyListenable(LandedEventInternal)

    var<private> Velocity:vector3 = vector3{}
    # このフレームだけ重力に掛ける倍率（ScaleGravityThisFrame。毎フレーム PreMoveEvent の前に 1 に戻す）
    var<private> FrameGravityMultiplier:float = 1.0
    # 最後に着地した瞬間の下向きの速さ（cm/s）
    var<private> LastLandingSpeed:float = 0.0
    var<private> Grounded:logic = false
    var<private> Moving:logic = false
    var<private> GroundNormal:vector3 = vector3{Up := 1.0}
    # 立っている物（接地の掃引で当たった component の entity）。地面にいないときは false
    var<private> GroundEntity:?entity = false
    # 立っている物の動く速度（cm/s。character_ride_component が毎フレーム入れる。運ばれていなければ 0）
    var<private> GroundVelocity:vector3 = vector3{}
    # 動く地面から離れたときに受け継いだ水平の速度（cm/s。着地すると 0。walk が空中で減速しない分）
    var<private> InheritedVelocity:vector3 = vector3{}
    # ほかの部品（dash）が速度を決めているあいだ true（walk は速度を変えない）
    var<private> MoveOverridden:logic = false
    # OnTick のたびに 1 増やす番号と、最後に壁に触れた番号・その壁の外向き（水平の単位ベクトル）
    var<private> FrameIndex:int = 0
    var<private> LastWallFrame:int = -1000
    var<private> LastWallNormal:vector3 = vector3{}
    var<private> GravityScale:float = 1.0
    var<private> Owner:?player = false
    # 開始してから TeleportTo されたか（されていれば SpawnAtOwner の 1 フレーム後の移動はしない。ほかの部品が先に置いた位置を上書きしない）
    var<private> TeleportedSinceBegin:logic = false
    # AxisLock で保つ位置（cm）
    var<private> LockedValue:float = 0.0
    var<private> TickSubscription:?cancelable = false
    # 重ねている変更（番号, 変更）と、その合計
    var<private> Modifiers:[]tuple(int, character_modifier) = array{}
    var<private> NextModifierId:int = 0
    var<private> SpeedMultiplier:float = 1.0
    var<private> JumpMultiplier:float = 1.0
    var<private> GravityMultiplier:float = 1.0
    var<private> ExtraAirJumps:int = 0
    var<private> DashGrants:int = 0
    var<private> SideStyleOverride:?character_side_style = false
    # LockInput で止めている番号
    var<private> InputLocks:[]int = array{}
    var<private> NextInputLockId:int = 0
    OwnerTags<private>:player_tag_holder = player_tag_holder{}
    Rounds<private>:round_watcher = round_watcher{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (OwningPlayer := Entity.FindOwningPlayer[]):
            set Owner = option{OwningPlayer}
            OwnerTags.Add(OwningPlayer, custom_character_tag{})
        set LockedValue = LockedComponent(Entity.GetGlobalTransform().Translation)
        set TickSubscription = option{TickEvents.PrePhysics.Subscribe(OnTick)}
        if (ResetOnRoundStart?):
            Rounds.Start(Entity, OnRoundStarted, OnRoundEnded)

    # SpawnAtOwner の移動は 1 フレーム後に行う。OnBeginSimulation の中で動かすと、まだシーンに入っていない子（見た目のメッシュ）が付いてこず、
    # 体と見た目が離れたままになった（実機 v43.00：プレハブから作った体を開始時に動かすと、子のメッシュが作られた場所に残った）
    OnSimulate<override>()<suspends>:void =
        Sleep(0.0)
        if (SpawnAtOwner?, not TeleportedSinceBegin?, OwningPlayer := Owner?, Body := OwningPlayer.FindPlayerEntity[]):
            TeleportTo(Body.GetGlobalTransform().Translation)

    OnEndSimulation<override>():void =
        TickSubscription.CancelIfSet()
        set TickSubscription = false
        Rounds.Stop()
        OwnerTags.RemoveAll()
        (super:)OnEndSimulation()

    # 持ち主（このキャラクターを動かすプレイヤー）。持ち主のいない場所に置いたときは失敗する
    FindOwner<public>()<decides><transacts>:player =
        Owner?

    # 今の速度（cm/s。世界の向き）
    GetVelocity<public>()<transacts>:vector3 =
        Velocity

    # 速度を決める（cm/s。世界の向き）
    SetVelocity<public>(NewVelocity:vector3):void =
        set Velocity = NewVelocity

    # 速度に足す（cm/s。打ち上げ・はじき飛ばしなど）
    AddVelocity<public>(Delta:vector3):void =
        set Velocity = Velocity + Delta

    # 地面にいるなら成功する
    IsGrounded<public>()<decides><transacts>:void =
        Grounded?

    # 今 State なら成功する
    IsInState<public>(State:character_motor_state)<decides><transacts>:void =
        case (State):
            character_motor_state.Grounded => Grounded?
            character_motor_state.Airborne => not Grounded?
            character_motor_state.Rising => (not Grounded?, Velocity.Up > 0.0)
            character_motor_state.Falling => (not Grounded?, Velocity.Up <= 0.0)
            character_motor_state.Moving => Moving?
            character_motor_state.Still => not Moving?

    # 立っている地面の向き（上向きの単位ベクトル）。地面にいないときは最後に立っていた地面
    GetGroundNormal<public>()<transacts>:vector3 =
        GroundNormal

    # 今立っている物（接地の掃引で当たったメッシュの entity。動く床ならその entity か子）。地面にいなければ失敗する（前のフレームの動きの結果）
    GetGroundEntity<public>()<decides><transacts>:entity =
        GroundEntity?

    # 今乗って運ばれている地面の速度（cm/s。世界の向き。回る床なら足元の速度）。SurfaceKit の character_ride_component が入れる（無ければ・運ばれていなければ 0）
    GetGroundVelocity<public>()<transacts>:vector3 =
        GroundVelocity

    # 動く地面から離れたとき（ジャンプ・縁から落ちた）に受け継いだ水平の速度（cm/s。character_ride_component が入れる）。着地すると 0。walk は空中でこの分を減速しない（動く床から跳んでも床と一緒に進む）
    GetInheritedVelocity<public>()<transacts>:vector3 =
        InheritedVelocity

    # character_ride_component から呼ばれる：乗っている地面の速度を入れる
    SetGroundVelocity<internal>(Value:vector3)<transacts>:void =
        set GroundVelocity = Value

    # character_ride_component から呼ばれる：動く地面から離れたので、その速度 Value を体の速度に足し、水平の分を受け継いだ速度として覚える（着地まで）
    InheritVelocity<internal>(Value:vector3)<transacts>:void =
        set Velocity = Velocity + Value
        set InheritedVelocity = vector3{Forward := Value.Forward, Left := Value.Left}
        set GroundVelocity = vector3{}

    # MoveKit から呼ばれる：受け継いだ速度を Value（水平の分だけ）にする。walk が空中で、入力・壁で減った分だけ縮める（減った分は戻らない）。dash が消す（突進は勢いを置き換える）
    SetInheritedVelocity<internal>(Value:vector3)<transacts>:void =
        set InheritedVelocity = vector3{Forward := Value.Forward, Left := Value.Left}

    # MoveKit の dash から呼ばれる：Value が true のあいだ、ほかの部品（dash）が速度を決めている（walk は速度を変えない。どの順に PreMoveEvent が届いても突進の速さ・距離が変わらない）
    SetMoveOverride<internal>(Value:logic)<transacts>:void =
        set MoveOverridden = Value

    # SetMoveOverride(true) のあいだ成功する（walk が毎フレーム見る）
    IsMoveOverridden<internal>()<decides><transacts>:void =
        MoveOverridden?

    # character_ride_component から呼ばれる：乗っている地面 Ground が動いた分 Delta（世界、cm）だけ体を運ぶ。速度は変えない
    #   上下はそのまま動かす（床が上がった分を先に戻して、床にめり込んだまま掃引しない）。水平は Ground 以外に当たったら手前（面から SkinCm）で止め、残りを当たった面に沿わせて 1 回だけ動かす（運ばれて壁にめり込まない）
    #   掃引の始めから Ground 以外に触れていたら（めり込みかけ）、水平には運ばない
    #   AxisLock で縛った軸には動かさない
    CarryBy<internal>(Delta:vector3, Ground:entity)<transacts>:void =
        Move := ApplyLock(Delta, 0.0)
        if (Move.Up <> 0.0):
            MoveBy(vector3{Up := Move.Up})
        var Horizontal:vector3 = vector3{Forward := Move.Forward, Left := Move.Left}
        var Iteration:int = 0
        loop:
            HorizontalCm := Horizontal.Length()
            if (Iteration >= 2 or HorizontalCm < 0.01):
                break
            set Iteration += 1
            Feet := Entity.GetGlobalTransform().Translation
            if (Hit := FindFirstHitFromExcept[Feet, Horizontal, option{Ground}]):
                if (IsStartHit[Hit]):
                    break
                Allowed := StopDistance(Hit, Horizontal / HorizontalCm)
                MoveBy(Horizontal * (Allowed / HorizontalCm))
                Rest := Horizontal * (1.0 - Allowed / HorizontalCm)
                set Horizontal = SlideAlong(Rest, Hit.ContactNormal)
                set Horizontal = vector3{Forward := Horizontal.Forward, Left := Horizontal.Left}
            else:
                MoveBy(Horizontal)
                break

    # character_ride_component から呼ばれる：足元から下へ DistanceCm まで探し、歩ける面があれば、その entity（体は動かさない）。無ければ失敗する
    #   掃引の始めから触れている当たり（横の壁にめり込みかけ。法線が真上に見えることがある）は地面にしない（壁を同じ床と取り違えて運び続けない）
    FindGroundEntityBelow<internal>(DistanceCm:float)<decides><transacts>:entity =
        Hit := FindFirstHit[vector3{Up := -(DistanceCm + SkinCm)}]
        not IsStartHit[Hit]
        IsWalkable[Hit.ContactNormal]
        Hit.TargetComponent.Entity

    # 重力の倍率（1.0 で GravityCmPerSecondSquared どおり。0 で無重力）
    SetGravityScale<public>(Scale:float):void =
        set GravityScale = Scale

    # 今の重力の倍率
    GetGravityScale<public>()<transacts>:float =
        GravityScale

    # このフレームの重力にだけ Multiplier（0 以上）を掛ける。PreMoveEvent の中で呼ぶ（毎フレーム PreMoveEvent の前に 1 に戻るので、続けるなら毎フレーム呼ぶ）。何度も呼ぶと掛け合わせる
    #   SetGravityScale・重ねた変更の GravityMultiplier・下がっているときの FallGravityMultiplier にも掛け合わさる（SetGravityScale(0) なら 0 のまま）。jump の頂点の浮き（ApexGravityMultiplier）がこれを使う
    ScaleGravityThisFrame<public>(Multiplier:float):void =
        set FrameGravityMultiplier *= Max(Multiplier, 0.0)

    # 最後に空中から地面に降りた瞬間の下向きの速さ（cm/s。0 以上。まだ降りていなければ 0）。LandedEvent と同じ値
    GetLastLandingSpeed<public>()<transacts>:float =
        LastLandingSpeed

    # 当たりを見ずに Position（足元。世界の位置、cm）へ移る。速度はそのまま
    TeleportTo<public>(Position:vector3):void =
        Current := Entity.GetGlobalTransform()
        Entity.SetGlobalTransform(Current.WithTranslation(Position))
        set LockedValue = LockedComponent(Position)
        set TeleportedSinceBegin = true

    # 部品が、起きたこと（Jumped・Dashed など）を知らせる（ActionEvent に届く）。自分で作る動きの部品からも呼べる
    ReportAction<public>(Action:character_action):void =
        ActionEventInternal.Signal(Action)

    # 体の動きに Modifier を重ねる。返った cancelable の Cancel で外す（2 回目からは何もしない）。外し忘れないように、足した部品が止まるときに必ず Cancel する
    AddModifier<public>(Modifier:character_modifier)<transacts>:cancelable =
        set NextModifierId += 1
        Id := NextModifierId
        set Modifiers += array{(Id, Modifier)}
        RecomputeModifiers()
        character_modifier_handle{Motor := Self, Id := Id}

    # 今重ねている変更の数
    GetModifierCount<public>()<transacts>:int =
        Modifiers.Length

    # 入力を止める（ロビー・結果の画面など）。返った cancelable の Cancel で外す（2 回目からは何もしない）。いくつ重ねてもよく、全部外れると入力が戻る（呼ぶ側ごとに別々に止め・外しできる）
    #   止めているあいだ：walk は入力（ボタン・方向・SetMoveInput）を 0 として扱い（速度は BrakingCmPerSecondSquared で止まっていく）、TankTurn でも回さない。左右の入力のしかたの切り替えボタンも効かない
    #   jump は跳ばない（ボタン・Jump とも。押しは先行入力にも残さず捨てる。押しているとはみなさないので頂点の浮きも止まる）。dash は出さない（突進の途中なら終える）。face（character_face_movement_component）は体を回さない
    #   体の物理（重力・掃引・接地）は止めない。体ごと止めるなら、別に SetGravityScale(0) と SetVelocity(vector3{}) をする
    LockInput<public>()<transacts>:cancelable =
        set NextInputLockId += 1
        Id := NextInputLockId
        set InputLocks += array{Id}
        character_input_lock_handle{Motor := Self, Id := Id}

    # LockInput で入力を止めているあいだ成功する（walk / jump / dash / face が毎フレーム見る。自分で作る動きの部品もこれを見る）
    IsInputLocked<public>()<decides><transacts>:void =
        InputLocks.Length > 0

    # character_input_lock_handle の Cancel から呼ばれる：番号 Id の止めを外す
    UnlockInput<internal>(Id:int)<transacts>:void =
        set InputLocks = for (Each : InputLocks, Each <> Id):
            Each

    # 重ねている変更の速さの倍率（掛け合わせ。無ければ 1）
    GetSpeedMultiplier<public>()<transacts>:float =
        SpeedMultiplier

    # 重ねている変更のジャンプの倍率（掛け合わせ。無ければ 1）
    GetJumpMultiplier<public>()<transacts>:float =
        JumpMultiplier

    # 重ねている変更の重力の倍率（掛け合わせ。無ければ 1）。SetGravityScale の倍率とは別
    GetGravityMultiplier<public>()<transacts>:float =
        GravityMultiplier

    # 重ねている変更の、空中ジャンプに足す回数（足し合わせ。無ければ 0）
    GetExtraAirJumps<public>()<transacts>:int =
        ExtraAirJumps

    # ダッシュを許す変更（GrantsDash）が 1 つでも重なっていれば成功する
    IsDashGranted<public>()<decides><transacts>:void =
        DashGrants > 0

    # 重ねている変更が決める左右の入力のしかた（SideStyle を持つ変更のうち最後に足したもの）。無ければ失敗する（walk は自分の基本の値を使う）
    GetSideStyleOverride<public>()<decides><transacts>:character_side_style =
        SideStyleOverride?

    # character_modifier_handle の Cancel から呼ばれる：番号 Id の変更を外す
    RemoveModifier<internal>(Id:int)<transacts>:void =
        set Modifiers = for (Entry : Modifiers, Entry(0) <> Id):
            Entry
        RecomputeModifiers()

    RecomputeModifiers<private>()<transacts>:void =
        var Speed:float = 1.0
        var Jump:float = 1.0
        var Gravity:float = 1.0
        var AirJumps:int = 0
        var Dash:int = 0
        var Side:?character_side_style = false
        # Modifiers は足した順に並ぶので、SideStyle は後のもので上書きする（最後に足したものが勝つ）
        for (Entry : Modifiers):
            Modifier := Entry(1)
            set Speed *= Modifier.SpeedMultiplier
            set Jump *= Modifier.JumpMultiplier
            set Gravity *= Modifier.GravityMultiplier
            set AirJumps += Modifier.ExtraAirJumps
            if (Modifier.GrantsDash?):
                set Dash += 1
            if (Style := Modifier.SideStyle?):
                set Side = option{Style}
        set SpeedMultiplier = Speed
        set JumpMultiplier = Jump
        set GravityMultiplier = Gravity
        set ExtraAirJumps = AirJumps
        set DashGrants = Dash
        set SideStyleOverride = Side

    # ラウンドの始まり：速度を消して、持ち主のキャラクター（スポーン地点に出直している）の位置へ移る
    OnRoundStarted<private>()<suspends>:void =
        set Velocity = vector3{}
        set InheritedVelocity = vector3{}
        if (Player := Owner?, Body := Player.FindPlayerEntity[]):
            TeleportTo(Body.GetGlobalTransform().Translation)

    OnRoundEnded<private>():void =
        set Velocity = vector3{}

    OnTick<private>(DeltaTime:float):void =
        if (DeltaTime <= 0.0):
            return
        set FrameIndex += 1
        # このフレームだけの重力の倍率は、このあとの PreMoveEvent の中で決める（前のフレームの残りは使わない）
        set FrameGravityMultiplier = 1.0
        PreMoveEventInternal.Signal(DeltaTime)
        set Velocity = ApplyLock(Velocity, 0.0)
        ApplyGravity(DeltaTime)
        MoveWithCollision(Velocity * DeltaTime)
        if (AxisLock <> character_axis_lock.None):
            Current := Entity.GetGlobalTransform()
            Entity.SetGlobalTransform(Current.WithTranslation(ApplyLock(Current.Translation, LockedValue)))
        UpdateGround()
        UpdateMoving()
        PostMoveEventInternal.Signal(DeltaTime)

    # 空中か、地面から離れようとしている（ジャンプ・打ち上げ）ときだけ重力を足す。地面に沿って動いているあいだ（坂を上る・下る）は足さない
    ApplyGravity<private>(DeltaTime:float):void =
        if (not Grounded? or IsLeavingGround[]):
            # 下がっているときは FallGravityMultiplier を掛ける（速く落ちる）。SetGravityScale(0) なら全体が 0
            Shape := if (Velocity.Up < 0.0) then FallGravityMultiplier else 1.0
            Acceleration := GravityCmPerSecondSquared * GravityScale * GravityMultiplier * FrameGravityMultiplier * Shape
            Fall := Max(Velocity.Up - Acceleration * DeltaTime, -MaxFallSpeedCmPerSecond)
            set Velocity = vector3{Forward := Velocity.Forward, Left := Velocity.Left, Up := Fall}

    # 地面にいて、地面から離れる向きの速さが GroundStickSpeedCmPerSecond より速いなら成功する（ジャンプ・打ち上げで地面を離れるところ）
    IsLeavingGround<private>()<decides><transacts>:void =
        Grounded?
        DotProduct(Velocity, GroundNormal) > GroundStickSpeedCmPerSecond

    # Displacement だけ動かす。当たったら面から SkinCm 離れたところで止め、残りを面に沿わせてもう一度（最大 MaxSlideIterations 回）。当たった面に向かう速度は消す（壁なら水平の分だけ）
    #   滑らせる前に、角の補正（頭が天井の角にかすった）と段の補正（足元が段の角に当たった）を試す。補正できたら速度は変えない
    #   壁に貼り付いて止まらないための決まり（実機 v43.00：壁に押し付けたまま跳ぶ・落ちると、壁の途中で止まって動けなくなった）：
    #     1. 止まる距離は面の法線の向きに SkinCm（StopDistance）。前は掃引の向きに SkinCm 戻していたので、壁に浅い角度で近づくたびに隙間が縮んで 0 になった
    #     2. 掃引の始めから触れている当たり（距離 0）は、返る法線が掃引の逆向き（落ちていれば真上）になり、床・天井と取り違えて上下の動きと速度が消えていた。
    #        法線を使わずに押し出して掃引し直し（TryDepenetrate）、押し出せなければこのフレームはその物を無視して動く
    #     3. 壁（歩けない面で天井でないもの）は上下の動きを変えない（SlideAlong・ClipVelocity）。前は法線ごと消していたので、少し傾いた壁・縁の角で上下の速さが削られた
    #     4. 段の補正は地面にいるときだけ（空中は LedgeAssistCm）。角の補正は天井（下向きの面）だけ
    MoveWithCollision<private>(Displacement:vector3):void =
        var Remaining:vector3 = Displacement
        # このフレームの掃引で無視する物（押し出せなかった・かすっただけの物）
        var Skip:?entity = false
        var Iteration:int = 0
        loop:
            if (Iteration >= MaxSlideIterations or Remaining.LengthSquared() < 0.0001):
                break
            set Iteration += 1
            Feet := Entity.GetGlobalTransform().Translation
            if (Hit := FindFirstHitFromExcept[Feet, Remaining, Skip]):
                if (IsStartHit[Hit]):
                    # めり込みかけ：押し出せたら、そこから同じ動きを掃引し直す。押し出せなければ、その物を無視して動く（動きを止めない）
                    Pushed := TryDepenetrate(Hit, Remaining)
                    if (not Pushed?):
                        set Skip = option{Hit.TargetComponent.Entity}
                else:
                    Direction := Remaining / Remaining.Length()
                    Normal := Hit.ContactNormal
                    Allowed := StopDistance(Hit, Direction)
                    MoveBy(Direction * Allowed)
                    Rest := Remaining - Direction * Allowed
                    if (DotProduct(Direction, Normal) > -0.001):
                        # 動きに向かい合っていない面にかすっただけ：止めずに残りをそのまま動かす（このフレームはその物を無視する）
                        set Remaining = Rest
                        set Skip = option{Hit.TargetComponent.Entity}
                    else if (TryCornerCorrection(Hit, Rest)?):
                        # 横へずらせたので、残りの動きをそのまま続ける
                        set Remaining = Rest
                    else if (TryStepUp(Hit, Rest)?):
                        # 段の上へ乗った（残りの水平の動きは使い切った）
                        break
                    else:
                        set Remaining = SlideAlong(Rest, Normal)
                        ClipVelocity(Normal)
            else:
                MoveBy(Remaining)
                break

    # Hit の当たりの距離が StartHitCm 以下（掃引の始めから触れている。めり込みかけ）なら成功する
    IsStartHit<private>(Hit:sweep_hit)<decides><transacts>:void =
        Hit.SourceHitDistance <= StartHitCm

    # Normal が壁（歩けない面で、天井でないもの）なら成功する。壁は上下の動きを変えない
    IsWallNormal<private>(Normal:vector3)<decides><transacts>:void =
        not IsWalkable[Normal]
        Normal.Up > CeilingNormalUp

    # Direction（単位ベクトル）へ動いて Hit に当たったとき、進んでよい距離（cm）。面の法線の向きに測った離れが SkinCm になるところまで（0〜当たりの距離）
    #   掃引の向きに SkinCm 戻すだけだと、浅い角度で壁に近づく（壁沿いに落ちる・跳ぶ）たびに隙間が SkinCm × 角度まで縮み、数フレームで 0 になる
    StopDistance<private>(Hit:sweep_hit, Direction:vector3)<transacts>:float =
        HitCm := Hit.SourceHitDistance
        Approach := -DotProduct(Direction, Hit.ContactNormal)
        if (Approach > 0.001) then Clamp(HitCm - SkinCm / Approach, 0.0, HitCm) else Max(HitCm - SkinCm, 0.0)

    # 残りの動き Rest を当たった面（法線 Normal）に沿わせる。面に向かう分だけを除く（離れる向きの動きはそのまま）
    #   床・坂（歩ける面）と天井：面の法線の向きの分を除く（着地・頭をぶつけると上下の動きが止まる）
    #   壁：上下の動きは変えず、水平だけを面の外へずらして面に沿わせる（壁沿いに落ちる・跳ぶ動きを壁が止めない。少し傾いた壁・縁の角でも上下の動きが削られない）
    SlideAlong<private>(Rest:vector3, Normal:vector3)<transacts>:vector3 =
        Into := DotProduct(Rest, Normal)
        if (Into >= 0.0):
            return Rest
        if (IsWallNormal[Normal]):
            Flat := vector3{Forward := Normal.Forward, Left := Normal.Left}
            FlatSquared := Flat.LengthSquared()
            if (FlatSquared > 0.000001):
                # Rest + Flat × k の法線の向きの分を 0 にする（k = -Into / |Flat|²）。上下の成分は変わらない
                return Rest + Flat * (-Into / FlatSquared)
        Rest - Normal * Into

    # 当たった面（法線 Normal）に向かう速度を消す。壁なら水平の壁に向かう分だけ消し（上下の速さは変えない）、壁の外向きを覚える（めり込みからの押し出しに使う）
    #   歩けない面（壁・天井）に向かう速度を消したら HitWall を知らせる
    ClipVelocity<private>(Normal:vector3):void =
        if (IsWallNormal[Normal]):
            Flat := vector3{Forward := Normal.Forward, Left := Normal.Left}
            FlatCm := Flat.Length()
            if (FlatCm > 0.001):
                Away := Flat / FlatCm
                set LastWallNormal = Away
                set LastWallFrame = FrameIndex
                Into := DotProduct(Velocity, Away)
                if (Into < 0.0):
                    set Velocity = Velocity - Away * Into
                    ReportAction(character_action.HitWall)
        else:
            Into := DotProduct(Velocity, Normal)
            if (Into < 0.0):
                set Velocity = Velocity - Normal * Into
                if (not IsWalkable[Normal]):
                    ReportAction(character_action.HitWall)

    # 掃引の始めから Hit に触れている（めり込みかけ）とき、押し出す向きを順に試し、空いた位置（何にも触れていない）へ動かせたら成功（true）。動かせなければ体は動かさない
    #   試す向き：物理が返した法線（掃引の逆向きそのもの＝当てにならない、でなければ）→ 最近触れた壁の外向き → 動き Motion の水平の逆 → 速度の水平の逆 → 真上（床）→ 真下（天井）。それぞれ SkinCm + 0.5 と SkinCm × 4 の 2 通り
    TryDepenetrate<private>(Hit:sweep_hit, Motion:vector3)<transacts>:logic =
        Feet := Entity.GetGlobalTransform().Translation
        MotionCm := Motion.Length()
        Direction := if (MotionCm > 0.0001) then Motion / MotionCm else vector3{}
        Normal := Hit.ContactNormal
        var Candidates:[]vector3 = array{}
        if (DotProduct(Normal, Direction) > -0.99):
            set Candidates += array{Normal}
        if (FrameIndex - LastWallFrame <= WallMemoryFrames):
            set Candidates += array{LastWallNormal}
        set Candidates += array{vector3{Forward := -Motion.Forward, Left := -Motion.Left}, vector3{Forward := -Velocity.Forward, Left := -Velocity.Left}, vector3{Up := 1.0}, vector3{Up := -1.0}}
        var Pushed:logic = false
        for (Candidate : Candidates, Step : array{SkinCm + 0.5, SkinCm * 4.0}, not Pushed?):
            Free := ApplyLock(Candidate, 0.0)
            FreeCm := Free.Length()
            if (FreeCm > 0.001):
                Away := Free / FreeCm
                if (IsFreeAt(Feet + Away * Step, Away)?):
                    MoveBy(Away * Step)
                    set Pushed = true
        Pushed

    # 足元を Feet に置いたとき、何にも触れていなければ true（Away の逆向きへ SkinCm 掃引して、始めから触れている当たりが無いかを見る）
    IsFreeAt<private>(Feet:vector3, Away:vector3)<transacts>:logic =
        if (Hit := FindFirstHitFrom[Feet, Away * (-SkinCm)], IsStartHit[Hit]) then false else true

    # 角の補正：上がっている途中で、頭（上の半球）が天井（法線が CeilingNormalUp より下向きの面）の角にかすっただけなら、横へ CornerCorrectionCm までずらして成功（true）
    #   壁（ほぼ垂直の面）では使わない：壁は SlideAlong が上下の動きを変えずに沿わせるので、ずらす必要が無い（前は壁にかすっても横へずらしていた）
    #   角の位置（ContactPosition）が頭の中心から横にずれていれば、その反対へ、かすらなくなる分だけずらす
    #   平らな天井の面に当たった（ずれが無い）ときは、横の動きの向き（AxisLock なら動ける軸の両向き）へ、近い順に試す
    TryCornerCorrection<private>(Hit:sweep_hit, Rest:vector3)<transacts>:logic =
        if (CornerCorrectionCm <= 0.0 or Rest.Up <= 0.0 or Hit.ContactNormal.Up > CeilingNormalUp):
            return false
        Feet := Entity.GetGlobalTransform().Translation
        HeadCenter := Feet + vector3{Up := Max(HeightCm - RadiusCm, RadiusCm)}
        Contact := Hit.ContactPosition
        if (Contact.Up < HeadCenter.Up):
            return false
        Rise := vector3{Up := Max(Rest.Up, SkinCm)}
        Away := ApplyLock(vector3{Forward := HeadCenter.Forward - Contact.Forward, Left := HeadCenter.Left - Contact.Left}, 0.0)
        AwayCm := Away.Length()
        if (AwayCm >= 0.5):
            # 角が横にある：かすらなくなる（頭の中心と角の水平の距離が半径 + SkinCm になる）までずらす
            Need := RadiusCm + SkinCm - AwayCm + 0.5
            if (Need > 0.0, Need <= CornerCorrectionCm):
                return TryNudge(Feet, Away * (Need / AwayCm), Rise)
            return false
        var Nudged:logic = false
        for (Side : GetCornerSides(), Index := 1..CornerCorrectionSteps, not Nudged?):
            if (TryNudge(Feet, Side * (CornerCorrectionCm * (Index * 1.0) / (CornerCorrectionSteps * 1.0)), Rise)?):
                set Nudged = true
        Nudged

    # 平らな天井に当たったときに、ずらすのを試す向き（水平の単位ベクトル）。AxisLock なら動ける軸の両向き、無ければ横の動きの向きとその逆（横に動いていなければ試さない）
    GetCornerSides<private>()<transacts>:[]vector3 =
        Horizontal := vector3{Forward := Velocity.Forward, Left := Velocity.Left}
        HorizontalCm := Horizontal.Length()
        Moving2D := if (HorizontalCm > 1.0) then array{Horizontal / HorizontalCm, Horizontal * (-1.0 / HorizontalCm)} else array{}
        case (AxisLock):
            character_axis_lock.Left => array{vector3{Forward := 1.0}, vector3{Forward := -1.0}}
            character_axis_lock.Forward => array{vector3{Left := 1.0}, vector3{Left := -1.0}}
            character_axis_lock.None => Moving2D

    # Feet から横へ Nudge だけずらせて、そこから Rise だけ上が空いていれば、ずらして成功（true）
    TryNudge<private>(Feet:vector3, Nudge:vector3, Rise:vector3)<transacts>:logic =
        if (FindFirstHitFrom[Feet, Nudge]):
            return false
        if (FindFirstHitFrom[Feet + Nudge, Rise]):
            return false
        MoveBy(Nudge)
        true

    # 段の補正：地面にいて（跳んで離れるところでなく）水平に動いて、足元が StepUpCm 以下の段の角に当たったなら、段の上へ乗り上げて成功（true）
    #   空中では、下がっているときに LedgeAssistCm 以下の縁だけ（既定 0 で使わない）。壁沿いに落ちる・跳ぶあいだに壁へ乗り上げようとしない
    #   上が空いている → 上げた位置から前が空いている → 下に歩ける面がある、の 3 つを確かめてから動かす（どれかがだめなら何もしない＝いつもどおり滑る）
    #   角に乗っても滑り落ちないよう、角が歩ける向きに当たるところ（体の軸と角の水平の距離が 半径 × sin(MaxSlopeDegrees) 未満）まで進める（その分だけ、このフレームの動きより先へ進むことがある）
    TryStepUp<private>(Hit:sweep_hit, Rest:vector3)<transacts>:logic =
        OnGround := if (Grounded?, not IsLeavingGround[]) then true else false
        Limit := if (OnGround?) then StepUpCm else if (Velocity.Up <= 0.0) then LedgeAssistCm else 0.0
        if (Limit <= 0.0):
            return false
        Normal := Hit.ContactNormal
        if (IsWalkable[Normal] or Normal.Up < -0.1):
            return false
        Horizontal := vector3{Forward := Rest.Forward, Left := Rest.Left}
        HorizontalCm := Horizontal.Length()
        if (HorizontalCm < 0.01):
            return false
        # 水平の動きが角に向かっていなければ（壁沿いに上下に動いているだけなら）補正しない
        if (DotProduct(Horizontal, vector3{Forward := Normal.Forward, Left := Normal.Left}) >= 0.0):
            return false
        Feet := Entity.GetGlobalTransform().Translation
        Contact := Hit.ContactPosition
        StepCm := Contact.Up - Feet.Up
        if (StepCm <= 0.0 or StepCm > Limit):
            return false
        Ahead := Horizontal / HorizontalCm
        ToContact := DotProduct(vector3{Forward := Contact.Forward - Feet.Forward, Left := Contact.Left - Feet.Left}, Ahead)
        if (ToContact <= 0.0):
            return false
        SlopeCos := Cos(MaxSlopeDegrees * PiFloat / 180.0)
        Reach := RadiusCm * Sqrt(Max(1.0 - SlopeCos * SlopeCos, 0.0)) - 1.0
        AdvanceCm := Max(HorizontalCm, ToContact - Reach)
        if (AdvanceCm > RadiusCm + SkinCm):
            return false
        Lift := vector3{Up := StepCm + SkinCm}
        Push := Ahead * AdvanceCm
        if (FindFirstHitFrom[Feet, Lift]):
            return false
        if (FindFirstHitFrom[Feet + Lift, Push]):
            return false
        if (Down := FindFirstHitFrom[Feet + Lift + Push, vector3{Up := -(Lift.Up + SkinCm)}], IsWalkable[Down.ContactNormal]):
            MoveBy(Lift + Push + vector3{Up := -Max(Down.SourceHitDistance - SkinCm, 0.0)})
            return true
        false

    # 足元を下へ探し、歩ける面があれば吸い付いて接地にする
    #   地面にいた体：地面に沿って動いているあいだ（IsLeavingGround でない）、GroundSnapCm（GroundProbeCm より小さければ GroundProbeCm）まで探す。坂を下る・低い段を降りるときも浮かない
    #   空中の体：下がっている（上下の速さが 0 以下）ときだけ、GroundProbeCm まで探す
    #   接地したら、速度を地面に沿わせる（水平の速さはそのまま、上下の速さを地面の傾きに合わせる。平らな地面なら上下の速さが 0）。当たった entity を立っている物（GetGroundEntity）にする
    #   空中から接地したら、動く地面から受け継いだ速度（GetInheritedVelocity）を 0 にする
    #   掃引の始めから触れている当たり（横の壁にめり込みかけ）は地面にしない（FindGroundHit。壁を床と取り違えて、壁の途中に重力なしで立ったまま止まらない）
    UpdateGround<private>():void =
        WasGrounded := Grounded
        var NowGrounded:logic = false
        var NowGround:?entity = false
        Probing := if (WasGrounded?) then (if (IsLeavingGround[]) then false else true) else (if (Velocity.Up <= 0.0) then true else false)
        ProbeCm := if (WasGrounded?) then Max(GroundProbeCm, GroundSnapCm) else GroundProbeCm
        MaybeHit:?sweep_hit = if (Probing?) then FindGroundHit(ProbeCm) else false
        if (Hit := MaybeHit?, IsWalkable[Hit.ContactNormal]):
            set NowGrounded = true
            set NowGround = option{Hit.TargetComponent.Entity}
            set GroundNormal = Hit.ContactNormal
            MoveBy(vector3{Up := -Max(Hit.SourceHitDistance - SkinCm, 0.0)})
            if (not WasGrounded?):
                set LastLandingSpeed = Max(-Velocity.Up, 0.0)
                set InheritedVelocity = vector3{}
            set Velocity = AlongGround(Velocity, Hit.ContactNormal)
        set Grounded = NowGrounded
        set GroundEntity = NowGround
        if (WasGrounded? and not NowGrounded?):
            ReportAction(character_action.LeftGround)
        else if (not WasGrounded? and NowGrounded?):
            ReportAction(character_action.Landed)
            LandedEventInternal.Signal(LastLandingSpeed)

    # 足元から下へ DistanceCm（+ SkinCm）まで探して、最初に当たったもの。無ければ false
    #   掃引の始めから触れている当たりは使わない：押し出せたらそこから探し直し、押し出せなければその物を除いて探し直す（その下に本当の床があれば見つかる）
    FindGroundHit<private>(DistanceCm:float)<transacts>:?sweep_hit =
        Down := vector3{Up := -(DistanceCm + SkinCm)}
        if (First := FindFirstHit[Down]):
            if (not IsStartHit[First]):
                return option{First}
            Pushed := TryDepenetrate(First, Down)
            Except:?entity = if (Pushed?) then false else option{First.TargetComponent.Entity}
            if (Again := FindFirstHitFromExcept[Entity.GetGlobalTransform().Translation, Down, Except], not IsStartHit[Again]):
                return option{Again}
        false

    UpdateMoving<private>():void =
        Horizontal := vector3{Forward := Velocity.Forward, Left := Velocity.Left}
        NowMoving := if (Horizontal.Length() > MovingSpeedCmPerSecond) then true else false
        if (NowMoving <> Moving):
            set Moving = NowMoving
            ReportAction(if (NowMoving?) then character_action.StartedMoving else character_action.StoppedMoving)

    # Normal が立っていられる坂（MaxSlopeDegrees 以下）なら成功する
    IsWalkable<private>(Normal:vector3)<decides><transacts>:void =
        Normal.Up >= Cos(MaxSlopeDegrees * PiFloat / 180.0)

    # このカプセルを今の位置から Displacement だけ掃引して、最初に当たったもの（自分と持ち主の Fortnite キャラクターは除く）。当たらなければ失敗する
    FindFirstHit<private>(Displacement:vector3)<decides><transacts>:sweep_hit =
        FindFirstHitFrom[Entity.GetGlobalTransform().Translation, Displacement]

    # このカプセルを足元 Feet（世界の位置）に置いたとして、Displacement だけ掃引して最初に当たったもの。当たらなければ失敗する（体は動かさない。角・段の補正の下調べに使う）
    FindFirstHitFrom<private>(Feet:vector3, Displacement:vector3)<decides><transacts>:sweep_hit =
        FindFirstHitFromExcept[Feet, Displacement, false]

    # FindFirstHitFrom と同じ。Except の entity に当たったものも除く（動く床に運ぶとき、その床には当たらない）
    FindFirstHitFromExcept<private>(Feet:vector3, Displacement:vector3, Except:?entity)<decides><transacts>:sweep_hit =
        Capsule := collision_capsule{}
        set Capsule.Radius = RadiusCm
        set Capsule.Length = Max(HeightCm - RadiusCm * 2.0, 0.0)
        Center := Feet + vector3{Up := HeightCm / 2.0}
        var Found:?sweep_hit = false
        for (Hit : Entity.FindSweepHits(Displacement, MakeTranslationTransform(Center), Capsule), not Found?, not IsIgnored[Hit.TargetComponent.Entity], not IsOptionEntity[Hit.TargetComponent.Entity, Except]):
            set Found = option{Hit}
        Found?

    # 自分（この entity とその子孫）か、持ち主の Fortnite キャラクターなら成功する
    IsIgnored<private>(Other:entity)<decides><transacts>:void =
        var Current:?entity = option{Other}
        var Ignored:logic = false
        if (Player := Owner?, Body := Player.FindPlayerEntity[], Body = Other):
            set Ignored = true
        loop:
            if (Ignored?):
                break
            if (Candidate := Current?):
                if (Candidate = Entity):
                    set Ignored = true
                else:
                    set Current = if (Parent := Candidate.GetParent[]) then option{Parent} else false
            else:
                break
        Ignored?

    # AxisLock で縛る軸の値
    LockedComponent<private>(V:vector3)<transacts>:float =
        case (AxisLock):
            character_axis_lock.Left => V.Left
            character_axis_lock.Forward => V.Forward
            character_axis_lock.None => 0.0

    # V の縛る軸の値を Value にする（縛らないならそのまま）
    ApplyLock<private>(V:vector3, Value:float)<transacts>:vector3 =
        case (AxisLock):
            character_axis_lock.Left => vector3{Forward := V.Forward, Left := Value, Up := V.Up}
            character_axis_lock.Forward => vector3{Forward := Value, Left := V.Left, Up := V.Up}
            character_axis_lock.None => V

    MoveBy<private>(Delta:vector3)<transacts>:void =
        Current := Entity.GetGlobalTransform()
        Entity.SetGlobalTransform(Current.WithTranslation(Current.Translation + Delta))

# 役割：character_motor_component.AddModifier が返す、変更を外すための cancelable（実行時だけ）
character_modifier_handle<internal> := class<internal>(cancelable):
    Motor<internal>:character_motor_component
    Id<internal>:int
    var<private> Canceled:logic = false

    Cancel<override>()<transacts>:void =
        if (not Canceled?):
            set Canceled = true
            Motor.RemoveModifier(Id)

# 役割：character_motor_component.LockInput が返す、入力の止めを外すための cancelable（実行時だけ）
character_input_lock_handle<internal> := class<internal>(cancelable):
    Motor<internal>:character_motor_component
    Id<internal>:int
    var<private> Canceled:logic = false

    Cancel<override>()<transacts>:void =
        if (not Canceled?):
            set Canceled = true
            Motor.UnlockInput(Id)

# Candidate が Maybe の中身と同じ entity なら成功する（Maybe が false なら失敗する）
IsOptionEntity<internal>(Candidate:entity, Maybe:?entity)<decides><transacts>:void =
    Other := Maybe?
    Other = Candidate

# V から Normal の向きの成分を除く（面に沿わせる）
RemoveComponent<internal>(V:vector3, Normal:vector3)<reads>:vector3 =
    V - Normal * DotProduct(V, Normal)

# V を地面（向き Normal。上向き）に沿わせる：水平の速さはそのまま、上下の速さを地面の傾きに合わせる（V と Normal の内積を 0 にする）。Normal がほぼ横向きなら上下の速さを 0 にする
AlongGround<internal>(V:vector3, Normal:vector3)<reads>:vector3 =
    UpValue := if (Normal.Up > 0.01) then -(V.Forward * Normal.Forward + V.Left * Normal.Left) / Normal.Up else 0.0
    vector3{Forward := V.Forward, Left := V.Left, Up := UpValue}

# MakeRotationFromYawPitchRollDegrees のヨーが左回りなら 1.0、右回りなら -1.0（90 度で回した前の軸の Left で確かめる）
#   ArcTan(Left, Forward) は「左へ回ると正」なので、角度をヨーに渡すときはこれを掛ける（v43.00 実機：ヨーの正は右回り）
#   BodyKit（向き）と MoveKit（walk の TankTurn）の両方が使うので、CharacterSystem の直下に置く
YawSign<internal>()<reads>:float =
    if (MakeRotationFromYawPitchRollDegrees(90.0, 0.0, 0.0).GetForwardAxis().Left >= 0.0) then 1.0 else -1.0
