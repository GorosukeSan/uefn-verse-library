using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Devices }
using { ActivationSystem }
using { FNDeviceSystem.TooltipKit }

# ゲームの進行で、デバイスでしかできないこと（ゲームの終了・職業とチーム・スコア）を、起動の合図から行う部品。
# どの部品も、起動の合図を受けたら Recipients（合図を起こした人 / 持ち主 / 全員）に対してデバイスの操作をする。

# 役割：起動の合図で、ゲーム終了デバイスを Recipients に対して Activate する（勝ち・負けで終える。勝ち負けの設定はデバイス側）
# 置き方：エディターで entity に付ける（ゴールのボリューム・ゲームの流れの最後のノードなど、合図が届く場所）
device_end_game_component<public> := class<final_super>(component):

    # 終わらせるゲーム終了デバイス
    @editable:
        ToolTip := DeviceEndGameToolTip
        Categories := array{FNDeviceCategory}
    EndGame<public>:?end_game_device = false
    # だれに対して終えるか。既定 Activator（合図を起こした人）
    @editable:
        ToolTip := DeviceRecipientsToolTip
        Categories := array{FNDeviceCategory}
    Recipients<public>:device_target_agents = device_target_agents.Activator

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent], Device := EndGame?):
            for (Agent : GetDeviceTargets(Entity, SceneEvent, Recipients)):
                Device.Activate(Agent)
        false

# 職業・チームをどう変えるか
device_class_change<public> := enum:
    # 職業だけ
    Class
    # チームだけ
    Team
    # チームと職業
    TeamAndClass

# 役割：起動の合図で、職業とチームの選択デバイスを Recipients に使う（職業・チームを変える。どの職業・チームにするかはデバイス側）
#   ロードアウト（LoadoutSystem）の中に置くと、ロードアウトを付けたときに持ち主の職業も変わる（ロードアウトは付けた次のフレームに起動の合図を受ける。Recipients = Owner）
# 置き方：エディターで entity に付ける
device_class_component<public> := class<final_super>(component):

    # 使う職業とチームの選択デバイス
    @editable:
        ToolTip := DeviceClassSelectorToolTip
        Categories := array{FNDeviceCategory}
    Selector<public>:?class_and_team_selector_device = false
    # 何を変えるか。既定 Class
    @editable:
        ToolTip := DeviceClassChangeToolTip
        Categories := array{FNDeviceCategory}
    Change<public>:device_class_change = device_class_change.Class
    # だれを変えるか。既定 Owner（持ち主。いなければ合図を起こした人）
    @editable:
        ToolTip := DeviceRecipientsToolTip
        Categories := array{FNDeviceCategory}
    Recipients<public>:device_target_agents = device_target_agents.Owner

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent], Device := Selector?):
            for (Agent : GetDeviceTargets(Entity, SceneEvent, Recipients)):
                case (Change):
                    device_class_change.Class => Device.ChangeClass(Agent)
                    device_class_change.Team => Device.ChangeTeam(Agent)
                    device_class_change.TeamAndClass => Device.ChangeTeamAndClass(Agent)
        false

# スコアをどう変えるか
device_score_change<public> := enum:
    # スコア マネージャーの設定どおりに加点する（Activate）
    Award
    # 1 段上げる（Increment）
    Increment
    # 1 段下げる（Decrement）
    Decrement

# 役割：起動の合図で、スコア マネージャー デバイスを Recipients に使う（加点・増減。点数はデバイス側）
# 置き方：エディターで entity に付ける（コイン・ゴール・倒した数の反応など）
device_score_component<public> := class<final_super>(component):

    # 使うスコア マネージャー デバイス
    @editable:
        ToolTip := DeviceScoreManagerToolTip
        Categories := array{FNDeviceCategory}
    ScoreManager<public>:?score_manager_device = false
    # どう変えるか。既定 Award
    @editable:
        ToolTip := DeviceScoreChangeToolTip
        Categories := array{FNDeviceCategory}
    Change<public>:device_score_change = device_score_change.Award
    # だれのスコアを変えるか。既定 Activator
    @editable:
        ToolTip := DeviceRecipientsToolTip
        Categories := array{FNDeviceCategory}
    Recipients<public>:device_target_agents = device_target_agents.Activator

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent], Device := ScoreManager?):
            for (Agent : GetDeviceTargets(Entity, SceneEvent, Recipients)):
                case (Change):
                    device_score_change.Award => Device.Activate(Agent)
                    device_score_change.Increment => Device.Increment(Agent)
                    device_score_change.Decrement => Device.Decrement(Agent)
        false
