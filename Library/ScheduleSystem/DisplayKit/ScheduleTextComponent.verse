using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ScheduleSystem }
using { ScheduleSystem.TooltipKit }

# Text format
schedule_text_format<public> := enum:
    # 01:02:03 (hours may exceed 24)
    HoursMinutesSeconds
    # 62:03 (minutes may exceed 60)
    MinutesSeconds
    # 1d 01:02:03
    DaysHoursMinutesSeconds
    # Number of whole days only (1)
    Days
    # Total seconds (3723)
    TotalSeconds

# Format the remaining seconds RemainingWholeSeconds (rounded-up integer) as a Format string (with Prefix in front)
FormatRemaining<public>(RemainingWholeSeconds:int, Format:schedule_text_format, Prefix:string)<transacts>:string =
    Body := case (Format):
        schedule_text_format.HoursMinutesSeconds => FormatHoursMinutesSeconds(RemainingWholeSeconds)
        schedule_text_format.MinutesSeconds => FormatMinutesSeconds(RemainingWholeSeconds)
        schedule_text_format.DaysHoursMinutesSeconds => FormatDaysHoursMinutesSeconds(RemainingWholeSeconds)
        schedule_text_format.Days => FormatDays(RemainingWholeSeconds)
        schedule_text_format.TotalSeconds => "{Max(RemainingWholeSeconds, 0)}"
    "{Prefix}{Body}"

# Turn a string into a message that can be passed to a widget (cannot be called in a failure context or inside <transacts>)
ScheduleTextToMessage<public><localizes>(Text:string):message = "{Text}"

# Notification that the remaining-time text changed
# Direction: down from the schedule_text_component entity (SendDown). schedule_countdown_hud_component Forwards it to its own widgets
# Sender: schedule_text_component / schedule_countdown_hud_component. Receivers: widgets, signs and the like that show the text. Not consumed
schedule_text_changed_event<public> := class(scene_event):
    # The component that sent it
    Sender<public>:component
    # The text to show (with Prefix)
    Text<public>:message
    # The remaining seconds the text was made from (rounded-up integer)
    RemainingWholeSeconds<public>:int

# Role: turns the schedule's remaining time into text (message) such as "MM:SS" and notifies only when it changes (for signs, 3D text, your widgets)
# Placement: attach to an entity in the editor, on the schedule_component entity or a descendant
# Notifies: when the text changes, sends schedule_text_changed_event down and fires TextChangedEvent (every second while 1 s or more remains; not sent when the text is the same)
# From outside: GetText (the current text), GetRemainingWholeSeconds (the remaining seconds the text was made from). With OnlyWhileShown on, Show / Hide start and stop the updates (saves the work for displays nobody is looking at)
# Requirements / notes: messages cannot be concatenated, so the leading text is held as Prefix (string)
schedule_text_component<public> := class<final_super>(component):

    # Text format (schedule_text_format). Default MinutesSeconds (62:03)
    @editable:
        ToolTip := ScheduleTextFormatToolTip
        Categories := array{ScheduleDisplayCategory}
    Format<public>:schedule_text_format = schedule_text_format.MinutesSeconds

    # Which remaining value to use (UntilStart / UntilEnd). Default UntilEnd
    @editable:
        ToolTip := ScheduleRemainingKindToolTip
        Categories := array{ScheduleDisplayCategory}
    RemainingKind<public>:schedule_remaining_kind = schedule_remaining_kind.UntilEnd

    # Fixed string put before the text. Nothing is added when empty (default)
    @editable:
        ToolTip := ScheduleTextPrefixToolTip
        Categories := array{ScheduleDisplayCategory}
    Prefix<public>:string = ""

    # When on, updated every second only while Show has been called. When off, always updated (default)
    @editable:
        ToolTip := ScheduleTextOnlyWhileShownToolTip
        Categories := array{ScheduleDisplayCategory}
    OnlyWhileShown<public>:logic = false

    Follower<private>:schedule_follower = schedule_follower{}
    var<private> Shown:logic = true
    var<private> LastText:string = ""
    var<private> LastMessage:?message = false
    var<private> LastRemainingSeconds:int = -1

    TextChangedEventInternal<private><final>:event(message) = event(message){}

    # Fires with the new text when the text changes (Await / Subscribe; cannot be Signaled from outside)
    TextChangedEvent<public><final>:listenable(message) = MakeProxyListenable(TextChangedEventInternal)

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set Shown = if (OnlyWhileShown?) then false else true
        Attached := Follower.Attach(Entity, Refresh, option{Refresh})
        if (not Attached?):
            Print("[schedule_text_component] schedule_component not found on this entity or any ancestor")

    OnEndSimulation<override>():void =
        Follower.Detach()
        (super:)OnEndSimulation()

    # The current text (an empty message until computed for the first time)
    GetText<public>():message =
        if (Current := LastMessage?):
            Current
        else:
            ScheduleTextToMessage("")

    # The remaining seconds the current text was made from (rounded-up integer; -1 until then)
    GetRemainingWholeSeconds<public>()<transacts>:int =
        LastRemainingSeconds

    # Start updating (when OnlyWhileShown is on). Computes and notifies the current text immediately
    Show<public>():void =
        if (Shown?):
            return
        set Shown = true
        if (Schedule := Follower.FindSchedule[]):
            Refresh(Schedule.GetCurrentSnapshot())

    # Stop updating (when OnlyWhileShown is on)
    Hide<public>():void =
        set Shown = false

    # Succeeds while updating
    IsShown<public>()<decides><transacts>:void =
        Shown?

    Refresh<private>(Snapshot:schedule_snapshot):void =
        if (not Shown?):
            return
        Remaining := ToWholeSeconds(Snapshot.GetRemainingSeconds(RemainingKind))
        if (Remaining = LastRemainingSeconds):
            return
        set LastRemainingSeconds = Remaining
        Text := FormatRemaining(Remaining, Format, Prefix)
        if (Text = LastText and LastMessage?):
            return
        set LastText = Text
        Message := ScheduleTextToMessage(Text)
        set LastMessage = option{Message}
        Entity.SendDown(schedule_text_changed_event{Sender := Self, Text := Message, RemainingWholeSeconds := Remaining})
        TextChangedEventInternal.Signal(Message)
