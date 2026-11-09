using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { GameSequenceSystem }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# 役割：Flow ツールセット（宛先 "flow"）。ゲームの流れ（GameSequenceSystem の game_sequence_component）の一覧・状態、始める・止める・やり直す、ノードへ移る
#   流れは entity の番号か mcp_name_component の名前で指す（流れが 1 つだけなら省略できる）。ノードは entity の番号・名前か、Order の値（"order":1）で指す
#   ラウンドの状態は core.round
# 置き方：受け箱と同じ entity に付けるとよい
# タグ：自分の entity に mcp_controllable_tag
mcp_flow_toolset_component<public> := class<final_super>(component, mcp_controllable):

    # 同じツールセットを複数置くときの名前（空なら "flow" だけで届く）
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
            McpTool("list", "流れの一覧。data に [\{id,name,state,current,nodes:[\{id,name,order,active\}]\}]", array{})
            McpTool("state", "流れの状態（list と同じ。sequence を渡すとその流れだけ）", array{McpOptArg("sequence", "entity", "流れ")})
            McpTool("start", "最初のノードから始める（進めていれば何もしない）", array{McpOptArg("sequence", "entity", "流れ（1 つだけなら省略）")})
            McpTool("stop", "止める", array{McpOptArg("sequence", "entity", "流れ")})
            McpTool("restart", "最初のノードからやり直す", array{McpOptArg("sequence", "entity", "流れ")})
            McpTool("jump", "ノードへ移る（node か order のどちらか）", array{McpOptArg("sequence", "entity", "流れ"), McpOptArg("node", "entity", "ノードの entity"), McpOptArg("order", "int", "ノードの Order")})

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
                McpFail("no_entity", "sequence（game_sequence_component の entity。流れが複数なら必ず渡す）")

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
                McpFail("no_entity", "node（game_node_component）")
        else:
            McpFail("unknown_tool", Tool)

    FindSequences<private>()<transacts>:[]game_sequence_component =
        if (World := Entity.GetSimulationEntity[]):
            for (S : World.FindDescendantComponents(game_sequence_component)) { S }
        else:
            array{}

# 流れの直下のノード
GetNodes<internal>(Sequence:game_sequence_component)<transacts>:[]game_node_component =
    for (Child : Sequence.Entity.GetEntities(), Node := Child.GetComponent[game_node_component]) { Node }

# 流れ 1 つの JSON
SequenceJson<internal>(Inbox:mcp_inbox_component, Sequence:game_sequence_component)<transacts>:string =
    Current := if (Node := Sequence.CurrentNode?) then "{Inbox.GetHandle(Node.Entity)}" else "null"
    Nodes := for (Node : GetNodes(Sequence)):
        McpObject(array{McpField("id", "{Inbox.GetHandle(Node.Entity)}"), McpField("name", McpQuote(Node.Entity.GetMcpName())), McpField("order", "{Node.Order}"),
            McpField("active", if (Node.IsActive[]) then "true" else "false")})
    McpObject(array{McpField("id", "{Inbox.GetHandle(Sequence.Entity)}"), McpField("name", McpQuote(Sequence.Entity.GetMcpName())), McpField("state", McpQuote(Sequence.State.ToString())),
        McpField("current", Current), McpField("nodes", McpArray(Nodes))})
