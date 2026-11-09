# ツールの説明（describe が返すもの）と返事の形

# ツールの引数 1 つの説明
#   Type は送り手への目安："int" / "float" / "string" / "bool" / "vector3"（{"left","up","forward"} / {"x","y","z"} / [left, up, forward]）/
#   "entity"（entity.find などが返す番号か、mcp_name_component の名前）/ "player"（core.players の番号）/ "json"（何でも）/ "string[]" など
mcp_arg<public> := struct:
    Name<public>:string = ""
    Type<public>:string = "string"
    Doc<public>:string = ""
    # true なら省略できない（受け箱が handler を呼ぶ前に確かめ、無ければ bad_args を返す）
    Required<public>:logic = true

# ツール 1 つの説明
mcp_tool<public> := struct:
    Name<public>:string = ""
    Doc<public>:string = ""
    Args<public>:[]mcp_arg = array{}

# 省略できない引数（ツールの宣言は README の一覧の自動生成で読むので、McpTool / McpArg / McpOptArg の形で 1 行に書く）
McpArg<public>(Name:string, Type:string, Doc:string)<transacts>:mcp_arg =
    mcp_arg{Name := Name, Type := Type, Doc := Doc, Required := true}

# 省略できる引数
McpOptArg<public>(Name:string, Type:string, Doc:string)<transacts>:mcp_arg =
    mcp_arg{Name := Name, Type := Type, Doc := Doc, Required := false}

# ツールの説明を作る
McpTool<public>(Name:string, Doc:string, Args:[]mcp_arg)<transacts>:mcp_tool =
    mcp_tool{Name := Name, Doc := Doc, Args := Args}

# ツールの説明を JSON にする（{"name","doc","args":[{"name","type","doc","required"}]}）
(Tool:mcp_tool).ToJson<public>()<transacts>:string =
    ArgItems := for (Arg : Tool.Args):
        McpObject(array{McpField("name", McpQuote(Arg.Name)), McpField("type", McpQuote(Arg.Type)), McpField("doc", McpQuote(Arg.Doc)), McpField("required", McpLogic(Arg.Required))})
    McpObject(array{McpField("name", McpQuote(Tool.Name)), McpField("doc", McpQuote(Tool.Doc)), McpField("args", McpArray(ArgItems))})

# Tools の中から Name のツール。無ければ失敗する
FindMcpTool<public>(Tools:[]mcp_tool, Name:string)<transacts><decides>:mcp_tool =
    Found := for (Tool : Tools, Tool.Name = Name) { Tool }
    Found[0]

# ツールの返事
#   Ok が false のとき、Text の最初の語がエラーの種類（no_target / unknown_tool / bad_args / no_entity / no_player / not_shown / no_button / disabled / not_waiting / not_in_round / busy / failed）
#   Data は構造のある返事（JSON の文字列。空なら返事に "data" を付けない）。受け箱が Parse で確かめ、壊れていれば文字列として載せる
mcp_reply<public> := struct:
    Ok<public>:logic = true
    Text<public>:string = ""
    Data<public>:string = ""

# 成功の返事（文だけ）
McpOk<public>(Text:string)<transacts>:mcp_reply =
    mcp_reply{Ok := true, Text := Text}

# 成功の返事（文と JSON）
McpOkData<public>(Text:string, Data:string)<transacts>:mcp_reply =
    mcp_reply{Ok := true, Text := Text, Data := Data}

# 失敗の返事。Code はエラーの種類（上の一覧）、Detail は人が読む説明（空でもよい）
McpFail<public>(Code:string, Detail:string)<transacts>:mcp_reply =
    mcp_reply{Ok := false, Text := if (Detail = "") then Code else "{Code} {Detail}"}

# 引数が読めないときの返事（bad_args <引数の名前>）
McpBadArg<public>(Name:string)<transacts>:mcp_reply =
    McpFail("bad_args", Name)
