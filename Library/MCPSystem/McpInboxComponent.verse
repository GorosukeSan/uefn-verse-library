using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { /Verse.org/SpatialMath }
using { /UnrealEngine.com/JSON }
using { /Fortnite.com/Game }
using { /Fortnite.com/Characters }
using { MCPSystem.TooltipKit }

# MCPSystem の版（describe・hello の "v"。Python の送り手と約束の形が変わったら上げる）
MCPSystemVersion<public>:string = "1.0.0"

# ==== 送り手と受け手の約束（Python の送り手 mcpsystem と同じ。README の「命令と返事の形」）====
# 経路：送り手が MCP の EntityToolset.SetComponentProperty で mcp_inbox_component.Inbox（文字列の @editable）に JSON を書く
#   → ライブ編集でセッション中のゲームに届く（v43.00 実測、往復 約 0.1 秒）→ 受け箱が毎フレーム比べ、変わったら読む
#   → 宛先のツールセット（mcp_controllable）に渡す → 返事を Print("[MCPC] ...") → 送り手が MCP の GetVerseOutput で読む
# Inbox：{"n":<書くたびに変える数>,"cmds":[{"seq":S,"to":"<ツールセット>[@<インスタンス>]","tool":"<ツール>","args":{..} か [..]}, ...]}
#   （命令の配列 [...] や命令 1 つでもよい。"tool" の代わりに "cmd" でもよい）
#   cmds は返事をまだ見ていない命令だけ（送り手は返事を見たら外して書き直す）。seq は増やすだけ（送り手はミリ秒の時刻から始める）
# 返事：[MCPC] {"seq":S,"ok":true|false,"to":..,"tool":..,"hits":<受けた部品の数>,"reply":"<文>","error":"<種類>","data":<JSON>,"f":<フレーム>,"t":<秒>}
#   1 フレームの返事は 1 行にまとめる（[MCPC] [{...},{...}]。1 行 MaxLineChars 文字まで。残りは次のフレーム）
#   1 つの返事が MaxLineChars を超えるときは分ける：[MCPC] ~K:i:n:<JSON の一部をそのまま>（送り手が i の順につないで読む）。60 万文字を超える返事は too_large
#   長くかかるツールの終わり：[MCPC] {"event":"<名前>","seq":S,"data":<JSON>,"f":..,"t":..}
#   受け箱の起動：[MCPC] {"seq":0,"hello":true,"v":"1.0.0","boot":<起動ごとの数>,...}（送り手は見たら未完了を書き直す）
# 重複（seq が処理済み以下）は実行しない。覚えている返事（直近 256 件）を 1 秒に 1 回まで出し直す

# 1 つの命令（JSON から読んだもの）
mcp_command<public> := class<internal>:
    Seq<public>:int
    To<public>:string
    Tool<public>:string
    # "args" の値（無ければ false）
    Args<public>:?value

# JSON の値 1 つを命令にする。seq が無い・1 以上の整数でないなら失敗する
McpReadCommand<public>(V:value)<transacts><decides>:mcp_command =
    O := V.AsObject[]
    Seq := McpValueToInt[O["seq"]]
    Seq > 0
    To := if (T := O["to"].AsString[]) then T else ""
    Tool := if (X := O["tool"].AsString[]) then X else if (X := O["cmd"].AsString[]) then X else ""
    Args:?value = if (A := O["args"]) then option{A} else false
    mcp_command{Seq := Seq, To := To, Tool := Tool, Args := Args}

# 受け箱が集めた受け口（component と、その mcp_controllable）
mcp_target<internal> := class<internal>:
    Component<internal>:component
    Controllable<internal>:mcp_controllable

