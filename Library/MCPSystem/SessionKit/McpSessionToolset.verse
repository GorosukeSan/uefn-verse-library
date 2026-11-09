using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/JSON }
using { /Fortnite.com/Game }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# Role: Session toolset (destination "session"). State snapshot / restore (the base of session_restorable in DESIGN)
#   Collects mcp_session_restorable from the components of entities with mcp_session_restorable_tag, returns the per-key JSON as one object (snapshot) and distributes it back (restore)
#   At every round start, restores RestoreOnRoundStart (snapshot JSON) (empty does nothing; when MCP writes it before the session starts, the game starts from a chosen state)
# Placement: best attached to the same entity as the inbox
# State shape: {"v":1,"t":<seconds>,"players":<count>,"items":{"<key>":<that part's JSON>,...}} (the inbox splits it when large)
# Multiplayer: players are matched by "the index in that run" (the order of core.players). When fewer players than saved are present the extras are dropped; when more, the missing ones stay as they are
#   Restored positions closer than MinSeparationCm are shifted to the left (mcp_session_context.ClaimPosition; no collision sweep)
# Tags: mcp_controllable_tag on its own entity
mcp_session_toolset_component<public> := class<final_super>(component, mcp_controllable):

    # Name used when the same toolset is placed more than once (when empty, "session" alone reaches it)
    @editable:
        ToolTip := McpToolsetIdToolTip
        Categories := array{McpCategory}
    InstanceId<public>:string = ""
    # State restored at every round start (snapshot JSON). Empty does nothing
    @editable:
        ToolTip := McpSessionRestoreOnRoundStartToolTip
        Categories := array{McpCategory}
    RestoreOnRoundStart<public>:string = ""
    # Seconds between round start and the restore (waits for loadouts and custom characters to be created). Default 1.5
    @editable_number(float):
        ToolTip := McpSessionRestoreOnRoundStartToolTip
        Categories := array{McpCategory}
        MinValue := option{0.0}
        MaxValue := option{30.0}
    RestoreDelaySeconds<public>:float = 1.5
    # Minimum distance between restored positions (cm). Default 120
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
            McpTool("keys", "List of keys of the parts that can be snapshotted", array{})
            McpTool("snapshot", "Snapshots the state. data: \{v,t,players,items:\{key:JSON\}\}", array{McpOptArg("keys", "string[]", "only these keys")})
            McpTool("restore", "Restores the state (pass the data of snapshot as is). reply gives the result per key", array{McpArg("state", "json", "the data of snapshot"), McpOptArg("keys", "string[]", "only these keys")})

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

    # Distributes the items of State (the data of snapshot) by key. Returns the result text ("key=ok; key2=...")
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
