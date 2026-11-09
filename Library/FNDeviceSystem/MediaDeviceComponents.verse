using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Devices }
using { ActivationSystem }
using { FNDeviceSystem.TooltipKit }

# Parts that do, from the activation / deactivation signals, the presentation things only devices can do (cinematic sequences, audio).

# Whom to play for
device_play_scope<public> := enum:
    # Everyone (follows the device's Visibility setting)
    Everyone
    # Only the agent who caused the signal (when the device's Visibility = Instigator. Everyone when unknown)
    Activator

# Role: plays the cinematic sequence device on the activation signal and stops it on the deactivation signal
# Placement: attach to an entity in the editor (a node, a volume, the Targets of an interact, ...)
# From outside: Play / Stop
# Requirements: devices are chosen one at a time (an array of devices cannot be written through MCP). To use several devices, place one of this part on each child entity
device_sequence_component<public> := class<final_super>(component):

    # The cinematic sequence device to play
    @editable:
        ToolTip := DeviceSequencesToolTip
        Categories := array{FNDeviceCategory}
    Sequence<public>:?cinematic_sequence_device = false
    # Whom to play for. Default Everyone
    @editable:
        ToolTip := DevicePlayScopeToolTip
        Categories := array{FNDeviceCategory}
    Scope<public>:device_play_scope = device_play_scope.Everyone
    # When on, stops on the deactivation signal. Default on
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

    # Plays (for everyone)
    Play<public>():void =
        if (Device := Sequence?):
            Device.Play()

    # Stops
    Stop<public>():void =
        if (Device := Sequence?):
            Device.Stop()

# Role: plays the audio player device on the activation signal and stops it on the deactivation signal (sound effects, BGM)
# Placement: attach to an entity in the editor (reactions to a custom character's movement, the Targets of an interact or a volume, ...)
# From outside: Play / Stop
# Requirements: devices are chosen one at a time (an array of devices cannot be written through MCP). To use several devices, place one of this part on each child entity
device_audio_component<public> := class<final_super>(component):

    # The audio player device to play
    @editable:
        ToolTip := DeviceAudioPlayersToolTip
        Categories := array{FNDeviceCategory}
    AudioPlayer<public>:?audio_player_device = false
    # Whom to play for. Default Everyone
    @editable:
        ToolTip := DevicePlayScopeToolTip
        Categories := array{FNDeviceCategory}
    Scope<public>:device_play_scope = device_play_scope.Everyone
    # When on, stops on the deactivation signal. Default on
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

    # Plays (for everyone)
    Play<public>():void =
        if (Device := AudioPlayer?):
            Device.Play()

    # Stops
    Stop<public>():void =
        if (Device := AudioPlayer?):
            Device.Stop()
