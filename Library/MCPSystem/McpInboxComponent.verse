using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { /Verse.org/SpatialMath }
using { /UnrealEngine.com/JSON }
using { /Fortnite.com/Game }
using { /Fortnite.com/Characters }
using { MCPSystem.TooltipKit }

# MCPSystem version (the "v" of describe and hello; bumped when the contract with the Python sender changes)
MCPSystemVersion<public>:string = "1.0.0"

# ==== Contract between sender and receiver (same as the Python sender mcpsystem; "Command and reply format" in README) ====
# Path: the sender writes JSON into mcp_inbox_component.Inbox (a string @editable) with MCP's EntityToolset.SetComponentProperty
#   -> live edit delivers it to the running session (measured in v43.00: about 0.1 s round trip) -> the inbox compares every frame and reads it when changed
#   -> handed to the addressed toolset (mcp_controllable) -> the reply is Print("[MCPC] ...") -> the sender reads it with MCP's GetVerseOutput
# Inbox: {"n":<number changed on every write>,"cmds":[{"seq":S,"to":"<toolset>[@<instance>]","tool":"<tool>","args":{..} or [..]}, ...]}
#   (an array of commands [...] or a single command is also accepted; "cmd" may be used instead of "tool")
#   cmds holds only the commands whose reply has not been seen yet (the sender removes a command once it sees the reply and rewrites). seq only increases (the sender starts from the time in milliseconds)
# Reply: [MCPC] {"seq":S,"ok":true|false,"to":..,"tool":..,"hits":<number of parts that received it>,"reply":"<text>","error":"<code>","data":<JSON>,"f":<frame>,"t":<seconds>}
#   The replies of one frame are joined into one line ([MCPC] [{...},{...}]; up to MaxLineChars characters per line; the rest goes in the next frame)
#   A single reply above MaxLineChars is split: [MCPC] ~K:i:n:<a raw slice of the JSON> (the sender joins them in the order of i). A reply above 600k characters becomes too_large
#   End of a long-running tool: [MCPC] {"event":"<name>","seq":S,"data":<JSON>,"f":..,"t":..}
#   Inbox start-up: [MCPC] {"seq":0,"hello":true,"v":"1.0.0","boot":<number per start>,...} (the sender rewrites its pending commands when it sees this)
# Duplicates (seq at or below the last processed one) are not executed. The remembered reply (last 256) is re-emitted at most once per second

# One command (as read from JSON)
mcp_command<public> := class<internal>:
    Seq<public>:int
    To<public>:string
    Tool<public>:string
    # The "args" value (false when absent)
    Args<public>:?value

# Turns one JSON value into a command. Fails when seq is missing or not an integer of 1 or more
McpReadCommand<public>(V:value)<transacts><decides>:mcp_command =
    O := V.AsObject[]
    Seq := McpValueToInt[O["seq"]]
    Seq > 0
    To := if (T := O["to"].AsString[]) then T else ""
    Tool := if (X := O["tool"].AsString[]) then X else if (X := O["cmd"].AsString[]) then X else ""
    Args:?value = if (A := O["args"]) then option{A} else false
    mcp_command{Seq := Seq, To := To, Tool := Tool, Args := Args}

# A receiver collected by the inbox (the component and its mcp_controllable)
mcp_target<internal> := class<internal>:
    Component<internal>:component
    Controllable<internal>:mcp_controllable

