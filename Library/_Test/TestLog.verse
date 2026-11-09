using { /Verse.org/Simulation }
using { /Verse.org/Concurrency }

# Role: count the results of a verification test and write them to the log. Create one per test (component)
# Output: every Check / Pass / Fail Prints "[PASS] Name: item" or "[FAIL] Name: item (detail)", and Finish Prints "[TEST] Name: n passed, m failed". Search the output log for [FAIL] to see only the failures
test_log<public> := class<unique>:

    # Name of the test (prefixed to every log line)
    Name<public>:string

    var<private> Passed:int = 0
    var<private> Failed:int = 0

    # Count as a success
    Pass<public>(Label:string):void =
        set Passed += 1
        Print("[PASS] {Name}: {Label}")

    # Count as a failure. Put the expected and actual values etc. in Detail
    Fail<public>(Label:string, Detail:string):void =
        set Failed += 1
        Print("[FAIL] {Name}: {Label} ({Detail})")

    # Count as a success when Ok is true, as a failure when false
    Check<public>(Label:string, Ok:logic):void =
        if (Ok?):
            Pass(Label)
        else:
            Fail(Label, "false")

    # Success when Actual equals Expected
    CheckInt<public>(Label:string, Actual:int, Expected:int):void =
        if (Actual = Expected):
            Pass(Label)
        else:
            Fail(Label, "expected {Expected}, got {Actual}")

    # Success when Actual is within Tolerance of Expected
    CheckFloat<public>(Label:string, Actual:float, Expected:float, Tolerance:float):void =
        if (Abs(Actual - Expected) <= Tolerance):
            Pass(Label)
        else:
            Fail(Label, "expected {Expected} +- {Tolerance}, got {Actual}")

    # Print the summary. Succeeds when there are no failures
    Finish<public>()<decides><transacts>:void =
        Print("[TEST] {Name}: {Passed} passed, {Failed} failed")
        Failed = 0

    GetFailedCount<public>()<transacts>:int = Failed

# Await Event for up to Seconds. Returns its payload when it arrives, false otherwise (tests use it to check "a notification arrives within N seconds")
AwaitWithin<public>(Event:listenable(t), Seconds:float where t:type)<suspends>:?t =
    race:
        block:
            Payload := Event.Await()
            option{Payload}
        block:
            Sleep(Seconds)
            false
