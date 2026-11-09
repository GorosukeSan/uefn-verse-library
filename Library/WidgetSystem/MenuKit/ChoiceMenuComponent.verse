using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/UI }
using { /Fortnite.com/UI }
using { ActivationSystem }
using { WidgetSystem }
using { WidgetSystem.TooltipKit }

# Notification that an option was chosen in the choice menu
# Direction: from the choice_menu_component's entity to the root (SendUp)
# Sender: choice_menu_component (Menu). Receivers: ancestor components (conditions, game sequence, your components). Not consumed
widget_choice_event<public> := class(scene_event):
    # The menu that sent it
    Menu<public>:choice_menu_component
    # The person who chose
    Agent<public>:agent
    # Index of the chosen option (the order of Options, from 0)
    Index<public>:int

# Role: a choice menu that can be placed without writing code. Lines up the Options as buttons under Title and notifies which option was pressed.
#   When pressed, sends widget_choice_event upward, delivers ChoiceEvent, and sends an activation signal (activated_event) to the entity Targets[index]. With CloseOnChoice, then closes that person's menu
#   With ShowCloseButton, adds a "close" button (CloseText) at the end (pressing it closes without choosing)
# Placement: in the editor, attach to an entity. Who sees it and when is decided by the player_widget_component settings (Audience, ActiveOnBegin, activation signals) and a widget_show_*_component on the same entity
# Parent: where the activation signal arrives (to open with an interact, put this entity in the Targets of interact_trigger_component)
# From outside: OpenFor(Agent) (same as ShowFor), HideFor(Agent) closes. Subscribe to ChoiceEvent
# Requirements: Mode defaults to Menu (takes input; no movement while shown). On a gamepad, focus moves to the top button
choice_menu_component<public> := class<final_super>(player_widget_component):

    Mode<override>:player_widget_mode = player_widget_mode.Menu
    ZOrder<override>:int = 1000

    # Heading shown above the menu. Not shown if empty
    @editable:
        ToolTip := ChoiceMenuTitleToolTip
        Categories := array{ChoiceMenuCategory}
    Title<public>:string = ""
    # Options to line up (top to bottom, index 0, 1, 2 ...)
    @editable:
        ToolTip := ChoiceMenuOptionsToolTip
        Categories := array{ChoiceMenuCategory}
    Options<public>:[]string = array{"OK"}
    # Entity that receives an activation signal per option (same order as Options. Missing or empty entries send nothing)
    @editable:
        ToolTip := ChoiceMenuTargetsToolTip
        Categories := array{ChoiceMenuCategory}
    Targets<public>:[]entity = array{}
    # When on, closes that person's menu after choosing. Default on
    @editable:
        ToolTip := ChoiceMenuCloseOnChoiceToolTip
        Categories := array{ChoiceMenuCategory}
    CloseOnChoice<public>:logic = true
    # When on, adds a button at the end that closes without choosing. Default on
    @editable:
        ToolTip := ChoiceMenuShowCloseToolTip
        Categories := array{ChoiceMenuCategory}
    ShowCloseButton<public>:logic = true
    # Text of the close button
    @editable:
        ToolTip := ChoiceMenuCloseTextToolTip
        Categories := array{ChoiceMenuCategory}
    CloseText<public>:string = "Close"
    # Menu position (horizontal screen ratio 0.0-1.0). Default 0.5 (center)
    @editable_number(float):
        ToolTip := WidgetPositionXToolTip
        Categories := array{ChoiceMenuCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionXRatio<public>:float = 0.5
    # Menu position (vertical screen ratio 0.0-1.0). Default 0.5 (center)
    @editable_number(float):
        ToolTip := WidgetPositionYToolTip
        Categories := array{ChoiceMenuCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionYRatio<public>:float = 0.5

    ChoiceEventInternal<private><final>:event(tuple(agent, int)) = event(tuple(agent, int)){}

    # Delivered as (the person, the option index) each time someone chooses an option (Await / Subscribe; cannot be Signaled from outside)
    ChoiceEvent<public><final>:listenable(tuple(agent, int)) = MakeProxyListenable(ChoiceEventInternal)

    # Open the menu for Agent (same as ShowFor)
    OpenFor<public>(Agent:agent):void =
        ShowFor(Agent)

    CreateWidget<override>(View:widget_view):widget =
        var Items:[]widget = array{}
        if (Title <> ""):
            set Items += array{text_block{DefaultText := StringToMessage(Title)}}
        Buttons := for (Option : Options):
            button_regular{DefaultText := StringToMessage(Option)}
        for (Button : Buttons):
            set Items += array{Button}
        CloseButton := button_quiet{DefaultText := StringToMessage(CloseText)}
        if (ShowCloseButton?):
            set Items += array{CloseButton}
        if (First := Buttons[0]):
            View.SetDefaultFocus(First)
        else if (ShowCloseButton?):
            View.SetDefaultFocus(CloseButton)
        Choices := if (ShowCloseButton?) then Buttons + array{CloseButton} else Buttons
        spawn{RunChoices(View, Choices, Buttons.Length)}
        MakeScreenCanvas(MakeStack(Items, orientation.Vertical, 8.0), PositionXRatio, PositionYRatio)

    # Notify each time a button is pressed. Index CloseCount (the close button) closes. Ends when closed
    RunChoices<private>(View:widget_view, Buttons:[]text_button_base, OptionCount:int)<suspends>:void =
        loop:
            MaybeIndex := View.AwaitChoice(Buttons)
            if (Index := MaybeIndex?):
                if (Index >= OptionCount):
                    View.Close()
                    return
                Choose(View.Player, Index)
                if (CloseOnChoice?):
                    View.Close()
                    return
            else:
                return

    Choose<private>(Agent:agent, Index:int):void =
        Entity.SendUp(widget_choice_event{Menu := Self, Agent := Agent, Index := Index})
        ChoiceEventInternal.Signal((Agent, Index))
        if (Target := Targets[Index]):
            Target.SendActivatedBy(Agent)
