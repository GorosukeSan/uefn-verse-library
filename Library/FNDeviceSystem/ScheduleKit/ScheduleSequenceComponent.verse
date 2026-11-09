using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Devices }
using { PlayerSystem }
using { SceneGraphSystem }
using { ScheduleSystem }
using { ScheduleSystem.TooltipKit }

# Role: plays the cinematic sequence device while the schedule is Active. When entering mid-period (server start, debug time travel), aligns the position with SetPlaybackTime(elapsed seconds) after Play; Stops when the period ends
# Placement: attach to an entity in the editor, on the entity of schedule_component or a descendant. Put a device (Visibility = Everyone) in Sequence (one, since an array of devices cannot be written through MCP; for several, place one of this part on each child entity)
# From outside: IsPlaying, Resync (re-align to the current elapsed time)
# Requirements (to be confirmed in UEFN):
#   - Whether late joiners see the video in sync depends on the device. When ResyncOnPlayerJoin is on, Play + SetPlaybackTime are redone on every join (everyone's playback may jump for a moment). If it does not sync, change to one device per player (Visibility = Instigator) and Play(Agent)
#   - SetPlaybackTime is called right after Play (the order known to work). Offsets under 1 second are not aligned (not called under 0.5 s)
#   - When the sequence is shorter than the Active length, it stays stopped after it ends (no loop is set)
schedule_sequence_component<public> := class<final_super>(component):

    # The cinematic sequence device played during the period (one with Visibility = Everyone)
    @editable:
        ToolTip := ScheduleSequencesToolTip
        Categories := array{ScheduleCategory}
    Sequence<public>:?cinematic_sequence_device = false

    # Does not play if more than this many seconds have passed since the start when the period is entered. 0 means no limit (default)
    @editable_number(float):
        ToolTip := ScheduleMaxLateStartToolTip
        Categories := array{ScheduleCategory}
        MinValue := option{0.0}
    MaxLateStartSeconds<public>:float = 0.0

    # When on, every time a player joins during the period, Plays and re-aligns to the elapsed time (confirm in UEFN). Default on
    @editable:
        ToolTip := ScheduleResyncOnJoinToolTip
        Categories := array{ScheduleCategory}
    ResyncOnPlayerJoin<public>:logic = true

    Follower<private>:schedule_follower = schedule_follower{}
    var<private> Playing:logic = false
    var<private> JoinSubscription:?cancelable = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Attached := Follower.Attach(Entity, OnScheduleChanged, false)
        if (not Attached?):
            Print("[schedule_sequence_component] schedule_component not found on this entity or any ancestor")
        if (ResyncOnPlayerJoin?, Manager := Entity.FindScopedComponent[player_manager_component]):
            set JoinSubscription = option{Manager.PlayerAddedEvent.Subscribe(OnPlayerAdded)}

    OnEndSimulation<override>():void =
        JoinSubscription.CancelIfSet()
        set JoinSubscription = false
        Follower.Detach()
        StopAll()
        (super:)OnEndSimulation()

    # Succeeds while playing
    IsPlaying<public>()<decides><transacts>:void =
        Playing?

    # If playing, re-aligns to the current elapsed time (Play + SetPlaybackTime). Does nothing when not playing
    Resync<public>():void =
        if (not Playing?):
            return
        if (Schedule := Follower.FindSchedule[]):
            Snapshot := Schedule.GetCurrentSnapshot()
            if (Snapshot.IsActive[]):
                PlayAll(Snapshot.ElapsedSeconds)

    OnScheduleChanged<private>(Snapshot:schedule_snapshot):void =
        if (Snapshot.IsActive[]):
            if (Playing?):
                return
            if (MaxLateStartSeconds > 0.0 and Snapshot.ElapsedSeconds > MaxLateStartSeconds):
                return
            set Playing = true
            PlayAll(Snapshot.ElapsedSeconds)
        else:
            StopAll()

    OnPlayerAdded<private>(Player:player):void =
        Resync()

    PlayAll<private>(ElapsedSeconds:float):void =
        if (Device := Sequence?):
            Device.Play()
            if (ElapsedSeconds >= 0.5):
                Device.SetPlaybackTime(ElapsedSeconds)

    StopAll<private>():void =
        if (not Playing?):
            return
        set Playing = false
        if (Device := Sequence?):
            Device.Stop()
