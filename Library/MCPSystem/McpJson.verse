using { /Verse.org/SpatialMath }

# MCPSystem の JSON の小道具。v43.00 の Verse には JSON を書き出す関数が無い（/UnrealEngine.com/JSON は Parse と value.As* だけ）ので、返事は文字列で組み立てる
# 読む側（Python）は json.loads(..., strict=False) で読む（制御文字は " \ 改行 タブ 復帰 だけを逃がす）

# JSON の文字列の中身にする（" と \ と改行・タブ・復帰を逃がす。囲みの " は付けない）
#   長い文字列を 1 文字ずつ += でつなぐと O(n^2)（10 万文字で数秒）、Concatenate は中で再帰していて 10 万文字で実行時エラー（ErrRuntime_InfiniteLoop。v43.00 実機）になる
#   → 256 文字ずつの塊に分け、逃がす文字の無い塊はそのまま、ある塊だけ 1 文字ずつ逃がし、McpJoinTree（2 つずつ足す。O(n log n)）でつなぐ
McpEscape<public>(S:string)<transacts>:string =
    if (not McpHasEscapeChar[S]):
        return S
    BlockChars := 256
    Blocks := if (Q := Quotient[S.Length + BlockChars - 1, BlockChars]) then Q else 0
    Parts := for (Index := 0..Blocks - 1):
        Block := McpSlice(S, Index * BlockChars, BlockChars)
        if (McpHasEscapeChar[Block]) then McpEscapeSmall(Block) else Block
    McpJoinTree(Parts)

# 逃がす文字（" \ 改行 復帰 タブ）があれば成功する
McpHasEscapeChar<internal>(S:string)<transacts><decides>:void =
    var Found:logic = false
    for (C : S, not Found?):
        if (C = '"' or C = '\\' or C = '\n' or C = '\r' or C = '\t'):
            set Found = true
    Found?

# 短い文字列を 1 文字ずつ逃がす
McpEscapeSmall<internal>(S:string)<transacts>:string =
    var Out:string = ""
    for (C : S):
        if (C = '"'):
            set Out += "\\\""
        else if (C = '\\'):
            set Out += "\\\\"
        else if (C = '\n'):
            set Out += "\\n"
        else if (C = '\r'):
            set Out += "\\r"
        else if (C = '\t'):
            set Out += "\\t"
        else:
            set Out += array{C}
    Out

# Parts をつなぐ（隣どうしを 2 つずつ足すのを 1 つになるまで繰り返す。全体で O(n log n)。Concatenate より速く、深い再帰にならない）
McpJoinTree<public>(Parts:[]string)<transacts>:string =
    var Level:[]string = Parts
    loop:
        if (Level.Length <= 1):
            break
        Half := if (H := Quotient[Level.Length + 1, 2]) then H else 1
        Current := Level
        set Level = for (Index := 0..Half - 1):
            First := if (A := Current[Index * 2]) then A else ""
            Second := if (B := Current[Index * 2 + 1]) then B else ""
            First + Second
    if (Only := Level[0]) then Only else ""

# JSON の文字列（" で囲んで逃がす）
McpQuote<public>(S:string)<transacts>:string =
    "\"{McpEscape(S)}\""

# JSON の数（有限でなければ null。NaN・∞ は JSON に書けない）
McpNumber<public>(F:float)<transacts>:string =
    if (F.IsFinite[]) then "{F}" else "null"

# JSON の整数
McpInteger<public>(I:int)<transacts>:string =
    "{I}"

# JSON の true / false
McpLogic<public>(L:logic)<transacts>:string =
    if (L?) then "true" else "false"

# 位置・向きのベクトル（Verse の軸。{"left":..,"up":..,"forward":..}。単位は呼ぶ側で決める。位置なら cm）
McpVector<public>(V:vector3)<transacts>:string =
    "\{\"left\":{McpNumber(V.Left)},\"up\":{McpNumber(V.Up)},\"forward\":{McpNumber(V.Forward)}\}"

# 回転（{"yaw":..,"pitch":..,"roll":..}。度）
McpRotation<public>(R:rotation)<transacts>:string =
    Angles := R.GetYawPitchRollDegrees()
    "\{\"yaw\":{McpNumber(Angles(0))},\"pitch\":{McpNumber(Angles(1))},\"roll\":{McpNumber(Angles(2))}\}"

