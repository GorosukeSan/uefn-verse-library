using { /Verse.org/SceneGraph }

# スケジュールの状態
schedule_state<public> := enum:
    # 次の開始を待っている（繰り返しなら、前の回が終わったあともこれ）
    Before
    # 期間中
    Active
    # 終わった（単発だけ。繰り返しにはならない）
    After

# スケジュールの「時刻 T での値」。すべて T から計算で決まり、保存されない（途中参加・サーバの再起動でも同じ値になる）
# 毎秒 1 回作られ、StateChangedEvent / SecondEvent / schedule_state_changed_event で配られる
schedule_snapshot<public> := struct:
    # 計算に使った時刻（エポック秒。デバッグのずらしを含む）
    NowSeconds<public>:float = 0.0
    # 状態
    State<public>:schedule_state = schedule_state.Before
    # 回の番号。毎日なら「現地の何日目」、一定間隔なら最初の回を 0 とした回数、単発なら 0。Before では次に来る回、Active では今の回、After では最後の回
    CycleIndex<public>:int = 0
    # CycleIndex の回の開始時刻（エポック秒）
    CycleStartSeconds<public>:float = 0.0
    # 今の回の開始からの経過（秒）。Active 以外は 0
    ElapsedSeconds<public>:float = 0.0
    # 今の回の終わりまで（秒）。Active 以外は 0
    SecondsToEnd<public>:float = 0.0
    # 次の開始まで（秒）。Before なら CycleIndex の回の開始まで、Active なら次の回の開始まで（繰り返しのとき）、無ければ 0
    SecondsToStart<public>:float = 0.0
    # SecondsToStart に意味があるか（次の開始があるか）。単発の Active / After では false
    HasNextStart<public>:logic = false

# Snapshot が Active なら成功する
(Snapshot:schedule_snapshot).IsActive<public>()<decides><computes>:void =
    Snapshot.State = schedule_state.Active

# 2 つの snapshot が「同じ状態・同じ回」なら成功する（StateChangedEvent を出すかの判定に使う）
(Snapshot:schedule_snapshot).IsSameStateAndCycle<public>(Other:schedule_snapshot)<decides><computes>:void =
    Snapshot.State = Other.State
    Snapshot.CycleIndex = Other.CycleIndex

# 表示に使う「残り」の選び方
schedule_remaining_kind<public> := enum:
    # 次の開始までの残り（Active 中は次の回まで。無ければ 0）
    UntilStart
    # Active 中は今の回の終わりまで、それ以外は次の開始までの残り（「開始までを数え、始まったら終わりまでを数える」掲示板）
    UntilEnd

# Kind で選んだ残り秒数（小数。無ければ 0.0）
(Snapshot:schedule_snapshot).GetRemainingSeconds<public>(Kind:schedule_remaining_kind)<computes>:float =
    case (Kind):
        schedule_remaining_kind.UntilStart =>
            if (Snapshot.HasNextStart?) then Snapshot.SecondsToStart else 0.0
        schedule_remaining_kind.UntilEnd =>
            if (Snapshot.State = schedule_state.Active):
                Snapshot.SecondsToEnd
            else if (Snapshot.HasNextStart?):
                Snapshot.SecondsToStart
            else:
                0.0

# スケジュールの状態か回が変わった知らせ（最初の評価でも 1 回届く。Previous は false）
# 方向：schedule_component の entity から下へ（SendDown）
# 送り手：schedule_component。受け手：その entity と子孫（schedule_active_condition・利用者の component）。消費しない
# 前提：Active になるとき・Active から出るときは、この知らせの直後に activated_event / deactivated_event も下へ送られる
schedule_state_changed_event<public> := class(scene_event):
    # 送ったスケジュール
    Schedule<public>:schedule_component
    # 前回の値（最初の評価なら false）
    Previous<public>:?schedule_snapshot
    # 今の値
    Current<public>:schedule_snapshot
