# Stateless helpers for real time (epoch seconds). Computed with integers, without relying on float precision
# A "day" is always 86400 seconds (calendar months and years are not used: splitting the remaining days into y/m/d and adding them back drifts by 1-2 days)

# Seconds in a day
SecondsPerDay<public>:int = 86400
# Seconds in an hour
SecondsPerHour<public>:int = 3600
# Seconds in a minute
SecondsPerMinute<public>:int = 60
# Default time zone offset (seconds). Japan Standard Time = UTC+9 hours (no daylight saving time)
DefaultTimeZoneOffsetSeconds<public>:int = 32400

# Value rounded down to an integer. 0 for values where Floor fails (infinity, NaN)
FloorToInt<internal>(Value:float)<transacts>:int =
    Floor[Value] or 0

# Value rounded up to an integer. Values that are almost integers (error under 0.001) become that integer. 0 where Ceil fails
CeilToInt<internal>(Value:float)<transacts>:int =
    Ceil[Value - 0.001] or 0

# Remaining seconds (fraction) rounded up to an integer (the value used for display). 0 or less gives 0 (0.3 s remaining shows "1"; it ends the moment it reaches 0). Naming rule: fractional seconds are ...Seconds, rounded-up integer seconds are ...WholeSeconds
ToWholeSeconds<public>(Seconds:float)<transacts>:int =
    if (Seconds <= 0.0):
        0
    else:
        CeilToInt(Seconds)

# The "day number" of EpochSeconds in time zone TimeZoneOffsetSeconds (days since local midnight of 1970-01-01). Changes at local midnight
GetDayIndex<public>(EpochSeconds:float, TimeZoneOffsetSeconds:int)<transacts>:int =
    FloorToInt((EpochSeconds + TimeZoneOffsetSeconds * 1.0) / (SecondsPerDay * 1.0))

# Seconds since local midnight (0 up to but excluding 86400) of EpochSeconds in time zone TimeZoneOffsetSeconds
GetSecondsOfDay<public>(EpochSeconds:float, TimeZoneOffsetSeconds:int)<transacts>:float =
    Local := EpochSeconds + TimeZoneOffsetSeconds * 1.0
    Local - GetDayIndex(EpochSeconds, TimeZoneOffsetSeconds) * (SecondsPerDay * 1.0)

# Local midnight of local day number DayIndex, in epoch seconds
GetDayStartSeconds<public>(DayIndex:int, TimeZoneOffsetSeconds:int)<computes>:float =
    DayIndex * (SecondsPerDay * 1.0) - TimeZoneOffsetSeconds * 1.0

# Number of whole days from FromSeconds to ToSeconds (1 per 86400 seconds, rounded down). 45 days and a bit gives 45
DaysBetween<public>(FromSeconds:float, ToSeconds:float)<transacts>:int =
    FloorToInt((ToSeconds - FromSeconds) / (SecondsPerDay * 1.0))

# Hour, minute and second as seconds since local midnight (20:00:00 gives 72000)
MakeSecondsOfDay<public>(Hour:int, Minute:int, Second:int)<computes>:int =
    Hour * SecondsPerHour + Minute * SecondsPerMinute + Second

# TotalSeconds split into days, hours, minutes and seconds (all non-negative integers; negative values are treated as 0)
split_seconds<public> := struct:
    # Number of whole days
    Days<public>:int = 0
    # Hours excluding the days (0-23)
    Hours<public>:int = 0
    # Minutes (0-59)
    Minutes<public>:int = 0
    # Seconds (0-59)
    Seconds<public>:int = 0

# Split TotalSeconds into days, hours, minutes and seconds. Negative values count as 0
SplitSeconds<public>(TotalSeconds:int)<transacts>:split_seconds =
    Total := Max(TotalSeconds, 0)
    Days := Quotient[Total, SecondsPerDay] or 0
    Rest := Mod[Total, SecondsPerDay] or 0
    Hours := Quotient[Rest, SecondsPerHour] or 0
    Rest2 := Mod[Rest, SecondsPerHour] or 0
    Minutes := Quotient[Rest2, SecondsPerMinute] or 0
    Seconds := Mod[Rest2, SecondsPerMinute] or 0
    split_seconds{Days := Days, Hours := Hours, Minutes := Minutes, Seconds := Seconds}

# 0-99 as a two-digit string (7 -> "07"). 100 and above are left as is
PadTwoDigits<internal>(Value:int)<computes>:string =
    if (Value >= 0 and Value < 10):
        "0{Value}"
    else:
        "{Value}"

# TotalSeconds as "HH:MM:SS" (hours may exceed 24; negative values are 0 seconds)
FormatHoursMinutesSeconds<public>(TotalSeconds:int)<transacts>:string =
    Split := SplitSeconds(TotalSeconds)
    Hours := Split.Days * 24 + Split.Hours
    "{PadTwoDigits(Hours)}:{PadTwoDigits(Split.Minutes)}:{PadTwoDigits(Split.Seconds)}"

# TotalSeconds as "MM:SS" (minutes may exceed 60; negative values are 0 seconds)
FormatMinutesSeconds<public>(TotalSeconds:int)<transacts>:string =
    Split := SplitSeconds(TotalSeconds)
    Minutes := (Split.Days * 24 + Split.Hours) * 60 + Split.Minutes
    "{PadTwoDigits(Minutes)}:{PadTwoDigits(Split.Seconds)}"

# TotalSeconds as "Dd HH:MM:SS" (1 day, 1 hour, 1 minute and 1 second gives "1d 01:01:01"; negative values are 0 seconds)
FormatDaysHoursMinutesSeconds<public>(TotalSeconds:int)<transacts>:string =
    Split := SplitSeconds(TotalSeconds)
    "{Split.Days}d {PadTwoDigits(Split.Hours)}:{PadTwoDigits(Split.Minutes)}:{PadTwoDigits(Split.Seconds)}"

# TotalSeconds as a number of whole days (rounded down; negative values are 0). The N of "N days left"
FormatDays<public>(TotalSeconds:int)<transacts>:string =
    "{SplitSeconds(TotalSeconds).Days}"

# 10 to the power Exponent (1 when Exponent is 0 or less). Computed in integers
PowerOfTen<internal>(Exponent:int)<transacts>:int =
    var Result:int = 1
    for (Index := 0..Exponent - 1):
        set Result *= 10
    Result

# The digit (0-9) at position Digit of Value (1 = ones, 2 = tens). A negative Value is taken as its absolute value
GetDigit<public>(Value:int, Digit:int)<transacts>:int =
    Divisor := PowerOfTen(Digit - 1)
    Mod[Quotient[Abs(Value), Divisor] or 0, 10] or 0

# Succeeds when digit position Digit of Value is a "leading zero" (no value in that position or above). The ones position fails
IsLeadingZero<public>(Value:int, Digit:int)<decides><transacts>:void =
    Digit > 1
    Abs(Value) < PowerOfTen(Digit - 1)
