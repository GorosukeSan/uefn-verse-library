using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { SceneGraphSystem }
using { InteractSystem.TooltipKit }

# 押し終わった知らせ
# 方向：interact_trigger_component の entity から根へ（SendUp）
# 送り手：interact_trigger_component。受け手：祖先の interacted_condition_component など。消費しない
interacted_event<public> := class(scene_event):
    # 送ったトリガー
    Trigger<public>:interact_trigger_component
    # 押した人
    Agent<public>:agent

# 役割：押し終わる（interactable_component の SucceededEvent）たびに、押した人を上へ知らせ、Targets の entity へ起動の合図を送る（Toggle なら、押すたびに起動の合図と停止の合図を交互に送る：スイッチ・レバー）
# 置き方：エディターで entity に付ける
# 親：押されたことを受けたいものの子孫（ゲームの流れの条件なら interacted_condition_component の entity の下）。どこでもよい
# 同じ entity：interactable_component（basic_interactable_component など）。起動中だけ押せるようにするなら interact_gate_component
# 知らせ：interacted_event をこの entity から上へ送る。実行時のコードは InteractedEvent（押し終わった）、StartedEvent（押し始めた。長押しの開始。v43.00 から開始の時点で届く）、CanceledEvent（長押しを途中でやめた）を Await / Subscribe できる
# 外から：IsOn（Toggle のとき、今オンか）、SetOn（オン・オフを直接決めて合図を送る）
interact_trigger_component<public> := class<final_super>(component):

    # 押し終わるたびに起動の合図を送る entity（その entity と子孫に届く）。空なら上へ知らせるだけ
    @editable:
        ToolTip := InteractTargetsToolTip
        Categories := array{InteractCategory, InteractTargetsCategory}
    Targets<public>:[]entity = array{}

    # true なら押すたびに Targets へ起動の合図と停止の合図を交互に送る（スイッチ・レバー）。false なら起動の合図だけ（既定 false）
    @editable:
        ToolTip := InteractToggleToolTip
        Categories := array{InteractCategory}
    Toggle<public>:logic = false

    InteractedEventInternal<private><final>:event(agent) = event(agent){}

    # 押し終わるたびに、押した人で届く（Await / Subscribe する。外から Signal はできない）
    InteractedEvent<public><final>:listenable(agent) = MakeProxyListenable(InteractedEventInternal)

    StartedEventInternal<private><final>:event(agent) = event(agent){}
    CanceledEventInternal<private><final>:event(agent) = event(agent){}

    # 押し始めるたびに、押した人で届く（長押しなら押し始めた時点。押す時間が 0 なら InteractedEvent と同じ時点）
    StartedEvent<public><final>:listenable(agent) = MakeProxyListenable(StartedEventInternal)

    # 長押しを途中でやめるたびに、その人で届く
    CanceledEvent<public><final>:listenable(agent) = MakeProxyListenable(CanceledEventInternal)

    var Subscription<private>:?cancelable = false
    var<private> On:logic = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Interactable := Entity.GetComponent[interactable_component]):
            Group := cancelable_group:
                Cancelables := array:
                    Interactable.SucceededEvent.Subscribe(OnSucceeded)
                    Interactable.StartedEvent.Subscribe(OnStarted)
                    Interactable.CanceledEvent.Subscribe(OnCanceled)
            set Subscription = option{Group}

    OnEndSimulation<override>():void =
        Subscription.CancelIfSet()
        set Subscription = false
        (super:)OnEndSimulation()

    # Toggle のとき、今オン（最後に起動の合図を送った）なら成功する。Toggle でなければ失敗する
    IsOn<public>()<decides><transacts>:void =
        Toggle?
        On?

    # オン・オフを Value にして、Targets へ起動の合図（オン）か停止の合図（オフ）を送る。変わらなければ何もしない
    SetOn<public>(Value:logic):void =
        if (On <> Value):
            set On = Value
            for (Target : Targets):
                if (Value?):
                    Target.SendActivated()
                else:
                    Target.SendDeactivated()

    OnSucceeded<private>(Agent:agent):void =
        Entity.SendUp(interacted_event{Trigger := Self, Agent := Agent})
        if (Toggle?):
            SetOn(if (On?) then false else true)
        else:
            for (Target : Targets):
                Target.SendActivatedBy(Agent)
        InteractedEventInternal.Signal(Agent)

    OnStarted<private>(Agent:agent):void =
        StartedEventInternal.Signal(Agent)

    OnCanceled<private>(Agent:agent):void =
        CanceledEventInternal.Signal(Agent)
