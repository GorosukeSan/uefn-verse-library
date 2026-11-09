using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /UnrealEngine.com/JSON }
using { /Fortnite.com/Playspaces }

# 1 つの命令の呼び出し。受け箱が作って mcp_controllable.McpHandle に渡す（利用者は作らない）
#   引数は名前つき（"args":{"entity":3}）でも、並び（"args":[3]。ツールの説明の引数の順）でも読める
#   Find*[] は読めない・範囲外なら失敗する（if の中で使う）。Get*Or は読めなければ既定の値
mcp_call<public> := class<internal>:
    # 命令の連番
    Seq<public>:int
    # 宛先のツールセットとインスタンス（"widget@main" なら "widget" と "main"。インスタンスが無ければ空）
    Toolset<public>:string
    Id<public>:string
    # ツールの名前
    Tool<public>:string
    # 命令を受けた受け箱（番号・名前の表、知らせ、ログの詳しさ）
    Inbox<public>:mcp_inbox_component
    # 名前つきの引数（"args" がオブジェクトのとき）
    Named<internal>:[string]value = map{}
    # 並びの引数（"args" が配列のとき）と、ツールの説明の引数の名前（並びを名前に直すため）
    Positional<internal>:[]value = array{}
    ArgNames<internal>:[]string = array{}

    # 引数 Name の JSON の値。無い・null なら失敗する
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

    # 引数 Name があれば成功する
    HasArg<public>(Name:string)<transacts><decides>:void =
        FindArg[Name]

    # 文字列（数なら数の文字）
    FindString<public>(Name:string)<transacts><decides>:string =
        McpValueToString[FindArg[Name]]

    # 整数（JSON の数・数の文字列。±9.0e15 まで。小数なら 0 の側へ切る）
    FindInt<public>(Name:string)<transacts><decides>:int =
        McpValueToInt[FindArg[Name]]

    # 小数（有限・±1.0e15 まで）
    FindFloat<public>(Name:string)<transacts><decides>:float =
        McpValueToFloat[FindArg[Name]]

    # true / false（"true" "false" "1" "0" "yes" "no" "on" "off" と数。v43 の Verse は JSON の true / false を読めないので、送り手は文字か数で送る）
    FindLogic<public>(Name:string)<transacts><decides>:logic =
        McpValueToLogic[FindArg[Name]]

    # ベクトル（{"left","up","forward"}・{"x","y","z"}（UE の軸。x = forward、y = right = -left、z = up）・[left, up, forward]）。各成分は有限・±1.0e15 まで
    FindVector<public>(Name:string)<transacts><decides>:vector3 =
        McpValueToVector[FindArg[Name]]

    # オブジェクト
    FindObject<public>(Name:string)<transacts><decides>:[string]value =
        FindArg[Name].AsObject[]

    # 配列
    FindArray<public>(Name:string)<transacts><decides>:[]value =
        FindArg[Name].AsArray[]

    # entity（番号（entity.find などの "id"）か、mcp_name_component の名前か、{"id":..} / {"name":..}）。見つからなければ失敗する
    FindEntity<public>(Name:string)<transacts><decides>:entity =
        Inbox.ResolveEntity[FindArg[Name]]

    # プレイヤー（core.players の番号。0 から）。いなければ失敗する
    FindPlayer<public>(Name:string)<transacts><decides>:player =
        Index := FindInt[Name]
        Inbox.Entity.McpGetPlayers()[Index]

    # プレイヤー（agent として）
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

    # 長くかかるツールが終わったときの知らせ（[MCPC] {"event":EventName,"seq":<この命令の seq>,"data":Data}）。Data は JSON（空なら付けない）
    Notify<public>(EventName:string, Data:string)<transacts>:void =
        Inbox.Notify(EventName, Seq, Data)

# ---- JSON の値の読み方（失敗しうる変換はすべて <decides>。範囲外の値で実行時エラーにしない） ----

# 文字列か、数なら数の文字
McpValueToString<public>(V:value)<transacts><decides>:string =
    if (S := V.AsString[]):
        S
    else if (I := McpValueToInt[V], F := V.AsFloat[], F = I * 1.0):
        "{I}"
    else:
        F := McpValueToFloat[V]
        "{F}"

# 整数。JSON の数（±9.0e15 まで。小数は 0 の側へ切る）か、整数の文字列
McpValueToInt<public>(V:value)<transacts><decides>:int =
    if (F := V.AsFloat[]):
        McpFloatToInt[F]
    else if (S := V.AsString[]):
        McpParseInt[S]
    else:
        # AsFloat で読めない数（あれば）。範囲は確かめられないので、文字列にできない int だけ受ける
        V.AsInt[]

# 小数。JSON の数か小数の文字列（有限・±1.0e15 まで）
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

# ベクトル（{"left","up","forward"}・{"x","y","z"}・[left, up, forward]）
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

# ---- プレイヤーの番号 ----

# 今のプレイヤー（playspace の GetPlayers の順。番号は 0 から。人の出入りで変わるので、core.players の返事の番号をそのまま使う）
(InEntity:entity).McpGetPlayers<public>()<transacts>:[]player =
    if (Playspace := InEntity.GetPlayspaceForEntity[]) then Playspace.GetPlayers() else array{}

# Agent の番号。いなければ -1
(InEntity:entity).McpGetPlayerIndex<public>(Agent:agent)<transacts>:int =
    var Found:int = -1
    for (Index -> Player : InEntity.McpGetPlayers(), Found < 0, Player = Agent):
        set Found = Index
    Found
