using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SceneGraphSystem }
using { ScheduleSystem }
using { ScheduleSystem.TooltipKit }

# Which part of the remaining time to show
schedule_time_field<public> := enum:
    # Number of whole days (remaining seconds / 86400, rounded down)
    Days
    # Hours excluding the days (0-23)
    Hours
    # Minutes (0-59)
    Minutes
    # Seconds (0-59)
    Seconds
    # Unsplit total seconds
    TotalSeconds
    # Unsplit total minutes (rounded down)
    TotalMinutes

# Extract the Field value from the remaining seconds RemainingWholeSeconds (rounded-up integer)
GetTimeField<public>(RemainingWholeSeconds:int, Field:schedule_time_field)<transacts>:int =
    Split := SplitSeconds(RemainingWholeSeconds)
    case (Field):
        schedule_time_field.Days => Split.Days
        schedule_time_field.Hours => Split.Hours
        schedule_time_field.Minutes => Split.Minutes
        schedule_time_field.Seconds => Split.Seconds
        schedule_time_field.TotalSeconds => Max(RemainingWholeSeconds, 0)
        schedule_time_field.TotalMinutes => Quotient[Max(RemainingWholeSeconds, 0), SecondsPerMinute] or 0

# Role: marker for the mesh of one digit. schedule_digit_display_component toggles Visible on this entity's mesh (mesh_component)
# Placement: attach in the editor to an entity with a digit-shaped mesh (arrange the 10 digits 0-9 directly under the schedule_digit_display_component entity)
# Parent: the schedule_digit_display_component entity
schedule_digit_glyph_component<public> := class<final_super>(component):

    # The digit (0-9) this mesh represents. Any number of meshes may share the same value. Default 0
    @editable_number(int):
        ToolTip := ScheduleGlyphValueToolTip
        Categories := array{ScheduleDisplayCategory}
        MinValue := option{0}
        MaxValue := option{9}
    Value<public>:int = 0

    # Show / hide this entity's mesh. Never writes the same value twice in a row (it is a replicated property, so write only on change)
    var<private> LastVisible:?logic = false

    SetVisible<internal>(Visible:logic):void =
        if (Previous := LastVisible?, Previous = Visible):
            return
        set LastVisible = option{Visible}
        if (Mesh := Entity.GetComponent[mesh_component]):
            set Mesh.Visible = Visible

# Role: shows one digit of the schedule's remaining time by showing / hiding the child digit meshes (schedule_digit_glyph_component). Writes to the meshes only when the digit value changes (the ones of seconds every second, the tens every 10 seconds, minutes every minute, ...)
# Placement: attach to an entity in the editor, as a descendant of the schedule_component entity. One entity per digit position ("tens of minutes", "ones of minutes", ...)
# Children: entities with digit meshes 0-9 carrying schedule_digit_glyph_component (direct children; order does not matter. A missing digit shows nothing)
# Notifies: DigitChangedEvent (when the digit value changes; -1 = show nothing). On islands that show digits through material parameters, subscribe to this and write to your own MI (asset class) (materials are single precision, so pass only small numbers such as the digit value, never epoch seconds)
# Requirements / notes: the digit value is computed once per second (writes to the meshes only on change)
schedule_digit_display_component<public> := class<final_super>(component):

    # Which digit position to show (1 = ones, 2 = tens, 3 = hundreds; 1-9). Default 1
    @editable_number(int):
        ToolTip := ScheduleDigitToolTip
        Categories := array{ScheduleDisplayCategory}
        MinValue := option{1}
        MaxValue := option{9}
    Digit<public>:int = 1

    # Which part of the remaining time the digit belongs to (schedule_time_field). Default Seconds
    @editable:
        ToolTip := ScheduleDigitFieldToolTip
        Categories := array{ScheduleDisplayCategory}
    Field<public>:schedule_time_field = schedule_time_field.Seconds

    # Which remaining value to use (UntilStart / UntilEnd). Default UntilEnd
    @editable:
        ToolTip := ScheduleRemainingKindToolTip
        Categories := array{ScheduleDisplayCategory}
    RemainingKind<public>:schedule_remaining_kind = schedule_remaining_kind.UntilEnd

    # When on, no digit is shown when the higher positions are 0 (all digit meshes are hidden). Default off
    @editable:
        ToolTip := ScheduleBlankLeadingZeroToolTip
        Categories := array{ScheduleDisplayCategory}
    BlankLeadingZero<public>:logic = false

    Follower<private>:schedule_follower = schedule_follower{}
    # The last digit value shown (-1 = showing nothing, -2 = not shown even once yet)
    var<private> LastDigit:int = -2

    DigitChangedEventInternal<private><final>:event(int) = event(int){}

    # Fires when the digit value (0-9; -1 when showing nothing) changes (Await / Subscribe; cannot be Signaled from outside)
    DigitChangedEvent<public><final>:listenable(int) = MakeProxyListenable(DigitChangedEventInternal)

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Attached := Follower.Attach(Entity, Refresh, option{Refresh})
        if (not Attached?):
            Print("[schedule_digit_display_component] schedule_component not found on this entity or any ancestor")

    OnEndSimulation<override>():void =
        Follower.Detach()
        (super:)OnEndSimulation()

    # The digit value currently shown (0-9; -1 when showing nothing)
    GetDigitValue<public>()<transacts>:int =
        Max(LastDigit, -1)

    Refresh<private>(Snapshot:schedule_snapshot):void =
        Remaining := ToWholeSeconds(Snapshot.GetRemainingSeconds(RemainingKind))
        Value := GetTimeField(Remaining, Field)
        NewDigit := if (BlankLeadingZero? and IsLeadingZero[Value, Digit]) then -1 else GetDigit(Value, Digit)
        if (NewDigit = LastDigit):
            return
        set LastDigit = NewDigit
        for (Glyph : Entity.GetChildComponents(schedule_digit_glyph_component)):
            Glyph.SetVisible(if (Glyph.Value = NewDigit) then true else false)
        DigitChangedEventInternal.Signal(NewDigit)
