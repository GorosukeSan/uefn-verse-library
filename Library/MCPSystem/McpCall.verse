using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /UnrealEngine.com/JSON }
using { /Fortnite.com/Playspaces }

# One command invocation. The inbox builds it and hands it to mcp_controllable.McpHandle (your code never creates one)
#   Arguments can be read either named ("args":{"entity":3}) or positional ("args":[3], in the order of the tool's argument list)
#   Find*[] fails when the value is unreadable or out of range (use inside if). Get*Or returns the default when unreadable
mcp_call<public> := class<internal>:
    # Sequence number of the command
    Seq<public>:int
    # Destination toolset and instance ("widget@main" gives "widget" and "main"; empty when there is no instance)
    Toolset<public>:string
    Id<public>:string
    # Tool name
    Tool<public>:string
    # The inbox that received the command (id / name tables, notifications, log verbosity)
    Inbox<public>:mcp_inbox_component
    # Named arguments (when "args" is an object)
    Named<internal>:[string]value = map{}
    # Positional arguments (when "args" is an array) and the argument names from the tool description (to map positions to names)
    Positional<internal>:[]value = array{}
    ArgNames<internal>:[]string = array{}

    # JSON value of argument Name. Fails when missing or null
    FindArg<public>(Name:string)<transacts><decides>:value =
        var Found:?value = false
        if (ByName := Named[Name]):
            set Found = option{ByName}
        else:
            for (Index -> ArgName : ArgNames, ArgName = Name, ByIndex := Positional[Index]):
                set Found = option{ByIndex}
        Result := Found?
        not Result.AsNull[]
        Result

    # Succeeds when argument Name is present
    HasArg<public>(Name:string)<transacts><decides>:void =
        FindArg[Name]

    # String (a number becomes its text)
    FindString<public>(Name:string)<transacts><decides>:string =
        McpValueToString[FindArg[Name]]

    # Integer (JSON number or numeric string; up to +-9.0e15; fractions truncate toward 0)
    FindInt<public>(Name:string)<transacts><decides>:int =
        McpValueToInt[FindArg[Name]]

    # Float (finite, up to +-1.0e15)
    FindFloat<public>(Name:string)<transacts><decides>:float =
        McpValueToFloat[FindArg[Name]]

    # true / false ("true" "false" "1" "0" "yes" "no" "on" "off" and numbers. Verse in v43 cannot read JSON true / false, so the sender sends a string or a number)
    FindLogic<public>(Name:string)<transacts><decides>:logic =
        McpValueToLogic[FindArg[Name]]

    # Vector ({"left","up","forward"}, {"x","y","z"} (UE axes: x = forward, y = right = -left, z = up) or [left, up, forward]). Each component finite, up to +-1.0e15
    FindVector<public>(Name:string)<transacts><decides>:vector3 =
        McpValueToVector[FindArg[Name]]

    # Object
    FindObject<public>(Name:string)<transacts><decides>:[string]value =
        FindArg[Name].AsObject[]

    # Array
    FindArray<public>(Name:string)<transacts><decides>:[]value =
        FindArg[Name].AsArray[]

    # entity (an id (the "id" from entity.find etc.), an mcp_name_component name, or {"id":..} / {"name":..}). Fails when not found
    FindEntity<public>(Name:string)<transacts><decides>:entity =
        Inbox.ResolveEntity[FindArg[Name]]

    # Player (index from core.players, from 0). Fails when absent
    FindPlayer<public>(Name:string)<transacts><decides>:player =
        Index := FindInt[Name]
        Inbox.Entity.McpGetPlayers()[Index]

    # Player (as an agent)
    FindAgent<public>(Name:string)<transacts><decides>:agent =
        FindPlayer[Name]

    GetStringOr<public>(Name:string, Default:string)<transacts>:string =
        if (V := FindString[Name]) then V else Default

    GetIntOr<public>(Name:string, Default:int)<transacts>:int =
        if (V := FindInt[Name]) then V else Default

    GetFloatOr<public>(Name:string, Default:float)<transacts>:float =
        if (V := FindFloat[Name]) then V else Default

    GetLogicOr<public>(Name:string, Default:logic)<transacts>:logic =
        if (V := FindLogic[Name]) then V else Default

    # Notification when a long-running tool finishes ([MCPC] {"event":EventName,"seq":<this command's seq>,"data":Data}). Data is JSON (omitted when empty)
    Notify<public>(EventName:string, Data:string)<transacts>:void =
        Inbox.Notify(EventName, Seq, Data)

