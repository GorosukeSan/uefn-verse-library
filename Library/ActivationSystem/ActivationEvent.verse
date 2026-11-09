using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

# 起動の合図。受けた component は動き出す（カウントダウンを始める、画面を出す、入力を受け付けるなど）
# 方向：送った entity から下へ（SendDown）。ゲームの流れならノードに入ったとき（game_node_entered_event）、ほかに interact_trigger_component の Targets、activate_on_begin_component、利用者のコード（SendActivated）
# 受け手：その entity と子孫で起動を待つ component。消費しない
activated_event<public> := class(scene_event):

# 停止の合図。受けた component は止まり、起動中に作ったものを片付ける
# 方向：送った entity から下へ（SendDown）。ゲームの流れならノードから出たとき（game_node_exited_event）、ほかに利用者のコード（SendDeactivated）
# 受け手：その entity と子孫で起動を待つ component。消費しない
deactivated_event<public> := class(scene_event):

# InEntity とその子孫へ起動の合図（activated_event）を送る。ゲームの流れの外で、起動を待つ component を動かすときに使う
(InEntity:entity).SendActivated<public>():void =
    InEntity.SendDown(activated_event{})

# InEntity とその子孫へ停止の合図（deactivated_event）を送る
(InEntity:entity).SendDeactivated<public>():void =
    InEntity.SendDown(deactivated_event{})

# だれが起こしたかの分かる起動の合図（activated_event の派生なので、起動を待つ部品はそのまま動く）
# 方向・受け手は activated_event と同じ。送り手：押した人・入った人・選んだ人などが分かる部品（interact_trigger_component・choice_menu_component・volume_activation_component・動きの反応など）
# 受け手のうち、人が要るもの（FNDeviceSystem のデバイスの橋渡しなど）は Agent を使う
activated_by_agent_event<public> := class(activated_event):
    # 起こした人
    Agent<public>:agent

# InEntity とその子孫へ、Agent が起こした起動の合図（activated_by_agent_event）を送る
(InEntity:entity).SendActivatedBy<public>(Agent:agent):void =
    InEntity.SendDown(activated_by_agent_event{Agent := Agent})

# SceneEvent が、だれが起こしたかの分かる起動の合図なら、その人を返す。そうでなければ失敗する
(SceneEvent:scene_event).FindActivatingAgent<public>()<decides><transacts>:agent =
    activated_by_agent_event[SceneEvent].Agent
