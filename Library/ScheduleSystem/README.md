# ScheduleSystem

実時刻（エポック秒）で決まるスケジュール（毎日 20:00 から 10 分、1 時間ごと、決まった日時に 1 回など）を扱う System です。区画に 1 つの `realtime_clock_component` が毎秒 1 回すべてのスケジュールを評価し、`schedule_component` は状態が変わったときに知らせ、期間（Active）に入る・出るときに起動・停止の合図（`activated_event` / `deactivated_event`）を子孫へ送ります。値はいつも「今の時刻」から計算するので、途中参加・サーバの再起動でも同じ状態になります。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `realtime_clock_component` | 区画（`game_scope_component` の配下）か世界に 1 つ | 実時刻の時計。登録されたスケジュールを、整数秒の境目のすぐあとに 1 回ずつ評価して配る |
| `schedule_component` | スケジュールに合わせて動かすものの親の entity | `Kind` と時刻・長さで期間を決める。状態か回が変わったときに知らせ、Active に入る・出るとき起動・停止の合図を自分と子孫へ送る |
| `schedule_active_condition_component`（ConditionKit） | `game_transition_component` か `condition_all` / `condition_any`（または `ability_grant_condition_component`）の entity の直下。そのうえで `schedule_component` の entity の子孫 | スケジュールが Active のあいだ満たす |
| `schedule_text_component`（DisplayKit） | `schedule_component` の entity かその子孫 | 残り時間を "MM:SS" などの文字にして、変わったときだけ知らせる |
| `schedule_digit_display_component`（DisplayKit） | `schedule_component` の entity の子孫。桁ごとに 1 entity | 残り時間の 1 桁を、子の数字メッシュの表示・非表示で出す |
| `schedule_digit_glyph_component`（DisplayKit） | 数字の形のメッシュを持つ entity。`schedule_digit_display_component` の entity の直下に 0〜9 を並べる | 数字 1 つ分のメッシュの目印 |
| `schedule_countdown_hud_component`（HudKit） | `schedule_component` の entity の子孫 | 開始の `ShowWithinSeconds` 秒前から開始まで、区画の全プレイヤー（途中参加も）の画面にカウントダウンの文字を出す |

Kit の component は、自分の entity か一番近い祖先の `schedule_component` を見ます（`schedule_follower`）。

期間中にシネマティック シーケンス デバイスを再生する `schedule_sequence_component` は、デバイスに依存するので FNDeviceSystem（`FNDeviceSystem/ScheduleKit/`）にあります。置き方は同じく `schedule_component` の entity かその子孫です。

例：「毎日 20:00 から 10 分のイベント」
```
区画（game_scope_component）
├ 時計（realtime_clock_component）
└ 夜のイベント（schedule_component、Kind = Daily、StartHour = 20、DurationSeconds = 600）
  ├ 看板の文字（schedule_text_component）
  ├ カウントダウン（schedule_countdown_hud_component）
  └ 足場（spawner_component など。起動の合図で動き出すもの）
```

