using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { PlayerSystem }
using { SceneGraphSystem }

# 役割：参加者が 1 人以上いて、全員が「準備 OK」なら満たす
# 置き方：エディターで entity に付ける
# 親：game_transition_component か condition_all / condition_any の entity の直下
# 前提：区画（または世界）に player_manager_component と player_ready_component が 1 つずつ（開始時と知らせを受けたときに探して、見つけたら覚えておく）
all_players_ready_condition_component<public> := class<final_super>(condition_component):

    var<private> Manager:?player_manager_component = false
    var<private> Ready:?player_ready_component = false

    IsSatisfied<override>()<decides><transacts>:void =
        # 判定の中では探さない（覚えているものだけを見る）
        PlayerCount := Manager?.GetPlayerCount()
        PlayerCount > 0
        Ready?.GetReadyCount() = PlayerCount

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Resolve()

    OnReceive<override>(SceneEvent:scene_event):logic =
        Resolve()
        if (Changed := player_ready_changed_event[SceneEvent], Changed.PlayerReady = Ready?):
            NotifyChanged()
        else if (Added := player_added_event[SceneEvent], Added.Manager = Manager?):
            NotifyChanged()
        else if (Removed := player_removed_event[SceneEvent], Removed.Manager = Manager?):
            NotifyChanged()
        false

    OnEndSimulation<override>():void =
        set Manager = false
        set Ready = false
        (super:)OnEndSimulation()

    # 区画から player_manager_component と player_ready_component を探して覚える（覚えていれば探さない）。OnBeginSimulation と知らせを受けたときに呼ぶ
    Resolve<private>():void =
        set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)
        set Ready = Entity.ResolveScopedComponent(Ready, player_ready_component)
