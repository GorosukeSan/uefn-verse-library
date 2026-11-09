using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { MoverSystem }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# 役割：Mover ツールセット（宛先 "mover"）。動く物（MoverSystem の mover_component）の一覧・状態、動かす・止める・やり直す・速さ
#   動く物は entity の番号か名前で指す
# 置き方：受け箱と同じ entity に付けるとよい
# タグ：自分の entity に mcp_controllable_tag
# 前提・注意：動く物の途中の位置へは戻せない（MoverSystem に途中から始める API が無い）ので、状態の書き出し・復元には入れていない
mcp_mover_toolset_component<public> := class<final_super>(component, mcp_controllable):

    # 同じツールセットを複数置くときの名前（空なら "mover" だけで届く）
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

    McpToolset<override>()<transacts>:string = "mover"

    McpId<override>()<transacts>:string = InstanceId

    McpTools<override>()<transacts>:[]mcp_tool =
        array:
            McpTool("list", "動く物の一覧。data に [\{id,name,moving,finished,speed,pos,target\}]", array{})
            McpTool("state", "動く物 1 つの状態", array{McpArg("mover", "entity", "動く物")})
            McpTool("play", "動き出す・止まった位置から続ける", array{McpArg("mover", "entity", "動く物")})
            McpTool("pause", "その場で一時停止", array{McpArg("mover", "entity", "動く物")})
            McpTool("restart", "道のりの最初からやり直す", array{McpArg("mover", "entity", "動く物"), McpOptArg("return_to_start", "bool", "開始の位置へ戻してから（既定 true）")})
            McpTool("set_speed", "速さ（cm/s。1 未満は 1）", array{McpArg("mover", "entity", "動く物"), McpArg("speed", "float", "cm/s")})

    McpHandle<override>(Call:mcp_call):mcp_reply =
        Tool := Call.Tool
        Inbox := Call.Inbox
        if (Tool = "list"):
            Items := for (Mover : FindMovers()) { MoverJson(Inbox, Mover) }
            McpOkData("{Items.Length} movers", McpArray(Items))
        else if (Target := Call.FindEntity["mover"], Mover := Target.GetComponent[mover_component]):
            if (Tool = "state"):
                McpOkData("ok", MoverJson(Inbox, Mover))
            else if (Tool = "play"):
                Mover.Play()
                McpOk("playing")
            else if (Tool = "pause"):
                Mover.Pause()
                McpOk("paused")
            else if (Tool = "restart"):
                Mover.Restart(?ReturnToStart := Call.GetLogicOr("return_to_start", true))
                McpOk("restarted")
            else if (Tool = "set_speed"):
                if (Speed := Call.FindFloat["speed"]):
                    Mover.SetSpeed(Speed)
                    McpOk("speed={Mover.GetSpeedCmPerSecond()}")
                else:
                    McpBadArg("speed")
            else:
                McpFail("unknown_tool", Tool)
        else:
            McpFail("no_entity", "mover（mover_component の entity）")

    FindMovers<private>()<transacts>:[]mover_component =
        if (World := Entity.GetSimulationEntity[]):
            for (Mover : World.FindDescendantComponents(mover_component)) { Mover }
        else:
            array{}

MoverJson<internal>(Inbox:mcp_inbox_component, Mover:mover_component)<transacts>:string =
    Target := if (T := Mover.FindTarget[]) then McpObject(array{McpField("pos", McpVector(T.Position)), McpField("index", "{T.Index}")}) else "null"
    McpObject(array{McpField("id", "{Inbox.GetHandle(Mover.Entity)}"), McpField("name", McpQuote(Mover.Entity.GetMcpName())), McpField("moving", if (Mover.IsMoving[]) then "true" else "false"),
        McpField("finished", if (Mover.IsFinished[]) then "true" else "false"), McpField("speed", McpNumber(Mover.GetSpeedCmPerSecond())),
        McpField("pos", McpVector(Mover.Entity.GetGlobalTransform().Translation)), McpField("target", Target)})
