using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Input }
using { /Fortnite.com/Playspaces }
using { ItemSystem }
using { MovementSystem }
using { SceneGraphSystem }

# 役割：1 人分のスイングを Run のあいだ動かす（設定はすべて Ability＝swing_ability_component の項目。長さは cm、速さは cm/s、加速は cm/s²）。GrabAction を押すと、レティクルの先 MaxRangeCm 以内の物にロープをかけてつかみ、ジャンプ（ReleaseAction）を押すまで振り子で振る
# つかむ：レティクルの向きへ半径 GrabRadiusCm の球を飛ばして当たった点をつかむ（少しずれても届く）。カメラとキャラクターのあいだの物と、プレイヤーの持ち物は除く。見つけた点は覚えておき、レティクルが外れても GrabGraceSeconds のあいだ（次の点が見つかるまで）は、その点をつかめる（HUD も緑のまま）。つかむ操作を押したのがつかんでいるあいだでも、離す GrabBufferSeconds 前までの押下なら、離した直後に次をつかむ（押し直し不要）。動く物でも、覚えた点はその物の上の位置として持つ。つかんだ点は、当たった entity を SetOrigin の基準にした entity にするので、その物が動くとついてくる
# 地面：地面でつかむとロープだけかけて待ち（待っているあいだに ReelOutAction（狙う）を押すと、振り出さずにロープを外す）、ジャンプで GrabLiftHeightCm だけ持ち上げて、空中の GroundLaunchMultiplier 倍の勢いで振り出す（地面から落ちたら 1 倍）。つかんでいるあいだ（待つ・振るとも）MaxRangeCm より離れたら外す（加速は足さない）。振り出してから LandingGraceSeconds より後に着地したら、また待つ（それまでは地面に触れても振り続ける）
# 振り子：自分で計算して毎フレーム（Tick＝持ち主の TickEvents.PrePhysics。届いた DeltaTime で積分する）SetLinearVelocity で入れる。振り出しで動いている向きへ GrabKickSpeedCmPerSecond、SwingEaseSeconds かけて SwingStartSpeedCmPerSecond、振り出してから AutoReelSeconds かけて、ロープを振り出したときの長さの AutoReelRatio（既定 2/3）まで、だんだんゆっくり縮め、毎フレーム重力 SwingGravityCmPerSecondSquared・見ている向きへの加速 SwingSteerAccelerationCmPerSecondSquared・空気の抵抗 SwingDrag を入れる。ロープの外向きの速さだけを消し、はみ出しは MaxRopeCorrectionSpeedCmPerSecond までの速さで引き戻す（引き戻しは次のフレームに持ち越さない）。速さは MaxSwingSpeedCmPerSecond まで。壁や床にぶつかって実際の速度が大きく変わったら、実際の速度に合わせ直す（速度はエンジンの単位のメートル毎秒で持ち、設定は ToEngineSpeed で直して使う）
# 長さ：振っているあいだ、つかむ操作を押し直すと縮め、ReelOutAction（狙う）で伸ばす（ReelSpeedCmPerSecond）
# マルチスイング：ロープを MaxRopes 本（swing_stats.ExtraRopes を足す）までかけられる。振っているあいだにつかむ操作を押すと、本数に空きがあれば次の点にもロープをかける（押したことは縮めるのにも使う）。振り子の中心は、かけたロープの点の真ん中。点が壊れる・MaxRangeCm より離れる・つかんだ物が消えると（毎フレーム確かめる）、そのロープだけ外れ（swing_rope_detached_event）、1 本も無くなると離す
# ついていく：ほかの agent（プレイヤーに限らない。参加者のキャラクターか、その持ち物）にもロープをかけられる。相手にかけたロープがあるときは、地面からのジャンプを待たず、相手との距離がロープの上限（MaxRangeCm）の FollowDistanceRatio 倍（既定 1/4）から 50 センチメートル以内まで離れたら、GrabLiftHeightCm だけ持ち上げて、相手（につけた点）を起点に振り子で振り出す（相手が動くと、ついていく。ジャンプで振り出してもよい）。振っている途中で着地しても、また離れたら同じように振り出す。相手にかけたロープは、上限より離れても外れない
# ロープを引く：自分が地面にいて、自分にロープをかけている人（相手の swing_runner が HasRopeOn で答える。相手は Registry から引く）をレティクルで見ると swing_reel_hint_event{Holder := その人} を Notify に渡し（案内を出す。見なくなったら Holder := false）、つかむ操作を押すと、つかむ代わりに相手の ReelToward を呼ぶ。呼ばれた側は、地面で待っていればすぐ振り出し、振り子をいったん止めて、引いた人の方へまっすぐ ReelPullSpeedCmPerSecond で ReelPullLengthCm ぶん（近づき切ったらそこまで）引き寄せられ、ロープはその分短くなる。そのあとは短いロープで振り子に戻る。区画に swing_registry_component が要る
# 引っ張り：相手にかけたロープがあるあいだは、自分を引き戻す強さを PullerCorrectionRatio 倍にする（引っ張る側に少し補正が入る）。相手（引っ張られている側）には、こちらから力を掛けない
# 離す：振っているあいだにジャンプを押し続けると、動いている向きへ HoldAccelerationCmPerSecondSquared で加速し（速さは MaxHoldSpeedCmPerSecond まで）、ジャンプを離すと、それまでの勢いのまま動いている向きに ReleaseBoostCmPerSecond を足して離す。つかんだ物が壊れる（swing_anchor_component.Break）か、ForceRelease（swing_ability_component.Release）で、そこで途切れる（加速は足さない）
# 強さ：Registry（swing_registry_component）がその人に掛かる倍率をまとめた swing_stats を、始めたときと、Registry が倍率の元の変化を知らせたとき（ModifiersChangedEvent）だけ読み直し、つかめる距離・速さの上限・加速・離す勢い・巻き取りの速さに掛ける（決まった間隔では探さない）。つかめないとされたら新しくつかまない。変わったら swing_stats_changed_event を Notify に渡す
# 確かめる間隔：地面を離れた・着地した・相手とのロープが張った・レティクルの先（つかめるか、ロープを引けるか）は、知らせ（イベント）が無いので CheckIntervalSeconds（0.1 秒）ごとに確かめる
# 知らせ：待機中、つかめるかが変わったら swing_target_changed_event。ロープを 1 本かけるたびに swing_grabbed_event（つかんだ点の entity）、1 本だけ外れると swing_rope_detached_event、離すと swing_released_event、状態（待機 / 地面で待つ / 振り子）が変わると swing_state_changed_event を Notify に渡す。つかんだ物（当たった entity）には、つかむと swing_attached_event、振り出すたびに swing_pulled_event、離すと swing_detached_event を下へ送る
# 置き方：実行時に swing_ability_component が、付与された人ごとに作る。つかんだ点の entity は能力の entity の simulation entity の下に作る。Registry があれば自分を登録する（SetRunner。ロープを引く相手を探すため）。状態は Notify に渡し、能力がタグ（swinging_tag の派生）にする
swing_runner := class<unique><internal>:

    # 設定（つかむ・ロープ・離す・加速・振り子・入力）と、知らせの送り元
    Ability<internal>:swing_ability_component
    # 知らせ（swing_*_event）を受け取る関数。作った側の component が、自分の entity から送り直す
    Notify<internal>:type{_(:agent, :scene_event):void}
    # 毎フレームの合図（持ち主の component の TickEvents.PrePhysics）。Await の戻り値は前のフレームからの秒数
    Tick<internal>:listenable(float)
    # 区画の台帳（持ち主が 1 回だけ探して渡す）。無ければ false
    Registry<internal>:?swing_registry_component
    Agent<internal>:agent
    PlayerInput<internal>:player_input

    # 地面・着地・相手との距離・レティクルを確かめる間隔（秒）。キャラクターの着地やカメラの向きには知らせ（イベント）が無いので、この間隔で確かめる
    CheckIntervalSeconds<private>:float = 0.1
    # 相手にかけたロープを「張った」とみなす余裕（センチメートル）
    TautSlackCm<private>:float = 50.0
    # 実際の速度が、最後に入れた速度からこれ（メートル毎秒。エンジンの速度の単位）より変わったら、ぶつかったとみなして合わせ直す
    VelocitySyncThreshold<private>:float = 3.0

    var RopeLength<private>:float = 0.0
    var ReelingIn<private>:logic = false
    var ReelingOut<private>:logic = false
    var SwingVelocity<private>:vector3 = vector3{}
    var LastApplied<private>:vector3 = vector3{}
    var LastCorrection<private>:vector3 = vector3{}
    var LaunchScale<private>:float = 1.0
    var AutoReelLength<private>:float = 0.0
    var Boosting<private>:logic = false
    var State<private>:swing_state = swing_state.Idle
    var LastCanGrab<private>:?logic = false
    var LastGrab<private>:?swing_grab = false
    var LastGrabTime<private>:float = 0.0
    var PressCount<private>:int = 0
    var UsedPressCount<private>:int = 0
    var LastPressTime<private>:float = 0.0
    var Stats<private>:swing_stats = swing_stats{}
    var Ropes<private>:[]swing_rope = array{}
    var LastReelHolder<private>:?agent = false
    var PendingReel<private>:?agent = false
    var ReelLeft<private>:float = 0.0

    ReelRequestedEvent<private>:event() = event(){}

    GrabPressedEvent<private>:event() = event(){}

    ForceReleaseEvent<private>:event() = event(){}

    Run<internal>()<suspends>:void =
        PlayerInput.AddInputMapping(Ability.GrabMapping)
        PlayerInput.AddInputMapping(Ability.ReleaseMapping)
        PlayerInput.AddInputMapping(Ability.ReelOutMapping)
        GrabEvents := PlayerInput.GetInputEvents(Ability.GrabAction)
        UpdateStats()
        if (Current := Registry?):
            Current.SetRunner(Agent, Self)
        defer:
            if (Current := Registry?):
                Current.ForgetRunner(Agent, Self)
        race:
            TrackGrabPresses(GrabEvents)
            RunGrabLoop()
            WatchAim()
            WatchModifiers()

    # つかんでいれば（地面で待つ・振っている）離させる。加速は足さない
    ForceRelease<internal>():void =
        ForceReleaseEvent.Signal()

    TrackGrabPresses<private>(GrabEvents:input_events(logic))<suspends>:void =
        loop:
            GrabEvents.BeginDetectEvent.Await()
            set PressCount += 1
            set LastPressTime = GetSimulationElapsedTime()
            GrabPressedEvent.Signal()

    RunGrabLoop<private>()<suspends>:void =
        loop:
            if (not HasBufferedPress[]):
                GrabPressedEvent.Await()
            set UsedPressCount = PressCount
            if (FortCharacter := Agent.GetFortCharacter[]):
                if (Holder := FindReelableHolder[FortCharacter]):
                    Holder.ReelToward(Agent)
                else if (Grab := FindGrab[FortCharacter]):
                    set LastGrab = false
                    Attached := AttachRope(Grab)
                    if (Attached?):
                        Swing(FortCharacter)

    HasRopeOn<internal>(Target:agent)<decides><transacts>:void =
        first (Rope : Ropes, Held := Rope.TargetAgent?, Held = Target):
            Rope

    ReelToward<internal>(Puller:agent):void =
        if (HasRopeOn[Puller]):
            set PendingReel = option{Puller}
            ReelRequestedEvent.Signal()
            if (State = swing_state.Swinging, FortCharacter := Agent.GetFortCharacter[]):
                ApplyReel(FortCharacter)

    ApplyReel<private>(FortCharacter:fort_character):void =
        if (PendingReel?):
            set PendingReel = false
            set ReelLeft = Ability.ReelPullLengthCm

    StepReel<private>(FortCharacter:fort_character, Position:vector3, Pivot:vector3, DeltaTime:float):void =
        Offset := Pivot - Position
        Closest := Ability.MinRopeLengthCm
        if (Offset.Length() <= Closest):
            set ReelLeft = 0.0
            set RopeLength = Closest
        else:
            Step := Ability.ReelPullSpeedCmPerSecond * DeltaTime
            set ReelLeft -= Step
            set RopeLength = Max(Offset.Length() - Step, Closest)
            set SwingVelocity = Offset.MakeUnitVector() * ToEngineSpeed(Ability.ReelPullSpeedCmPerSecond)
            ApplyVelocity(FortCharacter, SwingVelocity, vector3{})

    FindReelableHolder<private>(FortCharacter:fort_character)<decides><transacts>:swing_runner =
        FortCharacter.IsOnGround[]
        Hit := FindGrabHit[FortCharacter]
        Holder := FindPullTarget(Hit.TargetComponent.Entity)?
        Runner := Registry?.FindRunner[Holder]
        Runner.HasRopeOn[Agent]
        Runner

    HasBufferedPress<private>()<decides><transacts>:void =
        PressCount > UsedPressCount
        GetSimulationElapsedTime() - LastPressTime <= Ability.GrabBufferSeconds

    FindGrab<private>(FortCharacter:fort_character)<decides><transacts>:swing_grab =
        Stats.CanGrab?
        if (Hit := FindGrabHit[FortCharacter]):
            Target := Hit.TargetComponent.Entity
            Grab := swing_grab{Target := Target, LocalPosition := Target.ToLocalPosition(Hit.ContactPosition), TargetAgent := FindPullTarget(Target)}
            set LastGrab = option{Grab}
            set LastGrabTime = GetSimulationElapsedTime()
            Grab
        else:
            Remembered := LastGrab?
            GetSimulationElapsedTime() - LastGrabTime <= Ability.GrabGraceSeconds
            Remembered.Target.GetSimulationEntity[]
            Remembered

    FindGrabHit<private>(FortCharacter:fort_character)<decides><transacts>:sweep_hit =
        CharacterEntity := FortCharacter.GetEntity[]
        Origin := FortCharacter.GetViewOrigin()
        CameraGap := Distance(Origin, CharacterEntity.GetGlobalTranslation())
        Displacement := FortCharacter.GetViewDirection() * GetMaxRangeCm()
        first:
            Hit : CharacterEntity.FindSweepHits(Displacement, MakeTranslationTransform(Origin), GetGrabVolume())
            Hit.SourceHitDistance > CameraGap
            Hit.TargetComponent.Entity <> CharacterEntity
            CanGrabEntity[Hit.TargetComponent.Entity]
        do:
            Hit

    CanGrabEntity<private>(Target:entity)<decides><transacts>:void =
        if (Owner := Target.FindOwnerAgent[]):
            Owner <> Agent
            Owner.GetFortCharacter[]

    FindPullTarget<private>(Target:entity)<transacts>:?agent =
        if (Found := FindCharacterAgent[Target]):
            option{Found}
        else if (Owner := Target.FindOwnerAgent[], Owner <> Agent, Owner.GetFortCharacter[]):
            option{Owner}
        else:
            false

    FindCharacterAgent<private>(Target:entity)<decides><transacts>:agent =
        Playspace := Ability.Entity.GetPlayspaceForEntity[]
        first:
            Participant : Playspace.GetParticipants()
            Participant <> Agent
            Participant.GetFortCharacter[].GetEntity[] = Target
        do:
            Participant

    GetGrabVolume<private>()<transacts>:collision_volume =
        if (Ability.GrabRadiusCm > 0.0):
            collision_sphere{Radius := Ability.GrabRadiusCm}
        else:
            collision_point{}

    CreateAnchor<private>(Grab:swing_grab):?entity =
        if (SimulationEntity := Ability.Entity.GetSimulationEntity[]):
            Anchor := entity{}
            Anchor.SetOrigin(entity_origin{Entity := Grab.Target})
            Anchor.SetLocalTransform(MakeTranslationTransform(Grab.LocalPosition))
            Anchor.AddComponents(array{swing_anchor_component{Entity := Anchor}})
            SimulationEntity.AddEntities(array{Anchor})
            option{Anchor}
        else:
            false

    AttachRope<private>(Grab:swing_grab):?swing_rope =
        NewAnchor := CreateAnchor(Grab)
        if (Anchor := NewAnchor?):
            Rope := swing_rope{Anchor := Anchor, Target := Grab.Target, TargetAgent := Grab.TargetAgent}
            set Ropes += array{Rope}
            Notify(Agent, swing_grabbed_event{Ability := Ability, Agent := Agent, Anchor := Anchor})
            Grab.Target.SendDown(swing_attached_event{Ability := Ability, Agent := Agent, Anchor := Anchor})
            option{Rope}
        else:
            false

    GetDistanceTo<private>(Anchor:entity)<transacts>:float =
        if (Position := Agent.GetFortCharacter[].FindGlobalTranslation[]):
            Distance(Position, Anchor.GetGlobalTranslation())
        else:
            0.0

    DetachRope<private>(Rope:swing_rope):void =
        set Ropes = for:
            Current : Ropes
            Current <> Rope
        do:
            Current
        Rope.Target.SendDown(swing_detached_event{Ability := Ability, Agent := Agent, Anchor := Rope.Anchor})
        Rope.Anchor.RemoveFromParent()

    DetachAll<private>():void =
        for (Rope : Ropes):
            DetachRope(Rope)

    Swing<private>(FortCharacter:fort_character)<suspends>:void =
        defer:
            DetachAll()
            Notify(Agent, swing_released_event{Ability := Ability, Agent := Agent})
            SetState(swing_state.Idle)
        ReleaseEvents := PlayerInput.GetInputEvents(Ability.ReleaseAction)
        race:
            WatchReel(Ability.GrabAction, true)
            WatchReel(Ability.ReelOutAction, false)
            KeepSwinging(FortCharacter, ReleaseEvents)
            WatchRopes(FortCharacter)
            WatchExtraGrabs(FortCharacter)
            ForceReleaseEvent.Await()

    WatchRopes<private>(FortCharacter:fort_character)<suspends>:void =
        loop:
            Tick.Await()
            for (Rope : Ropes):
                if (not IsRopeKept[FortCharacter, Rope]):
                    DetachRope(Rope)
                    Notify(Agent, swing_rope_detached_event{Ability := Ability, Agent := Agent, Anchor := Rope.Anchor})
            if (Ropes.Length = 0):
                return

    IsRopeKept<private>(FortCharacter:fort_character, Rope:swing_rope)<decides><transacts>:void =
        Rope.Target.GetSimulationEntity[]
        Marker := Rope.Anchor.GetComponent[swing_anchor_component]
        not Marker.Broken?
        Position := FortCharacter.FindGlobalTranslation[]
        Limit := if (Rope.TargetAgent?) then Inf else GetMaxRangeCm()
        Distance(Position, Rope.Anchor.GetGlobalTranslation()) <= Limit

    WatchExtraGrabs<private>(FortCharacter:fort_character)<suspends>:void =
        loop:
            GrabPressedEvent.Await()
            if (Ropes.Length < GetMaxRopes(), Grab := FindGrab[FortCharacter]):
                set UsedPressCount = PressCount
                set LastGrab = false
                Attached := AttachRope(Grab)
                if (Attached?):
                    FitRopeLength(FortCharacter)

    FitRopeLength<private>(FortCharacter:fort_character):void =
        if (Position := FortCharacter.FindGlobalTranslation[]):
            set RopeLength = Max(Distance(Position, GetPivot()), Ability.MinRopeLengthCm)

    GetMaxRopes<private>()<reads>:int =
        Max(Ability.MaxRopes + Stats.ExtraRopes, 1)

    GetPivot<private>()<transacts>:vector3 =
        var Sum:vector3 = vector3{}
        for (Rope : Ropes):
            set Sum = Sum + Rope.Anchor.GetGlobalTranslation()
        if (Ropes.Length > 0):
            Sum / (Ropes.Length * 1.0)
        else:
            Sum

    HasAgentRope<private>()<decides><reads>:void =
        Ropes.Length > 0
        for (Rope : Ropes):
            Rope.TargetAgent?

    KeepSwinging<private>(FortCharacter:fort_character, ReleaseEvents:input_events(logic))<suspends>:void =
        loop:
            Launch := AwaitLaunch(FortCharacter, ReleaseEvents)
            if (Scale := Launch?):
                Landed := Fly(FortCharacter, ReleaseEvents, Scale)
                if (not Landed?):
                    break
            else:
                break

    AwaitLaunch<private>(FortCharacter:fort_character, ReleaseEvents:input_events(logic))<suspends>:?float =
        if (FortCharacter.IsOnGround[]):
            SetState(swing_state.Anchored)
            WaitForLaunch(FortCharacter, ReleaseEvents)
        else:
            option{1.0}

    WaitForLaunch<private>(FortCharacter:fort_character, ReleaseEvents:input_events(logic))<suspends>:?float =
        race:
            block:
                ReleaseEvents.BeginDetectEvent.Await()
                option{Ability.GroundLaunchMultiplier}
            block:
                AwaitLeftGround(FortCharacter)
                option{1.0}
            block:
                AwaitAgentRopeTaut()
                option{1.0}
            block:
                ReelRequestedEvent.Await()
                option{1.0}
            block:
                PlayerInput.GetInputEvents(Ability.ReelOutAction).BeginDetectEvent.Await()
                false

    AwaitAgentRopeTaut<private>()<suspends>:void =
        loop:
            Sleep(CheckIntervalSeconds)
            if (IsAgentRopeTaut[]):
                return

    IsAgentRopeTaut<private>()<decides><transacts>:void =
        first:
            Rope : Ropes
            Rope.TargetAgent?
            GetDistanceTo(Rope.Anchor) >= GetMaxRangeCm() * Ability.FollowDistanceRatio - TautSlackCm
        do:
            Rope

    AwaitLeftGround<private>(FortCharacter:fort_character)<suspends>:void =
        loop:
            Sleep(CheckIntervalSeconds)
            if (FortCharacter.IsInAir[]):
                return

    AwaitLanded<private>(FortCharacter:fort_character)<suspends>:void =
        Sleep(Ability.LandingGraceSeconds)
        loop:
            Sleep(CheckIntervalSeconds)
            if (FortCharacter.IsOnGround[]):
                return

    Fly<private>(FortCharacter:fort_character, ReleaseEvents:input_events(logic), Scale:float)<suspends>:logic =
        if (FortCharacter.IsOnGround[]):
            FortCharacter.LiftBy(Ability.GrabLiftHeightCm)
        set LaunchScale = Scale
        set SwingVelocity = FortCharacter.GetLinearVelocity()
        if (Position := FortCharacter.FindGlobalTranslation[]):
            AnchorPosition := GetPivot()
            set RopeLength = Max(Distance(Position, AnchorPosition), Ability.MinRopeLengthCm)
            set AutoReelLength = RopeLength * (1.0 - Ability.AutoReelRatio)
            Outward := GetOutward(Position, AnchorPosition)
            Kick := GetMoveTangent(FortCharacter, Outward) * (ToEngineSpeed(Ability.GrabKickSpeedCmPerSecond) * Stats.AccelerationScale * Scale)
            set SwingVelocity = SwingVelocity + Kick
        ApplyVelocity(FortCharacter, SwingVelocity, vector3{})
        SetState(swing_state.Swinging)
        ApplyReel(FortCharacter)
        for (Rope : Ropes):
            Rope.Target.SendDown(swing_pulled_event{Ability := Ability, Agent := Agent, Anchor := Rope.Anchor})
        Landed := race:
            block:
                KeepRope(FortCharacter)
                false
            block:
                BoostUntilReleased(ReleaseEvents)
                false
            block:
                AwaitLanded(FortCharacter)
                true
        if (not Landed?):
            Release(FortCharacter)
        Landed

    BoostUntilReleased<private>(ReleaseEvents:input_events(logic))<suspends>:void =
        ReleaseEvents.BeginDetectEvent.Await()
        set Boosting = true
        defer:
            set Boosting = false
        ReleaseEvents.EndDetectEvent.Await()

    Release<private>(FortCharacter:fort_character):void =
        Speed := SwingVelocity.Length()
        if (Speed > 0.1):
            Boost := SwingVelocity * (ToEngineSpeed(Ability.ReleaseBoostCmPerSecond) * Stats.BoostScale / Speed)
            FortCharacter.SetLinearVelocity(SwingVelocity + Boost)

    SetState<private>(NewState:swing_state):void =
        set State = NewState
        set LastCanGrab = false
        Notify(Agent, swing_state_changed_event{Ability := Ability, Agent := Agent, State := NewState})

    KeepRope<private>(FortCharacter:fort_character)<suspends>:void =
        var Elapsed:float = 0.0
        loop:
            FrameSeconds := Tick.Await()
            DeltaTime := Max(FrameSeconds, 0.001)
            set Elapsed += DeltaTime
            UpdateRopeLength(DeltaTime, Elapsed)
            if (Elapsed > Ability.SwingEaseSeconds):
                SyncWithActualVelocity(FortCharacter)
            if (Position := FortCharacter.FindGlobalTranslation[], Ropes.Length > 0):
                if (ReelLeft > 0.0):
                    StepReel(FortCharacter, Position, GetPivot(), DeltaTime)
                else:
                    StepPendulum(FortCharacter, Position, GetPivot(), DeltaTime, Elapsed)

    SyncWithActualVelocity<private>(FortCharacter:fort_character):void =
        Actual := FortCharacter.GetLinearVelocity()
        if (Distance(Actual, LastApplied) > VelocitySyncThreshold):
            set SwingVelocity = Actual - LastCorrection

    UpdateRopeLength<private>(DeltaTime:float, Elapsed:float)<transacts>:void =
        Step := Ability.ReelSpeedCmPerSecond * Stats.ReelScale * DeltaTime
        if (ReelingIn?):
            ShortenRope(Step)
        if (ReelingOut?):
            set RopeLength = Min(RopeLength + Step, GetMaxRangeCm())
        Progress := GetAutoReelProgress(Elapsed) - GetAutoReelProgress(Elapsed - DeltaTime)
        if (Progress > 0.0):
            ShortenRope(AutoReelLength * Progress)

    GetAutoReelProgress<private>(Elapsed:float)<reads>:float =
        if (Ability.AutoReelSeconds > 0.0):
            Ratio := Min(Max(Elapsed / Ability.AutoReelSeconds, 0.0), 1.0)
            1.0 - (1.0 - Ratio) * (1.0 - Ratio)
        else:
            0.0

    ShortenRope<private>(Amount:float)<transacts>:void =
        set RopeLength = Max(RopeLength - Amount, Ability.MinRopeLengthCm)

    StepPendulum<private>(FortCharacter:fort_character, Position:vector3, AnchorPosition:vector3, DeltaTime:float, Elapsed:float):void =
        CurrentLength := Distance(Position, AnchorPosition)
        Outward := GetOutward(Position, AnchorPosition)
        Gravity := vector3{Up := -ToEngineSpeed(Ability.SwingGravityCmPerSecondSquared) * DeltaTime}
        Steer := GetViewTangent(FortCharacter, Outward) * (ToEngineSpeed(Ability.SwingSteerAccelerationCmPerSecondSquared) * Stats.AccelerationScale * DeltaTime)
        Push := GetMoveTangent(FortCharacter, Outward) * ((GetStartAcceleration(Elapsed) + GetHoldAcceleration()) * DeltaTime)
        DragScale := Max(1.0 - Ability.SwingDrag * DeltaTime, 0.0)
        var Velocity:vector3 = (SwingVelocity + Gravity + Steer + Push) * DragScale
        var Correction:vector3 = vector3{}
        if (CurrentLength >= RopeLength):
            OutwardSpeed := DotProduct(Velocity, Outward)
            if (OutwardSpeed > 0.0):
                set Velocity = Velocity - Outward * OutwardSpeed
            Stretch := (CurrentLength - RopeLength) / 100.0
            CorrectionSpeed := Min(Stretch * GetCorrectionRate(), ToEngineSpeed(Ability.MaxRopeCorrectionSpeedCmPerSecond))
            set Correction = Outward * -CorrectionSpeed
        Speed := Velocity.Length()
        SpeedLimit := GetSpeedLimit()
        if (Speed > SpeedLimit):
            set Velocity = Velocity * (SpeedLimit / Speed)
        set SwingVelocity = Velocity
        ApplyVelocity(FortCharacter, Velocity, Correction)

    GetCorrectionRate<private>()<reads>:float =
        if (HasAgentRope[]):
            Ability.RopeCorrectionRate * Ability.PullerCorrectionRatio
        else:
            Ability.RopeCorrectionRate

    ApplyVelocity<private>(FortCharacter:fort_character, Velocity:vector3, Correction:vector3):void =
        set LastApplied = Velocity + Correction
        set LastCorrection = Correction
        FortCharacter.SetLinearVelocity(LastApplied)

    GetStartAcceleration<private>(Elapsed:float)<reads>:float =
        if (Elapsed < Ability.SwingEaseSeconds):
            ToEngineSpeed(Ability.SwingStartSpeedCmPerSecond) * Stats.AccelerationScale * LaunchScale / Ability.SwingEaseSeconds
        else:
            0.0

    GetHoldAcceleration<private>()<reads>:float =
        if (Boosting?):
            ToEngineSpeed(Ability.HoldAccelerationCmPerSecondSquared) * Stats.AccelerationScale
        else:
            0.0

    GetSpeedLimit<private>()<reads>:float =
        if (Boosting?):
            ToEngineSpeed(Max(Ability.MaxSwingSpeedCmPerSecond, Ability.MaxHoldSpeedCmPerSecond)) * Stats.SpeedScale
        else:
            ToEngineSpeed(Ability.MaxSwingSpeedCmPerSecond) * Stats.SpeedScale

    GetOutward<private>(Position:vector3, AnchorPosition:vector3)<reads>:vector3 =
        Offset := Position - AnchorPosition
        if (Offset.Length() > 1.0):
            Offset.MakeUnitVector()
        else:
            vector3{Up := -1.0}

    GetMoveTangent<private>(FortCharacter:fort_character, Outward:vector3)<transacts>:vector3 =
        Tangent := SwingVelocity - Outward * DotProduct(SwingVelocity, Outward)
        if (Tangent.Length() > 0.5):
            Tangent.MakeUnitVector()
        else:
            GetViewTangent(FortCharacter, Outward)

    GetViewTangent<private>(FortCharacter:fort_character, Outward:vector3)<transacts>:vector3 =
        View := FortCharacter.GetViewDirection()
        Tangent := View - Outward * DotProduct(View, Outward)
        if (Tangent.Length() > 0.01):
            Tangent.MakeUnitVector()
        else:
            vector3{}

    WatchReel<private>(Action:input_action(logic), Inward:logic)<suspends>:void =
        Events := PlayerInput.GetInputEvents(Action)
        defer:
            SetReeling(Inward, false)
        loop:
            Events.BeginDetectEvent.Await()
            SetReeling(Inward, true)
            Events.EndDetectEvent.Await()
            SetReeling(Inward, false)

    SetReeling<private>(Inward:logic, Value:logic):void =
        if (Inward?):
            set ReelingIn = Value
        else:
            set ReelingOut = Value

    WatchAim<private>()<suspends>:void =
        loop:
            Sleep(CheckIntervalSeconds)
            if (State = swing_state.Idle):
                NotifyCanGrab(IsGrabbable())
            NotifyReelHint(FindReelHolder())

    NotifyCanGrab<private>(CanGrab:logic):void =
        Unchanged := logic{LastCanGrab? = CanGrab}
        if (not Unchanged?):
            set LastCanGrab = option{CanGrab}
            Notify(Agent, swing_target_changed_event{Ability := Ability, Agent := Agent, CanGrab := CanGrab})

    NotifyReelHint<private>(Holder:?agent):void =
        Same := logic{Holder? = LastReelHolder? or (not Holder?, not LastReelHolder?)}
        if (not Same?):
            set LastReelHolder = Holder
            Notify(Agent, swing_reel_hint_event{Ability := Ability, Agent := Agent, Holder := Holder})

    FindReelHolder<private>()<transacts>:?agent =
        if (State = swing_state.Idle, FortCharacter := Agent.GetFortCharacter[], Runner := FindReelableHolder[FortCharacter]):
            option{Runner.Agent}
        else:
            false

    IsGrabbable<private>()<transacts>:logic =
        if (FortCharacter := Agent.GetFortCharacter[], FindGrab[FortCharacter]):
            true
        else:
            false

    GetMaxRangeCm<private>()<reads>:float =
        Ability.MaxRangeCm * Stats.RangeScale

    # 設定の速さ・加速（cm/s・cm/s²）を、エンジンの速度（SetLinearVelocity のメートル毎秒）に直す
    ToEngineSpeed<private>(CmPerSecond:float)<computes>:float =
        CmPerSecond / 100.0

    # 倍率の元が変わったと台帳が知らせたときだけ作り直す（台帳が無ければ倍率は掛からない）
    WatchModifiers<private>()<suspends>:void =
        if (Current := Registry?):
            loop:
                Current.ModifiersChangedEvent.Await()
                UpdateStats()
        else:
            Sleep(Inf)

    UpdateStats<private>():void =
        NewStats := ComputeStats()
        Unchanged := logic{Stats = NewStats}
        if (not Unchanged?):
            set Stats = NewStats
            Notify(Agent, swing_stats_changed_event{Ability := Ability, Agent := Agent, Stats := NewStats})

    ComputeStats<private>()<transacts>:swing_stats =
        if (Current := Registry?) then Current.GetStats(Agent) else swing_stats{}

swing_grab<internal> := struct:
    # つかむ物の entity
    Target<public>:entity
    # Target から見た、つかむ点の位置（センチメートル）
    LocalPosition<public>:vector3
    # Target がほかの人（のキャラクターか持ち物）ならその人。違えば false
    TargetAgent<public>:?agent = false

swing_rope<internal> := class<unique>:
    # ロープの点の entity（swing_anchor_component 付き）
    Anchor<public>:entity
    # ロープをかけた物の entity
    Target<public>:entity
    # ほかの人にかけたロープならその人。違えば false
    TargetAgent<public>:?agent
