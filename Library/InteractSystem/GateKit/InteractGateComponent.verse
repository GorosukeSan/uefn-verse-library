using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { InteractSystem.TooltipKit }

# 役割：開いているあいだだけ、同じ entity の interactable_component を押せるようにする（閉じているあいだは押せない）
# 置き方：エディターで entity に付ける
# 親：起動の合図が届く場所（ゲームの流れなら、ノードの entity かその子孫。interact_trigger_component の Targets で選ばれた entity でもよい）
# 同じ entity：interactable_component（basic_interactable_component など）
# いつ開くか：起動の合図（activated_event）で開き、停止の合図（deactivated_event）で閉じる。OpenOnBegin が true ならシミュレーション開始から開いている。コードから Open / Close を呼んでもよい
# 外から：Open / Close / IsOpen
interact_gate_component<public> := class<final_super>(component):

    # true ならシミュレーション開始から押せる。false なら起動の合図から（既定 false）
    @editable:
        ToolTip := InteractGateOpenOnBeginToolTip
        Categories := array{InteractCategory}
    OpenOnBegin<public>:logic = false

    var<private> Opened:logic = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set Opened = OpenOnBegin
        Apply()

    OnSimulate<override>()<suspends>:void =
        # 同じ entity の interactable_component が OnBeginSimulation を終えてから、もう一度合わせる
        TickEvents.PrePhysics.Await()
        Apply()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Open()
        else if (deactivated_event[SceneEvent]):
            Close()
        false

    # 押せるようにする
    Open<public>():void =
        set Opened = true
        Apply()

    # 押せないようにする
    Close<public>():void =
        set Opened = false
        Apply()

    # 開いている（押せる）あいだ成功する
    IsOpen<public>()<decides><transacts>:void =
        Opened?

    Apply<private>():void =
        if (Interactable := Entity.GetComponent[interactable_component]):
            if (Opened?):
                Interactable.Enable()
            else:
                Interactable.Disable()
