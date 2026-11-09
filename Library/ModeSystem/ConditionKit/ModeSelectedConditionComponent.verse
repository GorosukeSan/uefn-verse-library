using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { ModeSystem }
using { SceneGraphSystem }
using { ModeSystem.TooltipKit }

# 役割：Mode の entity のモードが選ばれていたら満たす
# 置き方：エディターで entity に付ける
# 親：game_transition_component か condition_all / condition_any の entity の直下
# 前提：区画（または世界）に mode_select_component が 1 つ（開始時と知らせを受けたときに探して、見つけたら覚えておく）
mode_selected_condition_component<public> := class<final_super>(condition_component):

    # このモード（game_mode_component を付けた entity）が選ばれていたら満たす。空なら満たさない。既定 空
    @editable:
        ToolTip := ModeSelectedModeToolTip
        Categories := array{ModeCategory}
    Mode<public>:?entity = false

    var<private> Selector:?mode_select_component = false

    IsSatisfied<override>()<decides><transacts>:void =
        # 判定の中では探さない（覚えているものだけを見る）
        Expected := Mode?
        Selected := Selector?.FindSelected[]
        Selected.Entity = Expected

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set Selector = Entity.ResolveScopedComponent(Selector, mode_select_component)

    OnReceive<override>(SceneEvent:scene_event):logic =
        set Selector = Entity.ResolveScopedComponent(Selector, mode_select_component)
        if (Changed := mode_changed_event[SceneEvent], Changed.Selector = Selector?):
            NotifyChanged()
        false

    OnEndSimulation<override>():void =
        set Selector = false
        (super:)OnEndSimulation()
