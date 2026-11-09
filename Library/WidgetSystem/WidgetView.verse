using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/UI }
using { /Fortnite.com/UI }

# Role: the view of a widget shown on one person's screen. player_widget_component creates one each time it shows and passes it to CreateWidget (your code does not create it)
#   Has the closed notification (HiddenEvent), notifications forwarded by the creating component (ReceivedEvent), button waits (AwaitClick / AwaitChoice / AwaitButtonChoice) and Close / Focus
#   Also the list of buttons being waited on (GetWaitingButtons) and an entry point to press from code (PressButton: reaches AwaitClick / AwaitChoice exactly like a real click. Used by MCPSystem's WidgetKit)
# Requirements: after closing (after IsShown fails), waits return false immediately. Button waits always go through this view (no wait is left behind after closing)
widget_view<public> := class<internal>:
    # The person this display is shown to
    Player<public>:player
    # The component that showed this display
    Owner<public>:player_widget_component

    var<private> Shown:logic = true
    var<private> DefaultFocus:?widget = false
    # Buttons currently waited on by AwaitClick / AwaitChoice (the destination of PressButton from code)
    var<private> Waits:[]widget_wait = array{}

    HiddenEventInternal<private><final>:event() = event(){}
    PointerFedInternal<private><final>:event(tuple(float, float, logic)) = event(tuple(float, float, logic)){}

    # A pointer injected from code (screen ratio X, Y (top-left 0,0 to bottom-right 1,1), whether pressed). Delivered by InjectPointer.
    #   PointerKit's RunCardPointerPress treats it the same as a Virtual Pointer press (MCPSystem's widget.pointer lets you try pressing without a mouse)
    PointerFed<public><final>:listenable(tuple(float, float, logic)) = MakeProxyListenable(PointerFedInternal)

    # Inject a pointer (X, Y are screen ratios; Down true = pressed, false = released). Does nothing if not on screen
    InjectPointer<public>(X:float, Y:float, Down:logic):void =
        if (Shown?):
            PointerFedInternal.Signal((X, Y, Down))
    ReceivedEventInternal<private><final>:event(scene_event) = event(scene_event){}

    # Delivered once when it disappears from the screen (Close, HideFor, Deactivate, leaving, menu swap, deactivation) (Await / Subscribe; cannot be Signaled from outside)
    HiddenEvent<public><final>:listenable(tuple()) = MakeProxyListenable(HiddenEventInternal)

    # Delivers notifications the Owner passed with SendToWidgets / SendToWidgetFor, and the contents of player_events from the same person's other views
    ReceivedEvent<public><final>:listenable(scene_event) = MakeProxyListenable(ReceivedEventInternal)

    # Succeeds while still on screen
    IsShown<public>()<decides><transacts>:void =
        Shown?

    # Close this display on this person's screen (same as Owner.HideFor)
    Close<public>():void =
        Owner.HideFor(Player)

    # Move focus to Target (a menu button operated with a gamepad, etc. Pass the inner button, not the canvas). Does nothing if not on screen
    Focus<public>(Target:widget):void =
        if (Shown?, PlayerUI := GetPlayerUI[Player]):
            PlayerUI.SetFocus(Target)

    # Decide where focus goes right after showing (call inside CreateWidget. With Mode = Menu, Focus is called on the frame after showing)
    SetDefaultFocus<public>(Target:widget):void =
        set DefaultFocus = option{Target}

    # Wait until this person presses OnClick. true if pressed, false if closed first (false immediately if already closed)
    # Usage: Clicked := View.AwaitClick(Button.OnClick())
    #   While waiting, this button appears in GetWaitingButtons and can be pressed from code with PressButton (MCPSystem's WidgetKit, etc. Returns true exactly like a real click)
    #   ButtonId is the ID used when pressing from code (empty means "0"); Label is the text shown in the list (the button's text; may be empty)
    AwaitClick<public>(OnClick:listenable(widget_message), ?ButtonId:string = "", ?Label:string = "")<suspends>:logic =
        if (not Shown?):
            return false
        Pressed := event(int){}
        Wait := widget_wait{Ids := array{if (ButtonId = "") then "0" else ButtonId}, Labels := array{Label}, Buttons := array{}, Target := Pressed}
        AddWait(Wait)
        defer:
            RemoveWait(Wait)
        race:
            block:
                loop:
                    Message := OnClick.Await()
                    if (Message.Player = Player):
                        break
                true
            block:
                Pressed.Await()
                true
            block:
                HiddenEventInternal.Await()
                false

    # Wait until this person presses one of Buttons and return the index of the pressed button (from 0). false if closed first
    #   While waiting, the buttons appear in GetWaitingButtons and can be pressed from code with PressButton (returns the same index as a real click)
    #   ButtonIds are the IDs used when pressing from code (same order as Buttons. Missing entries become the index as text: "0", "1", ...)
    AwaitChoice<public>(Buttons:[]text_button_base, ?ButtonIds:[]string = array{})<suspends>:?int =
        Clicks := for (Button : Buttons) { array{Button.OnClick()} }
        AwaitChoiceOf(Clicks, Buttons, Buttons, ButtonIds, array{})

    # Wait until this person presses one of the buttons with free content (cards, etc.) and return the index of the pressed button (from 0). false if closed first
    #   Like AwaitChoice, they appear in GetWaitingButtons and can be pressed with PressButton. Labels are the text shown in the list (a button has no text, so pass it. Missing entries are empty)
    AwaitButtonChoice<public>(Buttons:[]button, ?ButtonIds:[]string = array{}, ?Labels:[]string = array{})<suspends>:?int =
        Clicks := for (Button : Buttons) { array{Button.OnClick()} }
        AwaitChoiceOf(Clicks, Buttons, array{}, ButtonIds, Labels)

    # When one choice is made of several buttons (hover cells laid over a card, etc.), return the index of that choice (the index in Groups) when any of them is pressed. false if closed first
    #   GetWaitingButtons / PressButton see one entry per choice (whether it can be pressed is read from the first button of that choice)
    AwaitButtonGroupChoice<public>(Groups:[][]button, ?ButtonIds:[]string = array{}, ?Labels:[]string = array{})<suspends>:?int =
        Clicks := for (Group : Groups) { for (Button : Group) { Button.OnClick() } }
        Firsts := for (Group : Groups, First := Group[0]) { First }
        AwaitChoiceOf(Clicks, Firsts, array{}, ButtonIds, Labels)

    AwaitChoiceOf<private>(Clicks:[][]listenable(widget_message), Widgets:[]widget, TextButtons:[]text_button_base, ButtonIds:[]string, Labels:[]string)<suspends>:?int =
        if (not Shown?):
            return false
        Chosen := event(int){}
        Ids := for (Index -> Click : Clicks):
            if (Id := ButtonIds[Index], Id <> "") then Id else "{Index}"
        Wait := widget_wait{Ids := Ids, Labels := Labels, Buttons := TextButtons, Widgets := Widgets, Target := Chosen}
        AddWait(Wait)
        var Handlers:[]cancelable = array{}
        for (Index -> Group : Clicks, Click : Group):
            Handler := widget_choice_handler{Index := Index, Player := Player, Target := Chosen}
            set Handlers += array{Click.Subscribe(Handler.Handle)}
        defer:
            RemoveWait(Wait)
            for (Subscription : Handlers):
                Subscription.Cancel()
        race:
            block:
                Index := Chosen.Await()
                option{Index}
            block:
                HiddenEventInternal.Await()
                false

    # Buttons currently waited on by AwaitClick / AwaitChoice (overlapping waits are listed in the order they started). Empty if not waiting
    GetWaitingButtons<public>():[]widget_button_info =
        var Out:[]widget_button_info = array{}
        for (Wait : Waits):
            set Out += Wait.GetInfos()
        Out

    # Press a button from code (reaches the waiting AwaitClick / AwaitChoice exactly like a real click)
    #   Key is the button ID (AwaitClick's ButtonId / AwaitChoice's ButtonIds), the button's text, or the index as text (from "0"). Presses the first matching button
    #   Result: Pressed (pressed) / NotShown (already closed) / NotWaiting (no button is being waited on) / NoButton (no matching button) / Disabled (the button is disabled)
    PressButton<public>(Key:string):widget_press_result =
        if (not Shown?):
            return widget_press_result.NotShown
        if (Waits.Length = 0):
            return widget_press_result.NotWaiting
        var Result:widget_press_result = widget_press_result.NoButton
        var Done:logic = false
        for (Wait : Waits):
            if (not Done?):
                Found := Wait.FindButton(Key)
                if (Found >= 0):
                    set Done = true
                    Disabled := Wait.IsDisabledAt(Found)
                    if (Disabled?):
                        set Result = widget_press_result.Disabled
                    else:
                        Wait.Target.Signal(Found)
                        set Result = widget_press_result.Pressed
        Result

    AddWait<private>(Wait:widget_wait):void =
        set Waits += array{Wait}

    RemoveWait<private>(Wait:widget_wait):void =
        set Waits = for (Other : Waits, Other <> Wait) { Other }

    # Called from player_widget_view_component
    NotifyShown<internal>()<suspends>:void =
        if (Target := DefaultFocus?):
            Sleep(0.0)
            Focus(Target)

    NotifyHidden<internal>():void =
        if (Shown?):
            set Shown = false
            HiddenEventInternal.Signal()

    NotifyReceived<internal>(SceneEvent:scene_event):void =
        ReceivedEventInternal.Signal(SceneEvent)

