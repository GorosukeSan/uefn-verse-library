using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Assets }
using { /Fortnite.com/Input }
using { CharacterSystem }
using { CharacterSystem.BodyKit }
using { CharacterSystem.CameraExperimentalKit }
using { CharacterSystem.MoveKit }
using { PlayerSystem }
using { ActivationSystem }
using { SceneGraphSystem }
using { VolumeSystem }

# 役割：独自キャラクター（CharacterSystem）の見本。横スクロールの 2D で、移動・ジャンプ・ゴールだけがある
#   StartOnBegin なら参加した人ごと（オフなら、ボタンなど だれが起こしたかの分かる起動の合図を受けた人だけ）に、その人の slot の下に独自キャラクター（character_motor_component・walk・jump・owner_stasis・camera）を作る。作るのはこの component の位置（スタート）
#   動きは左右（世界の前後。AxisLock = Left）とジャンプ（2 段ジャンプ・短く押すと低い）。見た目は Fortnite のキャラクター（隠さずに体へ付いていかせる）。カメラは横から見る正射影
#   Fortnite のラウンドが始まるたびに、全員をスタートへ戻す。ゴール（この entity から GoalOffsetCm の位置、GoalSizeCm の箱）に入ると、Print して、スタートへ戻す
# 置き方：エディターで、床（当たり判定のあるメッシュ）の上の空の entity に付ける。前（Forward）の向きに床・足場を並べ、GoalOffsetCm の先に着地できる場所を作る。区画（または世界）に player_manager_component を 1 つ置く
# 試し方：左右（移動の入力）で動き、ジャンプで跳ぶ。ゴールに着くと「ゴール」と出てスタートに戻る
# 前提・注意：移動の入力 Character.Move と、カメラ（CameraExperimentalKit）は @experimental。この見本は島を公開できない（VerseShare では「実験的を含む」のプロジェクトにだけ配る）
# ⚠ 未検証：カメラの向き（YawDegrees）。横から写らないときは CameraYawDegrees の符号を変える
platformer_2d_sample_component<public> := class<final_super>(component):

    # 左右の入力（方向の入力）。既定は Fortnite の移動（@experimental）
    @editable
    MoveAction<public>:input_action(vector3) = Character.Move
    # ゴールの位置（この entity からのずらし、cm）。既定は前に 3000
    @editable
    GoalOffsetCm<public>:vector3 = vector3{Forward := 3000.0}
    # ゴールの箱の大きさ（cm）。既定 300
    @editable
    GoalSizeCm<public>:float = 300.0
    # カメラの水平の向き（度）。横から写らないときは符号を変える。既定 -90
    @editable
    CameraYawDegrees<public>:float = -90.0
    # オンなら、開始から全員に独自キャラクターを作る。オフなら、だれが起こしたかの分かる起動の合図（ボタン・ボリュームの入り口など）を受けた人にだけ作る。既定オン
    @editable
    StartOnBegin<public>:logic = true
    # オンなら、ゴールでその人の独自キャラクターを消す（操作が Fortnite のキャラクターに戻る）。オフならスタートへ戻す。既定オフ
    @editable
    ExitOnGoal<public>:logic = false

    var<private> Characters:[agent]entity = map{}
    var<private> Subscriptions:[]cancelable = array{}
    var<private> Goal:?entity = false
    Rounds<private>:round_watcher = round_watcher{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        MakeGoal()
        # Fortnite のラウンドが始まるたびに、全員をスタートへ戻す
        Rounds.Start(Entity, OnRoundStarted, OnRoundEnded)
        if (Manager := Entity.FindScopedComponent[player_manager_component]):
            set Subscriptions += array{Manager.PlayerRemovedEvent.Subscribe(OnPlayerRemoved)}
            if (StartOnBegin?):
                set Subscriptions += array{Manager.PlayerAddedEvent.Subscribe(OnPlayerAdded)}
                for (Slot : Manager.GetSlots()):
                    Spawn(Slot)
        else:
            Print("[platformer_2d_sample_component] player_manager_component が見つかりません")

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        Rounds.Stop()
        for (Agent -> Pawn : Characters):
            Pawn.RemoveFromParent()
        set Characters = map{}
        if (Current := Goal?):
            Current.RemoveFromParent()
        set Goal = false
        (super:)OnEndSimulation()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent], Agent := SceneEvent.FindActivatingAgent[], Player := player[Agent]):
            OnPlayerAdded(Player)
        else if (deactivated_event[SceneEvent], not StartOnBegin?):
            for (Agent -> Pawn : Characters):
                OnPlayerRemoved(Agent)
        false

    OnPlayerAdded<private>(Player:player):void =
        if (Manager := Entity.FindScopedComponent[player_manager_component], Slot := Manager.FindSlot[Player]):
            Spawn(Slot)

    OnPlayerRemoved<private>(Agent:agent):void =
        if (Pawn := Characters[Agent]):
            Pawn.RemoveFromParent()
            set Characters = Characters.RemoveKey(Agent)

    # 1 人分の独自キャラクターを、その人の slot の下に作る（slot の下なので、持ち主はその人になる）
    Spawn<private>(Slot:player_slot_component):void =
        if (Characters[Slot.Player]):
            return
        Pawn := entity{}
        Pawn.SetGlobalTransform(MakeTranslationTransform(GetStart()))
        Camera := character_camera_component:
            Entity := Pawn
            Projection := character_camera_projection.Orthographic
            OffsetCm := vector3{Left := 2000.0, Up := 150.0}
            YawDegrees := CameraYawDegrees
            PitchDegrees := 0.0
            OrthographicWidthCm := 2500.0
        Parts:[]component = array:
            character_motor_component{Entity := Pawn, AxisLock := character_axis_lock.Left, SpawnAtOwner := false, ResetOnRoundStart := false}
            character_walk_component{Entity := Pawn, MoveAction := option{MoveAction}, Space := character_walk_space.SideView, MaxSpeedCmPerSecond := 700.0}
            character_jump_component{Entity := Pawn, AirJumps := 1, JumpSpeedCmPerSecond := 1000.0}
            character_owner_stasis_component{Entity := Pawn}
            Camera
        Pawn.AddComponents(Parts)
        Slot.Entity.AddEntities(array{Pawn})
        if (set Characters[Slot.Player] = Pawn) {}

    # ゴールの箱を作る（player_volume_component。入ったら OnGoal）
    MakeGoal<private>():void =
        GoalEntity := entity{}
        GoalEntity.SetGlobalTransform(MakeTranslationTransform(GetStart() + GoalOffsetCm))
        Volume := player_volume_component{Entity := GoalEntity, WidthCm := GoalSizeCm, DepthCm := GoalSizeCm * 4.0, HeightCm := GoalSizeCm, PollIntervalSeconds := 0.1}
        GoalEntity.AddComponents(array{Volume})
        Entity.AddEntities(array{GoalEntity})
        set Goal = option{GoalEntity}
        set Subscriptions += array{Volume.PlayerEnteredEvent.Subscribe(OnGoal)}

    OnGoal<private>(Agent:agent):void =
        if (ExitOnGoal?):
            Print("[platformer_2d_sample_component] ゴール！", ?Duration := 3.0)
            OnPlayerRemoved(Agent)
            return
        Print("[platformer_2d_sample_component] ゴール！スタートに戻ります", ?Duration := 3.0)
        if (Pawn := Characters[Agent], Motor := Pawn.GetComponent[character_motor_component]):
            Motor.SetVelocity(vector3{})
            Motor.TeleportTo(GetStart())

    OnRoundStarted<private>()<suspends>:void =
        for (Agent -> Pawn : Characters, Motor := Pawn.GetComponent[character_motor_component]):
            Motor.SetVelocity(vector3{})
            Motor.TeleportTo(GetStart())

    OnRoundEnded<private>():void = {}

    GetStart<private>()<transacts>:vector3 =
        Entity.GetGlobalTransform().Translation