# 役割：MCP からの命令の受け箱。Inbox（文字列の @editable）に書かれた命令を読み、宛先のツールセット（mcp_controllable）に渡し、返事を Print する。Core ツールセット（"core"）を自分で持つ
# 置き方：最上位の entity を 1 つ作って付ける（ライブ編集で書くのはこの component の Inbox だけ。Lore のロックはその entity のパッケージだけ）。
#   ツールセットの component（EntityKit の mcp_entity_toolset_component など）は同じ entity に置くとよい（どこに置いても、タグで集める）
# いつ：開始から止まるまで毎フレーム Inbox を比べる。起動時の中身は実行しない（RunInboxAtStart がオフのとき。作り直しのあと、前に実行した命令を繰り返さない）
# 知らせ：[MCPC] で始まる 1 行の JSON（返事・知らせ・起動の合図）。送り手は MCP の GetVerseOutput で読む
# タグ：mcp_controllable_tag の entity から mcp_controllable を集める（実行中に増えた部品にも追いつく）
# 外から：ResolveEntity / GetHandle / FindHandleEntity / FindNamed（entity の番号と名前）、FindTagEntry（タグの名前）、Notify、GetLogLevel / SetLogLevel、IsInRound / GetRoundNumber
# 前提・注意：ライブ編集の無い環境（公開した島）では Inbox はクック時の値のまま変わらず、何もしない。公開版では Quiet をオンにする
mcp_inbox_component<public> := class<final_super>(component):

    # MCP が書く命令の JSON（{"n":..,"cmds":[...]}、命令の配列、命令 1 つのどれか）。エディターでは空にしておく
    @editable:
        ToolTip := McpInboxTextToolTip
        Categories := array{McpCategory}
    Inbox<public>:string = ""
    # オンなら、起動時（ラウンドの開始・リセット・Verse の入れ直し）に Inbox に入っている命令を実行する（セッション開始前に書いておいた命令で始める使い方）。既定オフ
    @editable:
        ToolTip := McpInboxRunAtStartToolTip
        Categories := array{McpCategory}
    RunInboxAtStart<public>:logic = false
    # 1 フレームに実行する命令の数の上限（1〜1000。重い命令が多いなら下げる）。既定 50
    @editable_number(int):
        ToolTip := McpInboxMaxPerFrameToolTip
        Categories := array{McpCategory}
        MinValue := option{1}
        MaxValue := option{1000}
    MaxPerFrame<public>:int = 50
    # 返事 1 行の文字数の上限（2000〜15000。GetVerseOutput は 1 行 16384 文字で切る）。既定 12000
    @editable_number(int):
        ToolTip := McpInboxMaxLineCharsToolTip
        Categories := array{McpCategory}
        MinValue := option{2000}
        MaxValue := option{15000}
    MaxLineChars<public>:int = 12000
    # オンなら返事・知らせを Print しない（命令は実行する）。公開版でログを汚さないため。既定オフ
    @editable:
        ToolTip := McpInboxQuietToolTip
        Categories := array{McpCategory}
    Quiet<public>:logic = false
    # 受け箱のログの詳しさの初期値（0 = 返事だけ、1 = 起動・壊れた命令、2 = 命令ごと、3 = さらに詳しく）。debug.set_level で変えられる。既定 1
    @editable_number(int):
        ToolTip := McpInboxLogLevelToolTip
        Categories := array{McpCategory}
        MinValue := option{0}
        MaxValue := option{3}
    LogLevel<public>:int = 1
    # 返事の行をクライアントの画面にも出す秒数（0 ならログだけ。Print は既定で 2 秒画面に出るので、0 にしてプレイの邪魔をしない）。既定 0
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
    # 1 つの返事の文字数の上限（これを超える返事は too_large にする）
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

    # ---- 外から ----

    # ラウンドの途中（始まってから終わるまで）なら成功する。round manager が無ければ失敗する
    IsInRound<public>()<transacts><decides>:void =
        InRound?

    # 今のラウンドの番号（round manager が無ければ 0）
    GetRoundNumber<public>()<transacts>:int =
        if (Manager := RoundManager?) then Manager.RoundNumber else 0

    # 今のフレームの番号（受け箱が始まってから数えた数）
    GetFrame<public>()<transacts>:int = Frame

    # ログの詳しさ（0〜3）
    GetLogLevel<public>()<transacts>:int = Level

    # ログの詳しさを変える（0〜3 に丸める）
    SetLogLevel<public>(NewLevel:int)<transacts>:void =
        set Level = Clamp(NewLevel, 0, 3)

    # Level 以下の詳しさなら「[mcp_inbox_component] Text」を Print する（Quiet なら出さない）
    Log<public>(AtLevel:int, Text:string)<transacts>:void =
        if (AtLevel <= Level, not Quiet?):
            Print("[mcp_inbox_component] {Text}", ?Duration := ScreenSeconds)

    # 長くかかるツールが終わったときの知らせを出す（このフレームの返事の行に入る）。Data は JSON（空なら付けない）
    Notify<public>(EventName:string, Seq:int, Data:string)<transacts>:void =
        var Fields:[]string = array{McpField("event", McpQuote(EventName)), McpField("seq", "{Seq}")}
        if (Data <> ""):
            set Fields += array{McpDataField(Data)}
        set Fields += array{McpField("f", "{Frame}"), McpField("t", McpNumber(GetSimulationElapsedTime()))}
        AddToBatch(McpObject(Fields))

    # entity の番号（このセッションの中で変わらない。entity.find などの "id"）。初めての entity なら番号を付ける
    GetHandle<public>(Target:entity)<transacts>:int =
        if (Known := EntityHandles[Target]):
            Known
        else:
            Handle := NextHandle
            set NextHandle += 1
            if (set EntityHandles[Target] = Handle) {}
            if (set HandleEntities[Handle] = Target) {}
            Handle

    # 番号 Handle の entity。知らない番号なら失敗する
    FindHandleEntity<public>(Handle:int)<transacts><decides>:entity =
        HandleEntities[Handle]

    # mcp_name_component の名前が Name の entity（世界から。並び順は決まらない）
    FindNamed<public>(Name:string)<transacts>:[]entity =
        if (World := Entity.GetSimulationEntity[]):
            for (Found : World.FindDescendantEntitiesWithTag(mcp_name_tag), Found.GetMcpName() = Name):
                Found
        else:
            array{}

    # 引数の値から entity を探す（番号・数の文字列・名前・{"id":..}・{"name":..}）。見つからなければ失敗する
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

    # 名前を付けたタグの一覧（受け箱が知っているもの ＋ mcp_controllable_tag の entity の mcp_tag_provider が知らせたもの）
    GetTagEntries<public>()<transacts>:[]mcp_tag_entry =
        var Entries:[]mcp_tag_entry = array:
            McpTagEntry("mcp_controllable_tag", mcp_controllable_tag)
            McpTagEntry("mcp_name_tag", mcp_name_tag)
            McpTagEntry("mcp_session_restorable_tag", mcp_session_restorable_tag)
        if (World := Entity.GetSimulationEntity[]):
            for (Tagged : World.FindDescendantEntitiesWithTag(mcp_controllable_tag), Component : Tagged.GetComponents(), Provider := mcp_tag_provider[Component]):
                set Entries += Provider.McpTagEntries()
        Entries

    # 名前 Name のタグ。知らない名前なら失敗する
    FindTagEntry<public>(Name:string)<transacts><decides>:mcp_tag_entry =
        Found := for (Entry : GetTagEntries(), Entry.Name = Name) { Entry }
        Found[0]

    # 今の受け口（mcp_controllable）をすべて（集め直す）
    GetControllables<public>()<transacts>:[]mcp_controllable =
        Rescan()
        for (Target : Targets) { Target.Controllable }

    # 命令 1 つ（{"seq":..,"to":..,"tool":..,"args":..}。seq は省略でき、無ければ 1）をその場で実行して、返事の JSON を返す（Print しない。重複の扱い・連番は見ない）
    #   ゲームのコードやテストから、MCP と同じ形で受け口を呼ぶときに使う。読めない JSON なら bad_json / bad_command の返事
    ExecuteJson<public>(CommandJson:string):string =
        if (Root := Parse[CommandJson], O := Root.AsObject[]):
            Seq := if (SeqValue := O["seq"], S := McpValueToInt[SeqValue], S > 0) then S else 1
            To := if (T := O["to"].AsString[]) then T else ""
            Tool := if (X := O["tool"].AsString[]) then X else if (X := O["cmd"].AsString[]) then X else ""
            Args:?value = if (A := O["args"]) then option{A} else false
            RunCommand(mcp_command{Seq := Seq, To := To, Tool := Tool, Args := Args})
        else:
            "\{\"seq\":-1,\"ok\":false,\"error\":\"bad_json\",\"reply\":\"bad_json\"\}"

    # ---- 読む ----

    # 新しい命令を Todo に積む。重複には（1 秒に 1 回まで）覚えている返事を返す
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

    # Todo から MaxPerFrame 件まで実行し、このフレームの返事を 1 行で出す
    Step<private>():void =
        var Ran:int = 0
        var Rest:[]mcp_command = array{}
        for (C : Todo):
            if (Ran < MaxPerFrame and BatchChars < MaxLineChars):
                Json := RunCommand(C)
                set Ran += 1
                set DoneSeq = C.Seq
                if (set Replies[C.Seq] = Json) {}
                # 出したばかりの返事は 1 秒（30 フレーム）は出し直さない（送り手がまだ読んでいないだけのことが多い）
                if (set ReEmitFrame[C.Seq] = Frame) {}
                AddToBatch(Json)
            else:
                set Rest += array{C}
        set Todo = Rest
        Flush()
        # 古い返事を忘れる（直近 256 件だけ残す）
        if (Replies[DoneSeq - 256]):
            var Kept:[int]string = map{}
            for (Key -> Json : Replies, Key > DoneSeq - 256):
                if (set Kept[Key] = Json) {}
            set Replies = Kept
            set ReEmitFrame = map{}

    # ---- 返事を出す ----

    Emit<private>(Line:string)<transacts>:void =
        if (not Quiet?):
            Print("[MCPC] {Line}", ?Duration := ScreenSeconds)

    # 返事・知らせを今のフレームの行に足す。1 つで行に入らない大きさなら分けて出す
    AddToBatch<private>(Json:string)<transacts>:void =
        if (Json.Length > MaxReplyChars):
            # 大きすぎる返事は出さない（Print の行が多すぎて間引かれ、送り手が待ち続けるのを避ける）
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

    # 大きい JSON を分けて出す：[MCPC] ~<chunk_id>:<part>:<parts>:<JSON の一部をそのまま>（逃がさない。返事の JSON に改行は無いので 1 行に収まる）
    #   送り手は part の順につないで読む。UTF-8 の文字の途中で切らないよう、ASCII の文字の前で切る
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

    # ---- 実行する ----

    # 宛先に渡して返事の JSON を作る
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

    # 1 つの受け口でツールを実行する（ツールの有無・省略できない引数を先に確かめる）
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

    # 省略できない引数のうち、無いものの名前。全部あれば失敗する
    FindMissingArg<private>(Call:mcp_call, Tool:mcp_tool)<transacts><decides>:string =
        Missing := for (Arg : Tool.Args, Arg.Required?, not Call.HasArg[Arg.Name]) { Arg.Name }
        Missing[0]

    # "widget@main" → ("widget", "main")、"widget" → ("widget", "")
    SplitTarget<private>(To:string)<transacts>:tuple(string, string) =
        if (At := McpFindChar[To, '@']):
            (McpSlice(To, 0, At), McpSlice(To, At + 1, To.Length))
        else:
            (To, "")

    # Toolset（と Id）に合う受け口。見つからなければ集め直してもう一度探す
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

    # タグの entity の component から mcp_controllable を集める
    Rescan<private>()<transacts>:void =
        set ScannedAt = GetSimulationElapsedTime()
        if (World := Entity.GetSimulationEntity[]):
            set Targets = for (Tagged : World.FindDescendantEntitiesWithTag(mcp_controllable_tag), Component : Tagged.GetComponents(), Controllable := mcp_controllable[Component]):
                mcp_target{Component := Component, Controllable := Controllable}
        else:
            set Targets = array{}

    # ---- Core ツールセット（宛先 "core"。"inbox" でもよい） ----

    CoreTools<private>()<transacts>:[]mcp_tool =
        array:
            McpTool("ping", "受け箱が動いているか（pong を返す）", array{})
            McpTool("echo", "引数をそのまま返す（text か、並びの引数を空白でつないだもの）", array{McpOptArg("text", "string", "返す文字")})
            McpTool("describe", "ツールセットとツールの一覧（引数の説明つき）。data に JSON", array{McpOptArg("toolset", "string", "このツールセットだけ")})
            McpTool("list", "受け口（ツールセット）の一覧。data に [\{toolset,id,tools\}]", array{})
            McpTool("status", "受け箱の状態（処理済みの seq・待ち・フレーム・受け口の数・ログの詳しさ）", array{})
            McpTool("time", "シミュレーションの秒・UTC の Unix 時刻・フレーム", array{})
            McpTool("round", "ラウンドの途中か・番号", array{})
            McpTool("players", "プレイヤーの一覧（番号・キャラクターの有無・位置 cm）。ほかのツールの player はこの番号", array{})
            McpTool("tags", "名前を付けたタグの一覧（entity.find / player.has_tag などで使える名前）", array{})
            McpTool("batch", "命令の配列を同じフレームで順に実行する。data に返事の配列", array{McpArg("cmds", "json", "[\{to,tool,args\}, ...]（seq は要らない。core.batch は入れられない）")})

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