# Remembers the index of each button inside AwaitChoice
widget_choice_handler<internal> := class<internal>:
    Index<internal>:int
    Player<internal>:player
    Target<internal>:event(int)

    Handle<internal>(Message:widget_message):void =
        if (Message.Player = Player):
            Target.Signal(Index)

# Result of PressButton
widget_press_result<public> := enum:
    # Pressed (reached the waiting AwaitClick / AwaitChoice)
    Pressed
    # Already gone from the screen
    NotShown
    # Shown, but no button is being waited on (outside AwaitClick / AwaitChoice)
    NotWaiting
    # No button matches Key
    NoButton
    # The button is disabled (SetEnabled(false))
    Disabled

# Info about one button being waited on (GetWaitingButtons)
widget_button_info<public> := struct:
    # ID used when pressing from code
    Id<public>:string = ""
    # Index within the wait (the index AwaitChoice returns. 0 for AwaitClick)
    Index<public>:int = 0
    # The button's text (empty if it cannot be read)
    Label<public>:string = ""
    # Whether it can be pressed (false if SetEnabled(false))
    Enabled<public>:logic = true

# One wait of AwaitClick / AwaitChoice (the destination when pressing from code)
widget_wait<internal> := class<unique><internal>:
    Ids<internal>:[]string
    # Text passed to AwaitClick / AwaitButtonChoice (AwaitChoice reads it from the text buttons)
    Labels<internal>:[]string
    # Text buttons (AwaitChoice. Their text is shown in the list)
    Buttons<internal>:[]text_button_base
    # Buttons checked for whether they can be pressed (AwaitChoice / AwaitButtonChoice. Empty for AwaitClick)
    Widgets<internal>:[]widget = array{}
    Target<internal>:event(int)

    GetLabel<internal>(Index:int):string =
        if (Button := Buttons[Index]) then Button.GetText() else if (Label := Labels[Index]) then Label else ""

    # true if the button at Index is disabled (unknown for AwaitClick buttons, so false)
    IsDisabledAt<internal>(Index:int):logic =
        if (Widget := Widgets[Index]):
            Enabled := Widget.IsEnabled()
            if (Enabled?) then false else true
        else:
            false

    GetInfos<internal>():[]widget_button_info =
        for (Index -> Id : Ids):
            Disabled := IsDisabledAt(Index)
            Enabled := if (Disabled?) then false else true
            widget_button_info{Id := Id, Index := Index, Label := GetLabel(Index), Enabled := Enabled}

    # Index of the button matching Key (checked in the order ID -> text -> index as text). -1 if none
    FindButton<internal>(Key:string):int =
        var Found:int = -1
        for (Index -> Id : Ids, Found < 0, Id = Key):
            set Found = Index
        if (Found < 0):
            for (Index -> Id : Ids):
                if (Found < 0):
                    Label := GetLabel(Index)
                    if (Label <> "", Label = Key):
                        set Found = Index
        if (Found < 0, Number := WidgetParseIndex[Key], Number >= 0, Number < Ids.Length):
            set Found = Number
        Found

# Turn an index string "0" to "999" into an int. Fails if it is not a number
WidgetParseIndex<internal>(Key:string)<decides><transacts>:int =
    Key.Length > 0
    Key.Length <= 3
    var N:int = 0
    var Bad:int = 0
    for (C : Key):
        var Digit:int = -1
        for (Index -> D : "0123456789", D = C):
            set Digit = Index
        if (Digit >= 0):
            set N = N * 10 + Digit
        else:
            set Bad += 1
    Bad = 0
    N
