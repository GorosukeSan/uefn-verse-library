using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { ConditionSystem }

# 役割：カウントダウンが 0 になったら満たす（起動し直す・数え直すと満たさなくなる）
# 置き方：エディターで entity に付ける
# 親：game_transition_component か condition_all / condition_any の entity の直下。そのうえで countdown_component の entity の子孫
countdown_finished_condition_component<public> := class<final_super>(condition_component):

    var Finished<private>:logic = false

    IsSatisfied<override>()<decides><transacts>:void =
        Finished?

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent] or countdown_remaining_changed_event[SceneEvent]):
            SetFinished(false)
        else if (countdown_finished_event[SceneEvent]):
            SetFinished(true)
        false

    SetFinished<private>(Value:logic):void =
        if (Finished <> Value):
            set Finished = Value
            NotifyChanged()
