# 実時刻（エポック秒）を扱うための、状態を持たない補助。整数で計算し、float の精度に頼らない
# 「日」は常に 86400 秒（暦の月・年は使わない。残り日数を年月日に分けてから足し戻すと 1〜2 日ずれるため）

# 1 日の秒数
SecondsPerDay<public>:int = 86400
# 1 時間の秒数
SecondsPerHour<public>:int = 3600
# 1 分の秒数
SecondsPerMinute<public>:int = 60
# 時間帯の既定のずれ（秒）。日本標準時 = UTC+9 時間（夏時間は無い）
DefaultTimeZoneOffsetSeconds<public>:int = 32400

# Value を切り捨てた整数。Floor が失敗する値（無限・NaN）は 0
FloorToInt<internal>(Value:float)<transacts>:int =
    Floor[Value] or 0

# Value を切り上げた整数。ほぼ整数の値（誤差 0.001 未満）はその整数にする。Ceil が失敗する値は 0
CeilToInt<internal>(Value:float)<transacts>:int =
    Ceil[Value - 0.001] or 0

# 残り秒数（小数）を切り上げた整数（表示に使う値）にする。0 以下は 0（残り 0.3 秒は「1」と出す。0 になった瞬間に終わる）。名前の決まり：小数の秒は …Seconds、切り上げた整数の秒は …WholeSeconds
ToWholeSeconds<public>(Seconds:float)<transacts>:int =
    if (Seconds <= 0.0):
        0
    else:
        CeilToInt(Seconds)

# EpochSeconds の時点が、時間帯 TimeZoneOffsetSeconds での「何日目」か（1970-01-01 の現地 0 時からの日数）。現地の 0 時で切り替わる
GetDayIndex<public>(EpochSeconds:float, TimeZoneOffsetSeconds:int)<transacts>:int =
    FloorToInt((EpochSeconds + TimeZoneOffsetSeconds * 1.0) / (SecondsPerDay * 1.0))

# EpochSeconds の時点の、時間帯 TimeZoneOffsetSeconds での現地 0 時からの経過秒（0 以上 86400 未満）
GetSecondsOfDay<public>(EpochSeconds:float, TimeZoneOffsetSeconds:int)<transacts>:float =
    Local := EpochSeconds + TimeZoneOffsetSeconds * 1.0
    Local - GetDayIndex(EpochSeconds, TimeZoneOffsetSeconds) * (SecondsPerDay * 1.0)

# 現地の「何日目」DayIndex の現地 0 時を、エポック秒で返す
GetDayStartSeconds<public>(DayIndex:int, TimeZoneOffsetSeconds:int)<computes>:float =
    DayIndex * (SecondsPerDay * 1.0) - TimeZoneOffsetSeconds * 1.0

# FromSeconds から ToSeconds までの丸 1 日の数（86400 秒ごとに 1。切り捨て）。45 日と少しなら 45
DaysBetween<public>(FromSeconds:float, ToSeconds:float)<transacts>:int =
    FloorToInt((ToSeconds - FromSeconds) / (SecondsPerDay * 1.0))

# 時・分・秒を現地の 0 時からの秒数にする（20:00:00 なら 72000）
MakeSecondsOfDay<public>(Hour:int, Minute:int, Second:int)<computes>:int =
    Hour * SecondsPerHour + Minute * SecondsPerMinute + Second

# TotalSeconds 秒を日・時・分・秒に分ける（すべて 0 以上の整数。負の値は 0 として扱う）
split_seconds<public> := struct:
    # 丸 1 日の数
    Days<public>:int = 0
    # 日を除いた時（0〜23）
    Hours<public>:int = 0
    # 分（0〜59）
    Minutes<public>:int = 0
    # 秒（0〜59）
    Seconds<public>:int = 0

# TotalSeconds 秒を日・時・分・秒に分ける。負の値は 0 とする
SplitSeconds<public>(TotalSeconds:int)<transacts>:split_seconds =
    Total := Max(TotalSeconds, 0)
    Days := Quotient[Total, SecondsPerDay] or 0
    Rest := Mod[Total, SecondsPerDay] or 0
    Hours := Quotient[Rest, SecondsPerHour] or 0
    Rest2 := Mod[Rest, SecondsPerHour] or 0
    Minutes := Quotient[Rest2, SecondsPerMinute] or 0
    Seconds := Mod[Rest2, SecondsPerMinute] or 0
    split_seconds{Days := Days, Hours := Hours, Minutes := Minutes, Seconds := Seconds}

# 0〜99 を 2 桁の文字列にする（7 → "07"）。100 以上はそのまま
PadTwoDigits<internal>(Value:int)<computes>:string =
    if (Value >= 0 and Value < 10):
        "0{Value}"
    else:
        "{Value}"

# TotalSeconds 秒を "HH:MM:SS" にする（時は 24 を超えてもそのまま。負の値は 0 秒）
FormatHoursMinutesSeconds<public>(TotalSeconds:int)<transacts>:string =
    Split := SplitSeconds(TotalSeconds)
    Hours := Split.Days * 24 + Split.Hours
    "{PadTwoDigits(Hours)}:{PadTwoDigits(Split.Minutes)}:{PadTwoDigits(Split.Seconds)}"

# TotalSeconds 秒を "MM:SS" にする（分は 60 を超えてもそのまま。負の値は 0 秒）
FormatMinutesSeconds<public>(TotalSeconds:int)<transacts>:string =
    Split := SplitSeconds(TotalSeconds)
    Minutes := (Split.Days * 24 + Split.Hours) * 60 + Split.Minutes
    "{PadTwoDigits(Minutes)}:{PadTwoDigits(Split.Seconds)}"

# TotalSeconds 秒を "Dd HH:MM:SS" にする（1 日と 1 時間 1 分 1 秒なら "1d 01:01:01"。負の値は 0 秒）
FormatDaysHoursMinutesSeconds<public>(TotalSeconds:int)<transacts>:string =
    Split := SplitSeconds(TotalSeconds)
    "{Split.Days}d {PadTwoDigits(Split.Hours)}:{PadTwoDigits(Split.Minutes)}:{PadTwoDigits(Split.Seconds)}"

# TotalSeconds 秒を丸 1 日の数にする（切り捨て。負の値は 0）。「あと N 日」の N
FormatDays<public>(TotalSeconds:int)<transacts>:string =
    "{SplitSeconds(TotalSeconds).Days}"

# 10 の Exponent 乗（Exponent が 0 以下なら 1）。整数のまま計算する
PowerOfTen<internal>(Exponent:int)<transacts>:int =
    var Result:int = 1
    for (Index := 0..Exponent - 1):
        set Result *= 10
    Result

# Value の Digit 桁目（1 = 一の位、2 = 十の位）の数字（0〜9）。Value が負なら絶対値で見る
GetDigit<public>(Value:int, Digit:int)<transacts>:int =
    Divisor := PowerOfTen(Digit - 1)
    Mod[Quotient[Abs(Value), Divisor] or 0, 10] or 0

# Value の Digit 桁目が「先頭の 0」（それより上の桁も含めて値が無い）なら成功する。一の位は失敗する
IsLeadingZero<public>(Value:int, Digit:int)<decides><transacts>:void =
    Digit > 1
    Abs(Value) < PowerOfTen(Digit - 1)
