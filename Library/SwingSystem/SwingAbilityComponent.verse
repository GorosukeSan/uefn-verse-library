using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Fortnite.com/Input }
using { /UnrealEngine.com/Abilities }
using { AbilitySystem }
using { InputSystem }
using { ItemSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { SwingSystem.TooltipKit }

# 役割：スイングの能力。付与された人ごとに swing_runner を動かす（動きの詳しいことは swing_runner の説明）。つかむのは GrabAction（既定は射撃）
# 付与の仕方は同じ entity に置く component で選ぶ：
#   - 全員に最初から／起動しているあいだ → ability_grant_players_component
#   - アイテムとして（装備しているあいだ） → アイテムの entity に item_component・item_holder_component・ability_grant_item_component と一緒に置く
#   - 条件を満たしているあいだ → ability_grant_condition_component（子に条件）
#   - コードから → Grant / Revoke
# 知らせ：swing_runner の知らせ（swing_target_changed_event・swing_grabbed_event・swing_rope_detached_event・swing_released_event・swing_state_changed_event・swing_reel_hint_event・swing_stats_changed_event）を、その人の slot の下へ player_event として送り（同じ人の HUD などの view が受ける）、この entity から上へも送る。コードからは StateChangedEvent / GrabbedEvent / RopeDetachedEvent / ReleasedEvent を購読する
# 外から：Release(Agent) で離させる。今の状態は能力ではなくタグで読む（Agent.IsSwinging[] / Agent.GetSwingState()。SwingEvent.verse）
# タグ：つかんでいるあいだ、その人（agent）に地面で待つなら swing_anchored_tag、振っているなら swing_pendulum_tag（どちらも swinging_tag ← controlled_movement_tag の派生）を付ける。ほかの System は Agent.HasPlayerTag[swinging_tag] で確かめられる
# 演出：この entity に fort_item_ability_component があれば、振っているあいだ ItemEquippedAbilities をその人に使う
# 前提：区画（または世界）に player_manager_component（slot へ送るため）と swing_registry_component（ロープを引く・倍率のため。任意）。どちらも最初に 1 回だけ探して覚える
# 設定：この component に直接並べている（同じ設定を複数の能力で共有するには、能力の entity をプレハブにする）。長さは cm、速さは cm/s、加速は cm/s²、時間は秒
swing_ability_component<public> := class<final_super>(ability_component):

    # 押すとレティクルの先の物にロープをかけてつかむ操作。つかんでいるあいだは押し直すと縮める。既定は WeaponPrimary
    @editable:
        ToolTip := SwingGrabActionToolTip
        Categories := array{SwingCategory, SwingInputCategory}
    GrabAction<public>:input_action(logic) = Character.WeaponPrimary
    # GrabAction を含むキー割り当て。既定は RangedWeaponMapping（外さずに残す）
    @editable:
        ToolTip := SwingGrabMappingToolTip
        Categories := array{SwingCategory, SwingInputCategory}
    GrabMapping<public>:input_mapping = Character.RangedWeaponMapping
    # つかんだあと押し続けると加速し、離すとロープを外す操作。地面で待っているあいだは振り出す。既定は Jump
    @editable:
        ToolTip := SwingReleaseActionToolTip
        Categories := array{SwingCategory, SwingInputCategory}
    ReleaseAction<public>:input_action(logic) = Character.Jump
    # ReleaseAction を含むキー割り当て。既定は TraversalMapping（外さずに残す）
    @editable:
        ToolTip := SwingReleaseMappingToolTip
        Categories := array{SwingCategory, SwingInputCategory}
    ReleaseMapping<public>:input_mapping = Character.TraversalMapping
    # つかんでいるあいだ押しているとロープを伸ばす操作。地面で待っているあいだはロープを外す。既定は WeaponSecondary
    @editable:
        ToolTip := SwingReelOutActionToolTip
        Categories := array{SwingCategory, SwingInputCategory}
    ReelOutAction<public>:input_action(logic) = Character.WeaponSecondary
    # ReelOutAction を含むキー割り当て。既定は RangedWeaponMapping（外さずに残す）
    @editable:
        ToolTip := SwingReelOutMappingToolTip
        Categories := array{SwingCategory, SwingInputCategory}
    ReelOutMapping<public>:input_mapping = Character.RangedWeaponMapping

    # つかめる距離（センチメートル。既定 4000）。ロープを伸ばせる長さの上限にもなる
    @editable_number(float):
        ToolTip := SwingMaxRangeToolTip
        Categories := array{SwingCategory, SwingGrabCategory}
        MinValue := option{100.0}
        MaxValue := option{20000.0}
    MaxRangeCm<public>:float = 4000.0
    # つかむ判定の球の半径（センチメートル。既定 50）。0 なら点で判定する
    @editable_number(float):
        ToolTip := SwingGrabRadiusToolTip
        Categories := array{SwingCategory, SwingGrabCategory}
        MinValue := option{0.0}
        MaxValue := option{500.0}
    GrabRadiusCm<public>:float = 50.0
    # レティクルが外れても最後に見つけた点をつかめる時間（秒。既定 0.5）
    @editable_number(float):
        ToolTip := SwingGrabGraceSecondsToolTip
        Categories := array{SwingCategory, SwingGrabCategory}
        MinValue := option{0.0}
        MaxValue := option{3.0}
    GrabGraceSeconds<public>:float = 0.5
    # つかんでいるあいだの押下を、離す前この秒数以内なら離した直後のつかみに使う（秒。既定 0.3）
    @editable_number(float):
        ToolTip := SwingGrabBufferSecondsToolTip
        Categories := array{SwingCategory, SwingGrabCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    GrabBufferSeconds<public>:float = 0.3
    # 地面から振り出す前に位置を直接動かして持ち上げる高さ（センチメートル。既定 20）
    @editable_number(float):
        ToolTip := SwingGrabLiftHeightToolTip
        Categories := array{SwingCategory, SwingGrabCategory}
        MinValue := option{0.0}
        MaxValue := option{300.0}
    GrabLiftHeightCm<public>:float = 20.0
    # 振り出す瞬間に動いている向きへ足す速さ（センチメートル毎秒。既定 300）
    @editable_number(float):
        ToolTip := SwingGrabKickSpeedToolTip
        Categories := array{SwingCategory, SwingGrabCategory}
        MinValue := option{0.0}
        MaxValue := option{3000.0}
    GrabKickSpeedCmPerSecond<public>:float = 300.0
    # 地面でつかんでジャンプしたときの振り出しの勢いの倍率（空中でつかんだときに対して。既定 2）
    @editable_number(float):
        ToolTip := SwingGroundLaunchMultiplierToolTip
        Categories := array{SwingCategory, SwingGrabCategory}
        MinValue := option{1.0}
        MaxValue := option{10.0}
    GroundLaunchMultiplier<public>:float = 2.0
    # 振り出してから、地面に触れても着地とみなさない時間（秒。既定 1）
    @editable_number(float):
        ToolTip := SwingLandingGraceSecondsToolTip
        Categories := array{SwingCategory, SwingGrabCategory}
        MinValue := option{0.0}
        MaxValue := option{5.0}
    LandingGraceSeconds<public>:float = 1.0
    # ロープを縮められる一番短い長さ（センチメートル。既定 200）
    @editable_number(float):
        ToolTip := SwingMinRopeLengthToolTip
        Categories := array{SwingCategory, SwingRopeCategory}
        MinValue := option{50.0}
        MaxValue := option{5000.0}
    MinRopeLengthCm<public>:float = 200.0
    # 押して縮める・伸ばすときのロープの長さが変わる速さ（センチメートル毎秒。既定 500）
    @editable_number(float):
        ToolTip := SwingReelSpeedToolTip
        Categories := array{SwingCategory, SwingRopeCategory}
        MinValue := option{0.0}
        MaxValue := option{5000.0}
    ReelSpeedCmPerSecond<public>:float = 500.0
    # ロープからはみ出した長さを毎秒どれだけの割合で引き戻すか（既定 5。大きいほど硬い）
    @editable_number(float):
        ToolTip := SwingRopeCorrectionRateToolTip
        Categories := array{SwingCategory, SwingRopeCategory}
        MinValue := option{0.0}
        MaxValue := option{50.0}
    RopeCorrectionRate<public>:float = 5.0
    # 振り子が始まってからロープを自動で縮める時間（秒。既定 1）。0 なら縮めない
    @editable_number(float):
        ToolTip := SwingAutoReelSecondsToolTip
        Categories := array{SwingCategory, SwingRopeCategory}
        MinValue := option{0.0}
        MaxValue := option{5.0}
    AutoReelSeconds<public>:float = 1.0
    # 振り出したときのロープの長さの、どこまで自動で縮めるかの割合（既定 0.67。1 なら縮めない）
    @editable_number(float):
        ToolTip := SwingAutoReelRatioToolTip
        Categories := array{SwingCategory, SwingRopeCategory}
        MinValue := option{0.1}
        MaxValue := option{1.0}
    AutoReelRatio<public>:float = 0.67
    # はみ出しを引き戻す速さの上限（センチメートル毎秒。既定 1000）
    @editable_number(float):
        ToolTip := SwingMaxRopeCorrectionSpeedToolTip
        Categories := array{SwingCategory, SwingRopeCategory}
        MinValue := option{0.0}
        MaxValue := option{5000.0}
    MaxRopeCorrectionSpeedCmPerSecond<public>:float = 1000.0
    # 離したときに動いている向きへ足す速さ（センチメートル毎秒。既定 600）
    @editable_number(float):
        ToolTip := SwingReleaseBoostToolTip
        Categories := array{SwingCategory, SwingReleaseCategory}
        MinValue := option{0.0}
        MaxValue := option{5000.0}
    ReleaseBoostCmPerSecond<public>:float = 600.0
    # 振っているあいだ ReleaseAction を押し続けたときの加速（センチメートル毎秒毎秒。既定 1000）
    @editable_number(float):
        ToolTip := SwingHoldAccelerationToolTip
        Categories := array{SwingCategory, SwingBoostCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    HoldAccelerationCmPerSecondSquared<public>:float = 1000.0
    # 長押しで加速しているあいだの速さの上限（センチメートル毎秒。既定 4500）
    @editable_number(float):
        ToolTip := SwingMaxHoldSpeedToolTip
        Categories := array{SwingCategory, SwingBoostCategory}
        MinValue := option{100.0}
        MaxValue := option{15000.0}
    MaxHoldSpeedCmPerSecond<public>:float = 4500.0
    # 振り出してから SwingEaseSeconds かけて足す速さの合計（センチメートル毎秒。既定 400）
    @editable_number(float):
        ToolTip := SwingStartSpeedToolTip
        Categories := array{SwingCategory, SwingPendulumCategory}
        MinValue := option{0.0}
        MaxValue := option{5000.0}
    SwingStartSpeedCmPerSecond<public>:float = 400.0
    # 振り始めの速さを足し終えるまでの時間（秒。既定 0.3）
    @editable_number(float):
        ToolTip := SwingEaseSecondsToolTip
        Categories := array{SwingCategory, SwingPendulumCategory}
        MinValue := option{0.05}
        MaxValue := option{3.0}
    SwingEaseSeconds<public>:float = 0.3
    # 振り子の計算で使う重力（センチメートル毎秒毎秒。既定 980）
    @editable_number(float):
        ToolTip := SwingGravityToolTip
        Categories := array{SwingCategory, SwingPendulumCategory}
        MinValue := option{0.0}
        MaxValue := option{6000.0}
    SwingGravityCmPerSecondSquared<public>:float = 980.0
    # つかんでいるあいだ見ている向きへ足す加速（センチメートル毎秒毎秒。既定 300）
    @editable_number(float):
        ToolTip := SwingSteerAccelerationToolTip
        Categories := array{SwingCategory, SwingPendulumCategory}
        MinValue := option{0.0}
        MaxValue := option{5000.0}
    SwingSteerAccelerationCmPerSecondSquared<public>:float = 300.0
    # 振り子の空気の抵抗（毎秒、速さのこの割合が減る。既定 0.15）
    @editable_number(float):
        ToolTip := SwingDragToolTip
        Categories := array{SwingCategory, SwingPendulumCategory}
        MinValue := option{0.0}
        MaxValue := option{5.0}
    SwingDrag<public>:float = 0.15
    # 振り子の速さの上限（センチメートル毎秒。既定 2500）
    @editable_number(float):
        ToolTip := SwingMaxSpeedToolTip
        Categories := array{SwingCategory, SwingPendulumCategory}
        MinValue := option{100.0}
        MaxValue := option{10000.0}
    MaxSwingSpeedCmPerSecond<public>:float = 2500.0
    # 同時にかけられるロープの本数（既定 1）。2 以上で振りながら別の点にもかけられる
    @editable_number(int):
        ToolTip := SwingMaxRopesToolTip
        Categories := array{SwingCategory, SwingMultiCategory}
        MinValue := option{1}
        MaxValue := option{5}
    MaxRopes<public>:int = 1
    # 相手にロープをかけているあいだ、自分が引き戻される強さの倍率（既定 0.5）
    @editable_number(float):
        ToolTip := SwingPullerCorrectionRatioToolTip
        Categories := array{SwingCategory, SwingPullCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PullerCorrectionRatio<public>:float = 0.5
    # 「ロープを引く」で引かれた人が引き寄せられる速さ（センチメートル毎秒。既定 800）
    @editable_number(float):
        ToolTip := SwingReelPullSpeedToolTip
        Categories := array{SwingCategory, SwingPullCategory}
        MinValue := option{0.0}
        MaxValue := option{6000.0}
    ReelPullSpeedCmPerSecond<public>:float = 800.0
    # 「ロープを引く」で引き寄せる長さ（センチメートル。既定 1000）
    @editable_number(float):
        ToolTip := SwingReelPullLengthToolTip
        Categories := array{SwingCategory, SwingPullCategory}
        MinValue := option{0.0}
        MaxValue := option{20000.0}
    ReelPullLengthCm<public>:float = 1000.0
    # 相手にかけて地面で待っているとき、MaxRangeCm のこの倍まで離れたらついていく（既定 0.25）
    @editable_number(float):
        ToolTip := SwingFollowDistanceRatioToolTip
        Categories := array{SwingCategory, SwingPullCategory}
        MinValue := option{0.05}
        MaxValue := option{1.0}
    FollowDistanceRatio<public>:float = 0.25

    StateChangedEventInternal<private><final>:event(tuple(agent, swing_state)) = event(tuple(agent, swing_state)){}
    GrabbedEventInternal<private><final>:event(tuple(agent, entity)) = event(tuple(agent, entity)){}
    RopeDetachedEventInternal<private><final>:event(tuple(agent, entity)) = event(tuple(agent, entity)){}
    ReleasedEventInternal<private><final>:event(agent) = event(agent){}

    # だれかのスイングの状態（待機 / 地面で待つ / 振り子）が変わるたびに、（その人, 新しい状態）で届く（Await / Subscribe する。外から Signal はできない）
    StateChangedEvent<public><final>:listenable(tuple(agent, swing_state)) = MakeProxyListenable(StateChangedEventInternal)

    # ロープを 1 本かけるたびに、（その人, つかんだ点の entity）で届く
    GrabbedEvent<public><final>:listenable(tuple(agent, entity)) = MakeProxyListenable(GrabbedEventInternal)

    # 複数かけたロープのうち 1 本だけ外れるたびに、（その人, 外れた点の entity）で届く
    RopeDetachedEvent<public><final>:listenable(tuple(agent, entity)) = MakeProxyListenable(RopeDetachedEventInternal)

    # ロープをすべて外して離したとき（自分で離した・点が壊れた・Release）に、その人で届く
    ReleasedEvent<public><final>:listenable(agent) = MakeProxyListenable(ReleasedEventInternal)

    var<private> Runners:[agent]swing_runner = map{}
    var<private> Effects:[agent][]ability_effect = map{}
    var<private> Registry:?swing_registry_component = false
    var<private> PlayerManager:?player_manager_component = false
    # スイング中の人（agent）に付けたタグ（swing_anchored_tag / swing_pendulum_tag）
    var<private> SwingingTags:player_tag_holder = player_tag_holder{}

    # Agent がつかんでいれば（地面で待つ・振っている）離させる。加速（ReleaseBoost）は足さない。つかんでいなければ・付与されていなければ何もしない
    Release<public>(Agent:agent):void =
        if (Runner := Runners[Agent]):
            Runner.ForceRelease()

    RunFor<override>(Agent:agent)<suspends>:void =
        MaybeInput := Agent.AwaitPlayerInput()
        if (PlayerInput := MaybeInput?):
            Runner := swing_runner:
                Ability := Self
                Notify := OnSwingEvent
                Tick := TickEvents.PrePhysics
                Registry := FindRegistry()
                Agent := Agent
                PlayerInput := PlayerInput
            if (set Runners[Agent] = Runner) {}
            defer:
                ForgetRunner(Agent, Runner)
                EndEffects(Agent)
                SwingingTags.Remove(Agent)
            Runner.Run()
        else if (not player[Agent]):
            Print("[swing_ability_component] プレイヤーでない agent に付与されました。入力が取れないので動きません")

    # 区画の swing_registry_component を探して覚える（覚えていれば探さない）。見つからなければ false
    FindRegistry<private>()<transacts>:?swing_registry_component =
        set Registry = Entity.ResolveScopedComponent(Registry, swing_registry_component)
        Registry

    # 区画の player_manager_component を探して覚える（覚えていれば探さない）。見つからなければ false
    FindPlayerManager<private>()<transacts>:?player_manager_component =
        set PlayerManager = Entity.ResolveScopedComponent(PlayerManager, player_manager_component)
        PlayerManager

    ForgetRunner<private>(Agent:agent, Runner:swing_runner):void =
        if (Current := Runners[Agent], Current = Runner):
            set Runners = Runners.RemoveKey(Agent)

    OnSwingEvent<private>(Agent:agent, SceneEvent:scene_event):void =
        if (Changed := swing_state_changed_event[SceneEvent]):
            EndEffects(Agent)
            if (Changed.State = swing_state.Swinging):
                Started := Entity.BeginItemAbilities(Agent)
                if (set Effects[Agent] = Started) {}
            UpdateStateTag(Agent, Changed.State)
            StateChangedEventInternal.Signal((Agent, Changed.State))
        else if (Grabbed := swing_grabbed_event[SceneEvent]):
            GrabbedEventInternal.Signal((Agent, Grabbed.Anchor))
        else if (Detached := swing_rope_detached_event[SceneEvent]):
            RopeDetachedEventInternal.Signal((Agent, Detached.Anchor))
        else if (swing_released_event[SceneEvent]):
            ReleasedEventInternal.Signal(Agent)
        SendToSlot(Agent, SceneEvent)
        Entity.SendUp(SceneEvent)

    # 状態に合わせてタグを付け替える（Idle なら外す）
    UpdateStateTag<private>(Agent:agent, State:swing_state):void =
        SwingingTags.Remove(Agent)
        if (Tag := MakeSwingStateTag(State)?):
            SwingingTags.Add(Agent, Tag)

    SendToSlot<private>(Agent:agent, SceneEvent:scene_event):void =
        # 探して覚えるのは if の外で（条件の中で set すると、slot が無いときに覚えたことまで巻き戻る）
        MaybeManager := FindPlayerManager()
        if:
            Player := player[Agent]
            Manager := MaybeManager?
            Slot := Manager.FindSlot[Player]
        then:
            Slot.Entity.SendDown(player_event{Sender := Self, Event := SceneEvent})

    EndEffects<private>(Agent:agent):void =
        if (Current := Effects[Agent]):
            EndItemAbilities(Current)
            if (set Effects[Agent] = array{}) {}
