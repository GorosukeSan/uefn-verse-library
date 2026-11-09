using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { /UnrealEngine.com/JSON }
using { CountdownSystem }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# Role: Countdown toolset (destination "countdown"). Lists countdowns (CountdownSystem's countdown_component) and their state; start, restart, stop, pause, resume, add seconds
#   A countdown is addressed by entity id or name
# Placement: best attached to the same entity as the inbox
# Tags: mcp_controllable_tag and mcp_session_restorable_tag on its own entity (key "countdowns": remaining seconds, paused)
mcp_countdown_toolset_component<public> := class<final_super>(component, mcp_controllable, mcp_session_restorable):

    # Name used when the same toolset is placed more than once (when empty, "countdown" alone reaches it)
    @editable:
        ToolTip := McpToolsetIdToolTip
        Categories := array{McpCategory}
    InstanceId<public>:string = ""

    RoleTags<private>:mcp_role_tags = mcp_role_tags{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        RoleTags.Add(Entity, mcp_controllable_tag{})
        RoleTags.Add(Entity, mcp_session_restorable_tag{})

    OnEndSimulation<override>():void =
        RoleTags.RemoveAll()
        (super:)OnEndSimulation()

    McpToolset<override>()<transacts>:string = "countdown"

    McpId<override>()<transacts>:string = InstanceId

    McpTools<override>()<transacts>:[]mcp_tool =
        array:
            McpTool("list", "List of countdowns. data: [\{id,name,running,paused,remaining,duration\}]", array{})
            McpTool("state", "State of one countdown", array{McpArg("countdown", "entity", "countdown")})
            McpTool("start", "Starts it if not counting", array{McpArg("countdown", "entity", "countdown")})
            McpTool("restart", "Counts again from the start (seconds overrides the duration for this run only)", array{McpArg("countdown", "entity", "countdown"), McpOptArg("seconds", "float", "seconds")})
            McpTool("stop", "Stops it (no finished notification)", array{McpArg("countdown", "entity", "countdown")})
            McpTool("pause", "Pauses", array{McpArg("countdown", "entity", "countdown")})
            McpTool("resume", "Resumes", array{McpArg("countdown", "entity", "countdown")})
            McpTool("add_seconds", "Adds to the remaining time (negative subtracts)", array{McpArg("countdown", "entity", "countdown"), McpArg("seconds", "float", "seconds")})

    McpHandle<override>(Call:mcp_call):mcp_reply =
        Tool := Call.Tool
        Inbox := Call.Inbox
        if (Tool = "list"):
            Items := for (Countdown : FindCountdowns()) { CountdownJson(Inbox, Countdown) }
            McpOkData("{Items.Length} countdowns", McpArray(Items))
        else if (Target := Call.FindEntity["countdown"], Countdown := Target.GetComponent[countdown_component]):
            if (Tool = "state"):
                McpOkData("remaining={Countdown.GetRemainingSeconds()}", CountdownJson(Inbox, Countdown))
            else if (Tool = "start"):
                Countdown.Start()
                McpOk("remaining={Countdown.GetRemainingSeconds()}")
            else if (Tool = "restart"):
                if (Seconds := Call.FindFloat["seconds"]):
                    Countdown.Restart(?Seconds := option{Clamp(Seconds, 0.0, 86400.0)})
                else:
                    Countdown.Restart()
                McpOk("remaining={Countdown.GetRemainingSeconds()}")
            else if (Tool = "stop"):
                Countdown.Stop()
                McpOk("stopped")
            else if (Tool = "pause"):
                Countdown.Pause()
                McpOk("paused")
            else if (Tool = "resume"):
                Countdown.Resume()
                McpOk("resumed")
            else if (Tool = "add_seconds"):
                if (Seconds := Call.FindFloat["seconds"]):
                    Countdown.AddSeconds(Clamp(Seconds, -86400.0, 86400.0))
                    McpOk("remaining={Countdown.GetRemainingSeconds()}")
                else:
                    McpBadArg("seconds")
            else:
                McpFail("unknown_tool", Tool)
        else:
            McpFail("no_entity", "countdown (an entity with countdown_component)")

    FindCountdowns<private>()<transacts>:[]countdown_component =
        if (World := Entity.GetSimulationEntity[]):
            for (Countdown : World.FindDescendantComponents(countdown_component)) { Countdown }
        else:
            array{}

    # ---- State (key "countdowns": {"<key>":{"running","paused","remaining"}}) ----

    McpSessionKey<override>()<transacts>:string = "countdowns"

    McpSessionSave<override>(Context:mcp_session_context):string =
        Fields := for (Countdown : FindCountdowns()):
            Running := if (Countdown.IsRunning[] or Countdown.IsPaused[]) then "\"1\"" else "\"0\""
            Paused := if (Countdown.IsPaused[]) then "\"1\"" else "\"0\""
            McpField(Countdown.Entity.GetMcpKey(), McpObject(array{McpField("running", Running), McpField("paused", Paused), McpField("remaining", McpNumber(Countdown.GetRemainingSeconds()))}))
        McpObject(Fields)

    McpSessionRestore<override>(Context:mcp_session_context, State:value):string =
        if (O := State.AsObject[]):
            Pairs := for (Countdown : FindCountdowns(), V := O[Countdown.Entity.GetMcpKey()], Item := V.AsObject[]) { (Countdown, Item) }
            for (Pair : Pairs):
                Countdown := Pair(0)
                Item := Pair(1)
                Running := if (X := Item["running"], R := McpValueToLogic[X]) then R else false
                Paused := if (X := Item["paused"], P := McpValueToLogic[X]) then P else false
                Remaining := if (X := Item["remaining"], F := McpValueToFloat[X]) then F else 0.0
                if (Running? and Remaining > 0.0):
                    Countdown.Restart(?Seconds := option{Remaining})
                    if (Paused?):
                        Countdown.Pause()
                else:
                    Countdown.Stop()
            "ok restored={Pairs.Length}"
        else:
            "bad_state"

CountdownJson<internal>(Inbox:mcp_inbox_component, Countdown:countdown_component)<transacts>:string =
    McpObject(array{McpField("id", "{Inbox.GetHandle(Countdown.Entity)}"), McpField("name", McpQuote(Countdown.Entity.GetMcpName())),
        McpField("running", if (Countdown.IsRunning[]) then "true" else "false"), McpField("paused", if (Countdown.IsPaused[]) then "true" else "false"),
        McpField("remaining", McpNumber(Countdown.GetRemainingSeconds())), McpField("duration", McpNumber(Countdown.DurationSeconds))})
