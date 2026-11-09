using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { /UnrealEngine.com/JSON }
using { CountdownSystem }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# 役割：Countdown ツールセット（宛先 "countdown"）。カウントダウン（CountdownSystem の countdown_component）の一覧・状態、始める・やり直す・止める・一時停止・続ける・秒を足す
#   カウントダウンは entity の番号か名前で指す
# 置き方：受け箱と同じ entity に付けるとよい
# タグ：自分の entity に mcp_controllable_tag と mcp_session_restorable_tag（キー "countdowns"：残り秒・一時停止）
mcp_countdown_toolset_component<public> := class<final_super>(component, mcp_controllable, mcp_session_restorable):

    # 同じツールセットを複数置くときの名前（空なら "countdown" だけで届く）
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
            McpTool("list", "カウントダウンの一覧。data に [\{id,name,running,paused,remaining,duration\}]", array{})
            McpTool("state", "カウントダウン 1 つの状態", array{McpArg("countdown", "entity", "カウントダウン")})
            McpTool("start", "数えていなければ始める", array{McpArg("countdown", "entity", "カウントダウン")})
            McpTool("restart", "最初から数え直す（seconds で今回だけの長さ）", array{McpArg("countdown", "entity", "カウントダウン"), McpOptArg("seconds", "float", "秒")})
            McpTool("stop", "やめる（数え終わりは知らせない）", array{McpArg("countdown", "entity", "カウントダウン")})
            McpTool("pause", "一時停止", array{McpArg("countdown", "entity", "カウントダウン")})
            McpTool("resume", "続ける", array{McpArg("countdown", "entity", "カウントダウン")})
            McpTool("add_seconds", "残りを増やす（マイナスで減らす）", array{McpArg("countdown", "entity", "カウントダウン"), McpArg("seconds", "float", "秒")})

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
            McpFail("no_entity", "countdown（countdown_component の entity）")

    FindCountdowns<private>()<transacts>:[]countdown_component =
        if (World := Entity.GetSimulationEntity[]):
            for (Countdown : World.FindDescendantComponents(countdown_component)) { Countdown }
        else:
            array{}

    # ---- 状態（キー "countdowns"：{"<キー>":{"running","paused","remaining"}}） ----

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
