using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { WidgetSystem }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# Tag that mcp_widget_control_component attaches to its own entity (the widget toolset collects screens by this tag)
mcp_widget_control_tag<public> := class<concrete>(tag){}

# Role: opt-in per screen. Only the screens (every player_widget_component subclass) on entities that carry this component are visible and pressable from MCP's widget toolset
# Placement: one on the same entity as the screen (a player_widget_component subclass) you want to drive from MCP
# Tags: mcp_widget_control_tag on its own entity
# Requirements, caveats: pressing goes through WidgetSystem's widget_view.PressButton (reaches AwaitClick / AwaitChoice like a real click). A screen not waiting for a button gives not_waiting
mcp_widget_control_component<public> := class<final_super>(component):

    # Name used to address the screen from MCP (the screen of widget.screens). Empty means "screen"
    @editable:
        ToolTip := McpWidgetScreenIdToolTip
        Categories := array{McpCategory}
    ScreenId<public>:string = ""
    # When on, MCP can press buttons. Default on
    @editable:
        ToolTip := McpWidgetAllowPressToolTip
        Categories := array{McpCategory}
    AllowPress<public>:logic = true
    # When on, MCP can show and close the screen. Default on
    @editable:
        ToolTip := McpWidgetAllowShowHideToolTip
        Categories := array{McpCategory}
    AllowShowHide<public>:logic = true

    RoleTags<private>:mcp_role_tags = mcp_role_tags{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        RoleTags.Add(Entity, mcp_widget_control_tag{})

    OnEndSimulation<override>():void =
        RoleTags.RemoveAll()
        (super:)OnEndSimulation()

    # Screen name used by MCP
    GetScreenName<public>()<transacts>:string =
        if (ScreenId = "") then "screen" else ScreenId

    # Screens of this entity (every player_widget_component subclass)
    GetWidgets<public>()<transacts>:[]player_widget_component =
        Entity.GetPlayerWidgets()

# Role: Widget toolset (destination "widget"). Lists open screens, presses buttons (reaches AwaitClick / AwaitChoice like a real click), shows and closes screens
#   Only screens on entities that carry mcp_widget_control_component are targets (the author opts in per screen). Other screens are invisible (no_target)
#   Screens only show during a round (a WidgetSystem rule). Outside a round, screens is empty, press gives not_shown and show gives not_in_round
# Placement: best attached to the same entity as the inbox (one only)
# Tags: mcp_controllable_tag on its own entity
mcp_widget_toolset_component<public> := class<final_super>(component, mcp_controllable):

    # Name used when the same toolset is placed more than once (when empty, "widget" alone reaches it)
    @editable:
        ToolTip := McpToolsetIdToolTip
        Categories := array{McpCategory}
    InstanceId<public>:string = ""

    RoleTags<private>:mcp_role_tags = mcp_role_tags{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        RoleTags.Add(Entity, mcp_controllable_tag{})

    OnEndSimulation<override>():void =
        RoleTags.RemoveAll()
        (super:)OnEndSimulation()

    McpToolset<override>()<transacts>:string = "widget"

    McpId<override>()<transacts>:string = InstanceId

    McpTools<override>()<transacts>:[]mcp_tool =
        array:
            McpTool("list", "List of opted-in screens (whether shown or not). data: [\{screen,entity,widgets:[\{widget,mode,audience,shown_to\}]\}]", array{})
            McpTool("screens", "Screens currently shown and the buttons waiting. data: [\{player,screen,widget,mode,buttons:[\{id,index,label,enabled\}]\}]", array{McpOptArg("player", "player", "only this player")})
            McpTool("press", "Presses a button (by id, label or index; reaches AwaitClick / AwaitChoice like a real click)", array{McpArg("player", "player", "player index"), McpArg("screen", "string", "screen name (ScreenId)"), McpArg("button", "string", "button id, label or index"), McpOptArg("widget", "int", "widget index when the entity has several screens (default: search all shown ones)")})
            McpTool("pointer", "Injects a pointer into the screen (widget_view.InjectPointer; treated like a Virtual Pointer press, so a card sinks where pressed). x, y are screen fractions (top-left 0,0 to bottom-right 1,1)", array{McpArg("player", "player", "player index"), McpArg("screen", "string", "screen name (ScreenId)"), McpArg("x", "float", "horizontal fraction 0-1"), McpArg("y", "float", "vertical fraction 0-1"), McpOptArg("down", "bool", "pressed (default true; false releases)"), McpOptArg("widget", "int", "widget index (default: all shown ones)")})
            McpTool("show", "Shows the screen (ShowFor)", array{McpArg("player", "player", "player index"), McpArg("screen", "string", "screen name"), McpOptArg("widget", "int", "widget index (default 0)")})
            McpTool("close", "Closes the screen (HideFor)", array{McpArg("player", "player", "player index"), McpArg("screen", "string", "screen name"), McpOptArg("widget", "int", "widget index (default: all)")})
            McpTool("state", "Number of opted-in screens and of screens currently shown", array{})

    McpHandle<override>(Call:mcp_call):mcp_reply =
        Tool := Call.Tool
        Inbox := Call.Inbox
        if (Tool = "list"):
            Items := for (Control : FindControls()):
                Widgets := for (Index -> Widget : Control.GetWidgets()):
                    Shown := for (Player : Entity.McpGetPlayers(), Widget.IsShownFor[Player]) { "{Entity.McpGetPlayerIndex(Player)}" }
                    McpObject(array{McpField("widget", "{Index}"), McpField("mode", McpQuote(ModeName(Widget.Mode))), McpField("audience", McpQuote(AudienceName(Widget.Audience))),
                        McpField("outside_round", if (Widget.IsOutsideRound[]) then "true" else "false"), McpField("shown_to", McpArray(Shown))})
                McpObject(array{McpField("screen", McpQuote(Control.GetScreenName())), McpField("entity", "{Inbox.GetHandle(Control.Entity)}"), McpField("widgets", McpArray(Widgets))})
            McpOkData("{Items.Length} screens", McpArray(Items))
        else if (Tool = "screens"):
            var OnlyPlayer:?player = false
            if (Call.HasArg["player"]):
                if (P := Call.FindPlayer["player"]):
                    set OnlyPlayer = option{P}
                else:
                    return McpFail("no_player", Call.GetStringOr("player", ""))
            Found := for (Control : FindControls(), Index -> Widget : Control.GetWidgets(), Player : Entity.McpGetPlayers(), (not OnlyPlayer? or OnlyPlayer? = Player), View := Widget.FindView[Player]):
                (Player, Control, Index, Widget, View)
            var Items:[]string = array{}
            for (Entry : Found):
                Infos := Entry(4).GetWaitingButtons()
                set Items += array{ScreenJson(Entity.McpGetPlayerIndex(Entry(0)), Entry(1).GetScreenName(), Entry(2), Entry(3), Infos)}
            McpOkData("{Items.Length} shown", McpArray(Items))
        else if (Tool = "state"):
            Controls := FindControls()
            var Shown:int = 0
            for (Control : Controls, Widget : Control.GetWidgets(), Player : Entity.McpGetPlayers(), Widget.IsShownFor[Player]):
                set Shown += 1
            McpOkData("screens={Controls.Length} shown={Shown}", McpObject(array{McpField("screens", "{Controls.Length}"), McpField("shown", "{Shown}")}))
        else if (Player := Call.FindPlayer["player"]):
            if (ScreenName := Call.FindString["screen"]):
                Matches := for (Control : FindControls(), Control.GetScreenName() = ScreenName) { Control }
                if (Control := Matches[0]):
                    HandleScreen(Call, Player, Control)
                else:
                    McpFail("no_target", "screen {ScreenName} (the ScreenId of an mcp_widget_control_component)")
            else:
                McpBadArg("screen")
        else:
            McpFail("no_player", Call.GetStringOr("player", ""))

    HandleScreen<private>(Call:mcp_call, Player:player, Control:mcp_widget_control_component):mcp_reply =
        Tool := Call.Tool
        Widgets := Control.GetWidgets()
        if (Widgets.Length = 0):
            return McpFail("no_target", "no player_widget_component on {Control.GetScreenName()}")
        WidgetIndex := Call.GetIntOr("widget", -1)
        if (Tool = "press"):
            if (not Control.AllowPress?):
                return McpFail("disabled", "AllowPress is off")
            Key := Call.GetStringOr("button", "")
            var Result:string = "not_shown"
            var Done:logic = false
            Views := for (Index -> Widget : Widgets, WidgetIndex < 0 or WidgetIndex = Index, View := Widget.FindView[Player]) { View }
            for (View : Views):
                if (not Done?):
                    Pressed := View.PressButton(Key)
                    set Result = PressResultName(Pressed)
                    if (Pressed = widget_press_result.Pressed or Pressed = widget_press_result.Disabled):
                        set Done = true
            if (Result = "pressed"):
                McpOk("pressed {Key}")
            else if (Result = "not_shown" and Widgets[0].IsOutsideRound[]):
                McpFail("not_shown", "between rounds")
            else:
                McpFail(Result, Key)
        else if (Tool = "pointer"):
            if (not Control.AllowPress?):
                return McpFail("disabled", "AllowPress is off")
            X := Call.GetFloatOr("x", 0.5)
            Y := Call.GetFloatOr("y", 0.5)
            Down := Call.GetLogicOr("down", true)
            Views := for (Index -> Widget : Widgets, WidgetIndex < 0 or WidgetIndex = Index, View := Widget.FindView[Player]) { View }
            for (View : Views):
                View.InjectPointer(X, Y, Down)
            if (Views.Length > 0) then McpOk("fed {Views.Length} ({X}, {Y}) {if (Down?) then "down" else "up"}") else McpFail("not_shown", Control.GetScreenName())
        else if (Tool = "show" or Tool = "close"):
            if (not Control.AllowShowHide?):
                return McpFail("disabled", "AllowShowHide is off")
            if (Tool = "show"):
                Target := if (W := Widgets[Max(WidgetIndex, 0)]) then W else return McpFail("bad_args", "widget")
                if (Target.IsOutsideRound[]):
                    return McpFail("not_in_round", "")
                Target.ShowFor(Player)
                if (Target.IsShownFor[Player]) then McpOk("shown") else McpFail("failed", "not shown (filtered out, overlapping menu etc.)")
            else:
                var Closed:int = 0
                for (Index -> Widget : Widgets, WidgetIndex < 0 or WidgetIndex = Index, Widget.IsShownFor[Player]):
                    Widget.HideFor(Player)
                    set Closed += 1
                McpOk("closed {Closed}")
        else:
            McpFail("unknown_tool", Tool)

    FindControls<private>()<transacts>:[]mcp_widget_control_component =
        if (World := Entity.GetSimulationEntity[]):
            for (Tagged : World.FindDescendantEntitiesWithTag(mcp_widget_control_tag), Control := Tagged.GetComponent[mcp_widget_control_component]) { Control }
        else:
            array{}

# One shown screen ({"player","screen","widget","mode","buttons"})
ScreenJson<internal>(PlayerIndex:int, ScreenName:string, WidgetIndex:int, Widget:player_widget_component, Infos:[]widget_button_info)<transacts>:string =
    Buttons := for (Info : Infos):
        McpObject(array{McpField("id", McpQuote(Info.Id)), McpField("index", "{Info.Index}"), McpField("label", McpQuote(Info.Label)), McpField("enabled", McpLogic(Info.Enabled))})
    McpObject(array{McpField("player", "{PlayerIndex}"), McpField("screen", McpQuote(ScreenName)), McpField("widget", "{WidgetIndex}"),
        McpField("mode", McpQuote(ModeName(Widget.Mode))), McpField("buttons", McpArray(Buttons))})

ModeName<internal>(Mode:player_widget_mode)<computes>:string =
    case (Mode):
        player_widget_mode.Hud => "Hud"
        player_widget_mode.Menu => "Menu"

AudienceName<internal>(Audience:player_widget_audience)<computes>:string =
    case (Audience):
        player_widget_audience.Everyone => "Everyone"
        player_widget_audience.Chosen => "Chosen"

# Maps a PressButton result to a reply error code
PressResultName<internal>(Result:widget_press_result)<computes>:string =
    case (Result):
        widget_press_result.Pressed => "pressed"
        widget_press_result.NotShown => "not_shown"
        widget_press_result.NotWaiting => "not_waiting"
        widget_press_result.NoButton => "no_button"
        widget_press_result.Disabled => "disabled"
