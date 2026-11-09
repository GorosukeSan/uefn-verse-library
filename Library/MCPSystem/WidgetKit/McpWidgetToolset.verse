using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { WidgetSystem }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# mcp_widget_control_component が自分の entity に付けるタグ（widget ツールセットがこのタグで画面を集める）
mcp_widget_control_tag<public> := class<concrete>(tag){}

# 役割：画面ごとのオプトイン。この component を置いた entity の画面（player_widget_component の派生すべて）だけが、MCP の widget ツールセットから見え、押せる
# 置き方：MCP から操作したい画面（player_widget_component の派生）と同じ entity に 1 つ
# タグ：自分の entity に mcp_widget_control_tag
# 前提・注意：押すのは WidgetSystem の widget_view.PressButton（本物のクリックと同じく AwaitClick / AwaitChoice に届く）。ボタンを待っていない画面は not_waiting
mcp_widget_control_component<public> := class<final_super>(component):

    # MCP から画面を指す名前（widget.screens の screen）。空なら "screen"
    @editable:
        ToolTip := McpWidgetScreenIdToolTip
        Categories := array{McpCategory}
    ScreenId<public>:string = ""
    # オンなら MCP からボタンを押せる。既定オン
    @editable:
        ToolTip := McpWidgetAllowPressToolTip
        Categories := array{McpCategory}
    AllowPress<public>:logic = true
    # オンなら MCP から出す・閉じることができる。既定オン
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

    # MCP で使う画面の名前
    GetScreenName<public>()<transacts>:string =
        if (ScreenId = "") then "screen" else ScreenId

    # この entity の画面（player_widget_component の派生すべて）
    GetWidgets<public>()<transacts>:[]player_widget_component =
        Entity.GetPlayerWidgets()

# 役割：Widget ツールセット（宛先 "widget"）。開いている画面の一覧、ボタンを押す（本物のクリックと同じく AwaitClick / AwaitChoice に届く）、出す・閉じる
#   対象は mcp_widget_control_component を置いた entity の画面だけ（画面ごとに作り手が選ぶオプトイン）。それ以外の画面は見えない（no_target）
#   画面はラウンドの中でだけ出る（WidgetSystem の決まり）。ラウンドの外では screens は空、press は not_shown、show は not_in_round
# 置き方：受け箱と同じ entity に付けるとよい（1 つ）
# タグ：自分の entity に mcp_controllable_tag
mcp_widget_toolset_component<public> := class<final_super>(component, mcp_controllable):

    # 同じツールセットを複数置くときの名前（空なら "widget" だけで届く）
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
            McpTool("list", "オプトインした画面の一覧（出しているかに関係なく）。data に [\{screen,entity,widgets:[\{widget,mode,audience,shown_to\}]\}]", array{})
            McpTool("screens", "今出ている画面と、待っているボタン。data に [\{player,screen,widget,mode,buttons:[\{id,index,label,enabled\}]\}]", array{McpOptArg("player", "player", "この人だけ")})
            McpTool("press", "ボタンを押す（ID・文字・番号のどれか。本物のクリックと同じく AwaitClick / AwaitChoice に届く）", array{McpArg("player", "player", "番号"), McpArg("screen", "string", "画面の名前（ScreenId）"), McpArg("button", "string", "ボタンの ID・文字・番号"), McpOptArg("widget", "int", "同じ entity に画面が複数あるときの番号（既定は、出ているもの全部から探す）")})
            McpTool("pointer", "画面にポインターを差し込む（widget_view.InjectPointer。Virtual Pointer の押下と同じに扱われ、カードなら押した位置が沈む）。x, y は画面の割合（左上 0,0 〜 右下 1,1）", array{McpArg("player", "player", "番号"), McpArg("screen", "string", "画面の名前（ScreenId）"), McpArg("x", "float", "横の割合 0〜1"), McpArg("y", "float", "縦の割合 0〜1"), McpOptArg("down", "bool", "押している（既定 true。false で離す）"), McpOptArg("widget", "int", "画面の番号（既定は出ているもの全部）")})
            McpTool("show", "画面を出す（ShowFor）", array{McpArg("player", "player", "番号"), McpArg("screen", "string", "画面の名前"), McpOptArg("widget", "int", "画面の番号（既定 0）")})
            McpTool("close", "画面を閉じる（HideFor）", array{McpArg("player", "player", "番号"), McpArg("screen", "string", "画面の名前"), McpOptArg("widget", "int", "画面の番号（既定は全部）")})
            McpTool("state", "オプトインした画面の数・今出ている数", array{})

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
                    McpFail("no_target", "screen {ScreenName}（mcp_widget_control_component の ScreenId）")
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
                if (Target.IsShownFor[Player]) then McpOk("shown") else McpFail("failed", "not shown（絞り込み・メニューの重なりなど）")
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

# 出ている画面 1 つ（{"player","screen","widget","mode","buttons"}）
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

# PressButton の結果を返事のエラーの種類にする
PressResultName<internal>(Result:widget_press_result)<computes>:string =
    case (Result):
        widget_press_result.Pressed => "pressed"
        widget_press_result.NotShown => "not_shown"
        widget_press_result.NotWaiting => "not_waiting"
        widget_press_result.NoButton => "no_button"
        widget_press_result.Disabled => "disabled"