## 設定（@editable）
- `realtime_clock_component.TimeZoneOffsetSeconds : int = DefaultTimeZoneOffsetSeconds（32400）` — 現地時刻と UTC のずれ（秒。-50400〜50400）。日本標準時は +9 時間。夏時間は考えない。
- `realtime_clock_component.WakeMarginSeconds : float = 0.02` — 整数秒の境目からどれだけ遅れて起きるか（秒。0〜0.5）。小さすぎると 1 秒ずれることがある。
- `schedule_component.Kind : schedule_kind = Daily` — 繰り返しの種類。`Daily` = 毎日同じ時刻、`FixedInterval` = 基準の時刻から一定間隔、`OneShot` = 1 回だけ。
- `schedule_component.StartHour : int = 20` / `StartMinute : int = 0` / `StartSecond : int = 0` — Daily の開始時刻（現地時刻。時 0〜23、分・秒 0〜59）。
- `schedule_component.DurationSeconds : float = 600.0` — 期間（Active）の長さ（秒。0 以上）。Daily では 86400 未満、FixedInterval では間隔未満にする（それ以上だと常に Active）。
- `schedule_component.IntervalSeconds : float = 3600.0` — FixedInterval の間隔（秒）。0 以下なら 1 回だけ（OneShot と同じ）。
- `schedule_component.EpochAnchorSeconds : float = 0.0` — FixedInterval の基準の時刻、OneShot の開始の時刻（エポック秒）。
- `schedule_component.SendActivation : logic = true` — オンなら Active に入るとき `activated_event`、出るとき `deactivated_event` を自分と子孫へ送る。
- `schedule_text_component.Format : schedule_text_format = MinutesSeconds` — 文字の形。
- `schedule_text_component.RemainingKind : schedule_remaining_kind = UntilEnd` — `UntilStart` は次の開始まで、`UntilEnd` は期間中は終わりまで・それ以外は次の開始まで。
- `schedule_text_component.Prefix : string = ""` — 文字の前に付ける固定の文字列。
- `schedule_text_component.OnlyWhileShown : logic = false` — オンなら `Show` を呼んでから `Hide` までのあいだだけ更新する。
- `schedule_digit_display_component.Digit : int = 1` — 何桁目か（1 = 一の位。1〜9）。
- `schedule_digit_display_component.Field : schedule_time_field = Seconds` — 残り時間のどの部分の桁か。
- `schedule_digit_display_component.RemainingKind : schedule_remaining_kind = UntilEnd`。
- `schedule_digit_display_component.BlankLeadingZero : logic = false` — オンなら上の桁が 0 のとき数字を出さない（全部の数字のメッシュを隠す）。
- `schedule_digit_glyph_component.Value : int = 0` — このメッシュが表す数字（0〜9）。同じ値のメッシュが何個あってもよい。
- `schedule_countdown_hud_component.ShowWithinSeconds : float = 300.0` — 開始の何秒前から出すか（秒。1 以上）。
- `schedule_countdown_hud_component.Format : schedule_text_format = MinutesSeconds` / `Prefix : string = ""`。
- `schedule_countdown_hud_component.TextSize : float = 48.0` — 文字の大きさ（8〜200）。
- `schedule_countdown_hud_component.PositionXRatio : float = 0.5` / `PositionYRatio : float = 0.15` — 画面の位置（0〜1。0 = 左端・上端、1 = 右端・下端。その点を文字の真ん中にする）。WidgetSystem/HudKit の HUD（`text_hud_component` など）と同じ名前・同じ意味で、ToolTip も WidgetSystem のもの（`WidgetPositionXToolTip` / `WidgetPositionYToolTip`）を使う。
- `schedule_countdown_hud_component` は `player_widget_component`（WidgetSystem）の派生なので、`Mode` / `Audience` / `ZOrder` / `MenuConflict` / `ActiveOnBegin` / `ForwardReceivedEvents` も持ちます。`Audience` は既定の `Everyone` のままにします（`Chosen` だと、だれかに `ShowFor` するまでだれにも出ません）。

## イベント
- `schedule_state_changed_event`（scene_event、SendDown）: `Schedule : schedule_component`、`Previous : ?schedule_snapshot`（最初の評価なら false）、`Current : schedule_snapshot`。`schedule_component` が送る。状態（Before / Active / After）か回が変わったときだけ。最初の評価でも 1 回届く。受け手はその entity と子孫。消費しない。
- `schedule_component` は Active に入るとき・出るとき、この知らせの直後に `activated_event` / `deactivated_event` を自分と子孫へ送る（`SendActivation` がオン）。期間の途中でサーバが立ち上がったときは、最初の評価で Active になり `activated_event` が届く。
- `schedule_text_changed_event`（scene_event、SendDown）: `Sender : component`、`Text : message`（Prefix 付き）、`RemainingWholeSeconds : int`（切り上げた整数）。`schedule_text_component` が自分の entity から下へ送る。`schedule_countdown_hud_component` は自分の widget へ（`SendToWidgets`）渡す。文字が変わったときだけ。受け手は文字を出す widget・看板など。消費しない。
- `schedule_component.StateChangedEvent : listenable(schedule_snapshot)` — 状態か回が変わったときだけ、新しい値で届く。最初の評価でも 1 回。
- `schedule_component.SecondEvent : listenable(schedule_snapshot)` — 毎秒 1 回。同じ秒の `StateChangedEvent` より後。購読者の数だけ毎秒の処理が増えるので、状態だけ要るなら `StateChangedEvent` を使う。
- `realtime_clock_component.SecondEvent : listenable(float)` — 毎秒 1 回、評価に使った時刻（`GetNowEpochSeconds`）で届く。全スケジュールの知らせを配ったあと。
- `schedule_text_component.TextChangedEvent : listenable(message)` — 文字が変わったとき。
- `schedule_digit_display_component.DigitChangedEvent : listenable(int)` — 桁の値（0〜9。何も出さないときは -1）が変わったとき。マテリアルのパラメータで数字を出すときは、これを購読して自分の MI に書く。
- 受けるもの: `schedule_countdown_hud_component` は、スケジュールから届く `activated_event` / `deactivated_event` を無視する（表示の切り替えは開始前の窓の判定だけで決め、`Activate` / `Deactivate` を自分で呼ぶ）。ほかの scene_event は `player_widget_component` と同じに扱う。

