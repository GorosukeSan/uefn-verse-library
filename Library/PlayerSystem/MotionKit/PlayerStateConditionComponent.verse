using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { SceneGraphSystem }
using { PlayerSystem.TooltipKit }

# 役割：持ち主のキャラクターが State（空中・しゃがみ・スプリント・水中など）にいるあいだ満たす条件
#   ability_grant_condition_component の子に置くと「しゃがんでいるあいだだけ使える能力」、game_transition_component の子に置くと「空中に出たら次へ」などをコードなしで作れる
#   毎フレーム状態を見て、変わったときだけ知らせる
# 置き方：エディターで entity に付ける。ロードアウトのプレハブ（loadout_component の Prefab）の中に置く（持ち主がいないと満たさない）
# 親：ability_grant_condition_component / game_transition_component / condition_all / condition_any の entity の直下
player_state_condition_component<public> := class<final_super>(condition_component):

    # 満たす状態。既定 Crouching
    @editable:
        ToolTip := PlayerStateToolTip
        Categories := array{PlayerMotionCategory}
    State<public>:player_motion_state = player_motion_state.Crouching

    Watchers<private>:player_motion_watcher_set = player_motion_watcher_set{}
    var<private> Satisfied:logic = false
    var<private> Owner:?player = false
    var<private> Subscription:?cancelable = false

    IsSatisfied<override>()<decides><transacts>:void =
        Satisfied?

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (OwningPlayer := Entity.FindOwningPlayer[]):
            set Owner = option{OwningPlayer}
            Watchers.Start(Entity, OnMotion, TickEvents.PrePhysics)
            set Subscription = option{TickEvents.PrePhysics.Subscribe(OnTick)}
        else:
            Print("[player_state_condition_component] 持ち主がいません（ロードアウトのプレハブの中など、持ち主のいる場所に置いてください）")

    OnEndSimulation<override>():void =
        Subscription.CancelIfSet()
        set Subscription = false
        Watchers.Stop()
        (super:)OnEndSimulation()

    OnMotion<private>(Agent:agent, Happened:player_motion):void = {}

    OnTick<private>(DeltaTime:float):void =
        if (Player := Owner?):
            Now := logic{Watchers.IsInState[Player, State]}
            if (Now <> Satisfied):
                set Satisfied = Now
                NotifyChanged()
