using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { SceneGraphSystem }
using { PlayerSystem.TooltipKit }

# 役割：参加人数が MinPlayerCount 以上なら満たす
# 置き方：エディターで entity に付ける
# 親：game_transition_component か condition_all / condition_any の entity の直下
# 前提：区画（または世界）に player_manager_component が 1 つ（開始時と知らせを受けたときに探して、見つけたら覚えておく）
player_count_condition_component<public> := class<final_super>(condition_component):

    # この人数以上が参加していれば満たす（1〜100、既定 2）
    @editable_number(int):
        ToolTip := MinPlayerCountToolTip
        Categories := array{PlayerCategory}
        MinValue := option{1}
        MaxValue := option{100}
    MinPlayerCount<public>:int = 2

    var<private> Manager:?player_manager_component = false

    IsSatisfied<override>()<decides><transacts>:void =
        # 判定の中では探さない（覚えているものだけを見る）
        Manager?.GetPlayerCount() >= MinPlayerCount

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)

    OnReceive<override>(SceneEvent:scene_event):logic =
        set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)
        if (Found := Manager?):
            if (Added := player_added_event[SceneEvent], Added.Manager = Found):
                NotifyChanged()
            else if (Removed := player_removed_event[SceneEvent], Removed.Manager = Found):
                NotifyChanged()
        false

    OnEndSimulation<override>():void =
        set Manager = false
        (super:)OnEndSimulation()
