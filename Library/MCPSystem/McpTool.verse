# Tool descriptions (what describe returns) and the reply shape

# Description of one tool argument
#   Type is a hint for the sender: "int" / "float" / "string" / "bool" / "vector3" ({"left","up","forward"} / {"x","y","z"} / [left, up, forward]) /
#   "entity" (the id returned by entity.find etc., or an mcp_name_component name) / "player" (index from core.players) / "json" (anything) / "string[]" etc.
mcp_arg<public> := struct:
    Name<public>:string = ""
    Type<public>:string = "string"
    Doc<public>:string = ""
    # true means required (the inbox checks before calling the handler and returns bad_args when missing)
    Required<public>:logic = true

# Description of one tool
mcp_tool<public> := struct:
    Name<public>:string = ""
    Doc<public>:string = ""
    Args<public>:[]mcp_arg = array{}

# Required argument (tool declarations are read by the README table generator, so write them on one line in the McpTool / McpArg / McpOptArg form)
McpArg<public>(Name:string, Type:string, Doc:string)<transacts>:mcp_arg =
    mcp_arg{Name := Name, Type := Type, Doc := Doc, Required := true}

# Optional argument
McpOptArg<public>(Name:string, Type:string, Doc:string)<transacts>:mcp_arg =
    mcp_arg{Name := Name, Type := Type, Doc := Doc, Required := false}

# Builds a tool description
McpTool<public>(Name:string, Doc:string, Args:[]mcp_arg)<transacts>:mcp_tool =
    mcp_tool{Name := Name, Doc := Doc, Args := Args}

# Tool description as JSON ({"name","doc","args":[{"name","type","doc","required"}]})
(Tool:mcp_tool).ToJson<public>()<transacts>:string =
    ArgItems := for (Arg : Tool.Args):
        McpObject(array{McpField("name", McpQuote(Arg.Name)), McpField("type", McpQuote(Arg.Type)), McpField("doc", McpQuote(Arg.Doc)), McpField("required", McpLogic(Arg.Required))})
    McpObject(array{McpField("name", McpQuote(Tool.Name)), McpField("doc", McpQuote(Tool.Doc)), McpField("args", McpArray(ArgItems))})

# The tool named Name in Tools. Fails when absent
FindMcpTool<public>(Tools:[]mcp_tool, Name:string)<transacts><decides>:mcp_tool =
    Found := for (Tool : Tools, Tool.Name = Name) { Tool }
    Found[0]

# Tool reply
#   When Ok is false, the first word of Text is the error code (no_target / unknown_tool / bad_args / no_entity / no_player / not_shown / no_button / disabled / not_waiting / not_in_round / busy / failed)
#   Data is the structured reply (a JSON string; when empty, no "data" is added to the reply). The inbox checks it with Parse and embeds it as a string when broken
mcp_reply<public> := struct:
    Ok<public>:logic = true
    Text<public>:string = ""
    Data<public>:string = ""

# Success reply (text only)
McpOk<public>(Text:string)<transacts>:mcp_reply =
    mcp_reply{Ok := true, Text := Text}

# Success reply (text and JSON)
McpOkData<public>(Text:string, Data:string)<transacts>:mcp_reply =
    mcp_reply{Ok := true, Text := Text, Data := Data}

# Failure reply. Code is the error code (list above), Detail is a human-readable explanation (may be empty)
McpFail<public>(Code:string, Detail:string)<transacts>:mcp_reply =
    mcp_reply{Ok := false, Text := if (Detail = "") then Code else "{Code} {Detail}"}

# Reply for an unreadable argument (bad_args <argument name>)
McpBadArg<public>(Name:string)<transacts>:mcp_reply =
    McpFail("bad_args", Name)
