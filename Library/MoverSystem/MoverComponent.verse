using { /Verse.org/SceneGraph }
using { /Verse.org/SceneGraph/KeyframedMovement }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { ActivationSystem }
using { SceneGraphSystem }
using { MoverSystem.TooltipKit }

# mover の動かし方
mover_motion<public> := enum:
    # エンジン（keyframed_movement_component）が、行き先までまっすぐ一定の速さで動かす（おすすめ）。サーバーが毎フレーム位置を送らないので、全員の画面で滑らか。ほかの物には当たらず、すり抜ける
    Keyframe
    # 毎フレーム Verse で少しずつ動かし、動く先にほかの物があれば、当たった面で跳ね返る（BounceSeconds）。跳ね返りが要るときだけ使う
    Physics

# 役割：entity を、同じ entity の道のり（mover_route_component の派生）が決める行き先へ、順に SpeedCmPerSecond（センチメートル毎秒）で動かす。行き先に着くと WaitSeconds 秒待ってから次へ。道のりが終わる（行き先が無い）と止まる
# 動かし方：Motion が Keyframe なら keyframed_movement_component（同じ entity に無ければ付ける）で 1 区間ずつ再生する。Physics なら毎フレーム（TickEvents.PrePhysics）動かし、当たったら BounceSeconds 秒跳ね返った向きに進んでから同じ行き先へ戻る（0 なら、その行き先をあきらめて次へ）
# いつ：StartOnBegin なら始めから動く。起動の合図（activated_event）で動き出す・再開し、停止の合図（deactivated_event）で一時停止する（その場で止まり、次の起動で続きから）。Restart で道のりの最初からやり直す（終わったあとでも）
# 置き方：エディターで、動かしたい entity に付ける（実行時に作ってもよい）。1 entity に 1 つ
# 同じ entity：道のり（RouteKit の mover_path_route_component / mover_random_route_component / mover_box_route_component のどれか 1 つ）。Physics なら当たり判定のあるメッシュ。Keyframe なら keyframed_movement_component（無ければ実行時に付ける。ほかの component で同じ entity を keyframe で動かさない）
# 知らせ：行き先を決めたとき mover_target_changed_event と TargetChangedEvent、着いたとき mover_target_reached_event と TargetReachedEvent、終わったとき mover_finished_event と FinishedEvent（scene event は自分の entity から SendDown。AlsoSendUp なら親から SendUp も）
# 片道：mover_path_route_component の Mode = Once なら最後の地点で止まり、FinishedEvent が届く（今の位置から別の行き先へ 1 回だけ動かすなら、SetPoints のあと Restart(?ReturnToStart := false)）
# 曲線：道のりが GetLeg で途中の点（mover_leg.Via）を返すと、その点を順に通って行き先へ一定の速さで進む（mover_spline_route_component）。Keyframe なら 1 つの行き先までの点をまとめて 1 回の SetKeyframes にする。mover_leg.FaceTravelDirection なら進む向きにヨーを合わせる
# 外から：Play / Pause / Restart / SetSpeed、IsMoving / IsFinished / FindTarget / FindStartPosition
# 前提・注意：動き出す位置は、シミュレーション開始の 1 フレーム後の位置（spawner が同じフレームに置き直すため）。Keyframe の区間は親の entity から見た差分で作る（親が回っていても世界の行き先に着くはず。⚠ 未検証：）
mover_component<public> := class<final_super>(component):

    # 動かし方（Keyframe = エンジンが滑らかに動かす・ほかの物はすり抜ける。Physics = Verse で動かし、当たると跳ね返る）。既定は Keyframe
    @editable:
        ToolTip := MoverMotionToolTip
        Categories := array{MoverCategory, MoverMoveCategory}
    Motion<public>:mover_motion = mover_motion.Keyframe
    # 動く速さ（センチメートル毎秒。1〜10000）。既定 300
    @editable_number(float):
        ToolTip := MoverSpeedToolTip
        Categories := array{MoverCategory, MoverMoveCategory}
        MinValue := option{1.0}
        MaxValue := option{10000.0}
    SpeedCmPerSecond<public>:float = 300.0
    # オンならゲームの始めから動く。オフなら起動の合図（activated_event）か Play で動き出す。既定オン
    @editable:
        ToolTip := MoverStartOnBeginToolTip
        Categories := array{MoverCategory, MoverMoveCategory}
    StartOnBegin<public>:logic = true
    # 行き先に着くたびに、次へ向かう前に止まっている時間（秒）。既定 0（止まらない）
    @editable_number(float):
        ToolTip := MoverWaitSecondsToolTip
        Categories := array{MoverCategory, MoverMoveCategory}
        MinValue := option{0.0}
        MaxValue := option{60.0}
    WaitSeconds<public>:float = 0.0
    # Physics のとき、当たって跳ね返った向きに進む時間（秒）。そのあと同じ行き先へ戻る。0 ならその行き先をあきらめて次へ。既定 0.3
    @editable_number(float):
        ToolTip := MoverBounceSecondsToolTip
        Categories := array{MoverCategory, MoverMoveCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    BounceSeconds<public>:float = 0.3
    # オンなら知らせ（mover_target_changed_event / mover_target_reached_event / mover_finished_event）を、子孫へ（SendDown）に加えて、親から祖先へ（SendUp）も送る（ゲームの流れのノード・祖先の部品が着いたことを受けるとき）。自分の entity には SendDown の 1 回だけ届く。既定オフ
    @editable:
        ToolTip := MoverAlsoSendUpToolTip
        Categories := array{MoverCategory, MoverMoveCategory}
    AlsoSendUp<public>:logic = false

    TargetChangedEventInternal<private><final>:event(mover_target) = event(mover_target){}

    # 次の行き先を決めて向かい始めたときに、その行き先で届く（Await / Subscribe する。外から Signal はできない）
    TargetChangedEvent<public><final>:listenable(mover_target) = MakeProxyListenable(TargetChangedEventInternal)

    TargetReachedEventInternal<private><final>:event(mover_target) = event(mover_target){}

    # 行き先に着いたときに、その行き先で届く（WaitSeconds の待ちの前。Await / Subscribe する。外から Signal はできない）
    TargetReachedEvent<public><final>:listenable(mover_target) = MakeProxyListenable(TargetReachedEventInternal)

    FinishedEventInternal<private><final>:event() = event(){}

    # 道のりが終わって止まったときに届く（Loop / PingPong / ランダムの道のりでは届かない。Restart でやり直すと、また終わったときにもう一度届く。Await / Subscribe する。外から Signal はできない）
    FinishedEvent<public><final>:listenable(tuple()) = MakeProxyListenable(FinishedEventInternal)

    var Playing<private>:logic = false
    var Finished<private>:logic = false
    var SpeedOverride<private>:?float = false
    var Target<private>:?mover_target = false
    var Keyframed<private>:?keyframed_movement_component = false
    var SegmentActive<private>:logic = false
    # シミュレーション開始の 1 フレーム後の位置（Restart で戻る位置）。まだ読んでいなければ false
    var StartPosition<private>:?vector3 = false
    # シミュレーション開始の 1 フレーム後の向き（Restart で戻る向き）
    var StartRotation<private>:rotation = IdentityRotation()
    # 次のやり直しで、最初の位置へ戻すか（Restart の引数）
    var ReturnOnRestart<private>:logic = true

    PlayEvent<private>:event() = event(){}
    ReplanEvent<private>:event() = event(){}
    RestartEvent<private>:event() = event(){}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (StartOnBegin?):
            set Playing = true

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Play()
        else if (deactivated_event[SceneEvent]):
            Pause()
        false

    OnSimulate<override>()<suspends>:void =
        # spawner などが同じフレームに位置を置き直すので、1 フレーム待ってから動き出しの位置を読む
        TickEvents.PrePhysics.Await()
        StartTransform := Entity.GetGlobalTransform()
        Start := StartTransform.Translation
        set StartPosition = option{Start}
        set StartRotation = StartTransform.Rotation
        var Home:vector3 = Start
        loop:
            # 道のりを最後まで進める。途中で Restart されたら、そこでやめてやり直す
            Restarted := race:
                block:
                    RunRoute(Home)
                    false
                block:
                    RestartEvent.Await()
                    true
            if (not Restarted?):
                Finish()
                RestartEvent.Await()
            set Home = PrepareRestart(Start)

    # 道のりの行き先へ順に動かす。行き先が無くなる（道のりの終わり・道のりの component が無い）と戻る
    RunRoute<private>(Home:vector3)<suspends>:void =
        if (Route := Entity.GetComponent[mover_route_component]):
            if (Motion = mover_motion.Keyframe, not Keyframed?):
                Found := FindOrAddKeyframed()
                set Keyframed = option{Found}
            loop:
                AwaitPlaying()
                MaybeNext := Route.NextTarget(Home, Entity.GetGlobalTranslation())
                if (Next := MaybeNext?):
                    set Target = option{Next}
                    Leg := Route.GetLeg(Entity.GetGlobalTranslation(), Next)
                    TargetChangedEventInternal.Signal(Next)
                    Send(mover_target_changed_event{Mover := Self, Target := Next})
                    Reached := MoveTo(Next.Position, Leg)
                    if (Reached?):
                        TargetReachedEventInternal.Signal(Next)
                        Send(mover_target_reached_event{Mover := Self, Target := Next})
                        WaitFor(WaitSeconds)
                else:
                    break
        else:
            Print("[mover_component] 同じ entity に道のりの component（mover_route_component の派生）がありません。動かずに終わります")

    Finish<private>():void =
        set Target = false
        set Finished = true
        FinishedEventInternal.Signal()
        Send(mover_finished_event{Mover := Self})

    # やり直しの準備。区間の再生を止め、ReturnOnRestart なら最初の位置と向きへ戻し、道のりを最初に戻す。次の道のりの Home（動き出す位置）を返す
    # ⚠ 未検証：keyframed_movement_component.Stop のあとの SetGlobalTransform が、全員の画面でその位置になるか（Stop が止めた位置を送り直して上書きしないか）
    PrepareRestart<private>(Start:vector3):vector3 =
        if (K := Keyframed?):
            K.Stop()
        set SegmentActive = false
        set Target = false
        set Finished = false
        if (ReturnOnRestart?):
            Entity.SetGlobalTransform(transform{Translation := Start, Rotation := StartRotation, Scale := Entity.GetGlobalTransform().Scale})
        if (Route := Entity.GetComponent[mover_route_component]):
            Route.Reset()
        if (ReturnOnRestart?) then Start else Entity.GetGlobalTranslation()

    # 自分と子孫へ送る。AlsoSendUp なら親から祖先へも送る（自分の entity に 2 回届かないよう、上へは親から）
    Send<private>(SceneEvent:scene_event):void =
        Entity.SendDown(SceneEvent)
        if (AlsoSendUp?, Parent := Entity.GetParent[]):
            Parent.SendUp(SceneEvent)

    # 動かす（StartOnBegin が false のときの動き出し、Pause のあとの再開）。止まった位置から続ける。道のりが終わっていれば何もしない
    Play<public>():void =
        if (not Playing?):
            set Playing = true
            if (K := Keyframed?, SegmentActive?):
                K.Play()
            PlayEvent.Signal()

    # その場で一時停止する（Play で続きから動く）。止まっていれば何もしない
    Pause<public>():void =
        if (Playing?):
            set Playing = false
            if (K := Keyframed?, SegmentActive?):
                K.Pause()

    # 道のりの最初からやり直して動かす（動いている途中・一時停止中・終わったあとでも。一時停止中なら動き出す）。ReturnToStart が true（既定）なら、シミュレーション開始の位置（FindStartPosition）と向きへその場で戻してから動く。false なら今の位置から動き、道のりの Home（IncludeStart の最初の地点・ランダムの中心）も今の位置にする。動き出す前（最初の 1 フレーム）に呼んだときは Play と同じ
    Restart<public>(?ReturnToStart:logic = true):void =
        set ReturnOnRestart = ReturnToStart
        set Playing = true
        PlayEvent.Signal()
        RestartEvent.Signal()

    # 速さを変える（センチメートル毎秒。1 未満は 1 にする）。動いている途中の区間にもすぐ効く
    SetSpeed<public>(CmPerSecond:float):void =
        set SpeedOverride = option{Max(CmPerSecond, 1.0)}
        ReplanEvent.Signal()

    # 今の速さ（センチメートル毎秒）。SetSpeed で変えていなければ SpeedCmPerSecond
    GetSpeedCmPerSecond<public>()<reads>:float =
        if (Speed := SpeedOverride?) then Speed else Max(SpeedCmPerSecond, 1.0)

    # 動いている（Play されていて、道のりが終わっていない）なら成功する。WaitSeconds の待ちのあいだも成功する
    IsMoving<public>()<decides><reads>:void =
        Playing?
        not Finished?

    # 道のりが終わって止まったなら成功する
    IsFinished<public>()<decides><reads>:void =
        Finished?

    # シミュレーション開始の 1 フレーム後の位置（世界の位置、センチメートル。Restart で戻る位置）。まだ読んでいなければ失敗する
    FindStartPosition<public>()<decides><reads>:vector3 =
        StartPosition?

    # 今向かっている（着いて待っている）行き先。動き出す前と、終わったあとは失敗する
    FindTarget<public>()<decides><reads>:mover_target =
        Target?

    AwaitPlaying<private>()<suspends>:void =
        loop:
            if (Playing?):
                break
            PlayEvent.Await()

    WaitFor<private>(Seconds:float)<suspends>:void =
        var Left:float = Seconds
        loop:
            if (Left <= 0.0):
                break
            AwaitPlaying()
            set Left -= TickEvents.PrePhysics.Await()

    # Leg.Via の点を順に通って Destination へ動かす。着いたら true（Physics で、ぶつかってその行き先をあきらめたら false）
    MoveTo<private>(Destination:vector3, Leg:mover_leg)<suspends>:logic =
        Path := Leg.Via + array{Destination}
        if (K := Keyframed?):
            MoveByKeyframes(K, Path, Leg.FaceTravelDirection)
        else:
            MoveAlongBySteps(Path, Leg.FaceTravelDirection)

    # Path の点を順に通る区間を、まとめて 1 回の SetKeyframes で再生する。SetSpeed（ReplanEvent）が来たら、今いる区間から先を新しい速さで組み直す
    MoveByKeyframes<private>(K:keyframed_movement_component, Path:[]vector3, Face:logic)<suspends>:logic =
        var Remaining:[]vector3 = Path
        loop:
            From := Entity.GetGlobalTranslation()
            Keyframes := MakeKeyframes(From, Remaining, Face)
            if (Keyframes.Length = 0):
                break
            K.SetKeyframes(Keyframes, oneshot_keyframed_movement_playback_mode{})
            set SegmentActive = true
            if (Playing?):
                K.Play()
            Done := race:
                block:
                    K.FinishedEvent.Await()
                    true
                block:
                    ReplanEvent.Await()
                    false
            set SegmentActive = false
            if (Done?):
                break
            set Remaining = DropPassedPoints(From, Remaining, Entity.GetGlobalTranslation())
        true

    # Physics：Path の点を 1 つずつ MoveBySteps で通る。途中であきらめたら false
    MoveAlongBySteps<private>(Path:[]vector3, Face:logic)<suspends>:logic =
        var Index:int = 0
        var Reached:logic = true
        loop:
            if (not Reached?):
                break
            if (Point := Path[Index]):
                set Reached = MoveBySteps(Point, Face)
                set Index += 1
            else:
                break
        Reached

    MoveBySteps<private>(Destination:vector3, Face:logic)<suspends>:logic =
        var DetourLeft:float = 0.0
        var Detour:vector3 = vector3{}
        var Done:logic = false
        var Reached:logic = false
        loop:
            if (Done?):
                break
            AwaitPlaying()
            DeltaTime := TickEvents.PrePhysics.Await()
            if (Playing?):
                if (DetourLeft > 0.0):
                    set DetourLeft -= DeltaTime
                    if (Reflected := Entity.MoveStep(Detour, DeltaTime)?):
                        set Detour = Reflected
                else:
                    Step := StepTowardPoint(Entity.GetGlobalTranslation(), Destination, GetSpeedCmPerSecond(), DeltaTime)
                    if (Reflected := Entity.MoveStep(Step(0), DeltaTime)?):
                        if (BounceSeconds > 0.0):
                            set Detour = Reflected
                            set DetourLeft = BounceSeconds
                        else:
                            set Done = true
                    else:
                        if (Face?):
                            Entity.FaceToward(Step(0))
                        if (Step(1)?):
                            set Reached = true
                            set Done = true
        Reached

    # From から Points を順に通る区間の keyframe（1 cm 未満の区間は飛ばす）。どの区間も GetSpeedCmPerSecond の速さで進む長さの秒数。Face なら区間の向きにヨーを合わせる回転を足す
    # ⚠ 未検証：keyframe の Translation（加算）が、同じ keyframe の回転で回されずに親から見た向きのまま足されるか（回すなら、Face のときの道筋がずれる）
    MakeKeyframes<private>(From:vector3, Points:[]vector3, Face:logic)<transacts>:[]keyframed_movement_delta =
        Speed := GetSpeedCmPerSecond()
        var Previous:vector3 = From
        var Yaw:float = Entity.GetYawRadians()
        var Keyframes:[]keyframed_movement_delta = array{}
        for (Point : Points):
            SegmentCm := Distance(Previous, Point)
            if (SegmentCm >= 1.0):
                var Turn:rotation = IdentityRotation()
                if (Face?, NewYaw := FindTravelYaw[Point - Previous]):
                    set Turn = MakeYawRotation(WrapRadians(NewYaw - Yaw))
                    set Yaw = NewYaw
                set Keyframes = Keyframes + array{MakeDelta(Previous, Point, SegmentCm / Speed, Turn)}
                set Previous = Point
        Keyframes

    MakeDelta<private>(From:vector3, To:vector3, Seconds:float, Turn:rotation)<transacts>:keyframed_movement_delta =
        keyframed_movement_delta:
            Transform := transform:
                Translation := ToParentSpace(From, To)
                Rotation := Turn
                Scale := vector3{}
            Duration := Max(Seconds, 0.01)
            Easing := linear_easing_function{}

    ToParentSpace<private>(From:vector3, To:vector3)<transacts>:vector3 =
        if (Parent := Entity.GetParent[]):
            Parent.ToLocalPosition(To) - Parent.ToLocalPosition(From)
        else:
            To - From

    FindOrAddKeyframed<private>():keyframed_movement_component =
        if (Found := Entity.GetComponent[keyframed_movement_component]):
            Found
        else:
            Added := keyframed_movement_component{Entity := Entity}
            Entity.AddComponents(array{Added})
            Added
