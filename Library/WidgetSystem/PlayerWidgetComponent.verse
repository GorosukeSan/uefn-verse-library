using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/UI }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { WidgetSystem.TooltipKit }

# Whether the on-screen display takes input
player_widget_mode<public> := enum:
    # Display that does not take input (HUD). Movement and camera controls keep working while it is shown
    Hud
    # Screen that takes input (menu). Only one at a time per person (MenuConflict). Showing it moves focus
    Menu

# Hud -> ui_input_mode.None, Menu -> ui_input_mode.All
(Mode:player_widget_mode).ToInputMode<public>()<computes>:ui_input_mode =
    case (Mode):
        player_widget_mode.Hud => ui_input_mode.None
        player_widget_mode.Menu => ui_input_mode.All

# Whose screen to show on
player_widget_audience<public> := enum:
    # When activated, show to everyone in the area (late joiners too)
    Everyone
    # Show only to people chosen with ShowFor (widget_show_*_component on the same entity, or your code calls ShowFor / HideFor)
    Chosen

# Type taken by player_ui_slot.ZOrder etc. (int, 0 or more)
widget_zorder<public> := type{_X:int where 0 <= _X, _X <= 2147483647}

# Build a player_ui_slot from a ZOrder (out of range is rounded to 0 or the maximum) and an input mode
MakePlayerUISlot<public>(ZOrder:int, InputMode:ui_input_mode)<transacts>:player_ui_slot =
    Clamped := Clamp(ZOrder, 0, 2147483647)
    if (Z := widget_zorder[Clamped]):
        player_ui_slot{ZOrder := Z, InputMode := InputMode}
    else:
        player_ui_slot{ZOrder := 0, InputMode := InputMode}

# What to do when another menu (Mode = Menu) is already shown to the same person
player_widget_menu_conflict<public> := enum:
    # Close the previous menu and show this one
    CloseOther
    # Keep the previous menu and do not show this one
    KeepOther

