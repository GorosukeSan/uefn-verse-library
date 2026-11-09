using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/UI }
using { /Fortnite.com/UI }
using { SceneGraphSystem }
using { WidgetSystem }
using { WidgetSystem.TooltipKit }

# Request to show a notification
# Direction: from your component to the notification_hud_component's entity (SendDown, or SendDown from an ancestor)
# Sender: your component. Receiver: notification_hud_component. Not consumed
hud_notification_request_event<public> := class(scene_event):
    # Who to show it to. false means everyone
    Agent<public>:?agent = false
    # Text to show
    Text<public>:message

# Role: HUD that shows notifications that disappear after a few seconds, stacked vertically at a fixed screen position (does not take input. Stacked in front). Showing several in a row to the same person stacks them downward; beyond MaxLines the oldest are removed
# Placement: in the editor, attach to an entity. By default shown to everyone from the start (ActiveOnBegin)
# Notifications received: shows via hud_notification_request_event (to show from other parts without writing code)
# From outside: Notify / NotifyAll
notification_hud_component<public> := class<final_super>(player_widget_component):

    ActiveOnBegin<override>:logic = true
    ZOrder<override>:int = 10000

    # How long one notification stays (seconds). Default 3
    @editable_number(float):
        ToolTip := NotificationSecondsToolTip
        Categories := array{NotificationHudCategory}
        MinValue := option{0.5}
        MaxValue := option{60.0}
    DisplaySeconds<public>:float = 3.0
    # Maximum number of notifications shown at once. Default 4
    @editable_number(int):
        ToolTip := NotificationMaxLinesToolTip
        Categories := array{NotificationHudCategory}
        MinValue := option{1}
        MaxValue := option{20}
    MaxLines<public>:int = 4
    # Position (horizontal screen ratio 0.0-1.0). Default 0.5
    @editable_number(float):
        ToolTip := WidgetPositionXToolTip
        Categories := array{NotificationHudCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionXRatio<public>:float = 0.5
    # Position (vertical screen ratio 0.0-1.0). Default 0.3
    @editable_number(float):
        ToolTip := WidgetPositionYToolTip
        Categories := array{NotificationHudCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionYRatio<public>:float = 0.3

    var<private> Stacks:[agent]stack_box = map{}
    var<private> Lines:[agent][]text_block = map{}

    # Show a notification to Agent. Does nothing if not shown to that person (Audience is Chosen without ShowFor, etc.)
    Notify<public>(Agent:agent, Text:message):void =
        if (Stack := Stacks[Agent]):
            Line := text_block{DefaultText := Text}
            Stack.AddWidget(stack_box_slot{Widget := Line, HorizontalAlignment := horizontal_alignment.Center})
            Current := if (Found := Lines[Agent]) then Found else array{}
            var Next:[]text_block = Current + array{Line}
            loop:
                if (Next.Length <= MaxLines):
                    break
                if (Oldest := Next[0], Rest := Next.Slice[1]):
                    Stack.RemoveWidget(Oldest)
                    set Next = Rest
                else:
                    break
            if (set Lines[Agent] = Next) {}
            spawn{ExpireLine(Agent, Line)}

    # Show a notification to everyone it is shown to
    NotifyAll<public>(Text:message):void =
        for (Agent -> Stack : Stacks):
            Notify(Agent, Text)

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Request := hud_notification_request_event[SceneEvent]):
            if (Agent := Request.Agent?):
                Notify(Agent, Request.Text)
            else:
                NotifyAll(Request.Text)
        (super:)OnReceive(SceneEvent)

    CreateWidget<override>(View:widget_view):widget =
        Stack := stack_box{Orientation := orientation.Vertical}
        if (set Stacks[View.Player] = Stack) {}
        if (set Lines[View.Player] = array{}) {}
        spawn{ForgetWhenHidden(View)}
        MakeScreenCanvas(Stack, PositionXRatio, PositionYRatio)

    ExpireLine<private>(Agent:agent, Line:text_block)<suspends>:void =
        Sleep(DisplaySeconds)
        if (Stack := Stacks[Agent], Current := Lines[Agent]):
            Stack.RemoveWidget(Line)
            Kept := for (Other : Current, Other <> Line):
                Other
            if (set Lines[Agent] = Kept) {}

    ForgetWhenHidden<private>(View:widget_view)<suspends>:void =
        View.HiddenEvent.Await()
        set Stacks = Stacks.RemoveKey(View.Player)
        set Lines = Lines.RemoveKey(View.Player)
