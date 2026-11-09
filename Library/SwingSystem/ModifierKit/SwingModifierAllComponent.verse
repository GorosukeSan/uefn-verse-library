using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { SwingSystem }
using { SwingSystem.TooltipKit }

# 役割：同じ entity の swing_modifier_component の倍率を、全プレイヤー（途中参加も）に掛ける（縛りのモードや、全員が強くなる段階など）
# いつ：ApplyOnBegin が true ならシミュレーション開始から。false なら起動の合図（activated_event）から停止の合図（deactivated_event）まで
# 置き方：エディターで、swing_modifier_component と同じ entity に付ける
# 親：起動の合図を使うなら、それが届く場所（ゲームの流れなら、ノードの entity かその子孫）
swing_modifier_all_component<public> := class<final_super>(component):

    # true なら開始から全員に掛ける。false（既定）なら起動の合図から停止の合図まで
    @editable:
        ToolTip := SwingModifierApplyOnBeginToolTip
        Categories := array{SwingCategory, SwingModifierCategory}
    ApplyOnBegin<public>:logic = false

    var<private> Active:logic = false

    # 掛けているあいだ成功する
    IsApplying<public>()<decides><transacts>:void =
        Active?

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (ApplyOnBegin?):
            Start()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Start()
        else if (deactivated_event[SceneEvent]):
            Stop()
        false

    OnEndSimulation<override>():void =
        Stop()
        (super:)OnEndSimulation()

    Start<private>():void =
        if (not Active?, Modifier := Entity.GetComponent[swing_modifier_component]):
            set Active = true
            Modifier.ApplyToAll()

    Stop<private>():void =
        if (Active?):
            set Active = false
            if (Modifier := Entity.GetComponent[swing_modifier_component]):
                Modifier.RemoveFromAll()