# Role: base class that shows a widget on players' screens while activated. Subclasses write only CreateWidget (builds the widget for one person)
#   Who sees it is Audience (everyone / people chosen with ShowFor). On an entity that has an owner (inside a CharacterSystem character, etc.), Everyone means "the owner only". Whether it takes input is Mode (Hud / Menu). "People holding the item", "people inside the volume", etc. are chosen with a widget_show_*_component placed on the same entity
#   A view for one person (widget_view) is passed to CreateWidget. It has the closed notification (HiddenEvent), notifications forwarded by this component (ReceivedEvent), button waits (AwaitClick / AwaitChoice) and Close / Focus
# Placement: not placed directly (place a subclass: MenuKit's choice_menu_component, HudKit's text_hud_component, etc.). Any number per entity
# Parent: where the activation signal arrives (for a game sequence, the node's entity or a descendant)
# Rounds: always goes through fort_round_manager (there is no setting to turn it off). Shown only during a round (from OnRoundStarted to OnRoundEnded). ActiveOnBegin screens are shown at OnRoundStarted and removed from everyone at OnRoundEnded (no screen is left behind while editing in UEFN). Without a round manager (tests, etc.) it shows at start and can show at any time
# When: with ActiveOnBegin, from the start. Starts showing on an activation signal (activated_event) or Activate, and removes from everyone on a deactivation signal (deactivated_event) or Deactivate. With Audience = Chosen and an activation signal that knows who triggered it (activated_by_agent_event: interact, volume, the Targets of a menu, etc.), shows to that person (ShowFor)
# From outside: Activate / Deactivate / ShowFor / HideFor / IsShown / IsShownFor / IsOutsideRound / IsOtherMenuShownFor / CanShowTo / FindView / SendToWidgets / SendToWidgetFor
# Filtering: if a widget_audience_filter_component subclass (ShowKit's widget_show_in_group_component, etc.) is on the same entity, shows only to the people it allows
# Requirements: only one widget per person per component (calling ShowFor repeatedly still gives one). Mode = Menu is one at a time per person (MenuConflict). One player_manager_component in the area (or world)
player_widget_component<public> := class<abstract><final_super>(component):

    # Hud is a display that does not take input; Menu takes input and moves focus the moment it is shown (default Hud)
    @editable:
        ToolTip := PlayerWidgetModeToolTip
        Categories := array{PlayerWidgetCategory}
    Mode<public>:player_widget_mode = player_widget_mode.Hud
    # Who sees it. Everyone shows to all on activation, Chosen only to people chosen with ShowFor (default Everyone)
    @editable:
        ToolTip := PlayerWidgetAudienceToolTip
        Categories := array{PlayerWidgetCategory}
    Audience<public>:player_widget_audience = player_widget_audience.Everyone
    # Stacking order on the screen (larger is in front. Guide: HUD 0-100, menus 1000, notifications 10000). Default 0
    @editable_number(int):
        ToolTip := PlayerWidgetZOrderToolTip
        Categories := array{PlayerWidgetCategory}
        MinValue := option{0}
        MaxValue := option{100000}
    ZOrder<public>:int = 0
    # When another menu is already shown to the same person: close the previous one (CloseOther) or do not show this one (KeepOther). Only with Mode = Menu (default CloseOther)
    @editable:
        ToolTip := PlayerWidgetMenuConflictToolTip
        Categories := array{PlayerWidgetCategory}
    MenuConflict<public>:player_widget_menu_conflict = player_widget_menu_conflict.CloseOther
    # When on, shows from the start of the game (with Audience = Chosen, starts accepting ShowFor). Default off
    @editable:
        ToolTip := PlayerWidgetActiveOnBeginToolTip
        Categories := array{PlayerWidgetCategory}
    ActiveOnBegin<public>:logic = false
    # When on, notifications that reach this entity (scene_events other than activation / deactivation signals) are passed to widget_view.ReceivedEvent of everyone it is shown to. Default off
    @editable:
        ToolTip := PlayerWidgetForwardToolTip
        Categories := array{PlayerWidgetCategory}
    ForwardReceivedEvents<public>:logic = false
    Views<private>:player_view_set = player_view_set{}
    RoundWatch<private>:round_watcher = round_watcher{}
    # Whether there is a fort_round_manager (without one it can show at any time, as in tests)
    var<private> HasRoundManager:logic = false
    # true during a round (from OnRoundStarted to OnRoundEnded). Shown only during this time
    var<private> InRound:logic = false

    # Implemented by subclasses. Builds and returns the (outermost) widget shown on View.Player's screen. Called once each time it is shown.
    # To wait for buttons, use View.AwaitClick / AwaitChoice inside spawn{...} (returns false and ends when closed). Subscribe to View.ReceivedEvent for notifications that change the display
    CreateWidget<protected>(View:widget_view):widget

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        # Screens always go through rounds (there is no setting to turn it off). ActiveOnBegin screens are also shown at OnRoundStarted
        # (SubscribeRoundStarted is called right after subscribing if a round is in progress, so nothing is missed)
        set HasRoundManager = RoundWatch.Start(Entity, OnRoundStarted, OnRoundEnded)
        if (ActiveOnBegin?, not HasRoundManager?):
            Activate()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            # With Chosen and a signal that knows who triggered it (the person who pressed the button, etc.), show to that person
            if (Audience = player_widget_audience.Chosen, Agent := SceneEvent.FindActivatingAgent[]):
                ShowFor(Agent)
            else:
                Activate()
        else if (deactivated_event[SceneEvent]):
            Deactivate()
        else if (ForwardReceivedEvents?, not player_view_source_event[SceneEvent], not player_event[SceneEvent]):
            SendToWidgets(SceneEvent)
        false

    OnEndSimulation<override>():void =
        RoundWatch.Stop()
        Views.Deactivate()
        (super:)OnEndSimulation()

    OnRoundStarted<private>()<suspends>:void =
        set InRound = true
        if (ActiveOnBegin?):
            Activate()

    OnRoundEnded<private>():void =
        set InRound = false
        Views.Deactivate()

    # Succeeds if a menu (Mode = Menu) other than this component is shown to Agent. Check before re-showing your own menu (so as not to fight other menus for the single slot)
    IsOtherMenuShownFor<public>(Agent:agent)<decides><transacts>:void =
        Player := player[Agent]
        NoManager:?player_manager_component = false
        Manager := Entity.ResolveScopedComponent(NoManager, player_manager_component)?
        PlayerSlot := Manager.FindSlot[Player]
        Others := for:
            Child : PlayerSlot.Entity.GetEntities()
            Other := Child.GetComponent[player_widget_view_component]
            Other.View.Owner <> Self
            Other.Slot.InputMode = ui_input_mode.All
            Other.View.IsShown[]
        do:
            Other
        Others.Length > 0

    # Succeeds outside a round (before it starts, or from its end until the next one starts). Nothing is shown during this time. Fails without a fort_round_manager (can show at any time)
    IsOutsideRound<public>()<decides><transacts>:void =
        HasRoundManager?
        not InRound?
        # Also check with the round manager's counter, so it can show even if another part calls ShowFor / Activate first at the start of the same round
        not RoundWatch.IsInRound[]

    # Start showing (Everyone shows to all. Chosen starts accepting ShowFor). Does nothing if already activated
    Activate<public>():void =
        if (IsOutsideRound[]):
            return
        # On an entity that has an owner (inside a character, etc.), show only to the owner
        if (OwningPlayer := Entity.FindOwningPlayer[]):
            if (not Views.IsActive[]):
                Views.Activate(Entity, CreateView, ?Everyone := false, ?ViewFilter := option{widget_view_filter{Widget := Self}})
                if (Audience = player_widget_audience.Everyone):
                    Views.ShowFor(OwningPlayer)
        else:
            Views.Activate(Entity, CreateView, ?Everyone := if (Audience = player_widget_audience.Everyone) then true else false, ?ViewFilter := option{widget_view_filter{Widget := Self}})

    # Remove from everyone's screen (same as a deactivation signal). From inside the widget (a close button, etc.) use View.Close
    Deactivate<public>():void =
        Views.Deactivate()

    # Show on Agent's screen (does nothing if already shown). With Chosen and not yet activated, activates first. Also used to bring back a person removed with HideFor under Everyone
    ShowFor<public>(Agent:agent):void =
        if (IsOutsideRound[]):
            return
        if (not Views.IsActive[], Audience = player_widget_audience.Chosen):
            Activate()
        Views.ShowFor(Agent)

    # Succeeds if it may be shown to Agent (when every widget_audience_filter_component (widget_show_in_group_component, etc.) on the same entity allows it. With none, it may be shown to everyone)
    CanShowTo<public>(Agent:agent)<decides><transacts>:void =
        Blocking := for (Component : Entity.GetComponents(), Filter := widget_audience_filter_component[Component], not Filter.AllowsWidgetFor[Agent]):
            Filter
        Blocking.Length = 0

    # Remove from Agent's screen only (stays shown to others). Does nothing if not shown
    HideFor<public>(Agent:agent):void =
        Views.HideFor(Agent)

    # Succeeds if shown on Agent's screen
    IsShownFor<public>(Agent:agent)<decides><transacts>:void =
        Views.FindViewFor[Agent]

    # Succeeds while activated (Everyone: showing to all; Chosen: accepting ShowFor)
    IsShown<public>()<decides><transacts>:void =
        Views.IsActive[]

    # The view shown to Agent. Fails if not shown
    FindView<public>(Agent:agent)<decides><transacts>:widget_view =
        Views.FindViewFor[Agent].GetComponent[player_widget_view_component].View

    # Pass SceneEvent to widget_view.ReceivedEvent of everyone it is shown to (notifications that change the display)
    SendToWidgets<public>(SceneEvent:scene_event):void =
        Views.SendToViews(SceneEvent)

    # Pass SceneEvent only to the widget_view.ReceivedEvent shown to Agent. Does nothing if not shown
    SendToWidgetFor<public>(Agent:agent, SceneEvent:scene_event):void =
        if (ViewEntity := Views.FindViewFor[Agent]):
            ViewEntity.SendDown(player_view_source_event{Event := SceneEvent})

    CreateView<private>(ViewEntity:entity, Slot:player_slot_component):component =
        View := widget_view{Player := Slot.Player, Owner := Self}
        Root := CreateWidget(View)
        player_widget_view_component:
            Entity := ViewEntity
            View := View
            Root := Root
            Slot := MakePlayerUISlot(ZOrder, Mode.ToInputMode())

# Base of components that restrict who may see a widget. Every player_widget_component on the same entity shows only to the people this allows (both when showing to everyone and with ShowFor)
#   Subclasses write AllowsWidgetFor. When the allowed people grow, call ShowFor on the widgets of the same entity; when they shrink, call HideFor (swapping the people shown is the subclass's job)
# Placement: not placed directly (place a subclass: ShowKit's widget_show_in_group_component, etc.)
widget_audience_filter_component<public> := class<abstract><final_super>(component):
    # Succeeds if it may be shown to Agent
    AllowsWidgetFor<public>(Agent:agent)<decides><transacts>:void

# The filter player_widget_component hands to player_view_set for who may see it
widget_view_filter<internal> := class<internal>(player_view_filter):
    Widget<internal>:player_widget_component

    AllowsView<override>(Agent:agent)<decides><transacts>:void =
        Widget.CanShowTo[Agent]

# Return every player_widget_component (subclass) attached to InEntity. Used by widget_show_*_component to find the widgets on the same entity
(InEntity:entity).GetPlayerWidgets<public>()<reads>:[]player_widget_component =
    for (Component : InEntity.GetComponents(), Widget := player_widget_component[Component]):
        Widget
