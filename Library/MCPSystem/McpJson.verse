using { /Verse.org/SpatialMath }

# JSON helpers for MCPSystem. Verse in v43.00 has no function that writes JSON (/UnrealEngine.com/JSON only has Parse and value.As*), so replies are built as strings
# The reader (Python) uses json.loads(..., strict=False) (only " \ newline, tab and carriage return are escaped)

# Makes the body of a JSON string (escapes " \ newline, tab and carriage return; the surrounding " are not added)
#   Appending a long string one character at a time with += is O(n^2) (seconds for 100k characters), and Concatenate recurses internally and hits a runtime error at 100k characters (ErrRuntime_InfiniteLoop; confirmed in UEFN v43.00)
#   -> split into 256-character blocks, keep blocks without escapable characters as they are, escape only the others character by character, and join with McpJoinTree (pairwise, O(n log n))
McpEscape<public>(S:string)<transacts>:string =
    if (not McpHasEscapeChar[S]):
        return S
    BlockChars := 256
    Blocks := if (Q := Quotient[S.Length + BlockChars - 1, BlockChars]) then Q else 0
    Parts := for (Index := 0..Blocks - 1):
        Block := McpSlice(S, Index * BlockChars, BlockChars)
        if (McpHasEscapeChar[Block]) then McpEscapeSmall(Block) else Block
    McpJoinTree(Parts)

# Succeeds when an escapable character (" \ newline, carriage return, tab) is present
McpHasEscapeChar<internal>(S:string)<transacts><decides>:void =
    var Found:logic = false
    for (C : S, not Found?):
        if (C = '"' or C = '\\' or C = '\n' or C = '\r' or C = '\t'):
            set Found = true
    Found?

# Escapes a short string character by character
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

# Joins Parts (adds neighbours pairwise until one remains; O(n log n) overall. Faster than Concatenate and never recurses deeply)
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

# JSON string (escaped and wrapped in ")
McpQuote<public>(S:string)<transacts>:string =
    "\"{McpEscape(S)}\""

# JSON number (null when not finite; NaN and infinity cannot be written in JSON)
McpNumber<public>(F:float)<transacts>:string =
    if (F.IsFinite[]) then "{F}" else "null"

# JSON integer
McpInteger<public>(I:int)<transacts>:string =
    "{I}"

# JSON true / false
McpLogic<public>(L:logic)<transacts>:string =
    if (L?) then "true" else "false"

# Position / direction vector (Verse axes: {"left":..,"up":..,"forward":..}. The caller decides the unit; cm for positions)
McpVector<public>(V:vector3)<transacts>:string =
    "\{\"left\":{McpNumber(V.Left)},\"up\":{McpNumber(V.Up)},\"forward\":{McpNumber(V.Forward)}\}"

# Rotation ({"yaw":..,"pitch":..,"roll":..}, degrees)
McpRotation<public>(R:rotation)<transacts>:string =
    Angles := R.GetYawPitchRollDegrees()
    "\{\"yaw\":{McpNumber(Angles(0))},\"pitch\":{McpNumber(Angles(1))},\"roll\":{McpNumber(Angles(2))}\}"

# One "key":value field (Json is already written as a JSON value; build it with McpQuote / McpNumber etc.)
McpField<public>(Key:string, Json:string)<transacts>:string =
    "{McpQuote(Key)}:{Json}"

# Object made of fields (built with McpField)
McpObject<public>(Fields:[]string)<transacts>:string =
    "\{{McpJoin(Fields, ",")}\}"

# Array of values (JSON)
McpArray<public>(Items:[]string)<transacts>:string =
    "[{McpJoin(Items, ",")}]"

# Turns a string array into a JSON array of strings
McpStringArray<public>(Items:[]string)<transacts>:string =
    McpArray(for (Item : Items) { McpQuote(Item) })

# Joins Items with Separator
McpJoin<public>(Items:[]string, Separator:string)<transacts>:string =
    McpJoinTree(for (Index -> Item : Items) { if (Index > 0) then Separator + Item else Item })

# Parses a decimal string into an int (signed, up to 18 digits). Fails on non-digit characters, empty input or too many digits (never a runtime error on out-of-range values)
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

# Parses a decimal string ("12", "-3.25", "0.5"; exponent notation is not read) into a float. Fails when unreadable
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

# Maps '0'-'9' to 0-9. Fails for a non-digit
McpDigit<public>(C:char)<transacts><decides>:int =
    var R:int = -1
    for (Index -> D : "0123456789"):
        if (D = C):
            set R = Index
    R >= 0
    R

# Converts a float to an int (fractions truncate toward 0). Fails when not finite or beyond +-9.0e15 (Floor[] / Int[] raise a runtime error instead of failing on out-of-range values, so the range is checked first)
McpFloatToInt<public>(F:float)<transacts><decides>:int =
    F.IsFinite[]
    F > -9.0e15
    F < 9.0e15
    if (F >= 0.0) then Floor[F] else Ceil[F]

# Position of the first C in string S. Fails when absent
McpFindChar<public>(S:string, C:char)<transacts><decides>:int =
    var Found:int = -1
    for (Index -> X : S, Found < 0, X = C):
        set Found = Index
    Found >= 0
    Found

# Count characters of S from Start (clamped to the string)
McpSlice<public>(S:string, Start:int, Count:int)<transacts>:string =
    Begin := Clamp(Start, 0, S.Length)
    End := Clamp(Start + Count, Begin, S.Length)
    if (Part := S.Slice[Begin, End]) then Part else ""
