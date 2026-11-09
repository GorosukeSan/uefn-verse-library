using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { ConditionSystem }
using { SceneGraphSystem }
using { InteractSystem.TooltipKit }

# 役割：押されたら満たす（起動し直すと満たさなくなる）
# 置き方：エディターで entity に付ける
# 親：game_transition_component か condition_all / condition_any の entity の直下
# 子：interact_trigger_component を付けた entity（子孫ならどこでも）。子に置けないときは Trigger で選ぶ
# 外から：Reset で満たさない状態に戻す（起動の合図 activated_event でも戻る）
interacted_condition_component<public> := class<final_super>(condition_component):

    # 見張るボタン（interact_trigger_component を付けた entity）。子孫のボタンは選ばなくても数える（既定 なし）
    @editable:
        ToolTip := InteractedTriggerToolTip
        Categories := array{InteractCategory, InteractedTriggerCategory}
    Trigger<public>:?entity = false

    var Interacted<private>:logic = false
    var Subscription<private>:?cancelable = false

    IsSatisfied<override>()<decides><transacts>:void =
        Interacted?

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if:
            TriggerEntity := Trigger?
            TriggerComponent := TriggerEntity.GetComponent[interact_trigger_component]
        then:
            set Subscription = option{TriggerComponent.InteractedEvent.Subscribe(OnInteracted)}

    OnEndSimulation<override>():void =
        Subscription.CancelIfSet()
        set Subscription = false
        (super:)OnEndSimulation()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            SetInteracted(false)
        else if (interacted_event[SceneEvent]):
            SetInteracted(true)
        false

    # 満たさない状態（まだ押されていない）に戻す
    Reset<public>():void =
        SetInteracted(false)

    OnInteracted<private>(Agent:agent):void =
        SetInteracted(true)

    SetInteracted<private>(Value:logic):void =
        if (Interacted <> Value):
            set Interacted = Value
            NotifyChanged()
