using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { MovementSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { CheckpointSystem.TooltipKit }

# チェックポイントの上に乗った知らせ。方向：区画全体（SendScoped。区画の根から SendDown、区画が無ければ世界全体）
# 送り手：checkpoint_component（Checkpoint）。Agent が上面に乗ったとき（ReachedEvent と同じタイミング。初めてかどうかは問わない）
# 受け手：checkpoint_presence_component、到達を数える component など。消費しない
checkpoint_reached_event<public> := class(scene_event):
    # 乗られたチェックポイント（知らせの送り元）
    Checkpoint<public>:checkpoint_component
    # 乗った人
    Agent<public>:agent

# チェックポイントから降りた知らせ。方向：区画全体（SendScoped。区画の根から SendDown、区画が無ければ世界全体）
# 送り手：checkpoint_component（Checkpoint）。Agent が上面から降りたとき・退出したとき・チェックポイントが世界から外れたとき（LeftEvent と同じタイミング）
# 受け手：checkpoint_presence_component など。消費しない
checkpoint_left_event<public> := class(scene_event):
    # 降りられたチェックポイント（知らせの送り元）
    Checkpoint<public>:checkpoint_component
    # 降りた人（退出した人を含む）
    Agent<public>:agent

# チェックポイントの上に立っている人（agent）に付くタグ。checkpoint_component が付け外しする（ほかの System は Agent.HasPlayerTag[on_checkpoint_tag] で確かめる）
on_checkpoint_tag<public> := class(player_state_tag):

# 役割：下からは通り抜けて上に乗れるが、上からは降りられない足場。この entity の位置を真ん中に、幅 WidthCm・奥行き DepthCm・厚さ ThicknessCm（センチメートル）の箱として扱う。毎フレーム、区画の全プレイヤーを見て、箱の真下（ApproachCm 以内）から上へ動いている人を上面の上へ移す（固いメッシュをすり抜けたように見せる。Verse ではコリジョンを人ごとに変えられないため）。上面に立っているかも毎フレーム確かめ、乗った・降りたを知らせる
#   見るのは同じ区画のチェックポイントでまとめて 1 か所（内部の checkpoint_tracker）。プレイヤーの位置は 1 フレームに 1 人 1 回だけ読み、すべてのチェックポイントと比べる（チェックポイントの数だけ全員の位置を読まない）
# 置き方：エディターで entity に付ける（実行時に checkpoint_factory_component が付けることもある）
# 同じ entity：当たり判定のあるメッシュ（WidthCm × DepthCm × ThicknessCm の大きさにする）
# いつ：シミュレーション開始から止まるまで。同じ区画のチェックポイントのうち 1 つの TickEvents.PrePhysics で、全部をまとめて確かめる
# 知らせ：乗ったとき checkpoint_reached_event と ReachedEvent、降りたとき checkpoint_left_event と LeftEvent。退出した人・止まるとき（世界から外れるとき）に立っていた人には、降りた知らせを出して立っている状態を消す
# タグ：立っているあいだ、その人（agent）に on_checkpoint_tag を付ける
# 外から：IsStanding で、だれかが立っているかを聞く（区画のどこに乗っているかをまとめて聞くなら PresenceKit の checkpoint_presence_component）
# 前提：区画（game_scope_component。無ければ世界）に player_manager_component が 1 つ。最初に見つけたものを覚えておく（見つかるまでは 1 秒ごとに探す）
checkpoint_component<public> := class<final_super>(component):

    ReachedEventInternal<private><final>:event(agent) = event(agent){}

    # 上に乗ったときに、乗った人で届く（checkpoint_reached_event と同じタイミング。Await / Subscribe する。外から Signal はできない）
    ReachedEvent<public><final>:listenable(agent) = MakeProxyListenable(ReachedEventInternal)

    LeftEventInternal<private><final>:event(agent) = event(agent){}

    # 上から降りたとき・立っていた人が退出したとき・止まるときに、その人で届く（checkpoint_left_event と同じタイミング。Await / Subscribe する。外から Signal はできない）
    LeftEvent<public><final>:listenable(agent) = MakeProxyListenable(LeftEventInternal)

    # 足場の前後（Forward）の幅（センチメートル）。メッシュの大きさに合わせる。既定 750
    @editable_number(float):
        ToolTip := CheckpointWidthToolTip
        Categories := array{CheckpointCategory}
        MinValue := option{50.0}
        MaxValue := option{10000.0}
    WidthCm<public>:float = 750.0
    # 足場の左右（Left）の幅（センチメートル）。メッシュの大きさに合わせる。既定 750
    @editable_number(float):
        ToolTip := CheckpointDepthToolTip
        Categories := array{CheckpointCategory}
        MinValue := option{50.0}
        MaxValue := option{10000.0}
    DepthCm<public>:float = 750.0
    # 足場の厚さ（センチメートル）。メッシュの大きさに合わせる。既定 250
    @editable_number(float):
        ToolTip := CheckpointThicknessToolTip
        Categories := array{CheckpointCategory}
        MinValue := option{10.0}
        MaxValue := option{2000.0}
    ThicknessCm<public>:float = 250.0
    # 足場の真下のこの距離（センチメートル）以内から上へ動いている人を、上面の上へ通す。既定 300
    @editable_number(float):
        ToolTip := CheckpointApproachToolTip
        Categories := array{CheckpointCategory}
        MinValue := option{50.0}
        MaxValue := option{1000.0}
    ApproachCm<public>:float = 300.0

    EdgeMarginCm<private>:float = 40.0
    LandOffsetCm<private>:float = 100.0
    StandHeightCm<private>:float = 250.0

    var Standing<private>:[agent]logic = map{}
    var StandingTags<private>:player_tag_holder = player_tag_holder{}
    var Tracker<private>:?checkpoint_tracker = false
    var Tracking<private>:logic = false
    var DriveSubscription<private>:?cancelable = false
    var FrameCenter<private>:vector3 = vector3{}

    # Agent がこの足場の上に立っていれば成功する。毎フレームの確認の結果なので最大 1 フレーム遅れる。まだ確かめていない人・降りた人・退出した人と、止まったあとは失敗する
    IsStanding<public>(Agent:agent)<decides><reads>:void =
        Standing[Agent]?

    # 今この足場の上に立っている人
    GetStandingAgents<public>()<reads>:[]agent =
        for (Agent -> Value : Standing, Value?):
            Agent

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Shared := FindSharedTracker()
        set Tracker = option{Shared}
        set Tracking = true
        Shared.Register(Self)

    OnEndSimulation<override>():void =
        set Tracking = false
        if (Shared := Tracker?):
            Shared.Unregister(Self)
        set Tracker = false
        StopDriving()
        for (Agent -> Value : Standing, Value?):
            SetStanding(Agent, false)
        set Standing = map{}
        StandingTags.RemoveAll()
        (super:)OnEndSimulation()

    # 同じ区画（区画が無ければ世界）で、先に始まったチェックポイントが使っている checkpoint_tracker。無ければ新しく作る
    # 区画が入れ子のときは、一番近い区画が同じものだけを使う（ほかの区画の player_manager_component を見ないように）
    FindSharedTracker<private>():checkpoint_tracker =
        MaybeRoot:?entity = if (Scope := Entity.FindScopeEntity[]) then option{Scope} else if (World := Entity.GetSimulationEntity[]) then option{World} else false
        if (Root := MaybeRoot?, Found := FindTrackerUnder[Root]):
            Found
        else:
            checkpoint_tracker{}

    FindTrackerUnder<private>(Root:entity)<decides><transacts>:checkpoint_tracker =
        first (Other : Root.FindDescendantComponents(checkpoint_component), Other <> Self, Shared := Other.Tracker?, IsInSameScope[Other]):
            Shared

    IsInSameScope<private>(Other:checkpoint_component)<decides><transacts>:void =
        if (Mine := Entity.FindScopeEntity[]):
            Theirs := Other.Entity.FindScopeEntity[]
            Mine = Theirs
        else:
            not Other.Entity.FindScopeEntity[]

    # checkpoint_tracker から呼ばれる：このチェックポイントの TickEvents.PrePhysics で、毎フレーム checkpoint_tracker の Tick を呼び始める
    StartDriving<internal>():void =
        if (not DriveSubscription?):
            set DriveSubscription = option{TickEvents.PrePhysics.Subscribe(OnDriverTick)}

    # checkpoint_tracker から呼ばれる：Tick を呼ぶのをやめる
    StopDriving<internal>():void =
        DriveSubscription.CancelIfSet()
        set DriveSubscription = false

    OnDriverTick<private>(DeltaTime:float):void =
        if (Shared := Tracker?):
            Shared.Tick()

    # checkpoint_tracker から呼ばれる：このフレームの足場の位置を読んでおく（プレイヤーごとに読み直さない）
    PrepareFrame<internal>():void =
        set FrameCenter = Entity.GetGlobalTranslation()

    # checkpoint_tracker から呼ばれる：Agent（位置 Position）を確かめる。真下から上面へ移したら true（呼び出し側は位置を読み直す）
    CheckAt<internal>(Agent:agent, FortCharacter:fort_character, Position:vector3):logic =
        var Moved:logic = false
        if (Tracking?):
            Center := FrameCenter
            Bottom := Center.Up - ThicknessCm / 2.0
            Top := Center.Up + ThicknessCm / 2.0
            if (IsAbove[Position, Center, EdgeMarginCm]):
                if (Position.Up < Bottom, Position.Up > Bottom - ApproachCm, FortCharacter.GetLinearVelocity().Up > 0.0):
                    set Moved = PassThrough(FortCharacter, Position, Top)
                UpdateStanding(Agent, FortCharacter, Position, Top)
            else:
                SetStanding(Agent, false)
        Moved

    # checkpoint_tracker から呼ばれる：退出した人の立っている状態を消す（立っていたら降りた知らせを出す）
    ForgetAgent<internal>(Agent:agent):void =
        SetStanding(Agent, false)

    IsAbove<private>(Position:vector3, Center:vector3, MarginCm:float)<decides><reads>:void =
        Abs(Position.Forward - Center.Forward) <= WidthCm / 2.0 + MarginCm
        Abs(Position.Left - Center.Left) <= DepthCm / 2.0 + MarginCm

    PassThrough<private>(FortCharacter:fort_character, Position:vector3, Top:float):logic =
        if (CharacterEntity := FortCharacter.GetEntity[]):
            Current := CharacterEntity.GetGlobalTransform()
            Lifted := vector3{Forward := Position.Forward, Left := Position.Left, Up := Top + LandOffsetCm}
            CharacterEntity.SetGlobalTransform(Current.WithTranslation(Lifted))
            true
        else:
            false

    UpdateStanding<private>(Agent:agent, FortCharacter:fort_character, Position:vector3, Top:float):void =
        if (Position.Up >= Top, Position.Up <= Top + StandHeightCm, FortCharacter.IsOnGround[]):
            SetStanding(Agent, true)
        else:
            SetStanding(Agent, false)

    SetStanding<private>(Agent:agent, Value:logic):void =
        Was := logic{Standing[Agent]?}
        if (Was <> Value):
            if (set Standing[Agent] = Value) {}
            StandingTags.Set(Agent, Value, on_checkpoint_tag{})
            if (Value?):
                Entity.SendScoped(checkpoint_reached_event{Checkpoint := Self, Agent := Agent})
                ReachedEventInternal.Signal(Agent)
            else:
                Entity.SendScoped(checkpoint_left_event{Checkpoint := Self, Agent := Agent})
                LeftEventInternal.Signal(Agent)