## 持ち主
- `schedule_countdown_hud_component` は `player_widget_component` の派生なので、プレイヤーの slot の下（ロードアウトの中など）に置くと、区画の全員ではなく持ち主の画面にだけ出します。ほかの component は持ち主で動きを変えません。

## 公開 API
```verse
# ScheduleTime.verse（状態を持たない補助）
SecondsPerDay<public>:int = 86400
SecondsPerHour<public>:int = 3600
SecondsPerMinute<public>:int = 60
DefaultTimeZoneOffsetSeconds<public>:int = 32400
ToWholeSeconds<public>(Seconds:float)<transacts>:int             # 0 以下は 0、それ以外は切り上げ（表示に使う整数）
GetDayIndex<public>(EpochSeconds:float, TimeZoneOffsetSeconds:int)<transacts>:int
GetSecondsOfDay<public>(EpochSeconds:float, TimeZoneOffsetSeconds:int)<transacts>:float
GetDayStartSeconds<public>(DayIndex:int, TimeZoneOffsetSeconds:int)<computes>:float
DaysBetween<public>(FromSeconds:float, ToSeconds:float)<transacts>:int
MakeSecondsOfDay<public>(Hour:int, Minute:int, Second:int)<computes>:int
split_seconds<public> := struct:
    Days<public>:int = 0
    Hours<public>:int = 0
    Minutes<public>:int = 0
    Seconds<public>:int = 0
SplitSeconds<public>(TotalSeconds:int)<transacts>:split_seconds
FormatHoursMinutesSeconds<public>(TotalSeconds:int)<transacts>:string      # "HH:MM:SS"
FormatMinutesSeconds<public>(TotalSeconds:int)<transacts>:string           # "MM:SS"
FormatDaysHoursMinutesSeconds<public>(TotalSeconds:int)<transacts>:string  # "Dd HH:MM:SS"
FormatDays<public>(TotalSeconds:int)<transacts>:string
GetDigit<public>(Value:int, Digit:int)<transacts>:int
IsLeadingZero<public>(Value:int, Digit:int)<decides><transacts>:void

realtime_clock_component<public> := class<final_super>(component):
    TimeZoneOffsetSeconds<public>:int
    WakeMarginSeconds<public>:float
    var<private> DebugOffsetSeconds<public>:float
    SecondEvent<public><final>:listenable(float)
    GetNowEpochSeconds<public>()<transacts>:float             # 同じトランザクションでは同じ値。OS の時計が戻っても戻らない
    GetTimeZoneOffsetSeconds<public>()<computes>:int
    GetDayIndex<public>(EpochSeconds:float)<transacts>:int
    GetSecondsOfDay<public>(EpochSeconds:float)<transacts>:float
    SetDebugOffsetSeconds<public>(OffsetSeconds:float):void   # デバッグ用。その場で評価し直す
    JumpTo<public>(EpochSeconds:float):void                   # デバッグ用
    GetSchedules<public>()<transacts>:[]schedule_component    # 登録順

schedule_kind<public> := enum:
    Daily
    FixedInterval
    OneShot

schedule_component<public> := class<final_super>(component):
    Kind<public>:schedule_kind
    StartHour<public>:int
    StartMinute<public>:int
    StartSecond<public>:int
    DurationSeconds<public>:float
    IntervalSeconds<public>:float
    EpochAnchorSeconds<public>:float
    SendActivation<public>:logic
    StateChangedEvent<public><final>:listenable(schedule_snapshot)
    SecondEvent<public><final>:listenable(schedule_snapshot)
    FindClock<public>()<decides><transacts>:realtime_clock_component
    GetTimeZoneOffsetSeconds<public>()<transacts>:int                  # 時計が無ければ DefaultTimeZoneOffsetSeconds
    FindLastSnapshot<public>()<decides><transacts>:schedule_snapshot   # まだ評価していなければ失敗する
    GetCurrentSnapshot<public>()<transacts>:schedule_snapshot
    IsActive<public>()<decides><transacts>:void
    Evaluate<public>(T:float)<transacts>:schedule_snapshot             # 状態を変えない純粋な計算
    EvaluateWithOffset<public>(T:float, TimeZoneOffsetSeconds:int)<transacts>:schedule_snapshot

schedule_state<public> := enum:
    Before
    Active
    After      # 単発だけ

schedule_snapshot<public> := struct:
    NowSeconds<public>:float = 0.0
    State<public>:schedule_state = schedule_state.Before
    CycleIndex<public>:int = 0
    CycleStartSeconds<public>:float = 0.0
    ElapsedSeconds<public>:float = 0.0
    SecondsToEnd<public>:float = 0.0
    SecondsToStart<public>:float = 0.0
    HasNextStart<public>:logic = false
(Snapshot:schedule_snapshot).IsActive<public>()<decides><computes>:void
(Snapshot:schedule_snapshot).IsSameStateAndCycle<public>(Other:schedule_snapshot)<decides><computes>:void
(Snapshot:schedule_snapshot).GetRemainingSeconds<public>(Kind:schedule_remaining_kind)<computes>:float   # 小数。整数にするなら ToWholeSeconds

schedule_remaining_kind<public> := enum:
    UntilStart
    UntilEnd

schedule_state_changed_event<public> := class(scene_event):
    Schedule<public>:schedule_component
    Previous<public>:?schedule_snapshot
    Current<public>:schedule_snapshot

# 自分の entity か祖先の schedule_component を見つけて購読する補助（フィールドに 1 つ持つ）
schedule_follower<public> := class<unique>:
    FindSchedule<public>()<decides><transacts>:schedule_component
    Attach<public>(Owner:entity, OnChanged:type{_(:schedule_snapshot):void}, OnSecond:?type{_(:schedule_snapshot):void}):logic   # 見つからなければ false
    Detach<public>():void

# ConditionKit
schedule_active_condition_component<public> := class<final_super>(condition_component):

# DisplayKit
schedule_time_field<public> := enum:
    Days
    Hours
    Minutes
    Seconds
    TotalSeconds
    TotalMinutes
GetTimeField<public>(RemainingWholeSeconds:int, Field:schedule_time_field)<transacts>:int

schedule_digit_glyph_component<public> := class<final_super>(component):
    Value<public>:int

schedule_digit_display_component<public> := class<final_super>(component):
    Digit<public>:int
    Field<public>:schedule_time_field
    RemainingKind<public>:schedule_remaining_kind
    BlankLeadingZero<public>:logic
    DigitChangedEvent<public><final>:listenable(int)
    GetDigitValue<public>()<transacts>:int        # 何も出していなければ -1

schedule_text_format<public> := enum:
    HoursMinutesSeconds
    MinutesSeconds
    DaysHoursMinutesSeconds
    Days
    TotalSeconds
FormatRemaining<public>(RemainingWholeSeconds:int, Format:schedule_text_format, Prefix:string)<transacts>:string
ScheduleTextToMessage<public><localizes>(Text:string):message

schedule_text_changed_event<public> := class(scene_event):
    Sender<public>:component
    Text<public>:message
    RemainingWholeSeconds<public>:int

schedule_text_component<public> := class<final_super>(component):
    Format<public>:schedule_text_format
    RemainingKind<public>:schedule_remaining_kind
    Prefix<public>:string
    OnlyWhileShown<public>:logic
    TextChangedEvent<public><final>:listenable(message)
    GetText<public>():message
    GetRemainingWholeSeconds<public>()<transacts>:int  # 文字にした残り秒数（切り上げた整数）。まだなら -1
    Show<public>():void
    Hide<public>():void
    IsShown<public>()<decides><transacts>:void

# HudKit
schedule_countdown_hud_component<public> := class<final_super>(player_widget_component):
    ShowWithinSeconds<public>:float
    Format<public>:schedule_text_format
    Prefix<public>:string
    TextSize<public>:float
    PositionXRatio<public>:float
    PositionYRatio<public>:float
```

