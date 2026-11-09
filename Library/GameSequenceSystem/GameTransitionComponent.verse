using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { SceneGraphSystem }
using { GameSequenceSystem.TooltipKit }

# 役割：条件を満たしたら Target のノードへ進む（Target が空なら流れを終える）
# 置き方：エディターで entity に付ける
# 親：game_node_component の entity の直下
# 子：条件（condition_component の派生）を付けた entity を直下に。複数置くと「すべて満たしたら」進む（どれか 1 つでよいなら condition_any でまとめる）。無ければすぐ進む
game_transition_component<public> := class<final_super>(component):

    # 条件を満たしたときに進むノード（game_node_component を付けた entity）。空ならここで流れを終える。既定 空
    @editable:
        ToolTip := TransitionTargetToolTip
        Categories := array{TransitionCategory, TransitionTargetCategory}
    Target<public>:?entity = false
    # 同じノードの遷移が同時に進めるとき、大きいほうを優先する（0〜100）。既定 0
    @editable_number(int):
        ToolTip := TransitionPriorityToolTip
        Categories := array{TransitionCategory, TransitionPriorityCategory}
        MinValue := option{0}
        MaxValue := option{100}
    Priority<public>:int = 0

    # 進めるなら成功する。直下の子の条件（condition_component）をすべて満たしていれば成功し、条件が無ければいつも成功する
    IsReady<public>()<decides><transacts>:void =
        Entity.AreChildConditionsSatisfied[]

    # Target が空（この遷移で流れを終える）なら成功する。Target にノードが無いことは、進むときに game_sequence_component が調べる
    IsFinish<public>()<decides><transacts>:void =
        not Target?