# ---- Reading JSON values (every conversion that can fail is <decides>; out-of-range values never raise a runtime error) ----

# String, or the text of a number
McpValueToString<public>(V:value)<transacts><decides>:string =
    if (S := V.AsString[]):
        S
    else if (I := McpValueToInt[V], F := V.AsFloat[], F = I * 1.0):
        "{I}"
    else:
        F := McpValueToFloat[V]
        "{F}"

# Integer. A JSON number (up to +-9.0e15; fractions truncate toward 0) or an integer string
McpValueToInt<public>(V:value)<transacts><decides>:int =
    if (F := V.AsFloat[]):
        McpFloatToInt[F]
    else if (S := V.AsString[]):
        McpParseInt[S]
    else:
        # A number AsFloat cannot read (if any). The range cannot be checked, so only accept an int that has no string form
        V.AsInt[]

# Float. A JSON number or a decimal string (finite, up to +-1.0e15)
McpValueToFloat<public>(V:value)<transacts><decides>:float =
    F := if (X := V.AsFloat[]) then X else if (S := V.AsString[]) then McpParseFloat[S] else (V.AsInt[] * 1.0)
    F.IsFinite[]
    F > -1.0e15
    F < 1.0e15
    F

# true / false
McpValueToLogic<public>(V:value)<transacts><decides>:logic =
    if (S := V.AsString[]):
        if (S = "true" or S = "1" or S = "yes" or S = "on" or S = "True" or S = "TRUE"):
            true
        else if (S = "false" or S = "0" or S = "no" or S = "off" or S = "False" or S = "FALSE"):
            false
        else:
            false?
            false
    else:
        F := McpValueToFloat[V]
        if (F <> 0.0) then true else false

# Vector ({"left","up","forward"}, {"x","y","z"} or [left, up, forward])
McpValueToVector<public>(V:value)<transacts><decides>:vector3 =
    if (Items := V.AsArray[]):
        Items.Length = 3
        vector3{Left := McpValueToFloat[Items[0]], Up := McpValueToFloat[Items[1]], Forward := McpValueToFloat[Items[2]]}
    else:
        O := V.AsObject[]
        if (O["left"] or O["up"] or O["forward"]):
            vector3:
                Left := if (X := O["left"]) then McpValueToFloat[X] else 0.0
                Up := if (X := O["up"]) then McpValueToFloat[X] else 0.0
                Forward := if (X := O["forward"]) then McpValueToFloat[X] else 0.0
        else:
            X := if (Item := O["x"]) then McpValueToFloat[Item] else 0.0
            Y := if (Item := O["y"]) then McpValueToFloat[Item] else 0.0
            Z := if (Item := O["z"]) then McpValueToFloat[Item] else 0.0
            vector3{Left := -Y, Up := Z, Forward := X}

# ---- Player indices ----

# Current players (in the order of the playspace's GetPlayers; indices from 0. They change as players join and leave, so use the indices from the core.players reply as they are)
(InEntity:entity).McpGetPlayers<public>()<transacts>:[]player =
    if (Playspace := InEntity.GetPlayspaceForEntity[]) then Playspace.GetPlayers() else array{}

# Index of Agent; -1 when absent
(InEntity:entity).McpGetPlayerIndex<public>(Agent:agent)<transacts>:int =
    var Found:int = -1
    for (Index -> Player : InEntity.McpGetPlayers(), Found < 0, Player = Agent):
        set Found = Index
    Found