## 名前の決まり
- 秒の値は、小数（float）なら `…Seconds`、切り上げた整数（int。画面に出す値）なら `…WholeSeconds` と書きます。CountdownSystem（`GetRemainingSeconds():float` / `GetRemainingWholeSeconds():int`）とそろえています。

## 前提・注意
- 区画（または世界）に `realtime_clock_component` が 1 つ要ります。無ければ `schedule_component` は評価されません（1 フレーム待って探し直し、それでも無ければ見つかるまで 1 秒ごとに探します（`AwaitScopedComponent`。プレハブで後から足した時計も拾う）。1 秒たっても無ければ 1 回だけ Print します）。Kit は `schedule_component` が自分の entity にも祖先にも無いと Print して何もしません。
- 実時刻は止められません（Pause はありません）。一時停止が要るものは CountdownSystem などシミュレーション時間のものを使います。
- 「日」は常に 86400 秒です（暦の月・年は使いません）。夏時間は考えません。
- OS の時計が逆に戻っても `GetNowEpochSeconds` は戻りません。デバッグで時刻を飛ばしたときは、途中の変化はまとめて 1 回の変化（飛んだ先の状態）になります。デバッグ用の `SetDebugOffsetSeconds` / `JumpTo` を公開する島に残すかは利用者が決めます。
- 毎フレームの処理はありません。時計が 1 秒に 1 回起きて、スケジュールの数だけ計算します。表示の Kit（文字・桁・HUD）は `SecondEvent` を購読するので、毎秒 1 回の計算があります（書き込みは値が変わったときだけ）。
- `schedule_countdown_hud_component` は区画（または世界）に `player_manager_component` が要ります（`player_widget_component` の前提）。開始前の窓の外では画面に何も出しません（毎秒の残り秒の比較だけは続きます）。
- `message` は連結できないので、前に付ける文字は `Prefix`（string）で持ちます。
- `schedule_sequence_component` は FNDeviceSystem に移りました（`FNDeviceSystem/ScheduleKit/`）。使い方と実機で確かめていない点は FNDeviceSystem の README にあります。ツールチップ（`ScheduleSequencesToolTip` など）はこの System の TooltipKit に残っています。
- この System のコードには `⚠ 未検証` の印はなく、`@experimental` の API も使っていません。

