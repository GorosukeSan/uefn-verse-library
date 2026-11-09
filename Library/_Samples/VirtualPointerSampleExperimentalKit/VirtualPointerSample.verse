using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Verse.org/Input/UI }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { /UnrealEngine.com/Temporary }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }

# 役割：Virtual Pointer（画面のカーソル）の見本。動いているあいだ、全プレイヤーに TouchMapping を足してポインターを出し、クリック（PointerSelect の押し始め）の画面座標を DeprojectViewportToWorld で光線にし、FindSweepHits で当たった場所を求める
#   (a) 当たった位置（LUF、cm）を Print する
#   (b) TeleportOnClick なら、その人をそこへ移動する
#   (c) UseOverheadCamera なら、その人の真上 CameraHeightCm に perspective_camera_component を作って camera_director_component.AddCamera で足す（俯瞰で地面をクリックしやすい）
#   止まるときは Mapping・カメラを必ず外す
# 置き方：エディターで空の entity に付ける。区画（または世界）に player_manager_component を 1 つ置く
# 試し方：セッションを始めると（StartOnBegin）ポインターが出る。地面をクリックすると出力ログと画面に当たった位置が出る。TeleportOnClick をオンにするとその場所へ移動する。UseOverheadCamera をオンにすると上空から見下ろす
# いつ：StartOnBegin が true ならシミュレーション開始から。false なら起動の合図（activated_event）から停止の合図（deactivated_event）まで
# 知らせ：ClickedEvent（クリックした人と、当たった世界座標）。ほかの component はこれを購読してポインターを使える
# 前提・注意：
#   - camera 系の component は v43.00 でも @experimental（使うと島を公開できない）。UseOverheadCamera はオフが既定
#   - プレイサーバーで camera_director_component が見つからない既知の不具合（v43.00）がある。見つからないときはカメラ無しで続ける
#   - 光線はカメラの目の位置から出るので、自分のキャラクターに当たった分は除く
virtual_pointer_sample_component<public> := class<final_super>(component):

    # オンなら、シミュレーション開始から始める。オフなら起動の合図を待つ
    @editable
    StartOnBegin<public>:logic = true

    # オンなら、クリックした場所へその人を移動する
    @editable
    TeleportOnClick<public>:logic = false

    # オンなら、その人の真上に俯瞰カメラを足す（@experimental）
    @editable
    UseOverheadCamera<public>:logic = false

    # 俯瞰カメラの高さ（cm）
    @editable
    CameraHeightCm<public>:float = 3000.0

    # クリック先を探す光線の長さ（cm）
    @editable
    MaxTraceDistanceCm<public>:float = 100000.0

    # 移動先を当たった面から浮かせる高さ（cm）
    @editable
    LandingOffsetCm<public>:float = 100.0

    ClickedEventInternal<private><final>:event(tuple(agent, vector3)) = event(tuple(agent, vector3)){}

    # クリックして何かに当たるたびに、(クリックした人, 当たった世界座標) で届く（Await / Subscribe する。外から Signal はできない）
    ClickedEvent<public><final>:listenable(tuple(agent, vector3)) = MakeProxyListenable(ClickedEventInternal)

    Views<private>:player_view_set = player_view_set{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (StartOnBegin?):
            Activate()

    OnReceive<override>(SceneEvent:scene_event):logic =
        Views.HandleActivation(SceneEvent, Entity, CreateView)
        false

    OnEndSimulation<override>():void =
        Views.Deactivate()
        (super:)OnEndSimulation()

    # 全員（途中参加も）にポインターを出す。もう出していれば何もしない
    Activate<public>():void =
        Views.Activate(Entity, CreateView)

    # 全員のポインター・カメラを外す
    Deactivate<public>():void =
        Views.Deactivate()

    # 動いているあいだ成功する
    IsActive<public>()<decides><transacts>:void =
        Views.IsActive[]

    CreateView<private>(ViewEntity:entity, Slot:player_slot_component):component =
        virtual_pointer_view_component{Entity := ViewEntity, Source := Self, Player := Slot.Player}

    # view から呼ばれる
    NotifyClicked<internal>(Agent:agent, Position:vector3):void =
        ClickedEventInternal.Signal((Agent, Position))

# 役割：1 人分のポインター。TouchMapping を足し、クリックを待って光線を飛ばす。俯瞰カメラもこの entity の子に作る（view が消えると一緒に消える）
# 置き方：実行時に virtual_pointer_sample_component が作る（エディターでは置かない）
virtual_pointer_view_component<public> := class<final_super>(component):

    Source<public>:virtual_pointer_sample_component
    Player<public>:player

    var<private> CameraEntity:?entity = false

    OnSimulate<override>()<suspends>:void =
        if (PlayerInput := GetPlayerInput[Player]):
            PlayerInput.AddInputMapping(TouchMapping)
            defer:
                PlayerInput.RemoveInputMapping(TouchMapping)
            if (Source.UseOverheadCamera?):
                CameraComponent := MakeOverheadCamera()
                if (Director := FindCameraDirector[], CameraHandle := Director.AddCamera[CameraComponent, 1000]):
                    defer:
                        CameraHandle.Cancel()
                    RunPointer(PlayerInput)
                else:
                    Print("[virtual_pointer_sample] カメラを足せませんでした（camera_director_component が無い）。カメラ無しで続けます", ?Duration := 6.0)
                    RunPointer(PlayerInput)
            else:
                RunPointer(PlayerInput)
        else:
            Print("[virtual_pointer_sample] この人の入力（player_input）が取れません")

    OnEndSimulation<override>():void =
        if (Camera := CameraEntity?):
            Camera.RemoveFromParent()
        set CameraEntity = false
        (super:)OnEndSimulation()

    RunPointer<private>(PlayerInput:player_input)<suspends>:void =
        Print("[virtual_pointer_sample] ポインターが出ました。地面をクリックしてください", ?Duration := 6.0)
        loop:
            Clicked := PlayerInput.GetInputEvents(PointerSelect).BeginDetectEvent.Await()
            ScreenPosition := Clicked(1)
            Ray := Player.DeprojectViewportToWorld(ScreenPosition)
            if (Hit := FindHit[Ray]):
                Print("[virtual_pointer_sample] 当たった位置 (cm): L={Hit.Left} U={Hit.Up} F={Hit.Forward}", ?Duration := 4.0)
                Source.NotifyClicked(Player, Hit)
                if (Source.TeleportOnClick?):
                    Teleport(Hit)
            else:
                Print("[virtual_pointer_sample] クリック先に何も当たりませんでした（画面座標 L={ScreenPosition.Left} U={ScreenPosition.Up}）", ?Duration := 4.0)

    # 光線を飛ばし、自分のキャラクターを除いて一番近い当たりの位置を返す
    FindHit<private>(Ray:deproject_results)<decides><transacts>:vector3 =
        var Best:?vector3 = false
        var BestDistance:float = Source.MaxTraceDistanceCm
        Start := transform{Translation := Ray.Origin, Rotation := IdentityRotation(), Scale := vector3{Forward := 1.0, Left := 1.0, Up := 1.0}}
        Probe := collision_sphere{Radius := 20.0}
        for (Hit : Entity.FindSweepHits(Ray.Direction * Source.MaxTraceDistanceCm, Start, Probe)):
            if (not IsOwnBody[Hit.TargetComponent.Entity], Hit.SourceHitDistance < BestDistance):
                set Best = option{Hit.ContactPosition}
                set BestDistance = Hit.SourceHitDistance
        Best?

    # HitEntity が自分（player の entity かキャラクターの entity）か、その子孫なら成功する
    IsOwnBody<private>(HitEntity:entity)<decides><transacts>:void =
        var Current:entity = HitEntity
        var Found:logic = false
        loop:
            if (Current = Player):
                set Found = true
                break
            if (FortCharacter := Player.GetFortCharacter[], CharacterEntity := FortCharacter.GetEntity[], Current = CharacterEntity):
                set Found = true
                break
            if (Parent := Current.GetParent[]):
                set Current = Parent
            else:
                break
        Found?

    Teleport<private>(Hit:vector3):void =
        Landing := Hit + vector3{Up := Source.LandingOffsetCm}
        if (FortCharacter := Player.GetFortCharacter[]):
            if (FortCharacter.TeleportTo[SpatialMath.FromVector3(Landing), SpatialMath.FromRotation(IdentityRotation())]):
                Print("[virtual_pointer_sample] 移動しました", ?Duration := 3.0)
                PlaceCameraAbove(Landing)
            else:
                Print("[virtual_pointer_sample] そこへは移動できません（はまる場所など）", ?Duration := 3.0)

    # 俯瞰カメラの entity をこの entity の子に作り、その人の真上に置く（camera_director_component に足すのは呼んだ側）
    MakeOverheadCamera<private>():perspective_camera_component =
        Camera := entity{}
        CameraComponent := perspective_camera_component{Entity := Camera}
        Camera.AddComponents(array{CameraComponent})
        Entity.AddEntities(array{Camera})
        set CameraEntity = option{Camera}
        if (FortCharacter := Player.GetFortCharacter[], CharacterEntity := FortCharacter.GetEntity[]):
            PlaceCameraAbove(CharacterEntity.GetGlobalTransform().Translation)
        CameraComponent

    # その人の camera_director_component（player の entity の子孫にある）。無ければ失敗する（v43.00 のプレイサーバーの既知の不具合でも失敗する）
    FindCameraDirector<private>()<decides><transacts>:camera_director_component =
        first (Found : Player.FindDescendantComponents(camera_director_component)):
            Found

    # 俯瞰カメラを Position の真上へ置き、まっすぐ下を向ける
    PlaceCameraAbove<private>(Position:vector3)<transacts>:void =
        if (Camera := CameraEntity?):
            Camera.SetGlobalTransform(transform:
                Translation := Position + vector3{Up := Source.CameraHeightCm}
                Rotation := MakeRotationFromYawPitchRollDegrees(0.0, -90.0, 0.0)
                Scale := vector3{Forward := 1.0, Left := 1.0, Up := 1.0}
            )
