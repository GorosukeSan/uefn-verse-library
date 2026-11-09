using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Colors }
using { /Verse.org/Input }
using { /Verse.org/Input/UI }
using { /Fortnite.com/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/UI }
using { ActivationSystem }
using { InputSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { WidgetSystem }

# Screen texts
WidgetSampleTitle<localizes>:message = "Screen sample (HUD. Input mode None: movement and camera still work)"
WidgetSamplePlayerMessage<localizes>(Agent:agent):message = "Player: {Agent}"
WidgetSampleElapsedMessage<localizes>(Seconds:int):message = "Elapsed: {Seconds} s (updated every second with SendToWidgets)"
WidgetSampleLastEventMessage<localizes>(Label:string):message = "Last notification received: {Label}"
WidgetSampleHint<localizes>:message = "C (RT) opens the menu (widget_sample_opener_component)"
MenuSampleTitle<localizes>:message = "Menu (input mode Menu = All)"
MenuSampleBody<localizes>:message = "While shown, movement and camera control stop and focus moves to this screen. Press the button to close (Esc also closes)"
MenuSampleClose<localizes>:message = "Close"

# HUD elapsed-time update. widget_sample_component SendToWidgets it every second
# Direction: from widget_sample_component to all of its own views (SendToWidgets -> widget_view.ReceivedEvent). Not consumed
widget_sample_tick_event<public> := class(scene_event):
    ElapsedSeconds<public>:int

# Notification that the menu was opened. Sent as a player_event under the opener's slot, and reaches widget_view.ReceivedEvent of the same player's HUD (the widget_sample_component view)
# Direction: from the widget_sample_opener view to the same player's slot (SendToPlayer). Not consumed
widget_sample_menu_opened_event<public> := class(scene_event):
    Agent<public>:agent

# Role: changes one player's HUD view according to the notifications received (widget_sample_component creates one per view and Subscribes it to ReceivedEvent)
widget_sample_hud_updater<public> := class:
    ElapsedText<public>:text_block
    LastEventText<public>:text_block

    # Receives Forwarded notifications (tick) and the contents of player_events from the same player's other views
    OnReceived<public>(SceneEvent:scene_event):void =
        if (Tick := widget_sample_tick_event[SceneEvent]):
            ElapsedText.SetText(WidgetSampleElapsedMessage(Tick.ElapsedSeconds))
        else if (widget_sample_menu_opened_event[SceneEvent]):
            LastEventText.SetText(WidgetSampleLastEventMessage("widget_sample_menu_opened_event (arrived as a player_event)"))
        else:
            LastEventText.SetText(WidgetSampleLastEventMessage("other scene_event"))

    OnHidden<public>(Unused:tuple()):void =
        Print("[widget_sample] HUD removed (HiddenEvent)", ?Duration := 3.0)

# Role: HUD sample (player_widget_component subclass; Mode = Hud). On the activate signal, shows everyone their name, the elapsed time and the last notification received, and passes the elapsed time to every view with SendToWidgets every second (no per-frame counting per view). Also shows notifications that arrive as player_events from the same player's other views
# Placement: attach to an entity in the editor, together with activate_on_begin_component on the same entity (the display starts on the activate signal). Place one player_manager_component in the scope (or the world)
# Try it: when the session starts, the name and elapsed time appear at the top left. With a widget_sample_opener_component placed, pressing C (RT) changes "Last notification received" and opens the menu of the menu_sample_component set in MenuEntity for that player only
# Notifies: SendToWidgets widget_sample_tick_event to its own views every second
widget_sample_component<public> := class<final_super>(player_widget_component):

    CreateWidget<override>(View:widget_view):widget =
        ElapsedText := text_block{DefaultText := WidgetSampleElapsedMessage(0), DefaultTextColor := NamedColors.White}
        LastEventText := text_block{DefaultText := WidgetSampleLastEventMessage("(none yet)"), DefaultTextColor := NamedColors.White}
        Updater := widget_sample_hud_updater{ElapsedText := ElapsedText, LastEventText := LastEventText}
        View.ReceivedEvent.Subscribe(Updater.OnReceived)
        View.HiddenEvent.Subscribe(Updater.OnHidden)
        Items:[]widget = array:
            text_block{DefaultText := WidgetSampleTitle, DefaultTextColor := NamedColors.White}
            text_block{DefaultText := WidgetSamplePlayerMessage(View.Player), DefaultTextColor := NamedColors.White}
            ElapsedText
            LastEventText
            text_block{DefaultText := WidgetSampleHint, DefaultTextColor := NamedColors.White}
        Lines := MakeStack(Items, orientation.Vertical, 4.0)
        Panel := overlay{}
        Panel.AddWidget(overlay_slot{Widget := color_block{DefaultColor := NamedColors.Black, DefaultOpacity := 0.7}, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill})
        Panel.AddWidget(overlay_slot{Widget := Lines, Padding := margin{Left := 16.0, Top := 12.0, Right := 16.0, Bottom := 12.0}})
        MakeScreenCanvas(Panel, 0.15, 0.2)

    OnSimulate<override>()<suspends>:void =
        StartSeconds := GetSimulationElapsedTime()
        loop:
            Sleep(1.0)
            if (IsShown[]):
                Elapsed := GetSimulationElapsedTime() - StartSeconds
                Seconds := if (Whole := Floor[Elapsed]) then Whole else 0
                SendToWidgets(widget_sample_tick_event{ElapsedSeconds := Seconds})

# Role: menu sample (player_widget_component subclass; Mode = Menu, Audience = Chosen). Shows the menu only to the player opened with OpenFor, and closes only the menu of the player who pressed the close button (button_loud; Back = Esc also presses it). Shows the difference from Hud (no movement while shown; focus moves)
# The button is awaited with View.AwaitClick (returns false and ends when closed, so no wait is left behind)
# Placement: attach to an entity in the editor (set it in MenuEntity of widget_sample_opener_component). Place one player_manager_component in the scope (or the world)
# Try it: no movement while open. Close with the button or Esc (Back, when MenuNavigationMapping is enabled). Closing prints to the output log
menu_sample_component<public> := class<final_super>(player_widget_component):

    # Defaults set to Menu and Chosen (they are @editable, so feel free to change and compare)
    Mode<override>:player_widget_mode = player_widget_mode.Menu
    Audience<override>:player_widget_audience = player_widget_audience.Chosen
    ZOrder<override>:int = 1000

    # Open the menu for Agent only
    OpenFor<public>(Agent:agent):void =
        ShowFor(Agent)

    CreateWidget<override>(View:widget_view):widget =
        CloseButton := button_loud{DefaultText := MenuSampleClose}
        set CloseButton.TriggeringInputAction = option{Back}
        View.SetDefaultFocus(CloseButton)
        spawn{CloseOnClick(View, CloseButton)}
        Items:[]widget = array:
            text_block{DefaultText := MenuSampleTitle, DefaultTextColor := NamedColors.White}
            text_block{DefaultText := MenuSampleBody, DefaultTextColor := NamedColors.White}
            CloseButton
        Lines := MakeStack(Items, orientation.Vertical, 8.0)
        Panel := overlay{}
        Panel.AddWidget(overlay_slot{Widget := color_block{DefaultColor := NamedColors.Black, DefaultOpacity := 0.85}, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill})
        Panel.AddWidget(overlay_slot{Widget := Lines, Padding := margin{Left := 32.0, Top := 24.0, Right := 32.0, Bottom := 24.0}})
        MakeScreenCanvas(Panel, 0.5, 0.5)

    CloseOnClick<private>(View:widget_view, CloseButton:button_loud)<suspends>:void =
        OnClick := CloseButton.OnClick()
        Clicked := View.AwaitClick(OnClick)
        if (Clicked?):
            Print("[menu_sample] Closing (View.Close)", ?Duration := 3.0)
            View.Close()

# Role: sample of an input that opens the menu (one player at a time with player_view_set). When OpenAction (default C / RT) is pressed, opens the player_widget_component of MenuEntity for the presser only (ShowFor) and sends widget_sample_menu_opened_event as a player_event under the same player's slot (reaches the same player's HUD)
# Placement: attach to an entity in the editor and set the entity carrying menu_sample_component in MenuEntity. Place one player_manager_component in the scope (or the world)
# Requirements / notes: OpenMapping is removed on stop, so do not choose a character-control Mapping
widget_sample_opener_component<public> := class<final_super>(component):

    # When on, accepts input from the start of the simulation. When off, waits for the activate signal
    @editable
    StartOnBegin<public>:logic = true

    # Input that opens the menu (choose one contained in OpenMapping)
    @editable
    OpenAction<public>:input_action(logic) = NextPage

    # Key mapping added to each player while running (removed on stop)
    @editable
    OpenMapping<public>:input_mapping = MenuNavigationMapping

    # The entity carrying menu_sample_component
    @editable
    MenuEntity<public>:?entity = false

    Views<private>:player_view_set = player_view_set{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (StartOnBegin?):
            Views.Activate(Entity, CreateView)

    OnReceive<override>(SceneEvent:scene_event):logic =
        Views.HandleActivation(SceneEvent, Entity, CreateView)
        false

    OnEndSimulation<override>():void =
        Views.Deactivate()
        (super:)OnEndSimulation()

    # Called from the view. Opens the menu for Agent only
    OpenMenu<internal>(Agent:agent):void =
        if (Target := MenuEntity?):
            for (Widget : Target.GetPlayerWidgets()):
                Widget.ShowFor(Agent)
        else:
            Print("[widget_sample_opener] MenuEntity is not set", ?Duration := 4.0)

    CreateView<private>(ViewEntity:entity, Slot:player_slot_component):component =
        widget_sample_opener_view_component{Entity := ViewEntity, Source := Self, Player := Slot.Player}

# Role: one player's open input. Adds OpenMapping, opens the menu every time OpenAction is pressed, and notifies the same player's HUD
# Placement: created at runtime by widget_sample_opener_component (never placed in the editor)
widget_sample_opener_view_component<public> := class<final_super>(component):

    Source<public>:widget_sample_opener_component
    Player<public>:player

    OnSimulate<override>()<suspends>:void =
        MaybeInput := Player.AwaitPlayerInput()
        if (PlayerInput := MaybeInput?):
            race:
                PlayerInput.HoldInputMapping(Source.OpenMapping, true)
                loop:
                    PlayerInput.AwaitPressed(Source.OpenAction)
                    Print("[widget_sample_opener] Opening the menu", ?Duration := 3.0)
                    Self.SendToPlayer(widget_sample_menu_opened_event{Agent := Player})
                    Source.OpenMenu(Player)
        else:
            Print("[widget_sample_opener] Cannot get this player's input (player_input)")
