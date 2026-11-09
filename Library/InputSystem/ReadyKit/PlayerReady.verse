using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { PlayerSystem }
using { SceneGraphSystem }

# 方向：区画全体（SendScoped。区画が無ければ世界全体）
# 送り手：player_ready_component（の view）。受け手：all_players_ready_condition_component など。消費しない
player_ready_changed_event<public> := class(scene_event):
    # 送った player_ready_component
    PlayerReady<public>:player_ready_component
    # 切り替えた人
    Agent<public>:agent
    # 切り替えたあと準備 OK なら true
    Ready<public>:logic

# 「準備 OK」の人（agent）に付くタグ。player_ready_component（の view）が付け外しする（ほかの System は Agent.HasPlayerTag[player_ready_tag] で確かめる）
player_ready_tag<public> := class(player_state_tag):

# 役割：1 人分の「準備 OK」を持つ（押されたときの切り替えは player_ready_component が呼ぶ）
# 置き方：実行時に player_ready_component が作る（エディターでは置かない）
# タグ：準備 OK のあいだ、その人（agent）に player_ready_tag を付ける（view が消える＝受け付けをやめる・その人が退出すると外す）
# いつ：view が止まる（OnEndSimulation。停止・HideFor・退出で slot ごと外れる）と「準備 OK でない」に戻る（知らせは送らない）
player_ready_view_component<public> := class<final_super>(component):

    # この view を作った player_ready_component
    Source<public>:player_ready_component
    # この view が受け持つ人
    Player<public>:player

    var<private> Ready:logic = false
    var<private> ReadyTags:player_tag_holder = player_tag_holder{}

    # 「準備 OK」のあいだ成功する
    IsReady<public>()<decides><reads>:void =
        Ready?

    # 準備 OK にする（Value が false なら取り消す）。変わったときだけ知らせる
    SetReady<public>(Value:logic):void =
        if (Ready = Value):
            return
        set Ready = Value
        ReadyTags.Set(Player, Value, player_ready_tag{})
        Source.NotifyReadyChanged(Player, Value)

    OnEndSimulation<override>():void =
        # 退出などで view が止まったら準備も戻す（止まった view が数に残らないように）
        set Ready = false
        ReadyTags.RemoveAll()
        (super:)OnEndSimulation()
