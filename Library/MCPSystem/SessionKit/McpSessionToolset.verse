using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/JSON }
using { /Fortnite.com/Game }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# 役割：Session ツールセット（宛先 "session"）。状態の書き出し・復元（DESIGN の session_restorable の土台）
#   mcp_session_restorable_tag の entity の component から mcp_session_restorable を集め、キーごとの JSON を 1 つにまとめて返す（snapshot）・配って戻す（restore）
#   ラウンドが始まるたびに RestoreOnRoundStart（snapshot の JSON）を戻す（空なら何もしない。MCP がセッション開始の前に書いておくと、決めた状態から始められる）
# 置き方：受け箱と同じ entity に付けるとよい
# 状態の形：{"v":1,"t":<秒>,"players":<人数>,"items":{"<キー>":<その部品の JSON>,...}}（大きければ受け箱が分けて出す）
# マルチプレイ：プレイヤーは「その回の番号」（core.players の順）で当てる。保存した人数より今が少なければ余りは捨て、多ければ足りない人はそのまま
#   復元する位置どうしが MinSeparationCm より近いときは左へずらす（mcp_session_context.ClaimPosition。当たりの掃引はしない）
# タグ：自分の entity に mcp_controllable_tag
mcp_session_toolset_component<public> := class<final_super>(component, mcp_controllable):

    # 同じツールセットを複数置くときの名前（空なら "session" だけで届く）
    @editable:
        ToolTip := McpToolsetIdToolTip
        Categories := array{McpCategory}
    InstanceId<public>:string = ""
    # ラウンドが始まるたびに戻す状態（snapshot の JSON）。空なら何もしない
    @editable:
        ToolTip := McpSessionRestoreOnRoundStartToolTip
        Categories := array{McpCategory}
    RestoreOnRoundStart<public>:string = ""
    # ラウンドが始まってから戻すまでの秒数（ロードアウト・独自キャラクターができるのを待つ）。既定 1.5
    @editable_number(float):
        ToolTip := McpSessionRestoreOnRoundStartToolTip
        Categories := array{McpCategory}
        MinValue := option{0.0}
        MaxValue := option{30.0}
    RestoreDelaySeconds<public>:float = 1.5
    # 復元する位置どうしを離す距離（cm）。既定 120
    @editable_number(float):
        ToolTip := McpSessionMinSeparationToolTip
        Categories := array{McpCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    MinSeparationCm<public>:float = 120.0

    RoleTags<private>:mcp_role_tags = mcp_role_tags{}
    var<private> Subscriptions:[]cancelable = array{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        RoleTags.Add(Entity, mcp_controllable_tag{})
        if (Manager := Entity.GetFortRoundManager[]):
            set Subscriptions = array{Manager.SubscribeRoundStarted(OnRoundStarted)}

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        RoleTags.RemoveAll()
        (super:)OnEndSimulation()

    OnRoundStarted<private>()<suspends>:void =
        if (RestoreOnRoundStart <> ""):
            Sleep(RestoreDelaySeconds)
            if (Root := Parse[RestoreOnRoundStart], O := Root.AsObject[]):
                Result := RestoreFrom(O, array{})
                Print("[mcp_session_toolset_component] restored on round start: {Result}")
            else:
                Print("[mcp_session_toolset_component] RestoreOnRoundStart is not a JSON object")

    McpToolset<override>()<transacts>:string = "session"

    McpId<override>()<transacts>:string = InstanceId

    McpTools<override>()<transacts>:[]mcp_tool =
        array:
            McpTool("keys", "状態を書き出せる部品のキーの一覧", array{})
            McpTool("snapshot", "状態を書き出す。data に \{v,t,players,items:\{キー:JSON\}\}", array{McpOptArg("keys", "string[]", "このキーだけ")})
            McpTool("restore", "状態を戻す（snapshot の data をそのまま渡す）。reply にキーごとの結果", array{McpArg("state", "json", "snapshot の data"), McpOptArg("keys", "string[]", "このキーだけ")})

    McpHandle<override>(Call:mcp_call):mcp_reply =
        Tool := Call.Tool
        Keys := if (Items := Call.FindArray["keys"]) then (for (V : Items, S := V.AsString[]) { S }) else array{}
        if (Tool = "keys"):
            Names := for (R : FindRestorables()) { R.McpSessionKey() }
            McpOkData("{Names.Length} keys", McpStringArray(Names))
        else if (Tool = "snapshot"):
            Context := MakeContext()
            var Fields:[]string = array{}
            for (R : FindRestorables()):
                Key := R.McpSessionKey()
                if (Keys.Length = 0 or HasKey(Keys, Key)?):
                    Saved := R.McpSessionSave(Context)
                    set Fields += array{McpField(Key, if (Parse[Saved]) then Saved else McpQuote(Saved))}
            McpOkData("{Fields.Length} items", McpObject(array{McpField("v", "1"), McpField("t", McpNumber(GetSimulationElapsedTime())), McpField("players", "{Context.Players.Length}"), McpField("items", McpObject(Fields))}))
        else if (Tool = "restore"):
            if (State := Call.FindObject["state"]):
                McpOk(RestoreFrom(State, Keys))
            else:
                McpBadArg("state")
        else:
            McpFail("unknown_tool", Tool)

    # State（snapshot の data）の items をキーごとに配る。結果の文（"key=ok; key2=..."）
    RestoreFrom<private>(State:[string]value, Keys:[]string):string =
        Context := MakeContext()
        Items := if (ItemsValue := State["items"], O := ItemsValue.AsObject[]) then O else State
        var Results:[]string = array{}
        for (R : FindRestorables()):
            Key := R.McpSessionKey()
            if (Keys.Length = 0 or HasKey(Keys, Key)?):
                if (Item := Items[Key]):
                    Result := R.McpSessionRestore(Context, Item)
                    set Results += array{"{Key}={Result}"}
        if (Results.Length = 0) then "nothing restored" else McpJoin(Results, "; ")

    MakeContext<private>()<transacts>:mcp_session_context =
        mcp_session_context{Players := Entity.McpGetPlayers(), MinSeparationCm := MinSeparationCm}

    FindRestorables<private>()<transacts>:[]mcp_session_restorable =
        if (World := Entity.GetSimulationEntity[]):
            for (Tagged : World.FindDescendantEntitiesWithTag(mcp_session_restorable_tag), Component : Tagged.GetComponents(), R := mcp_session_restorable[Component]) { R }
        else:
            array{}

HasKey<internal>(Keys:[]string, Key:string)<transacts>:logic =
    Found := for (K : Keys, K = Key) { K }
    if (Found.Length > 0) then true else false
