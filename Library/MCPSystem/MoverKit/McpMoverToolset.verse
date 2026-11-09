using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { MoverSystem }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# Role: Mover toolset (destination "mover"). Lists movers (MoverSystem's mover_component) and their state; play, pause, restart, speed
#   A mover is addressed by entity id or name
# Placement: best attached to the same entity as the inbox
# Tags: mcp_controllable_tag on its own entity
# Requirements, caveats: a mover cannot be restored to a mid-path position (MoverSystem has no API to start part-way), so it is not part of state snapshot / restore
mcp_mover_toolset_component<public> := class<final_super>(component, mcp_controllable):

    # Name used when the same toolset is placed more than once (when empty, "mover" alone reaches it)
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
            McpTool("list", "List of movers. data: [\{id,name,moving,finished,speed,pos,target\}]", array{})
            McpTool("state", "State of one mover", array{McpArg("mover", "entity", "mover")})
            McpTool("play", "Starts moving, or resumes from where it stopped", array{McpArg("mover", "entity", "mover")})
            McpTool("pause", "Pauses in place", array{McpArg("mover", "entity", "mover")})
            McpTool("restart", "Restarts the path from the beginning", array{McpArg("mover", "entity", "mover"), McpOptArg("return_to_start", "bool", "return to the start position first (default true)")})
            McpTool("set_speed", "Speed (cm/s; below 1 becomes 1)", array{McpArg("mover", "entity", "mover"), McpArg("speed", "float", "cm/s")})

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
            McpFail("no_entity", "mover (an entity with mover_component)")

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
