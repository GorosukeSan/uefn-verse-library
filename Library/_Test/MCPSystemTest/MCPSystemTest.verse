using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { /Verse.org/SpatialMath }
using { /UnrealEngine.com/JSON }
using { MCPSystem }
using { _Test }

# 役割：MCPSystemTest の受け口の見本（宛先 "mcptest"）。echo（名前つき・並びの引数）、sum（int の配列）、vec（ベクトル）、bad_data（壊れた data）、state
mcp_test_echo_component<public> := class<final_super>(component, mcp_controllable):
    # インスタンスの名前（"mcptest@<名前>"）
    TestId<public>:string = ""

    RoleTags<private>:mcp_role_tags = mcp_role_tags{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        RoleTags.Add(Entity, mcp_controllable_tag{})

    OnEndSimulation<override>():void =
        RoleTags.RemoveAll()
        (super:)OnEndSimulation()

    McpToolset<override>()<transacts>:string = "mcptest"

    McpId<override>()<transacts>:string = TestId

    McpTools<override>()<transacts>:[]mcp_tool =
        array:
            McpTool("echo", "text と n を返す", array{McpArg("text", "string", "文字"), McpOptArg("n", "int", "数")})
            McpTool("sum", "values の合計", array{McpArg("values", "json", "int の配列")})
            McpTool("vec", "v の left+up+forward", array{McpArg("v", "vector3", "ベクトル")})
            McpTool("bad_data", "壊れた data を返す", array{})
            McpTool("state", "状態", array{})

    McpHandle<override>(Call:mcp_call):mcp_reply =
        if (Call.Tool = "echo"):
            McpOk("{Call.GetStringOr("text", "")}:{Call.GetIntOr("n", -1)}:{TestId}")
        else if (Call.Tool = "sum"):
            if (Items := Call.FindArray["values"]):
                var Sum:int = 0
                for (Item : Items, N := McpValueToInt[Item]):
                    set Sum += N
                McpOkData("{Sum}", "\{\"sum\":{Sum}\}")
            else:
                McpBadArg("values")
        else if (Call.Tool = "vec"):
            if (V := Call.FindVector["v"]):
                Sum := if (R := Round[V.Left + V.Up + V.Forward]) then R else 0
                McpOk("{Sum}")
            else:
                McpBadArg("v")
        else if (Call.Tool = "bad_data"):
            McpOkData("bad", "\{broken")
        else:
            McpOk("state ok")

# 役割：MCPSystem の動作確認。JSON の小道具（逃がし・数の読み取り・範囲の確認）、受け箱の振り分け（ExecuteJson：Core・宛先・インスタンス・"*"・ツールの有無・省略できない引数・並びの引数・data の確かめ・batch・help）、
#   タグの名前の表、mcp_role_tags、mcp_session_context.ClaimPosition（重なりをずらす）を確かめる
# テストのレベル：この component を付けた entity を 1 つ置くだけ（受け箱・受け口の見本はテストが実行時に作る）。プレイヤーは要らない
# かかる時間：1 秒ほど
# 結果：出力ログの [TEST] MCPSystem
# 前提・注意：ライブ編集の経路（MCP → Inbox → 返事の Print）はセッションで Python の送り手から確かめる（README の「確かめ方」）
mcp_system_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "MCPSystem"}
        TestJsonHelpers(Results)
        Root := entity{}
        Inbox := mcp_inbox_component{Entity := Root, Quiet := true}
        EchoA := mcp_test_echo_component{Entity := Root}
        Child := entity{}
        EchoB := mcp_test_echo_component{Entity := Child, TestId := "b"}
        Root.AddComponents(array{Inbox, EchoA})
        Child.AddComponents(array{EchoB})
        Root.AddEntities(array{Child})
        Entity.AddEntities(array{Root})
        Sleep(0.0)
        Sleep(0.0)
        TestDispatch(Results, Inbox)
        TestRoleTags(Results)
        TestClaim(Results)
        Root.RemoveFromParent()
        if (Results.Finish[]) {}

    TestJsonHelpers<private>(Results:test_log):void =
        Results.Check("escape quote/backslash/newline", if (McpEscape("a\"b\\c\nd") = "a\\\"b\\\\c\\nd") then true else false)
        Results.Check("quote parses back", if (V := Parse[McpQuote("日本語 \" \\ x")], S := V.AsString[], S = "日本語 \" \\ x") then true else false)
        Results.CheckInt("parse int -42", if (N := McpParseInt["-42"]) then N else 0, -42)
        Results.Check("parse int rejects 12a", if (McpParseInt["12a"]) then false else true)
        Results.Check("parse int rejects 19 digits", if (McpParseInt["1234567890123456789"]) then false else true)
        Results.CheckFloat("parse float -3.25", if (F := McpParseFloat["-3.25"]) then F else 0.0, -3.25, 0.0001)
        Results.Check("float to int rejects 1e300", if (McpFloatToInt[1.0e300]) then false else true)
        Results.Check("float to int rejects -1e19", if (McpFloatToInt[-1.0e19]) then false else true)
        Results.CheckInt("float to int truncates -2.7", if (N := McpFloatToInt[-2.7]) then N else 0, -2)
        Results.Check("number of NaN is null", if (McpNumber(NaN) = "null", McpNumber(Inf) = "null", McpNumber(1.5) <> "null") then true else false)
        Results.Check("vector array", if (V := Parse["[1,2,3]"], X := McpValueToVector[V], X.Left = 1.0, X.Up = 2.0, X.Forward = 3.0) then true else false)
        Results.Check("vector xyz (x = forward, y = -left)", if (V := Parse["\{\"x\":5,\"y\":2,\"z\":1\}"], X := McpValueToVector[V], X.Forward = 5.0, X.Left = -2.0, X.Up = 1.0) then true else false)
        Results.Check("vector rejects 1e300", if (V := Parse["[1e300,0,0]"], McpValueToVector[V]) then false else true)
        Results.Check("logic from string", if (V := Parse["\"true\""], L := McpValueToLogic[V], L?) then true else false)
        Results.Check("object/array build parses", if (V := Parse[McpObject(array{McpField("a", McpArray(array{"1", McpQuote("x")})), McpField("v", McpVector(vector3{Left := 1.0}))})], O := V.AsObject[], O["v"]) then true else false)
        Results.Check("join tree", if (McpJoinTree(array{"a", "b", "c", "d", "e"}) = "abcde", McpJoinTree(array{}) = "") then true else false)
        Long := McpJoinTree(for (I := 1..4000) { "ab\"c\\d" })
        Results.CheckInt("long string length", Long.Length, 24000)
        Escaped := McpEscape(Long)
        Results.CheckInt("long escape length", Escaped.Length, 32000)
        Results.Check("long escape parses back", if (V := Parse["\"{Escaped}\""], S := V.AsString[], S = Long) then true else false)

    TestDispatch<private>(Results:test_log, Inbox:mcp_inbox_component):void =
        Ping := Inbox.ExecuteJson("\{\"seq\":5,\"to\":\"core\",\"tool\":\"ping\"\}")
        Results.Check("core.ping ok", ReplyOk(Ping, "pong"))
        Results.Check("reply seq", if (V := Parse[Ping], O := V.AsObject[], S := McpValueToInt[O["seq"]], S = 5) then true else false)
        Results.Check("inbox alias", ReplyOk(Inbox.ExecuteJson("\{\"to\":\"inbox\",\"cmd\":\"ping\"\}"), "pong"))
        Results.Check("named args", ReplyOk(Inbox.ExecuteJson("\{\"to\":\"mcptest@b\",\"tool\":\"echo\",\"args\":\{\"text\":\"hi\",\"n\":3\}\}"), "hi:3:b"))
        Results.Check("positional args", ReplyOk(Inbox.ExecuteJson("\{\"to\":\"mcptest@b\",\"tool\":\"echo\",\"args\":[\"yo\",\"7\"]\}"), "yo:7:b"))
        Results.Check("no target", ReplyError(Inbox.ExecuteJson("\{\"to\":\"nobody\",\"tool\":\"x\"\}"), "no_target"))
        Results.Check("unknown tool", ReplyError(Inbox.ExecuteJson("\{\"to\":\"mcptest@b\",\"tool\":\"nope\"\}"), "unknown_tool"))
        Results.Check("missing required arg", ReplyError(Inbox.ExecuteJson("\{\"to\":\"mcptest@b\",\"tool\":\"echo\"\}"), "bad_args"))
        R1 := Inbox.ExecuteJson("\{\"to\":\"mcptest\",\"tool\":\"echo\",\"args\":\{\"text\":\"t\"\}\}")
        Results.Check("two instances -> hits 2", if (V := Parse[R1], O := V.AsObject[], H := McpValueToInt[O["hits"]], H = 2, O["results"]) then true else false)
        R2 := Inbox.ExecuteJson("\{\"to\":\"mcptest@b\",\"tool\":\"sum\",\"args\":\{\"values\":[1,2,39]\}\}")
        Results.Check("data embedded", if (V := Parse[R2], O := V.AsObject[], D := O["data"].AsObject[], S := McpValueToInt[D["sum"]], S = 42) then true else false)
        R3 := Inbox.ExecuteJson("\{\"to\":\"mcptest@b\",\"tool\":\"bad_data\"\}")
        Results.Check("broken data -> data_error", if (V := Parse[R3], O := V.AsObject[], O["data_error"], O["data"].AsString[]) then true else false)
        Results.Check("vector arg object", ReplyOk(Inbox.ExecuteJson("\{\"to\":\"mcptest@b\",\"tool\":\"vec\",\"args\":\{\"v\":\{\"left\":1,\"up\":2,\"forward\":3\}\}\}"), "6"))
        Results.Check("vector arg too big -> bad_args", ReplyError(Inbox.ExecuteJson("\{\"to\":\"mcptest@b\",\"tool\":\"vec\",\"args\":\{\"v\":[1e300,0,0]\}\}"), "bad_args"))
        R4 := Inbox.ExecuteJson("\{\"to\":\"mcptest@b\",\"tool\":\"help\"\}")
        Results.Check("help", if (V := Parse[R4], O := V.AsObject[], T := O["data"].AsObject[], T["tools"]) then true else false)
        Results.Check("bad json", ReplyError(Inbox.ExecuteJson("\{oops"), "bad_json"))
        Batch := Inbox.ExecuteJson("\{\"to\":\"core\",\"tool\":\"batch\",\"args\":\{\"cmds\":[\{\"to\":\"core\",\"tool\":\"ping\"\},\{\"to\":\"mcptest@b\",\"tool\":\"echo\",\"args\":\{\"text\":\"z\"\}\},\{\"to\":\"core\",\"tool\":\"batch\"\}]\}\}")
        Results.Check("batch returns 3 replies", if (V := Parse[Batch], O := V.AsObject[], A := O["data"].AsArray[], A.Length = 3) then true else false)
        R5 := Inbox.ExecuteJson("\{\"to\":\"core\",\"tool\":\"describe\",\"args\":\{\"toolset\":\"mcptest\"\}\}")
        Results.Check("describe lists mcptest", if (V := Parse[R5], O := V.AsObject[], D := O["data"].AsObject[], L := D["toolsets"].AsArray[], L.Length = 2) then true else false)
        Results.Check("tag entry by name", if (Entry := Inbox.FindTagEntry["mcp_name_tag"], Entry.MakeTag[]) then true else false)
        Results.Check("unknown tag name fails", if (Inbox.FindTagEntry["no_such_tag"]) then false else true)
        Handle := Inbox.GetHandle(Inbox.Entity)
        Results.Check("handle is stable", if (Handle = Inbox.GetHandle(Inbox.Entity), Inbox.FindHandleEntity[Handle] = Inbox.Entity) then true else false)

    TestRoleTags<private>(Results:test_log):void =
        Target := entity{}
        Holder := mcp_role_tags{}
        Holder.Add(Target, mcp_name_tag{})
        Holder.Add(Target, mcp_controllable_tag{})
        Results.Check("role tags added", if (Target.ContainsTag[mcp_name_tag], Target.ContainsTag[mcp_controllable_tag]) then true else false)
        Results.Check("remove by type", if (Holder.Remove[Target, mcp_name_tag], not Target.ContainsTag[mcp_name_tag], Target.ContainsTag[mcp_controllable_tag]) then true else false)
        Holder.RemoveAll()
        Results.Check("remove all", if (Target.ContainsTag[mcp_controllable_tag]) then false else true)

    TestClaim<private>(Results:test_log):void =
        Context := MakeMcpSessionContext(array{}, 100.0)
        A := Context.ClaimPosition(vector3{Forward := 0.0})
        B := Context.ClaimPosition(vector3{Forward := 10.0})
        Results.CheckFloat("first claim stays", A.Left, 0.0, 0.001)
        Results.Check("second claim is shifted", if (DistanceSquared(A, B) >= 100.0 * 100.0 - 0.01) then true else false)

# 返事が ok（"error" が無い）で、reply が Text なら true（v43 の Verse は JSON の true / false を読めないので、ok は "error" の有無で見る）
ReplyOk<internal>(Json:string, Text:string)<transacts>:logic =
    if (V := Parse[Json], O := V.AsObject[], not O["error"], R := O["reply"].AsString[], R = Text) then true else false

# 返事のエラーの種類が Code なら true
ReplyError<internal>(Json:string, Code:string)<transacts>:logic =
    if (V := Parse[Json], O := V.AsObject[], E := O["error"].AsString[], E = Code) then true else false