# 受け口 1 つの説明（{"toolset","id","tools":[...]}）
McpToolsetJson<public>(Controllable:mcp_controllable)<transacts>:string =
    McpObject(array{McpField("toolset", McpQuote(Controllable.McpToolset())), McpField("id", McpQuote(Controllable.McpId())),
        McpField("tools", McpArray(for (T : Controllable.McpTools()) { T.ToJson() }))})

# 複数の受け口に届いたときの 1 つ分の結果
McpResultJson<internal>(Controllable:mcp_controllable, Reply:mcp_reply)<transacts>:string =
    Name := if (Controllable.McpId() = "") then Controllable.McpToolset() else "{Controllable.McpToolset()}@{Controllable.McpId()}"
    var Fields:[]string = array{McpField("to", McpQuote(Name)), McpField("ok", McpLogic(Reply.Ok)), McpField("reply", McpQuote(Reply.Text))}
    if (Reply.Data <> ""):
        set Fields += array{McpDataField(Reply.Data)}
    McpObject(Fields)

# "data":<JSON> の項目。Data が JSON として読めなければ、文字列として載せて "data_error":true を足す
McpDataField<internal>(Data:string)<transacts>:string =
    if (Parse[Data]):
        McpField("data", Data)
    else:
        "{McpField("data", McpQuote(Data))},{McpField("data_error", "true")}"

# 最初の空白までの語
McpFirstWord<internal>(Text:string)<transacts>:string =
    if (Space := McpFindChar[Text, ' ']) then McpSlice(Text, 0, Space) else Text

# 大きい返事を分けるとき、この文字の前で切ってよい（ASCII。UTF-8 の文字の途中ではない）
IsSafeSplitChar<internal>(C:char)<transacts><decides>:void =
    var Found:logic = false
    for (S : " ,:{}[]\"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ._-", S = C):
        set Found = true
    Found?
