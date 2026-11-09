using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/UI }
using { /Fortnite.com/UI }
using { ActivationSystem }
using { WidgetSystem }
using { WidgetSystem.CardKit }
using { WidgetSystem.PointerKit }
using { WidgetSystem.TooltipKit }

# Notification that a card was chosen in the card menu
# Direction: from the card_menu_component's entity to the root (SendUp)
# Sender: card_menu_component (Menu). Receivers: ancestor components (conditions, game sequence, your components). Not consumed
widget_card_chosen_event<public> := class(scene_event):
    # The menu that sent it
    Menu<public>:card_menu_component
    # The person who chose
    Agent<public>:agent
    # The chosen card's entity (the card_info_component's entity)
    Chosen<public>:entity

# Role: a card menu that can be placed without writing code. Turns the card_info_components of child entities into cards sorted by Order, and sends an activation signal to the pressed card's entity
#   When pressed, sends widget_card_chosen_event upward, delivers ChosenEvent, and sends an activation signal (SendActivatedBy) to that card's entity. With CloseOnChoice, then closes that person's menu
#   The card under the mouse or with gamepad focus is marked by its border color (selected look). A card pressed with the Virtual Pointer sinks in (PointerKit; press-in takes priority)
#   To add or remove cards, just add or remove child entities (this menu's settings do not change). Children are looked up again each time it is shown
# Placement: in the editor, attach to an entity and give each child entity a card_info_component (and the parts to run when chosen)
# From outside: OpenFor(Agent) (same as ShowFor), HideFor(Agent) closes. Subscribe to ChosenEvent. The look is Style (replace it in code)
# MCP: the button ID when pressing from MCPSystem's WidgetKit is the CardId of the card entity's card_info_component (Title if empty, the index if that is also empty). The close button is "__close"
card_menu_component<public> := class<final_super>(player_widget_component):

    Mode<override>:player_widget_mode = player_widget_mode.Menu
    ZOrder<override>:int = 1000

    # Heading shown at the top. Not shown if empty
    @editable:
        ToolTip := CardMenuTitleToolTip
        Categories := array{CardMenuCategory}
    Title<public>:string = ""
    # Number of cards per row. Default 4
    @editable_number(int):
        ToolTip := CardMenuColumnsToolTip
        Categories := array{CardMenuCategory}
        MinValue := option{1}
        MaxValue := option{12}
    Columns<public>:int = 4
    # When on, closes that person's menu after choosing. Default on
    @editable:
        ToolTip := ChoiceMenuCloseOnChoiceToolTip
        Categories := array{CardMenuCategory}
    CloseOnChoice<public>:logic = true
    # When on, adds a button at the bottom that closes without choosing. Default on
    @editable:
        ToolTip := ChoiceMenuShowCloseToolTip
        Categories := array{CardMenuCategory}
    ShowCloseButton<public>:logic = true
    # Text of the close button
    @editable:
        ToolTip := ChoiceMenuCloseTextToolTip
        Categories := array{CardMenuCategory}
    CloseText<public>:string = "Close"
    # Menu position (horizontal screen ratio 0.0-1.0). Default 0.5 (center)
    @editable_number(float):
        ToolTip := WidgetPositionXToolTip
        Categories := array{CardMenuCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionXRatio<public>:float = 0.5
    # Menu position (vertical screen ratio 0.0-1.0). Default 0.5 (center)
    @editable_number(float):
        ToolTip := WidgetPositionYToolTip
        Categories := array{CardMenuCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionYRatio<public>:float = 0.5
    # Horizontal camera field of view (degrees) used when pressing a card in with the Virtual Pointer (converts the pressed position to a screen ratio). Default 90
    @editable_number(float):
        ToolTip := CardMenuPointerFovToolTip
        Categories := array{CardMenuCategory}
        MinValue := option{10.0}
        MaxValue := option{170.0}
    PointerFieldOfViewDegrees<public>:float = 90.0

    # Card look (replace in code. Takes effect from the next time it is shown)
    var Style<public>:widget_card_style = widget_card_style{}

    ChosenEventInternal<private><final>:event(tuple(agent, entity)) = event(tuple(agent, entity)){}

    # Delivered as (the person, the card's entity) each time someone chooses a card (Await / Subscribe; cannot be Signaled from outside)
    ChosenEvent<public><final>:listenable(tuple(agent, entity)) = MakeProxyListenable(ChosenEventInternal)

    # Open the menu for Agent (same as ShowFor)
    OpenFor<public>(Agent:agent):void =
        ShowFor(Agent)

    # The cards of the current child entities (ascending Order)
    GetCardInfos<public>()<transacts>:[]card_info_component =
        Found := for (Child : Entity.GetEntities(), Info := Child.GetComponent[card_info_component]):
            Info
        SortCards(Found)

    CreateWidget<override>(View:widget_view):widget =
        Infos := GetCardInfos()
        Cards := for (Index -> Info : Infos):
            Info.GetCard(Info.GetCardId(?Fallback := "{Index}"))
        Views := for (Card : Cards):
            MakeCardView(Card, Style)
        Buttons := for (CardView : Views):
            CardView.Button
        var Items:[]widget = array{}
        if (Title <> ""):
            set Items += array{text_block{DefaultText := StringToMessage(Title)}}
        set Items += array{MakeCardGrid(Buttons, Columns, 16.0)}
        CloseButton := button_quiet{DefaultText := StringToMessage(CloseText)}
        if (ShowCloseButton?):
            set Items += array{CloseButton}
        if (First := Buttons[0]):
            View.SetDefaultFocus(First)
        else if (ShowCloseButton?):
            View.SetDefaultFocus(CloseButton)
        for (CardView : Views):
            spawn{CardView.TrackHighlight(View)}
        Rects := for (Index -> Card : Cards):
            CardGridRect(Index, Cards.Length, Columns, 16.0, Style, PositionXRatio, PositionYRatio)
        spawn{RunCardPointerPress(View, Views, Rects, PointerFieldOfViewDegrees)}
        spawn{RunChoices(View, Buttons, Cards, Infos, CloseButton)}
        MakeScreenCanvas(MakeStack(Items, orientation.Vertical, 8.0), PositionXRatio, PositionYRatio)

    # Notify each time a card is pressed. The close button closes. Ends when closed
    RunChoices<private>(View:widget_view, Buttons:[]button, Cards:[]widget_card, Infos:[]card_info_component, CloseButton:button_quiet)<suspends>:void =
        loop:
            # The index for a card, -1 for the close button, false if closed first
            Picked:?int = race:
                View.AwaitButtonChoice(Buttons, ?ButtonIds := for (Card : Cards) { Card.Id }, ?Labels := for (Card : Cards) { Card.Title })
                AwaitClose(View, CloseButton)
            if (Index := Picked?):
                if (Index < 0):
                    View.Close()
                    return
                # When closing, close first and then notify (so that if the receiver opens another menu for the same person, we do not close that one)
                if (CloseOnChoice?):
                    View.Close()
                    if (Info := Infos[Index]):
                        Choose(View.Player, Info.Entity)
                    return
                if (Info := Infos[Index]):
                    Choose(View.Player, Info.Entity)
            else:
                return

    # -1 when the close button is pressed, false if closed first. Waits forever if the close button is not shown
    AwaitClose<private>(View:widget_view, CloseButton:button_quiet)<suspends>:?int =
        if (not ShowCloseButton?):
            Sleep(Inf)
        # The ID must not collide with a card ID (a card named close, etc.)
        Clicked := View.AwaitClick(CloseButton.OnClick(), ?ButtonId := "__close", ?Label := CloseText)
        if (Clicked?) then option{-1} else false

    Choose<private>(Agent:agent, Chosen:entity):void =
        Entity.SendUp(widget_card_chosen_event{Menu := Self, Agent := Agent, Chosen := Chosen})
        ChosenEventInternal.Signal((Agent, Chosen))
        Chosen.SendActivatedBy(Agent)
