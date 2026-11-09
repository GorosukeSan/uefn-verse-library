using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/UI }
using { /Fortnite.com/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { ActivationSystem }
using { WidgetSystem }
using { WidgetSystem.TooltipKit }
using { ScheduleSystem }
using { ScheduleSystem.DisplayKit }
using { ScheduleSystem.TooltipKit }

# Role: from ShowWithinSeconds seconds before the schedule starts until it starts, shows countdown text on the screen of every player in the scope (late joiners too). Removed at the start. Outside the window nothing is shown and the per-second work is one comparison of the remaining seconds (no UI writes)
# Placement: attach to an entity in the editor, as a descendant of the schedule_component entity
# Requirements: one player_manager_component in the scope (or the world)
# Requirements / notes: the activated_event / deactivated_event from the schedule (start / end of the period) are ignored (showing is decided only by the window check, calling Activate / Deactivate directly)
schedule_countdown_hud_component<public> := class<final_super>(player_widget_component):

    # How many seconds before the start to show the countdown on screen (seconds). Default 300
    @editable_number(float):
        ToolTip := ScheduleHudShowWithinToolTip
        Categories := array{ScheduleDisplayCategory}
        MinValue := option{1.0}
    ShowWithinSeconds<public>:float = 300.0

    # Text format (schedule_text_format). Default MinutesSeconds
    @editable:
        ToolTip := ScheduleTextFormatToolTip
        Categories := array{ScheduleDisplayCategory}
    Format<public>:schedule_text_format = schedule_text_format.MinutesSeconds

    # Fixed string put before the text. Nothing is added when empty (default)
    @editable:
        ToolTip := ScheduleTextPrefixToolTip
        Categories := array{ScheduleDisplayCategory}
    Prefix<public>:string = ""

    # Text size (8-200). Default 48
    @editable_number(float):
        ToolTip := ScheduleHudTextSizeToolTip
        Categories := array{ScheduleDisplayCategory}
        MinValue := option{8.0}
        MaxValue := option{200.0}
    TextSize<public>:float = 48.0

    # Position (horizontal ratio of the screen. 0 = left edge, 0.5 = center, 1 = right edge; the text is centered on that point). Default 0.5. Same name and meaning as the WidgetSystem/HudKit HUDs
    @editable_number(float):
        ToolTip := WidgetPositionXToolTip
        Categories := array{ScheduleDisplayCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionXRatio<public>:float = 0.5

    # Position (vertical ratio of the screen. 0 = top edge, 0.5 = center, 1 = bottom edge; the text is centered on that point). Default 0.15. Same name and meaning as the WidgetSystem/HudKit HUDs
    @editable_number(float):
        ToolTip := WidgetPositionYToolTip
        Categories := array{ScheduleDisplayCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionYRatio<public>:float = 0.15

    Follower<private>:schedule_follower = schedule_follower{}
    var<private> LastRemainingSeconds:int = -1
    var<private> LastMessage:?message = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Attached := Follower.Attach(Entity, Refresh, option{Refresh})
        if (not Attached?):
            Print("[schedule_countdown_hud_component] schedule_component not found on this entity or any ancestor")

    OnEndSimulation<override>():void =
        Follower.Detach()
        (super:)OnEndSimulation()

    OnReceive<override>(SceneEvent:scene_event):logic =
        # Do not toggle on the start / end of the schedule period (activated / deactivated)
        if (activated_event[SceneEvent] or deactivated_event[SceneEvent]):
            false
        else:
            (super:)OnReceive(SceneEvent)

    CreateWidget<override>(View:widget_view):widget =
        Initial := if (Current := LastMessage?) then Current else ScheduleTextToMessage("")
        Label := text_block{DefaultText := Initial, DefaultTextSize := TextSize}
        spawn{FollowText(View, Label)}
        MakeScreenCanvas(Label, PositionXRatio, PositionYRatio)

    # Until closed, receive schedule_text_changed_event and change the text
    FollowText<private>(View:widget_view, Label:text_block)<suspends>:void =
        Updater := schedule_label_updater{Label := Label}
        Subscription := View.ReceivedEvent.Subscribe(Updater.Handle)
        View.HiddenEvent.Await()
        Subscription.Cancel()

    Refresh<private>(Snapshot:schedule_snapshot):void =
        Remaining := ToWholeSeconds(Snapshot.SecondsToStart)
        ShouldShow := if (Snapshot.State = schedule_state.Before and Remaining > 0 and Snapshot.SecondsToStart <= ShowWithinSeconds) then true else false
        if (not ShouldShow?):
            if (IsShown[]):
                Switch(false)
            return
        if (Remaining <> LastRemainingSeconds):
            set LastRemainingSeconds = Remaining
            Message := ScheduleTextToMessage(FormatRemaining(Remaining, Format, Prefix))
            set LastMessage = option{Message}
            if (IsShown[]):
                SendToWidgets(schedule_text_changed_event{Sender := Self, Text := Message, RemainingWholeSeconds := Remaining})
        if (not IsShown[]):
            Switch(true)

    Switch<private>(Show:logic):void =
        if (Show?):
            Activate()
        else:
            Deactivate()

# Receives schedule_text_changed_event and changes one player's text
schedule_label_updater<internal> := class<internal>:
    Label<internal>:text_block

    Handle<internal>(Received:scene_event):void =
        if (Changed := schedule_text_changed_event[Received]):
            Label.SetText(Changed.Text)