## 確かめ方
- テスト：`_Test/ScheduleSystemTest/` の `schedule_system_test_component`。この component を付けた entity を 1 つ置くだけ（時計・スケジュール・子はテストが実行時に作る）。レベルに別の `realtime_clock_component` を置かない（世界に 2 つあるとどれが使われるか決まらない）。プレイヤーは要らない。`Evaluate` の計算（毎日・一定間隔・単発、日付の境目）、`ToWholeSeconds`、日数・文字の形（`Format*`）・桁（`GetDigit` / `IsLeadingZero`）の補助、時計が戻らないこととデバッグの時刻移動、`StateChangedEvent` が変化のときだけ届くこと、子への `activated_event` / `deactivated_event`、条件 Kit を確かめます。約 12 秒。結果は出力ログの `[TEST] ScheduleSystem`。
- DisplayKit・HudKit の component そのもの（メッシュの切り替え・画面表示）はテストしていません。
- `_Samples/` に ScheduleSystem の見本はありません。

## 移行が要るもの（2026-11-08）
- `ToDisplaySeconds` → `ToWholeSeconds`。
- `schedule_text_component.GetRemainingSeconds():int` → `GetRemainingWholeSeconds():int`。
- `schedule_text_changed_event.RemainingSeconds` → `RemainingWholeSeconds`。
- `GetTimeField` / `FormatRemaining` の 1 つ目の引数の名前 `RemainingSeconds` → `RemainingWholeSeconds`（位置で渡していれば変更不要）。
- ToolTip の `ScheduleHudPositionXToolTip` / `ScheduleHudPositionYToolTip` を消した（HUD の位置は WidgetSystem の `WidgetPositionXToolTip` / `WidgetPositionYToolTip` を使う）。設定名 `PositionXRatio` / `PositionYRatio` は WidgetSystem/HudKit と同じだったので変えていない。
- `schedule_state_changed_event.Sender` → `Schedule`（送り元の項目名を Library 全体でそろえた。`schedule_text_changed_event.Sender : component` は送り手が 2 種類あるのでそのまま）。
- `schedule_follower`（Kit と FNDeviceSystem の `schedule_sequence_component` が使う）は、入れ子のスケジュールで必ず一番近いものを選ぶように直した（今までは自身に無いとき `FindAncestorComponents` の最初のものを使っていて、並び順が決まっていなかった）。名前・使い方は同じ。
