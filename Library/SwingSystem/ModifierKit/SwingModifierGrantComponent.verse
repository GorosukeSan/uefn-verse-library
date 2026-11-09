using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { SwingSystem }
using { SwingSystem.TooltipKit }
using { SceneGraphSystem }

# 役割：この entity に swing_modifier_request_event{Agent} が届くと、同じ entity の swing_modifier_component の倍率を、その人に DurationSeconds のあいだ掛ける（強化のアイテムや、触れると弱くなる物など）。同じ人がまた受けると、そこから数え直す。DurationSeconds が 0 なら停止するまで。停止の合図（deactivated_event）で全員から外す
# 置き方：エディターで、swing_modifier_component と同じ entity に付ける
# 親：停止の合図を使うなら、それが届く場所（ゲームの流れなら、ノードの entity かその子孫）
# 前提：掛けたいときに、この entity へ swing_modifier_request_event を送るもの（SendDown / SendUp）。コードから直接掛けるなら Request を呼ぶ
swing_modifier_grant_component<public> := class<final_super>(component):

    # 依頼を受けてから倍率を掛け続ける時間（秒。既定 10）。0 なら停止するまで
    @editable_number(float):
        ToolTip := SwingModifierDurationToolTip
        Categories := array{SwingCategory, SwingModifierCategory}
        MinValue := option{0.0}
        MaxValue := option{600.0}
    DurationSeconds<public>:float = 10.0

    # 掛けている人と、外す時刻（GetSimulationElapsedTime の値。期限なしは Inf）
    var<private> Expiries:[agent]float = map{}

    # 期限が変わった（依頼を受けた）ことを、期限を待つループ（OnSimulate）に知らせる
    ExpiriesChangedEvent<private>:event() = event(){}

    # 今この component が Agent に掛けているなら成功する
    IsApplyingTo<public>(Agent:agent)<decides><transacts>:void =
        Expiries[Agent]

    # swing_modifier_request_event を受けたのと同じ（Agent に DurationSeconds のあいだ掛ける。掛けていれば数え直す）
    Request<public>(Agent:agent):void =
        if (Modifier := Entity.GetComponent[swing_modifier_component]):
            Expiry := if (DurationSeconds > 0.0) then GetSimulationElapsedTime() + DurationSeconds else Inf
            if (not Expiries[Agent]):
                Modifier.ApplyTo(Agent)
            if (set Expiries[Agent] = Expiry) {}
            if (DurationSeconds > 0.0):
                ExpiriesChangedEvent.Signal()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Requested := swing_modifier_request_event[SceneEvent]):
            Request(Requested.Agent)
        else if (deactivated_event[SceneEvent]):
            RemoveAll()
        false

    OnEndSimulation<override>():void =
        RemoveAll()
        (super:)OnEndSimulation()

    # 期限で外す。1 本のループで、一番早い期限まで眠る（そのあいだに依頼が来たら起きて計算し直す）。止まると（OnEndSimulation の前に）このループも止まるので、眠ったままのタスクは残らない
    OnSimulate<override>()<suspends>:void =
        loop:
            Now := GetSimulationElapsedTime()
            for (Agent -> Expiry : Expiries, Expiry <= Now):
                Remove(Agent)
            var Next:float = Inf
            for (Agent -> Expiry : Expiries, Expiry < Next):
                set Next = Expiry
            if (Next < Inf):
                race:
                    Sleep(Next - Now)
                    ExpiriesChangedEvent.Await()
            else:
                ExpiriesChangedEvent.Await()

    Remove<private>(Agent:agent):void =
        set Expiries = Expiries.RemoveKey(Agent)
        if (Modifier := Entity.GetComponent[swing_modifier_component]):
            Modifier.RemoveFrom(Agent)

    RemoveAll<private>():void =
        for (Agent -> Expiry : Expiries):
            Remove(Agent)
