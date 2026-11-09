using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Devices }
using { ActivationSystem }
using { FNDeviceSystem.TooltipKit }

# 見せ方・聞かせ方で、デバイスでしかできないこと（シネマティック シーケンス・音）を、起動・停止の合図から行う部品。

# だれに再生するか
device_play_scope<public> := enum:
    # 全員（デバイスの Visibility の設定に従う）
    Everyone
    # 合図を起こした人だけ（デバイスの Visibility = Instigator のとき。分からなければ全員）
    Activator

# 役割：起動の合図でシネマティック シーケンス デバイスを再生し、停止の合図で止める
# 置き方：エディターで entity に付ける（ノード・ボリューム・インタラクトの Targets など）
# 外から：Play / Stop
# 前提・注意：デバイスは 1 つずつ選ぶ（デバイスの配列は MCP で書けないため）。複数のデバイスを使うときは、子の entity にこの部品を 1 つずつ置く
device_sequence_component<public> := class<final_super>(component):

    # 再生するシネマティック シーケンス デバイス
    @editable:
        ToolTip := DeviceSequencesToolTip
        Categories := array{FNDeviceCategory}
    Sequence<public>:?cinematic_sequence_device = false
    # だれに再生するか。既定 Everyone
    @editable:
        ToolTip := DevicePlayScopeToolTip
        Categories := array{FNDeviceCategory}
    Scope<public>:device_play_scope = device_play_scope.Everyone
    # オンなら停止の合図で止める。既定オン
    @editable:
        ToolTip := DeviceStopOnDeactivateToolTip
        Categories := array{FNDeviceCategory}
    StopOnDeactivate<public>:logic = true

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            if (Scope = device_play_scope.Activator, Agent := SceneEvent.FindActivatingAgent[], Device := Sequence?):
                Device.Play(Agent)
            else:
                Play()
        else if (deactivated_event[SceneEvent], StopOnDeactivate?):
            Stop()
        false

    # （全員に）再生する
    Play<public>():void =
        if (Device := Sequence?):
            Device.Play()

    # 止める
    Stop<public>():void =
        if (Device := Sequence?):
            Device.Stop()

# 役割：起動の合図でオーディオ プレイヤー デバイスを鳴らし、停止の合図で止める（効果音・BGM）
# 置き方：エディターで entity に付ける（独自キャラクターの動きの反応・インタラクト・ボリュームの Targets など）
# 外から：Play / Stop
# 前提・注意：デバイスは 1 つずつ選ぶ（デバイスの配列は MCP で書けないため）。複数のデバイスを使うときは、子の entity にこの部品を 1 つずつ置く
device_audio_component<public> := class<final_super>(component):

    # 鳴らすオーディオ プレイヤー デバイス
    @editable:
        ToolTip := DeviceAudioPlayersToolTip
        Categories := array{FNDeviceCategory}
    AudioPlayer<public>:?audio_player_device = false
    # だれに鳴らすか。既定 Everyone
    @editable:
        ToolTip := DevicePlayScopeToolTip
        Categories := array{FNDeviceCategory}
    Scope<public>:device_play_scope = device_play_scope.Everyone
    # オンなら停止の合図で止める。既定オン
    @editable:
        ToolTip := DeviceStopOnDeactivateToolTip
        Categories := array{FNDeviceCategory}
    StopOnDeactivate<public>:logic = true

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            if (Scope = device_play_scope.Activator, Agent := SceneEvent.FindActivatingAgent[], Device := AudioPlayer?):
                Device.Play(Agent)
            else:
                Play()
        else if (deactivated_event[SceneEvent], StopOnDeactivate?):
            Stop()
        false

    # （全員に）鳴らす
    Play<public>():void =
        if (Device := AudioPlayer?):
            Device.Play()

    # 止める
    Stop<public>():void =
        if (Device := AudioPlayer?):
            Device.Stop()
