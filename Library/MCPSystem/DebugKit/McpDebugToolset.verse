using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# 役割：Debug ツールセット（宛先 "debug"）。ログの詳しさ、ログに書く、状態のダンプ（"state" ツールを持つ受け口をまとめて呼ぶ）、フレームの速さ、長くかかるツールと大きい返事の見本
# 置き方：受け箱と同じ entity に付けるとよい
# 知らせ：frames / wait は "accepted" を返し、終わったら [MCPC] {"event":"frames" / "waited",...}
# タグ：自分の entity に mcp_controllable_tag
mcp_debug_toolset_component<public> := class<final_super>(component, mcp_controllable):

    # 同じツールセットを複数置くときの名前（空なら "debug" だけで届く）
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

    McpToolset<override>()<transacts>:string = "debug"

    McpId<override>()<transacts>:string = InstanceId

    McpTools<override>()<transacts>:[]mcp_tool =
        array:
            McpTool("log", "ログに「[MCP] text」を書く（ゲームのログと同じ時系列で見る目印に）", array{McpArg("text", "string", "書く文")})
            McpTool("get_level", "受け箱のログの詳しさ（0〜3）", array{})
            McpTool("set_level", "受け箱のログの詳しさを変える（0 = 返事だけ、1 = 起動・壊れた命令、2 = 命令ごと、3 = 詳しく）", array{McpArg("level", "int", "0〜3")})
            McpTool("dump", "引数の要らない \"state\" ツールを持つ受け口をまとめて呼ぶ。data に [\{to,ok,reply,data\}]", array{McpOptArg("toolset", "string", "このツールセットだけ")})
            McpTool("counts", "世界の entity の数・受け口の数・名前を付けた entity の数", array{})
            McpTool("frames", "seconds 秒のフレームの数と 1 フレームの秒（平均・最大）を測る（終わりに frames）", array{McpOptArg("seconds", "float", "秒（既定 1.0）")})
            McpTool("wait", "seconds 秒待ってから知らせる（長くかかるツールの見本。終わりに waited）", array{McpArg("seconds", "float", "秒")})
            McpTool("payload", "chars 文字の文字列を data で返す（大きい返事を分けて出す仕組みの確かめ）", array{McpArg("chars", "int", "文字数（1〜300000）")})

    McpHandle<override>(Call:mcp_call):mcp_reply =
        Tool := Call.Tool
        Inbox := Call.Inbox
        if (Tool = "log"):
            Text := Call.GetStringOr("text", "")
            Print("[MCP] {Text}", ?Duration := Inbox.ScreenSeconds)
            McpOk("logged")
        else if (Tool = "get_level"):
            McpOk("{Inbox.GetLogLevel()}")
        else if (Tool = "set_level"):
            if (Level := Call.FindInt["level"]):
                Inbox.SetLogLevel(Level)
                McpOk("level={Inbox.GetLogLevel()}")
            else:
                McpBadArg("level")
        else if (Tool = "dump"):
            Filter := Call.GetStringOr("toolset", "")
            # 引数の要らない "state" を持つ受け口だけ（state に対象を渡すツールセットは呼ばない）
            Targets := for (Controllable : Inbox.GetControllables(), Controllable.McpToolset() <> "debug", Filter = "" or Controllable.McpToolset() = Filter, StateTool := FindMcpTool[Controllable.McpTools(), "state"], not HasRequiredArg[StateTool]):
                Controllable
            var Items:[]string = array{}
            for (Controllable : Targets):
                StateCall := mcp_call{Seq := Call.Seq, Toolset := Controllable.McpToolset(), Id := Controllable.McpId(), Tool := "state", Inbox := Inbox}
                Reply := Controllable.McpHandle(StateCall)
                Name := if (Controllable.McpId() = "") then Controllable.McpToolset() else "{Controllable.McpToolset()}@{Controllable.McpId()}"
                var Fields:[]string = array{McpField("to", McpQuote(Name)), McpField("ok", McpLogic(Reply.Ok)), McpField("reply", McpQuote(Reply.Text))}
                if (Reply.Data <> ""):
                    set Fields += array{McpField("data", Reply.Data)}
                set Items += array{McpObject(Fields)}
            McpOkData("{Items.Length} toolsets", McpArray(Items))
        else if (Tool = "counts"):
            if (World := Entity.GetSimulationEntity[]):
                var Entities:int = 0
                for (E : World.FindDescendantEntities(entity)):
                    set Entities += 1
                var Named:int = 0
                for (E : World.FindDescendantEntitiesWithTag(mcp_name_tag)):
                    set Named += 1
                Controllables := Inbox.GetControllables().Length
                McpOkData("entities={Entities}", McpObject(array{McpField("entities", "{Entities}"), McpField("controllables", "{Controllables}"), McpField("named", "{Named}")}))
            else:
                McpFail("failed", "not in the scene")
        else if (Tool = "frames"):
            Seconds := Clamp(Call.GetFloatOr("seconds", 1.0), 0.1, 60.0)
            spawn{MeasureFrames(Call, Seconds)}
            McpOk("accepted")
        else if (Tool = "wait"):
            if (Seconds := Call.FindFloat["seconds"]):
                spawn{WaitAndNotify(Call, Clamp(Seconds, 0.0, 600.0))}
                McpOk("accepted")
            else:
                McpBadArg("seconds")
        else if (Tool = "payload"):
            if (Chars := Call.FindInt["chars"], Chars >= 1, Chars <= 300000):
                Unit := "abcdefghijklmnopqrstuvwxyz0123456789"
                Whole := if (Q := Quotient[Chars, Unit.Length]) then Q else 0
                Text := McpJoinTree(for (I := 1..Whole) { Unit }) + McpSlice(Unit, 0, Chars - Whole * Unit.Length)
                McpOkData("{Text.Length} chars", McpObject(array{McpField("chars", "{Text.Length}"), McpField("text", McpQuote(Text))}))
            else:
                McpBadArg("chars")
        else:
            McpFail("unknown_tool", Tool)

    MeasureFrames<private>(Call:mcp_call, Seconds:float)<suspends>:void =
        Start := GetSimulationElapsedTime()
        var Previous:float = Start
        var Frames:int = 0
        var MaxDelta:float = 0.0
        loop:
            Sleep(0.0)
            Now := GetSimulationElapsedTime()
            set MaxDelta = Max(MaxDelta, Now - Previous)
            set Previous = Now
            set Frames += 1
            if (Now - Start >= Seconds):
                break
        Elapsed := Previous - Start
        Average := if (Frames > 0) then Elapsed / (Frames * 1.0) else 0.0
        Call.Notify("frames", McpObject(array{McpField("frames", "{Frames}"), McpField("seconds", McpNumber(Elapsed)), McpField("avg_delta", McpNumber(Average)), McpField("max_delta", McpNumber(MaxDelta))}))

    WaitAndNotify<private>(Call:mcp_call, Seconds:float)<suspends>:void =
        Sleep(Seconds)
        Call.Notify("waited", McpObject(array{McpField("seconds", McpNumber(Seconds))}))

# 省略できない引数があれば成功する
HasRequiredArg<internal>(Tool:mcp_tool)<transacts><decides>:void =
    Required := for (Arg : Tool.Args, Arg.Required?) { Arg }
    Required.Length > 0
