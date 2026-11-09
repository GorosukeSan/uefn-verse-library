using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Fortnite.com/Input }
using { /UnrealEngine.com/Itemization }
using { AbilitySystem }
using { ItemSystem }
using { InputSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { JetpackSystem.TooltipKit }

# 役割：ジェットパックの能力。付与された人が空中で BoostAction（既定は Jump）を押すとチャージを始め（地面で押したときは何もしない。ふつうのジャンプになる）、離すと BoostPitchDegrees / BoostYawDegrees の向きに飛ぶ
#   チャージ：ChargeLiftCm だけ持ち上げ、そのあとは毎フレーム速度を「横 0・上 ChargeRiseSpeedCmPerSecond」にして浮く。MaxChargeSeconds を過ぎても最大のまま浮き続けられる
#   飛び出し：BoostDurationSeconds 秒のあいだ、速さを BoostSpeedCmPerSecond ×（1 − 経過 / 時間）^BoostEaseExponent で毎フレーム決める。距離は MinChargeSeconds まで 1 倍、MaxChargeSeconds で MaxChargeMultiplier 倍（初速と時間の両方に倍率の平方根を掛ける）
#   落下の軽減：チャージを始めたら着地するまでもう一度チャージできず、そのあいだ空中で押し続けると落ちる速さを GlideMaxFallSpeedCmPerSecond までに抑える
#   エネルギー（FindEnergyFor：この entity か子の energy_component、無ければプレイヤーに付いたもの）があれば、チャージが最大になった瞬間（それより前に離したときは離した瞬間）に BoostEnergyCost、落下の軽減で 1 秒に GlideEnergyPerSecond 使う（足りなくても飛べ、0 になる）。
#   0 のときはチャージも落下の軽減もできない。この entity がアイテムで RemoveItemWhenEmpty なら、0 になったとき（飛行の途中なら、それが終わったとき）アイテムごと無くなる
# 付与の仕方は同じ entity に置く component で選ぶ：
#   - アイテムとして（装備しているあいだ） → アイテムの entity に item_component・item_holder_component・ability_grant_item_component と一緒に置く。エネルギーはアイテムの entity に。
#     1 人 1 つまでにするなら exclusive_item_component。チャージ中・飛行中に持ち替えさせないなら item_equip_lock_component（あればロックする）
#   - 全員に最初から／起動しているあいだ → ability_grant_players_component（エネルギーをこの entity に置くと全員で分け合う。1 人ずつにするならプレイヤーに付ける）
#   - 条件を満たしているあいだ → ability_grant_condition_component（子に条件）
#   - コードから → Grant / Revoke
# 演出：この entity に fort_item_ability_component があれば、チャージ中・飛び出しのあいだ・落下の軽減のあいだ ItemEquippedAbilities をその人に使う
# 知らせ：ブーストのゲージが変わると BoostRatioChangedEvent と jetpack_boost_changed_event（上へ・その人の slot の下へ）
# 前提：slot へ送るなら区画（または世界）に player_manager_component（無ければ送らない）
jetpack_ability_component<public> := class<final_super>(ability_component):

    # チャージ 1 倍のときの飛び出した瞬間の速さ（センチメートル毎秒。既定 3000）
    @editable_number(float):
        ToolTip := JetpackBoostSpeedToolTip
        Categories := array{JetpackCategory, JetpackLaunchCategory}
        MinValue := option{0.0}
        MaxValue := option{20000.0}
    BoostSpeedCmPerSecond<public>:float = 3000.0
    # チャージ 1 倍のときに、飛び出してから速さが 0 になるまでの秒数（既定 0.8）
    @editable_number(float):
        ToolTip := JetpackBoostDurationToolTip
        Categories := array{JetpackCategory, JetpackLaunchCategory}
        MinValue := option{0.1}
        MaxValue := option{5.0}
    BoostDurationSeconds<public>:float = 0.8
    # 飛び出しの緩急（速さ = 初速 ×（1 − 経過 / 時間）のこの値乗。0 で一定、既定 2）
    @editable_number(float):
        ToolTip := JetpackBoostEaseExponentToolTip
        Categories := array{JetpackCategory, JetpackLaunchCategory}
        MinValue := option{0.0}
        MaxValue := option{5.0}
    BoostEaseExponent<public>:float = 2.0
    # 飛ぶ向きの上下の角度（度。90 で真上、0 で水平、-90 で真下。既定 90）
    @editable_number(float):
        ToolTip := JetpackBoostPitchToolTip
        Categories := array{JetpackCategory, JetpackDirectionCategory}
        MinValue := option{-90.0}
        MaxValue := option{90.0}
    BoostPitchDegrees<public>:float = 90.0
    # 飛ぶ向きの左右の角度（度。正面が 0、プラスで右。既定 0）
    @editable_number(float):
        ToolTip := JetpackBoostYawToolTip
        Categories := array{JetpackCategory, JetpackDirectionCategory}
        MinValue := option{-180.0}
        MaxValue := option{180.0}
    BoostYawDegrees<public>:float = 0.0
    # ここまでの秒数のチャージは飛ぶ距離が 1 倍のまま（既定 1）
    @editable_number(float):
        ToolTip := JetpackMinChargeSecondsToolTip
        Categories := array{JetpackCategory, JetpackChargeCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    MinChargeSeconds<public>:float = 1.0
    # この秒数までチャージすると距離が最大（MaxChargeMultiplier 倍）になり、エネルギーを使う（既定 3）
    @editable_number(float):
        ToolTip := JetpackMaxChargeSecondsToolTip
        Categories := array{JetpackCategory, JetpackChargeCategory}
        MinValue := option{0.1}
        MaxValue := option{10.0}
    MaxChargeSeconds<public>:float = 3.0
    # チャージを最大まで溜めたときの、飛ぶ距離の倍率（既定 3）
    @editable_number(float):
        ToolTip := JetpackMaxChargeMultiplierToolTip
        Categories := array{JetpackCategory, JetpackChargeCategory}
        MinValue := option{1.0}
        MaxValue := option{10.0}
    MaxChargeMultiplier<public>:float = 3.0
    # チャージを始めたときに位置を直接動かして持ち上げる高さ（センチメートル。既定 50）
    @editable_number(float):
        ToolTip := JetpackChargeLiftToolTip
        Categories := array{JetpackCategory, JetpackChargeCategory}
        MinValue := option{0.0}
        MaxValue := option{300.0}
    ChargeLiftCm<public>:float = 50.0
    # チャージのあいだ上がっていく速さ（センチメートル毎秒。既定 50）。0 ならその高さで止まる
    @editable_number(float):
        ToolTip := JetpackChargeRiseSpeedToolTip
        Categories := array{JetpackCategory, JetpackChargeCategory}
        MinValue := option{0.0}
        MaxValue := option{1000.0}
    ChargeRiseSpeedCmPerSecond<public>:float = 50.0
    # 1 回飛ぶたびに使うエネルギー（既定 30）。足りなくても飛べ、0 になる
    @editable_number(float):
        ToolTip := JetpackBoostEnergyCostToolTip
        Categories := array{JetpackCategory, JetpackEnergyCategory}
        MinValue := option{0.0}
        MaxValue := option{1000.0}
    BoostEnergyCost<public>:float = 30.0
    # 落下の軽減のあいだ 1 秒に使うエネルギー（既定 1）
    @editable_number(float):
        ToolTip := JetpackGlideEnergyPerSecondToolTip
        Categories := array{JetpackCategory, JetpackEnergyCategory}
        MinValue := option{0.0}
        MaxValue := option{100.0}
    GlideEnergyPerSecond<public>:float = 1.0
    # true（既定）なら、アイテムに置いたときエネルギーが 0 になるとアイテムごと無くす
    @editable:
        ToolTip := JetpackRemoveItemWhenEmptyToolTip
        Categories := array{JetpackCategory, JetpackEnergyCategory}
    RemoveItemWhenEmpty<public>:logic = true
    # 落下の軽減のあいだの落ちる速さの上限（センチメートル毎秒。既定 300）。0 で高さを保つ
    @editable_number(float):
        ToolTip := JetpackGlideMaxFallSpeedToolTip
        Categories := array{JetpackCategory, JetpackGlideCategory}
        MinValue := option{0.0}
        MaxValue := option{5000.0}
    GlideMaxFallSpeedCmPerSecond<public>:float = 300.0
    # 空中で押してチャージし、離して飛ぶ操作。既定は Jump
    @editable:
        ToolTip := JetpackBoostActionToolTip
        Categories := array{JetpackCategory, JetpackInputCategory}
    BoostAction<public>:input_action(logic) = Character.Jump
    # 付与しているあいだ有効にするキー割り当て。BoostAction を含むもの。既定は TraversalMapping
    @editable:
        ToolTip := JetpackBoostMappingToolTip
        Categories := array{JetpackCategory, JetpackInputCategory}
    BoostMapping<public>:input_mapping = Character.TraversalMapping
    # true なら剥奪したときに BoostMapping を外す（この能力専用の割り当てのときだけ。既定 false）
    @editable:
        ToolTip := JetpackRemoveMappingToolTip
        Categories := array{JetpackCategory, JetpackInputCategory}
    RemoveMappingOnRevoke<public>:logic = false

    BoostRatioChangedEventInternal<private><final>:event(tuple(agent, float)) = event(tuple(agent, float)){}

    # だれかのブーストのゲージが変わったときに、（その人, ゲージ 0.0〜1.0）で届く（Await / Subscribe する。外から Signal はできない）。使える = 1、チャージ中は 0 から 1、飛んだあと着地するまで 0、剥奪で 0
    BoostRatioChangedEvent<public><final>:listenable(tuple(agent, float)) = MakeProxyListenable(BoostRatioChangedEventInternal)

    var Ratios<private>:[agent]float = map{}
    var Manager<private>:?player_manager_component = false

    # Agent のブーストのゲージ（0.0〜1.0）。付与されていない人は 0.0
    GetBoostRatio<public>(Agent:agent)<transacts>:float =
        if (Ratio := Ratios[Agent]) then Ratio else 0.0

    RunFor<override>(Agent:agent)<suspends>:void =
        MaybeInput := Agent.AwaitPlayerInput()
        if (PlayerInput := MaybeInput?):
            CacheManager()
            Runner := jetpack_runner:
                Ability := Self
                Agent := Agent
                PlayerInput := PlayerInput
                Tick := TickEvents.PrePhysics
            Emptied := RunUntilEmpty(Runner)
            if (Emptied?):
                Entity.RemoveFromInventory()

    RunUntilEmpty<private>(Runner:jetpack_runner)<suspends>:logic =
        defer:
            Runner.Cleanup()
            SetBoostRatio(Runner.Agent, 0.0)
        Runner.Run()

    # エネルギーが 0 になったときにアイテムごと消すなら成功する（RemoveItemWhenEmpty で、この entity がアイテム）
    ShouldRemoveItemWhenEmpty<internal>()<decides><transacts>:void =
        RemoveItemWhenEmpty?
        Entity.GetComponent[item_component]

    SetBoostRatio<internal>(Agent:agent, Ratio:float):void =
        if (Ratios[Agent] = Ratio):
            return
        if (set Ratios[Agent] = Ratio) {}
        BoostRatioChangedEventInternal.Signal((Agent, Ratio))
        Changed := jetpack_boost_changed_event{Ability := Self, Agent := Agent, Ratio := Ratio}
        Entity.SendUp(Changed)
        if (Player := player[Agent], Found := Manager?, Slot := Found.FindSlot[Player]):
            Slot.Entity.SendDown(player_event{Sender := Self, Event := Changed})

    # slot へ送るための player_manager_component を探して覚える（覚えていれば探さない。見つかるまでは RunFor の開始のたびに探す）
    CacheManager<private>():void =
        set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)
