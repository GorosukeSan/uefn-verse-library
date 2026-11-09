using { /Verse.org/Simulation }
using { /Verse.org/Concurrency }

# 役割：動作確認テストの結果を数えてログに出す。1 つのテスト（component）につき 1 つ作る
# 出力：Check / Pass / Fail のたびに「[PASS] 名前: 項目」「[FAIL] 名前: 項目（詳細）」、Finish で「[TEST] 名前: n passed, m failed」を Print する。出力ログを [FAIL] で検索すれば失敗だけが分かる
test_log<public> := class<unique>:

    # テストの名前（ログの頭に付く）
    Name<public>:string

    var<private> Passed:int = 0
    var<private> Failed:int = 0

    # 成功として数える
    Pass<public>(Label:string):void =
        set Passed += 1
        Print("[PASS] {Name}: {Label}")

    # 失敗として数える。Detail に期待値と実際の値などを書く
    Fail<public>(Label:string, Detail:string):void =
        set Failed += 1
        Print("[FAIL] {Name}: {Label} ({Detail})")

    # Ok が true なら成功、false なら失敗として数える
    Check<public>(Label:string, Ok:logic):void =
        if (Ok?):
            Pass(Label)
        else:
            Fail(Label, "false")

    # Actual と Expected が同じなら成功
    CheckInt<public>(Label:string, Actual:int, Expected:int):void =
        if (Actual = Expected):
            Pass(Label)
        else:
            Fail(Label, "expected {Expected}, got {Actual}")

    # Actual と Expected の差が Tolerance 以下なら成功
    CheckFloat<public>(Label:string, Actual:float, Expected:float, Tolerance:float):void =
        if (Abs(Actual - Expected) <= Tolerance):
            Pass(Label)
        else:
            Fail(Label, "expected {Expected} +- {Tolerance}, got {Actual}")

    # まとめを出す。失敗が 0 なら成功する
    Finish<public>()<decides><transacts>:void =
        Print("[TEST] {Name}: {Passed} passed, {Failed} failed")
        Failed = 0

    GetFailedCount<public>()<transacts>:int = Failed

# Event を Seconds 秒まで待つ。届けばその中身、届かなければ false を返す（テストで「〜秒以内に知らせが来る」を確かめる）
AwaitWithin<public>(Event:listenable(t), Seconds:float where t:type)<suspends>:?t =
    race:
        block:
            Payload := Event.Await()
            option{Payload}
        block:
            Sleep(Seconds)
            false
