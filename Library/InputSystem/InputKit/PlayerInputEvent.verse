using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }

# 入力アクションが押された知らせ
# 方向：区画全体（SendScoped。区画が無ければ世界全体）
# 送り手：player_input_component。受け手：押されたことを見る component。消費しない（同じ component の押下だけを見るなら、TriggeredEvent を Subscribe するか Input で絞る）
player_input_triggered_event<public> := class(scene_event):
    # 送った player_input_component
    Input<public>:player_input_component
    # 押した人
    Agent<public>:agent
    # 押された操作（送った component の InputAction）
    Action<public>:input_action(logic)
