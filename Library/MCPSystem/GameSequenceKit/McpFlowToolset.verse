using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { GameSequenceSystem }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# Role: Flow toolset (destination "flow"). Lists game sequences (GameSequenceSystem's game_sequence_component) and their state; start, stop, restart, jump to a node
#   A sequence is addressed by entity id or mcp_name_component name (optional when there is only one). A node by entity id / name or by its Order value ("order":1)
#   Round state is core.round
# Placement: best attached to the same entity as the inbox
# Tags: mcp_controllable_tag on its own entity
mcp_flow_toolset_component<public> := class<final_super>(component, mcp_controllable):

    # Name used when the same toolset is placed more than once (when empty, "flow" alone reaches it)
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

    McpToolset<override>()<transacts>:string = "flow"

    McpId<override>()<transacts>:string = InstanceId

    McpTools<override>()<transacts>:[]mcp_tool =
        array:
            McpTool("list", "List of sequences. data: [\{id,name,state,current,nodes:[\{id,name,order,active\}]\}]", array{})
            McpTool("state", "Sequence state (same as list; with sequence, that one only)", array{McpOptArg("sequence", "entity", "sequence")})
            McpTool("start", "Starts from the first node (no-op if already running)", array{McpOptArg("sequence", "entity", "sequence (optional when there is only one)")})
            McpTool("stop", "Stops", array{McpOptArg("sequence", "entity", "sequence")})
            McpTool("restart", "Restarts from the first node", array{McpOptArg("sequence", "entity", "sequence")})
            McpTool("jump", "Jumps to a node (either node or order)", array{McpOptArg("sequence", "entity", "sequence"), McpOptArg("node", "entity", "node entity"), McpOptArg("order", "int", "the node's Order")})

    McpHandle<override>(Call:mcp_call):mcp_reply =
        Tool := Call.Tool
        Inbox := Call.Inbox
        All := FindSequences()
        if (Tool = "list" or (Tool = "state" and not Call.HasArg["sequence"])):
            McpOkData("{All.Length} sequences", McpArray(for (Sequence : All) { SequenceJson(Inbox, Sequence) }))
        else:
            var Target:?game_sequence_component = false
            if (Call.HasArg["sequence"]):
                if (E := Call.FindEntity["sequence"], S := E.GetComponent[game_sequence_component]):
                    set Target = option{S}
            else if (All.Length = 1, Only := All[0]):
                set Target = option{Only}
            if (Sequence := Target?):
                HandleSequence(Call, Sequence)
            else:
                McpFail("no_entity", "sequence (an entity with game_sequence_component; required when there are several sequences)")

    HandleSequence<private>(Call:mcp_call, Sequence:game_sequence_component):mcp_reply =
        Tool := Call.Tool
        Inbox := Call.Inbox
        if (Tool = "state"):
            McpOkData(Sequence.State.ToString(), SequenceJson(Inbox, Sequence))
        else if (Tool = "start"):
            Sequence.Start()
            McpOk("state={Sequence.State.ToString()}")
        else if (Tool = "stop"):
            Sequence.Stop()
            McpOk("state={Sequence.State.ToString()}")
        else if (Tool = "restart"):
            Sequence.Restart()
            McpOk("state={Sequence.State.ToString()}")
        else if (Tool = "jump"):
            var Node:?game_node_component = false
            if (Call.HasArg["node"]):
                if (E := Call.FindEntity["node"], N := E.GetComponent[game_node_component]):
                    set Node = option{N}
            else if (Order := Call.FindInt["order"]):
                Matches := for (N : GetNodes(Sequence), N.Order = Order) { N }
                if (First := Matches[0]):
                    set Node = option{First}
            if (Found := Node?):
                Sequence.JumpTo(Found)
                McpOk("jumped order={Found.Order}")
            else:
                McpFail("no_entity", "node (game_node_component)")
        else:
            McpFail("unknown_tool", Tool)

    FindSequences<private>()<transacts>:[]game_sequence_component =
        if (World := Entity.GetSimulationEntity[]):
            for (S : World.FindDescendantComponents(game_sequence_component)) { S }
        else:
            array{}

# Direct child nodes of the sequence
GetNodes<internal>(Sequence:game_sequence_component)<transacts>:[]game_node_component =
    for (Child : Sequence.Entity.GetEntities(), Node := Child.GetComponent[game_node_component]) { Node }

# One sequence as JSON
SequenceJson<internal>(Inbox:mcp_inbox_component, Sequence:game_sequence_component)<transacts>:string =
    Current := if (Node := Sequence.CurrentNode?) then "{Inbox.GetHandle(Node.Entity)}" else "null"
    Nodes := for (Node : GetNodes(Sequence)):
        McpObject(array{McpField("id", "{Inbox.GetHandle(Node.Entity)}"), McpField("name", McpQuote(Node.Entity.GetMcpName())), McpField("order", "{Node.Order}"),
            McpField("active", if (Node.IsActive[]) then "true" else "false")})
    McpObject(array{McpField("id", "{Inbox.GetHandle(Sequence.Entity)}"), McpField("name", McpQuote(Sequence.Entity.GetMcpName())), McpField("state", McpQuote(Sequence.State.ToString())),
        McpField("current", Current), McpField("nodes", McpArray(Nodes))})
