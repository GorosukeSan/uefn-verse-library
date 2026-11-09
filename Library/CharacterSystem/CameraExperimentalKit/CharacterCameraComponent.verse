using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/SceneGraphCameras }
using { CharacterSystem }
using { CharacterSystem.TooltipKit }

# カメラの写し方
character_camera_projection<public> := enum:
    # 遠近のある写し方（3D）
    Perspective
    # 遠近の無い写し方（2D・見下ろし型）
    Orthographic

# カメラの動かし方
character_camera_rig<public> := enum:
    # 持ち主が視点の入力（マウス・右スティック）でキャラクターの周りを回せる（fort_orbit_camera_modifier）
    Orbit
    # 決めた位置・向きでキャラクターに付いていく（OffsetCm・YawDegrees・PitchDegrees。横スクロールなど）
    Fixed

# 役割：持ち主の視点を、独自キャラクターを写すカメラにする。この entity の子にカメラの entity を作り、持ち主の camera_director_component に Priority で足す。止まると外して消す
#   Rig = Orbit（既定）：fort_orbit_camera_modifier で、持ち主が視点の入力でキャラクターの周りを回せる（OrbitDistanceCm・OrbitHeightCm・OrbitCollision）。歩く向きは character_walk_component の Space = View で視点に合う
#   Rig = Fixed：カメラはこの entity の子として OffsetCm・YawDegrees・PitchDegrees の位置・向きで付いていく（毎フレーム Verse で動かさない）。character_face_movement_component と同じ entity に置くと一緒に回る
# 置き方：エディターで、独自キャラクターの entity（character_motor_component と同じ entity）に付ける
# 前提・注意：@experimental のカメラ API（camera_component・camera_director_component）を使う。島を公開できない（VerseShare では「実験的を含む」のプロジェクトにだけ配る）
# ⚠ 未検証：Yaw / Pitch の正の向き。写る向きが違うときは YawDegrees / PitchDegrees で合わせる
character_camera_component<public> := class<final_super>(component):

    # カメラの動かし方。既定 Orbit（持ち主が回せる）
    @editable:
        ToolTip := CameraRigToolTip
        Categories := array{CharacterCameraCategory}
    Rig<public>:character_camera_rig = character_camera_rig.Orbit
    # Orbit：回る中心からカメラまでの距離（cm）。既定 600
    @editable_number(float):
        ToolTip := CameraOrbitDistanceToolTip
        Categories := array{CharacterCameraCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    OrbitDistanceCm<public>:float = 600.0
    # Orbit：回る中心の、キャラクターの足元からの高さ（cm）。既定 150
    @editable_number(float):
        ToolTip := CameraOrbitHeightToolTip
        Categories := array{CharacterCameraCategory}
        MinValue := option{-1000.0}
        MaxValue := option{5000.0}
    OrbitHeightCm<public>:float = 150.0
    # Orbit：カメラが壁などにめり込まないよう近づける。既定オフ
    #   ⚠ v43.00 の実機では、オンにすると接地中にカメラが回る中心まで引き戻されて一人称になった（ジャンプ中だけ三人称。原因は未確認）
    @editable:
        ToolTip := CameraOrbitCollisionToolTip
        Categories := array{CharacterCameraCategory}
    OrbitCollision<public>:logic = false
    # 写し方。既定 Perspective
    @editable:
        ToolTip := CameraProjectionToolTip
        Categories := array{CharacterCameraCategory}
    Projection<public>:character_camera_projection = character_camera_projection.Perspective
    # Fixed：カメラの位置（キャラクターの足元からのずらし、cm）。既定は後ろ 600・上 250
    @editable:
        ToolTip := CameraOffsetToolTip
        Categories := array{CharacterCameraCategory}
    OffsetCm<public>:vector3 = vector3{Forward := -600.0, Up := 250.0}
    # Fixed：カメラの水平の向き（度）。既定 0（キャラクターの前）
    @editable_number(float):
        ToolTip := CameraYawToolTip
        Categories := array{CharacterCameraCategory}
        MinValue := option{-360.0}
        MaxValue := option{360.0}
    YawDegrees<public>:float = 0.0
    # Fixed：カメラの上下の向き（度。負で見下ろす）。既定 -15
    @editable_number(float):
        ToolTip := CameraPitchToolTip
        Categories := array{CharacterCameraCategory}
        MinValue := option{-89.0}
        MaxValue := option{89.0}
    PitchDegrees<public>:float = -15.0
    # 遠近のある写し方の水平の画角（度）。既定 90
    @editable_number(float):
        ToolTip := CameraFieldOfViewToolTip
        Categories := array{CharacterCameraCategory}
        MinValue := option{10.0}
        MaxValue := option{170.0}
    FieldOfViewDegrees<public>:float = 90.0
    # 遠近の無い写し方で、画面の横幅に写る長さ（cm）。既定 3000
    @editable_number(float):
        ToolTip := CameraOrthographicWidthToolTip
        Categories := array{CharacterCameraCategory}
        MinValue := option{100.0}
        MaxValue := option{100000.0}
    OrthographicWidthCm<public>:float = 3000.0
    # ほかのカメラより優先する度合い（大きいほど優先）。既定 10
    @editable_number(int):
        ToolTip := CameraPriorityToolTip
        Categories := array{CharacterCameraCategory}
        MinValue := option{0}
        MaxValue := option{1000}
    Priority<public>:int = 10

    var<private> CameraEntity:?entity = false
    var<private> PivotEntity:?entity = false
    var<private> CameraBody:?camera_component = false
    var<private> Owner:?player = false
    var<private> Handle:?cancelable = false
    var<private> OrbitHandle:?cancelable = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Motor := Entity.FindCharacterMotorAbove[], Found := Motor.FindOwner[]):
            set Owner = option{Found}
            CreateCamera()
        else:
            Print("[character_camera_component] 持ち主の独自キャラクターが見つかりません（ロードアウトの中の、character_motor_component と同じ entity に置いてください）")

    # カメラの entity がシーンに入ってから（1 フレーム後）モディファイアを積み、持ち主のディレクターに足す。
    #   シーンに入る前の camera_component に積んだ Orbit は効かず、体の位置から写る一人称のままだった（実機 v43.00）
    OnSimulate<override>()<suspends>:void =
        Sleep(0.0)
        if (Body := CameraBody?, Found := Owner?):
            Activate(Body, Found)

    # 作ったカメラの entity（無ければ失敗）。診断用（カメラの位置・向きを読む）
    FindCameraEntity<public>()<decides><transacts>:entity = CameraEntity?

    # Orbit のモディファイアを積めたか。診断用
    HasOrbit<public>()<decides><transacts>:void = OrbitHandle?

    OnEndSimulation<override>():void =
        if (Current := OrbitHandle?):
            Current.Cancel()
        set OrbitHandle = false
        if (Current := Handle?):
            Current.Cancel()
        set Handle = false
        if (Current := CameraEntity?):
            Current.RemoveFromParent()
        set CameraEntity = false
        if (Current := PivotEntity?):
            Current.RemoveFromParent()
        set PivotEntity = false
        set CameraBody = false
        (super:)OnEndSimulation()

    CreateCamera<private>():void =
        Camera := entity{}
        if (Rig = character_camera_rig.Fixed):
            Camera.SetLocalTransform(transform{Translation := OffsetCm, Rotation := MakeRotationFromYawPitchRollDegrees(YawDegrees, PitchDegrees, 0.0), Scale := vector3{Forward := 1.0, Left := 1.0, Up := 1.0}})
        Body := MakeCamera(Camera)
        Camera.AddComponents(array{Body})
        Entity.AddEntities(array{Camera})
        set CameraEntity = option{Camera}
        set CameraBody = option{Body}
        if (Rig = character_camera_rig.Orbit):
            # 回る中心は足元ではなく、足元から OrbitHeightCm 上の子の entity にする。
            #   足元（体の根）を中心にすると、接地中は根が床にわずかにめり込み、カメラの当たり判定が床の中から始まってカメラが足元へ引き戻された（ジャンプ中だけ三人称・着地で一人称。実機 v43.00）
            Pivot := entity{}
            Pivot.SetLocalTransform(transform{Translation := vector3{Up := OrbitHeightCm}, Rotation := IdentityRotation(), Scale := vector3{Forward := 1.0, Left := 1.0, Up := 1.0}})
            Entity.AddEntities(array{Pivot})
            set PivotEntity = option{Pivot}

    Activate<private>(Body:camera_component, Found:player):void =
        Directors := for (Director : Found.FindDescendantComponents(camera_director_component)):
            Director
        if (Director := Directors[0], Added := Director.AddCamera[Body, Priority]):
            set Handle = option{Added}
            if (Rig = character_camera_rig.Orbit, Pivot := PivotEntity?):
                Orbit := fort_orbit_camera_modifier:
                    TargetEntity := Pivot
                    CameraDistanceCentimeters := OrbitDistanceCm
                    CameraHeightCentimeters := 0.0
                    EnableCollision := OrbitCollision
                # カメラ本体の CameraModifiers（Main レイヤー）に積む。カメラの entity がシーンに入ってから積む（入る前に積んだものは効かなかった：実機 v43.00）
                Stack := Body.CameraModifiers
                set OrbitHandle = option{Stack.AddModifier(Orbit, Stack.LastPosition)}
            Print("[character_camera_component] カメラを足しました（ディレクター {Directors.Length} 個の 1 つ目、優先度 {Priority}、Rig {if (Rig = character_camera_rig.Orbit) then "Orbit" else "Fixed"}）")
        else:
            Print("[character_camera_component] 持ち主の camera_director_component が見つからないか、カメラを足せませんでした（ディレクター {Directors.Length} 個）")

    MakeCamera<private>(Camera:entity):camera_component =
        case (Projection):
            character_camera_projection.Orthographic =>
                Ortho := orthographic_camera_component{Entity := Camera}
                set Ortho.OrthographicProjectionWidth = OrthographicWidthCm
                Ortho
            character_camera_projection.Perspective =>
                Perspective := perspective_camera_component{Entity := Camera}
                set Perspective.FieldOfView = FieldOfViewDegrees * PiFloat / 180.0
                Perspective
