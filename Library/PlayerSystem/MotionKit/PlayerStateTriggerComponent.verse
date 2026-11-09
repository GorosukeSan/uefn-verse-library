using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { SceneGraphSystem }
using { PlayerSystem.TooltipKit }

# 役割：持ち主のキャラクターが State（空中・しゃがみ・スプリント・水中など）に入ったら Targets へ起動の合図（activated_event）、出たら停止の合図（deactivated_event）を送る（「空中にいるあいだだけ光る」「しゃがんでいるあいだだけ HUD を出す」など）
#   毎フレーム状態を見て、変わったときだけ送る。開始時に State に入っていれば、すぐ起動の合図を送る
# 置き方：エディターで、ロードアウトのプレハブ（loadout_component の Prefab）の中に置く（持ち主がいないと何もしない。出力ログに出る）
# 外から：IsActive（今 State にいるか）
player_state_trigger_component<public> := class<final_super>(component):

    # 見張る状態。既定 InAir
    @editable:
        ToolTip := PlayerStateToolTip
        Categories := array{PlayerMotionCategory}
    State<public>:player_motion_state = player_motion_state.InAir
    # 合図を送る entity（その entity と子孫に届く）。空なら、この entity の子の entity へ送る（自分の entity へは送らない）
    @editable:
        ToolTip := PlayerStateTargetsToolTip
        Categories := array{PlayerMotionCategory}
    Targets<public>:[]entity = array{}

    Watchers<private>:player_motion_watcher_set = player_motion_watcher_set{}
    var<private> Inside:logic = false
    var<private> Owner:?player = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (OwningPlayer := Entity.FindOwningPlayer[]):
            set Owner = option{OwningPlayer}
            Watchers.Start(Entity, OnMotion, TickEvents.PrePhysics)
            set Subscription = option{TickEvents.PrePhysics.Subscribe(OnTick)}
        else:
            Print("[player_state_trigger_component] 持ち主がいません（ロードアウトのプレハブの中など、持ち主のいる場所に置いてください）")

    var<private> Subscription:?cancelable = false

    OnEndSimulation<override>():void =
        Subscription.CancelIfSet()
        set Subscription = false
        Watchers.Stop()
        if (Inside?):
            Send(false)
        (super:)OnEndSimulation()

    # 持ち主が今 State にいるなら成功する
    IsActive<public>()<decides><transacts>:void =
        Inside?

    OnMotion<private>(Agent:agent, Happened:player_motion):void = {}

    OnTick<private>(DeltaTime:float):void =
        if (Player := Owner?):
            Now := logic{Watchers.IsInState[Player, State]}
            if (Now <> Inside):
                Send(Now)

    Send<private>(Active:logic):void =
        set Inside = Active
        Receivers := if (Targets.Length > 0) then Targets else Entity.GetEntities()
        for (Receiver : Receivers):
            if (Active?):
                if (Player := Owner?):
                    Receiver.SendActivatedBy(Player)
                else:
                    Receiver.SendActivated()
            else:
                Receiver.SendDeactivated()