# Role: inbox for commands from MCP. Reads the commands written into Inbox (a string @editable), hands them to the addressed toolset (mcp_controllable) and Prints the replies. Carries the Core toolset ("core") itself
# Placement: create one top-level entity and attach it (live edit only ever writes this component's Inbox, so Lore locking is limited to that entity's package).
#   Toolset components (EntityKit's mcp_entity_toolset_component etc.) are best placed on the same entity (they are collected by tag, so any entity works)
# When: compares Inbox every frame from start until stop. The contents at start are not executed (when RunInboxAtStart is off, so a rebuilt inbox does not repeat commands it already ran)
# Notifications: one-line JSON prefixed [MCPC] (replies, notifications, start-up signal). The sender reads them with MCP's GetVerseOutput
# Tags: collects mcp_controllable from entities with mcp_controllable_tag (also picks up parts added while running)
# Public API: ResolveEntity / GetHandle / FindHandleEntity / FindNamed (entity ids and names), FindTagEntry (tag names), Notify, GetLogLevel / SetLogLevel, IsInRound / GetRoundNumber
# Requirements, caveats: without live edit (a published island) Inbox keeps its cooked value and nothing happens. Turn Quiet on for the published version
mcp_inbox_component<public> := class<final_super>(component):

    # Command JSON written by MCP ({"n":..,"cmds":[...]}, an array of commands, or a single command). Leave it empty in the editor
    @editable:
        ToolTip := McpInboxTextToolTip
        Categories := array{McpCategory}
    Inbox<public>:string = ""
    # When on, the commands in Inbox are executed at start (round start, reset, Verse reload) (to start from commands written before the session). Default off
    @editable:
        ToolTip := McpInboxRunAtStartToolTip
        Categories := array{McpCategory}
    RunInboxAtStart<public>:logic = false
    # Maximum commands executed per frame (1-1000; lower it for many heavy commands). Default 50
    @editable_number(int):
        ToolTip := McpInboxMaxPerFrameToolTip
        Categories := array{McpCategory}
        MinValue := option{1}
        MaxValue := option{1000}
    MaxPerFrame<public>:int = 50
    # Maximum characters per reply line (2000-15000; GetVerseOutput truncates a line at 16384 characters). Default 12000
    @editable_number(int):
        ToolTip := McpInboxMaxLineCharsToolTip
        Categories := array{McpCategory}
        MinValue := option{2000}
        MaxValue := option{15000}
    MaxLineChars<public>:int = 12000
    # When on, replies and notifications are not Printed (commands still run). Keeps the log clean in the published version. Default off
    @editable:
        ToolTip := McpInboxQuietToolTip
        Categories := array{McpCategory}
    Quiet<public>:logic = false
    # Initial verbosity of the inbox log (0 = replies only, 1 = start-up and broken commands, 2 = every command, 3 = verbose). Changeable with debug.set_level. Default 1
    @editable_number(int):
        ToolTip := McpInboxLogLevelToolTip
        Categories := array{McpCategory}
        MinValue := option{0}
        MaxValue := option{3}
    LogLevel<public>:int = 1
    # Seconds to show reply lines on the client screen as well (0 means log only; Print shows on screen for 2 s by default, so 0 keeps it out of the way of play). Default 0
    @editable_number(float):
        ToolTip := McpInboxScreenSecondsToolTip
        Categories := array{McpCategory}
        MinValue := option{0.0}
        MaxValue := option{30.0}
    ScreenSeconds<public>:float = 0.0

    var<private> LastText:string = ""
    var<private> DoneSeq:int = 0
    var<private> Todo:[]mcp_command = array{}
    var<private> QueuedSeq:int = 0
    var<private> Frame:int = 0
    var<private> Replies:[int]string = map{}
    var<private> ReEmitFrame:[int]int = map{}
    var<private> Batch:[]string = array{}
    var<private> BatchChars:int = 0
    var<private> NextChunkId:int = 1
    # Maximum characters of one reply (a larger reply becomes too_large)
    MaxReplyChars<private>:int = 600000
    var<private> Targets:[]mcp_target = array{}
    var<private> ScannedAt:float = -1000.0
    var<private> HandleEntities:[int]entity = map{}
    var<private> EntityHandles:[entity]int = map{}
    var<private> NextHandle:int = 1
    var<private> Level:int = 1
    var<private> BootId:int = 0
    var<private> InRound:logic = false
    var<private> RoundManager:?fort_round_manager = false
    var<private> RoundSubscriptions:[]cancelable = array{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set Level = Clamp(LogLevel, 0, 3)
        Epoch := GetSecondsSinceEpoch()
        set BootId = if (Ms := McpFloatToInt[Epoch * 1000.0], Boot := Mod[Ms, 1000000000]) then Boot else 0
        if (Manager := Entity.GetFortRoundManager[]):
            set RoundManager = option{Manager}
            set RoundSubscriptions = array{Manager.SubscribeRoundStarted(OnRoundStarted), Manager.SubscribeRoundEnded(OnRoundEnded)}

    OnEndSimulation<override>():void =
        for (Subscription : RoundSubscriptions):
            Subscription.Cancel()
        set RoundSubscriptions = array{}
        set RoundManager = false
        set Targets = array{}
        (super:)OnEndSimulation()

    OnSimulate<override>()<suspends>:void =
        Skipped := if (RunInboxAtStart?) then 0 else Inbox.Length
        if (not RunInboxAtStart?):
            set LastText = Inbox
        Emit(McpObject(array{McpField("seq", "0"), McpField("hello", "true"), McpField("v", McpQuote(MCPSystemVersion)), McpField("boot", "{BootId}"),
            McpField("skipped_len", "{Skipped}"), McpField("f", "0"), McpField("t", McpNumber(GetSimulationElapsedTime()))}))
        Log(1, "started (boot {BootId}, skipped {Skipped} chars)")
        loop:
            set Frame += 1
            Text := Inbox
            if (Text <> LastText):
                set LastText = Text
                Read(Text)
            Step()
            Sleep(0.0)

    OnRoundStarted<private>()<suspends>:void =
        set InRound = true

    OnRoundEnded<private>():void =
        set InRound = false

    # ---- Public API ----

    # Succeeds while a round is in progress (from start to end). Fails without a round manager
    IsInRound<public>()<transacts><decides>:void =
        InRound?

    # Current round number (0 without a round manager)
    GetRoundNumber<public>()<transacts>:int =
        if (Manager := RoundManager?) then Manager.RoundNumber else 0

    # Current frame number (counted since the inbox started)
    GetFrame<public>()<transacts>:int = Frame

    # Log verbosity (0-3)
    GetLogLevel<public>()<transacts>:int = Level

    # Changes the log verbosity (clamped to 0-3)
    SetLogLevel<public>(NewLevel:int)<transacts>:void =
        set Level = Clamp(NewLevel, 0, 3)

    # Prints "[mcp_inbox_component] Text" when AtLevel is within Level (nothing when Quiet)
    Log<public>(AtLevel:int, Text:string)<transacts>:void =
        if (AtLevel <= Level, not Quiet?):
            Print("[mcp_inbox_component] {Text}", ?Duration := ScreenSeconds)

    # Emits the notification for a finished long-running tool (goes into this frame's reply line). Data is JSON (omitted when empty)
    Notify<public>(EventName:string, Seq:int, Data:string)<transacts>:void =
        var Fields:[]string = array{McpField("event", McpQuote(EventName)), McpField("seq", "{Seq}")}
        if (Data <> ""):
            set Fields += array{McpDataField(Data)}
        set Fields += array{McpField("f", "{Frame}"), McpField("t", McpNumber(GetSimulationElapsedTime()))}
        AddToBatch(McpObject(Fields))

    # Id of an entity (stable within the session; the "id" of entity.find etc.). A new entity gets a new id
    GetHandle<public>(Target:entity)<transacts>:int =
        if (Known := EntityHandles[Target]):
            Known
        else:
            Handle := NextHandle
            set NextHandle += 1
            if (set EntityHandles[Target] = Handle) {}
            if (set HandleEntities[Handle] = Target) {}
            Handle

    # The entity with id Handle. Fails for an unknown id
    FindHandleEntity<public>(Handle:int)<transacts><decides>:entity =
        HandleEntities[Handle]

    # Entities whose mcp_name_component name is Name (from the whole world; order is undefined)
    FindNamed<public>(Name:string)<transacts>:[]entity =
        if (World := Entity.GetSimulationEntity[]):
            for (Found : World.FindDescendantEntitiesWithTag(mcp_name_tag), Found.GetMcpName() = Name):
                Found
        else:
            array{}

    # Resolves an entity from an argument value (id, numeric string, name, {"id":..} or {"name":..}). Fails when not found
    ResolveEntity<public>(V:value)<transacts><decides>:entity =
        var Found:?entity = false
        if (O := V.AsObject[]):
            if (IdValue := O["id"], Handle := McpValueToInt[IdValue], E := HandleEntities[Handle]):
                set Found = option{E}
            else if (NameValue := O["name"], Name := NameValue.AsString[], E := FindNamed(Name)[0]):
                set Found = option{E}
        else if (S := V.AsString[]):
            if (Handle := McpParseInt[S], E := HandleEntities[Handle]):
                set Found = option{E}
            else if (E := FindNamed(S)[0]):
                set Found = option{E}
        else if (Handle := McpValueToInt[V], E := HandleEntities[Handle]):
            set Found = option{E}
        Found?

    # List of named tags (those the inbox knows + those reported by mcp_tag_provider on entities with mcp_controllable_tag)
    GetTagEntries<public>()<transacts>:[]mcp_tag_entry =
        var Entries:[]mcp_tag_entry = array:
            McpTagEntry("mcp_controllable_tag", mcp_controllable_tag)
            McpTagEntry("mcp_name_tag", mcp_name_tag)
            McpTagEntry("mcp_session_restorable_tag", mcp_session_restorable_tag)
        if (World := Entity.GetSimulationEntity[]):
            for (Tagged : World.FindDescendantEntitiesWithTag(mcp_controllable_tag), Component : Tagged.GetComponents(), Provider := mcp_tag_provider[Component]):
                set Entries += Provider.McpTagEntries()
        Entries

    # The tag named Name. Fails for an unknown name
    FindTagEntry<public>(Name:string)<transacts><decides>:mcp_tag_entry =
        Found := for (Entry : GetTagEntries(), Entry.Name = Name) { Entry }
        Found[0]

    # All current receivers (mcp_controllable) (rescans)
    GetControllables<public>()<transacts>:[]mcp_controllable =
        Rescan()
        for (Target : Targets) { Target.Controllable }

    # Executes one command ({"seq":..,"to":..,"tool":..,"args":..}; seq is optional, 1 when absent) right away and returns the reply JSON (no Print; no duplicate handling or sequence check)
    #   For calling receivers from game code or tests in the same form as MCP. Unreadable JSON gives a bad_json / bad_command reply
    ExecuteJson<public>(CommandJson:string):string =
        if (Root := Parse[CommandJson], O := Root.AsObject[]):
            Seq := if (SeqValue := O["seq"], S := McpValueToInt[SeqValue], S > 0) then S else 1
            To := if (T := O["to"].AsString[]) then T else ""
            Tool := if (X := O["tool"].AsString[]) then X else if (X := O["cmd"].AsString[]) then X else ""
            Args:?value = if (A := O["args"]) then option{A} else false
            RunCommand(mcp_command{Seq := Seq, To := To, Tool := Tool, Args := Args})
        else:
            "\{\"seq\":-1,\"ok\":false,\"error\":\"bad_json\",\"reply\":\"bad_json\"\}"

    # ---- Reading ----

    # Queues new commands into Todo. Duplicates get the remembered reply (at most once per second)
    Read<private>(Text:string)<transacts>:void =
        if (Text = ""):
            return
        if (Root := Parse[Text]):
            var Items:[]value = array{}
            if (Arr := Root.AsArray[]):
                set Items = Arr
            else if (Obj := Root.AsObject[], CmdsValue := Obj["cmds"], Cmds := CmdsValue.AsArray[]):
                set Items = Cmds
            else:
                set Items = array{Root}
            for (Item : Items):
                if (C := McpReadCommand[Item]):
                    if (C.Seq <= DoneSeq):
                        PrevFrame := if (F := ReEmitFrame[C.Seq]) then F else -1000
                        if (Old := Replies[C.Seq], Frame - PrevFrame >= 30):
                            if (set ReEmitFrame[C.Seq] = Frame) {}
                            AddToBatch(Old)
                    else if (C.Seq > QueuedSeq):
                        set Todo += array{C}
                        set QueuedSeq = C.Seq
                        Log(2, "queued seq={C.Seq} to={C.To} tool={C.Tool}")
                else:
                    Log(1, "bad command (no seq)")
                    AddToBatch("\{\"seq\":-1,\"ok\":false,\"error\":\"bad_command\",\"reply\":\"bad_command no seq\"\}")
        else:
            Log(1, "bad json ({Text.Length} chars)")
            AddToBatch("\{\"seq\":-1,\"ok\":false,\"error\":\"bad_json\",\"reply\":\"bad_json\",\"len\":{Text.Length}\}")

    # Runs up to MaxPerFrame commands from Todo and emits this frame's replies as one line
    Step<private>():void =
        var Ran:int = 0
        var Rest:[]mcp_command = array{}
        for (C : Todo):
            if (Ran < MaxPerFrame and BatchChars < MaxLineChars):
                Json := RunCommand(C)
                set Ran += 1
                set DoneSeq = C.Seq
                if (set Replies[C.Seq] = Json) {}
                # A reply just emitted is not re-emitted for 1 s (30 frames) (usually the sender simply has not read it yet)
                if (set ReEmitFrame[C.Seq] = Frame) {}
                AddToBatch(Json)
            else:
                set Rest += array{C}
        set Todo = Rest
        Flush()
        # Forget old replies (keep only the last 256)
        if (Replies[DoneSeq - 256]):
            var Kept:[int]string = map{}
            for (Key -> Json : Replies, Key > DoneSeq - 256):
                if (set Kept[Key] = Json) {}
            set Replies = Kept
            set ReEmitFrame = map{}

    # ---- Emitting replies ----

    Emit<private>(Line:string)<transacts>:void =
        if (not Quiet?):
            Print("[MCPC] {Line}", ?Duration := ScreenSeconds)

    # Adds a reply / notification to the current frame's line. One that does not fit a line by itself is emitted in chunks
    AddToBatch<private>(Json:string)<transacts>:void =
        if (Json.Length > MaxReplyChars):
            # Do not emit an oversized reply (too many Print lines get dropped and the sender would wait forever)
            AddToBatch("\{\"seq\":-1,\"ok\":false,\"error\":\"too_large\",\"reply\":\"too_large {Json.Length} chars\"\}")
        else if (Json.Length + 2 > MaxLineChars):
            EmitChunks(Json)
        else:
            if (Batch.Length > 0 and BatchChars + Json.Length + 1 > MaxLineChars):
                Flush()
            set Batch += array{Json}
            set BatchChars += Json.Length + 1

    Flush<private>()<transacts>:void =
        if (Batch.Length = 1, One := Batch[0]):
            Emit(One)
        else if (Batch.Length > 1):
            Emit("[{McpJoin(Batch, ",")}]")
        set Batch = array{}
        set BatchChars = 0

    # Emits a large JSON in chunks: [MCPC] ~<chunk_id>:<part>:<parts>:<a raw slice of the JSON> (not escaped; reply JSON has no newlines, so it fits one line)
    #   The sender joins them in the order of part. Splits happen before an ASCII character so a UTF-8 character is never cut in half
    EmitChunks<private>(Json:string)<transacts>:void =
        Flush()
        PieceChars := Max(MaxLineChars - 100, 1000)
        var Starts:[]int = array{}
        var Position:int = 0
        loop:
            if (Position >= Json.Length):
                break
            set Starts += array{Position}
            var Next:int = Position + PieceChars
            if (Next < Json.Length):
                var Back:int = 0
                loop:
                    if (Back >= 64 or Next - Back <= Position + 1):
                        break
                    if (C := Json[Next - Back], IsSafeSplitChar[C]):
                        break
                    set Back += 1
                if (Back < 64 and Next - Back > Position + 1):
                    set Next = Next - Back
            set Position = Next
        ChunkId := NextChunkId
        set NextChunkId += 1
        for (Index -> Start : Starts):
            End := if (Following := Starts[Index + 1]) then Following else Json.Length
            Emit("~{ChunkId}:{Index}:{Starts.Length}:{McpSlice(Json, Start, End - Start)}")

    # ---- Executing ----

    # Hands the command to its destination and builds the reply JSON
    RunCommand<private>(C:mcp_command):string =
        Split := SplitTarget(C.To)
        Toolset := Split(0)
        Id := Split(1)
        var Reply:mcp_reply = McpFail("no_target", C.To)
        var Hits:int = 0
        var Results:[]string = array{}
        if (Toolset = "core" or Toolset = "inbox" or Toolset = ""):
            set Hits = 1
            set Reply = RunCore(C)
        else:
            Matches := FindTargets(Toolset, Id)
            for (Target : Matches):
                R := RunTarget(Target, C)
                set Hits += 1
                if (Hits = 1):
                    set Reply = R
                else:
                    set Reply = mcp_reply{Ok := if (Reply.Ok? or R.Ok?) then true else false, Text := "{Reply.Text} | {R.Text}"}
                set Results += array{McpResultJson(Target.Controllable, R)}
            if (Hits = 0):
                set Reply = McpFail("no_target", C.To)
        var Fields:[]string = array{McpField("seq", "{C.Seq}"), McpField("ok", McpLogic(Reply.Ok)), McpField("to", McpQuote(C.To)), McpField("tool", McpQuote(C.Tool)),
            McpField("hits", "{Hits}"), McpField("reply", McpQuote(Reply.Text))}
        if (not Reply.Ok?):
            set Fields += array{McpField("error", McpQuote(McpFirstWord(Reply.Text)))}
        if (Hits > 1):
            set Fields += array{McpField("results", McpArray(Results))}
        else if (Reply.Data <> ""):
            set Fields += array{McpDataField(Reply.Data)}
        set Fields += array{McpField("f", "{Frame}"), McpField("t", McpNumber(GetSimulationElapsedTime()))}
        Log(2, "ran seq={C.Seq} {C.To}.{C.Tool} ok={McpLogic(Reply.Ok)}")
        McpObject(Fields)

    # Runs the tool on one receiver (checks that the tool exists and the required arguments are present first)
    RunTarget<private>(Target:mcp_target, C:mcp_command):mcp_reply =
        Tools := Target.Controllable.McpTools()
        if (Tool := FindMcpTool[Tools, C.Tool]):
            Call := MakeCall(C, Target.Controllable.McpToolset(), Target.Controllable.McpId(), Tool)
            if (Missing := FindMissingArg[Call, Tool]):
                McpFail("bad_args", "missing {Missing}")
            else:
                Target.Controllable.McpHandle(Call)
        else if (C.Tool = "help"):
            McpOkData("{Tools.Length} tools", McpToolsetJson(Target.Controllable))
        else:
            McpFail("unknown_tool", C.Tool)

    MakeCall<private>(C:mcp_command, Toolset:string, Id:string, Tool:mcp_tool)<transacts>:mcp_call =
        var Named:[string]value = map{}
        var Positional:[]value = array{}
        if (Args := C.Args?):
            if (O := Args.AsObject[]):
                set Named = O
            else if (A := Args.AsArray[]):
                set Positional = A
            else if (not Args.AsNull[]):
                set Positional = array{Args}
        mcp_call:
            Seq := C.Seq
            Toolset := Toolset
            Id := Id
            Tool := C.Tool
            Inbox := Self
            Named := Named
            Positional := Positional
            ArgNames := for (Arg : Tool.Args) { Arg.Name }

    # Name of a missing required argument. Fails when all are present
    FindMissingArg<private>(Call:mcp_call, Tool:mcp_tool)<transacts><decides>:string =
        Missing := for (Arg : Tool.Args, Arg.Required?, not Call.HasArg[Arg.Name]) { Arg.Name }
        Missing[0]

    # "widget@main" -> ("widget", "main"), "widget" -> ("widget", "")
    SplitTarget<private>(To:string)<transacts>:tuple(string, string) =
        if (At := McpFindChar[To, '@']):
            (McpSlice(To, 0, At), McpSlice(To, At + 1, To.Length))
        else:
            (To, "")

    # Receivers matching Toolset (and Id). When none is found, rescans and searches again
    FindTargets<private>(Toolset:string, Id:string)<transacts>:[]mcp_target =
        if (GetSimulationElapsedTime() - ScannedAt > 1.0 or Targets.Length = 0 or HasStaleTarget[]):
            Rescan()
        First := MatchTargets(Toolset, Id)
        if (First.Length = 0):
            Rescan()
            MatchTargets(Toolset, Id)
        else:
            First

    MatchTargets<private>(Toolset:string, Id:string)<transacts>:[]mcp_target =
        if (Toolset = "*"):
            Targets
        else:
            for (Target : Targets, Target.Controllable.McpToolset() = Toolset, Id = "" or Target.Controllable.McpId() = Id):
                Target

    HasStaleTarget<private>()<transacts><decides>:void =
        Stale := for (Target : Targets, not Target.Component.IsSimulating[]) { Target }
        Stale.Length > 0

    # Collects mcp_controllable from the components of tagged entities
    Rescan<private>()<transacts>:void =
        set ScannedAt = GetSimulationElapsedTime()
        if (World := Entity.GetSimulationEntity[]):
            set Targets = for (Tagged : World.FindDescendantEntitiesWithTag(mcp_controllable_tag), Component : Tagged.GetComponents(), Controllable := mcp_controllable[Component]):
                mcp_target{Component := Component, Controllable := Controllable}
        else:
            set Targets = array{}

    # ---- Core toolset (destination "core"; "inbox" also works) ----

    CoreTools<private>()<transacts>:[]mcp_tool =
        array:
            McpTool("ping", "Is the inbox alive (returns pong)", array{})
            McpTool("echo", "Returns the arguments (text, or the positional arguments joined with spaces)", array{McpOptArg("text", "string", "text to return")})
            McpTool("describe", "List of toolsets and tools with argument descriptions. JSON in data", array{McpOptArg("toolset", "string", "only this toolset")})
            McpTool("list", "List of receivers (toolsets). data: [\{toolset,id,tools\}]", array{})
            McpTool("status", "Inbox status (last processed seq, pending, frame, receiver count, log level)", array{})
            McpTool("time", "Simulation seconds, UTC Unix time, frame", array{})
            McpTool("round", "Whether a round is in progress, and its number", array{})
            McpTool("players", "List of players (index, has character, position in cm). The player argument of other tools is this index", array{})
            McpTool("tags", "List of named tags (usable in entity.find / player.has_tag etc.)", array{})
            McpTool("batch", "Runs an array of commands in order within the same frame. data: array of replies", array{McpArg("cmds", "json", "[\{to,tool,args\}, ...] (no seq needed; core.batch cannot be nested)")})

    RunCore<private>(C:mcp_command):mcp_reply =
        Call := MakeCall(C, "core", "", if (Tool := FindMcpTool[CoreTools(), C.Tool]) then Tool else mcp_tool{})
        if (C.Tool = "ping"):
            McpOk("pong")
        else if (C.Tool = "echo"):
            if (Text := Call.FindString["text"]):
                McpOk(Text)
            else:
                Parts := for (V : Call.Positional, S := McpValueToString[V]) { S }
                McpOk(McpJoin(Parts, " "))
        else if (C.Tool = "describe"):
            Filter := Call.GetStringOr("toolset", "")
            var Items:[]string = array{}
            if (Filter = "" or Filter = "core"):
                set Items += array{McpObject(array{McpField("toolset", "\"core\""), McpField("id", "\"\""), McpField("tools", McpArray(for (T : CoreTools()) { T.ToJson() }))})}
            for (Controllable : GetControllables(), Filter = "" or Controllable.McpToolset() = Filter):
                set Items += array{McpToolsetJson(Controllable)}
            McpOkData("{Items.Length} toolsets", McpObject(array{McpField("v", McpQuote(MCPSystemVersion)), McpField("toolsets", McpArray(Items))}))
        else if (C.Tool = "list"):
            Items := for (Controllable : GetControllables()):
                McpObject(array{McpField("toolset", McpQuote(Controllable.McpToolset())), McpField("id", McpQuote(Controllable.McpId())), McpField("tools", "{Controllable.McpTools().Length}")})
            McpOkData("{Items.Length} toolsets", McpArray(Items))
        else if (C.Tool = "status"):
            McpOkData("done_seq={DoneSeq} queued={Todo.Length} frame={Frame}", McpObject(array{
                McpField("done_seq", "{DoneSeq}"), McpField("queued", "{Todo.Length}"), McpField("frame", "{Frame}"), McpField("boot", "{BootId}"),
                McpField("targets", "{GetControllables().Length}"), McpField("log_level", "{Level}"), McpField("handles", "{NextHandle - 1}"), McpField("v", McpQuote(MCPSystemVersion))}))
        else if (C.Tool = "time"):
            McpOkData("t={GetSimulationElapsedTime()}", McpObject(array{McpField("sim", McpNumber(GetSimulationElapsedTime())), McpField("epoch", McpNumber(GetSecondsSinceEpoch())), McpField("frame", "{Frame}")}))
        else if (C.Tool = "round"):
            InRoundText := if (InRound?) then "true" else "false"
            HasManager := if (RoundManager?) then "true" else "false"
            McpOkData("in_round={InRoundText} round={GetRoundNumber()}", McpObject(array{McpField("in_round", InRoundText), McpField("round", "{GetRoundNumber()}"), McpField("has_round_manager", HasManager)}))
        else if (C.Tool = "players"):
            Items := for (Index -> Player : Entity.McpGetPlayers()):
                var Fields:[]string = array{McpField("index", "{Index}")}
                if (Character := Player.GetFortCharacter[], Body := Character.GetEntity[]):
                    set Fields += array{McpField("has_character", "true"), McpField("pos", McpVector(Body.GetGlobalTransform().Translation))}
                else:
                    set Fields += array{McpField("has_character", "false")}
                McpObject(Fields)
            McpOkData("{Items.Length} players", McpArray(Items))
        else if (C.Tool = "tags"):
            Items := for (Entry : GetTagEntries()):
                McpObject(array{McpField("name", McpQuote(Entry.Name)), McpField("can_add", if (Entry.Concrete?) then "true" else "false")})
            McpOkData("{Items.Length} tags", McpArray(Items))
        else if (C.Tool = "batch"):
            if (Cmds := Call.FindArray["cmds"]):
                var Out:[]string = array{}
                for (Item : Cmds, O := Item.AsObject[]):
                    To := if (T := O["to"].AsString[]) then T else ""
                    Tool := if (X := O["tool"].AsString[]) then X else if (X := O["cmd"].AsString[]) then X else ""
                    Args:?value = if (A := O["args"]) then option{A} else false
                    if ((To = "core" or To = "inbox" or To = "") and Tool = "batch"):
                        set Out += array{"\{\"ok\":false,\"error\":\"bad_args\",\"reply\":\"bad_args nested batch\"\}"}
                    else:
                        set Out += array{RunCommand(mcp_command{Seq := C.Seq, To := To, Tool := Tool, Args := Args})}
                McpOkData("{Out.Length} commands", McpArray(Out))
            else:
                McpBadArg("cmds")
        else if (C.Tool = "help"):
            McpOkData("{CoreTools().Length} tools", McpArray(for (T : CoreTools()) { T.ToJson() }))
        else:
            McpFail("unknown_tool", C.Tool)

# Description of one receiver ({"toolset","id","tools":[...]})
McpToolsetJson<public>(Controllable:mcp_controllable)<transacts>:string =
    McpObject(array{McpField("toolset", McpQuote(Controllable.McpToolset())), McpField("id", McpQuote(Controllable.McpId())),
        McpField("tools", McpArray(for (T : Controllable.McpTools()) { T.ToJson() }))})

# One result when a command reached several receivers
McpResultJson<internal>(Controllable:mcp_controllable, Reply:mcp_reply)<transacts>:string =
    Name := if (Controllable.McpId() = "") then Controllable.McpToolset() else "{Controllable.McpToolset()}@{Controllable.McpId()}"
    var Fields:[]string = array{McpField("to", McpQuote(Name)), McpField("ok", McpLogic(Reply.Ok)), McpField("reply", McpQuote(Reply.Text))}
    if (Reply.Data <> ""):
        set Fields += array{McpDataField(Reply.Data)}
    McpObject(Fields)

# The "data":<JSON> field. When Data does not parse as JSON, it is embedded as a string and "data_error":true is added
McpDataField<internal>(Data:string)<transacts>:string =
    if (Parse[Data]):
        McpField("data", Data)
    else:
        "{McpField("data", McpQuote(Data))},{McpField("data_error", "true")}"

# The word up to the first space
McpFirstWord<internal>(Text:string)<transacts>:string =
    if (Space := McpFindChar[Text, ' ']) then McpSlice(Text, 0, Space) else Text

# A large reply may be split before this character (ASCII, so never inside a UTF-8 character)
IsSafeSplitChar<internal>(C:char)<transacts><decides>:void =
    var Found:logic = false
    for (S : " ,:{}[]\"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ._-", S = C):
        set Found = true
    Found?
