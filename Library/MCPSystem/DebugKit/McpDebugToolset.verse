using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# Role: Debug toolset (destination "debug"). Log verbosity, writing to the log, state dump (calls every receiver that has a "state" tool), frame rate, samples of a long-running tool and a large reply
# Placement: best attached to the same entity as the inbox
# Notifications: frames / wait return "accepted" and emit [MCPC] {"event":"frames" / "waited",...} when done
# Tags: mcp_controllable_tag on its own entity
mcp_debug_toolset_component<public> := class<final_super>(component, mcp_controllable):

    # Name used when the same toolset is placed more than once (when empty, "debug" alone reaches it)
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
            McpTool("log", "Writes \"[MCP] text\" to the log (a marker in the same timeline as the game log)", array{McpArg("text", "string", "text to write")})
            McpTool("get_level", "Inbox log verbosity (0-3)", array{})
            McpTool("set_level", "Changes the inbox log verbosity (0 = replies only, 1 = start-up and broken commands, 2 = every command, 3 = verbose)", array{McpArg("level", "int", "0-3")})
            McpTool("dump", "Calls every receiver that has an argument-less \"state\" tool. data: [\{to,ok,reply,data\}]", array{McpOptArg("toolset", "string", "only this toolset")})
            McpTool("counts", "Number of entities in the world, receivers, and named entities", array{})
            McpTool("frames", "Measures the frame count and the seconds per frame (average, max) over seconds (frames at the end)", array{McpOptArg("seconds", "float", "seconds (default 1.0)")})
            McpTool("wait", "Waits seconds, then notifies (a sample long-running tool; waited at the end)", array{McpArg("seconds", "float", "seconds")})
            McpTool("payload", "Returns a string of chars characters in data (to exercise the split-reply mechanism)", array{McpArg("chars", "int", "number of characters (1-300000)")})

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
            # Only receivers with an argument-less "state" (toolsets whose state takes a target are not called)
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

# Succeeds when the tool has a required argument
HasRequiredArg<internal>(Tool:mcp_tool)<transacts><decides>:void =
    Required := for (Arg : Tool.Args, Arg.Required?) { Arg }
    Required.Length > 0