# "key":値 の 1 項目（Json は JSON の値として書いたもの。McpQuote / McpNumber などで作る）
McpField<public>(Key:string, Json:string)<transacts>:string =
    "{McpQuote(Key)}:{Json}"

# 項目（McpField で作ったもの）を並べたオブジェクト
McpObject<public>(Fields:[]string)<transacts>:string =
    "\{{McpJoin(Fields, ",")}\}"

# 値（JSON）を並べた配列
McpArray<public>(Items:[]string)<transacts>:string =
    "[{McpJoin(Items, ",")}]"

# 文字列の配列を JSON の文字列の配列にする
McpStringArray<public>(Items:[]string)<transacts>:string =
    McpArray(for (Item : Items) { McpQuote(Item) })

# Items を Separator でつなぐ
McpJoin<public>(Items:[]string, Separator:string)<transacts>:string =
    McpJoinTree(for (Index -> Item : Items) { if (Index > 0) then Separator + Item else Item })

# 10 進の文字列を int にする（符号つき、18 桁まで）。数字でない文字・空・桁が多すぎるなら失敗する（範囲を超える値で実行時エラーにしない）
McpParseInt<public>(S:string)<transacts><decides>:int =
    S.Length > 0
    S.Length <= 19
    var Neg:logic = false
    var N:int = 0
    var Digits:int = 0
    var Bad:int = 0
    for (Index -> C : S):
        if (Index = 0, C = '-'):
            set Neg = true
        else if (Index = 0, C = '+'):
            set Neg = false
        else if (Digits < 18, D := McpDigit[C]):
            set N = N * 10 + D
            set Digits += 1
        else:
            set Bad += 1
    Digits > 0
    Bad = 0
    if (Neg?) then -N else N

# 10 進の小数の文字列（"12"・"-3.25"・"0.5"。指数の表記は読まない）を float にする。読めなければ失敗する
McpParseFloat<public>(S:string)<transacts><decides>:float =
    S.Length > 0
    S.Length <= 40
    var Neg:logic = false
    var Whole:float = 0.0
    var Frac:float = 0.0
    var Scale:float = 1.0
    var InFrac:logic = false
    var Digits:int = 0
    var Bad:int = 0
    for (Index -> C : S):
        if (Index = 0, C = '-'):
            set Neg = true
        else if (Index = 0, C = '+'):
            set Neg = false
        else if (C = '.', not InFrac?):
            set InFrac = true
        else if (D := McpDigit[C]):
            set Digits += 1
            if (InFrac?):
                set Scale = Scale / 10.0
                set Frac += Scale * (D * 1.0)
            else if (Digits <= 18):
                set Whole = Whole * 10.0 + (D * 1.0)
            else:
                set Bad += 1
        else:
            set Bad += 1
    Digits > 0
    Bad = 0
    Value := Whole + Frac
    if (Neg?) then -Value else Value

# '0'〜'9' を 0〜9 にする。数字でなければ失敗する
McpDigit<public>(C:char)<transacts><decides>:int =
    var R:int = -1
    for (Index -> D : "0123456789"):
        if (D = C):
            set R = Index
    R >= 0
    R

# float を int にする（小数は 0 の側へ切る）。有限でない・±9.0e15 を超えるなら失敗する（Floor[] / Int[] は範囲外の値で失敗ではなく実行時エラーになるため、先に範囲を見る）
McpFloatToInt<public>(F:float)<transacts><decides>:int =
    F.IsFinite[]
    F > -9.0e15
    F < 9.0e15
    if (F >= 0.0) then Floor[F] else Ceil[F]

# 文字列 S の中で最初に C がある位置。無ければ失敗する
McpFindChar<public>(S:string, C:char)<transacts><decides>:int =
    var Found:int = -1
    for (Index -> X : S, Found < 0, X = C):
        set Found = Index
    Found >= 0
    Found

# S の Start から Count 文字（範囲外は切り詰める）
McpSlice<public>(S:string, Start:int, Count:int)<transacts>:string =
    Begin := Clamp(Start, 0, S.Length)
    End := Clamp(Start + Count, Begin, S.Length)
    if (Part := S.Slice[Begin, End]) then Part else ""
