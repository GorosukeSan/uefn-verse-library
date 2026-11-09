using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SceneGraphSystem }

# 役割：子の条件をすべて満たしたときに満たす（子が無ければ満たす）
# 置き方：エディターで entity に付ける
# 親：game_transition_component か condition_all / condition_any の entity の直下
# 子：条件（condition_component の派生）を付けた entity を、直下に 1 つずつ（並び順は関係ない）
# 知らせ：子孫の条件から condition_changed_event が届くと、それを消費して自分の condition_changed_event を上へ送り直し、ChangedEvent にも届ける
condition_all_component<public> := class<final_super>(condition_component):

    IsSatisfied<override>()<decides><transacts>:void =
        Entity.AreChildConditionsSatisfied[]

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Changed := condition_changed_event[SceneEvent], Changed.Condition <> Self):
            NotifyChanged()
            true
        else:
            false
