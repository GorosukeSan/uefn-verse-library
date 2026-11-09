using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ScheduleSystem }
using { ScheduleSystem.TooltipKit }

# 文字の形
schedule_text_format<public> := enum:
    # 01:02:03（時は 24 を超えてもそのまま）
    HoursMinutesSeconds
    # 62:03（分は 60 を超えてもそのまま）
    MinutesSeconds
    # 1d 01:02:03
    DaysHoursMinutesSeconds
    # 丸 1 日の数だけ（1）
    Days
    # 合計の秒（3723）
    TotalSeconds

# 残り秒数 RemainingWholeSeconds（切り上げた整数）を Format の文字列にする（Prefix を前に付ける）
FormatRemaining<public>(RemainingWholeSeconds:int, Format:schedule_text_format, Prefix:string)<transacts>:string =
    Body := case (Format):
        schedule_text_format.HoursMinutesSeconds => FormatHoursMinutesSeconds(RemainingWholeSeconds)
        schedule_text_format.MinutesSeconds => FormatMinutesSeconds(RemainingWholeSeconds)
        schedule_text_format.DaysHoursMinutesSeconds => FormatDaysHoursMinutesSeconds(RemainingWholeSeconds)
        schedule_text_format.Days => FormatDays(RemainingWholeSeconds)
        schedule_text_format.TotalSeconds => "{Max(RemainingWholeSeconds, 0)}"
    "{Prefix}{Body}"

# 文字列を widget に渡せる message にする（失敗する文脈・<transacts> の中では呼べない）
ScheduleTextToMessage<public><localizes>(Text:string):message = "{Text}"

# 残り時間の文字が変わった知らせ
# 方向：schedule_text_component の entity から下へ（SendDown）。schedule_countdown_hud_component は自分の widget へ Forward する
# 送り手：schedule_text_component / schedule_countdown_hud_component。受け手：文字を出す widget・看板など。消費しない
schedule_text_changed_event<public> := class(scene_event):
    # 送った component
    Sender<public>:component
    # 表示する文字（Prefix 付き）
    Text<public>:message
    # 文字にした残り秒数（切り上げた整数）
    RemainingWholeSeconds<public>:int

# 役割：スケジュールの残り時間を "MM:SS" などの文字（message）にして、変わったときだけ知らせる（看板・3D の文字・利用者の widget に使う）
# 置き方：エディターで entity に付ける。schedule_component の entity かその子孫に置く
# 知らせ：文字が変わったとき schedule_text_changed_event を下へ送り、TextChangedEvent に届ける（残り 1 秒以上なら毎秒、同じ文字なら送らない）
# 外から：GetText（今の文字）、GetRemainingWholeSeconds（文字にした残り秒数）。OnlyWhileShown がオンなら Show / Hide で更新を止める（誰も見ていない表示の分を省く）
# 前提・注意：message は連結できないので、前に付ける文字は Prefix（string）で持つ
schedule_text_component<public> := class<final_super>(component):

    # 文字の形（schedule_text_format）。既定 MinutesSeconds（62:03）
    @editable:
        ToolTip := ScheduleTextFormatToolTip
        Categories := array{ScheduleDisplayCategory}
    Format<public>:schedule_text_format = schedule_text_format.MinutesSeconds

    # 残りの選び方（UntilStart / UntilEnd）。既定 UntilEnd
    @editable:
        ToolTip := ScheduleRemainingKindToolTip
        Categories := array{ScheduleDisplayCategory}
    RemainingKind<public>:schedule_remaining_kind = schedule_remaining_kind.UntilEnd

    # 文字の前に付ける固定の文字列。空なら付けない（既定）
    @editable:
        ToolTip := ScheduleTextPrefixToolTip
        Categories := array{ScheduleDisplayCategory}
    Prefix<public>:string = ""

    # オンなら Show を呼んでいるあいだだけ毎秒更新する。オフなら常に更新する（既定）
    @editable:
        ToolTip := ScheduleTextOnlyWhileShownToolTip
        Categories := array{ScheduleDisplayCategory}
    OnlyWhileShown<public>:logic = false

    Follower<private>:schedule_follower = schedule_follower{}
    var<private> Shown:logic = true
    var<private> LastText:string = ""
    var<private> LastMessage:?message = false
    var<private> LastRemainingSeconds:int = -1

    TextChangedEventInternal<private><final>:event(message) = event(message){}

    # 文字が変わったときに、新しい文字で届く（Await / Subscribe する。外から Signal はできない）
    TextChangedEvent<public><final>:listenable(message) = MakeProxyListenable(TextChangedEventInternal)

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set Shown = if (OnlyWhileShown?) then false else true
        Attached := Follower.Attach(Entity, Refresh, option{Refresh})
        if (not Attached?):
            Print("[schedule_text_component] schedule_component がこの entity にも祖先にも見つかりません")

    OnEndSimulation<override>():void =
        Follower.Detach()
        (super:)OnEndSimulation()

    # 今の文字（まだ 1 回も計算していなければ空の message）
    GetText<public>():message =
        if (Current := LastMessage?):
            Current
        else:
            ScheduleTextToMessage("")

    # 今の文字の元になった残り秒数（切り上げた整数。まだなら -1）
    GetRemainingWholeSeconds<public>()<transacts>:int =
        LastRemainingSeconds

    # 更新を始める（OnlyWhileShown がオンのとき）。その場で今の文字を計算して知らせる
    Show<public>():void =
        if (Shown?):
            return
        set Shown = true
        if (Schedule := Follower.FindSchedule[]):
            Refresh(Schedule.GetCurrentSnapshot())

    # 更新を止める（OnlyWhileShown がオンのとき）
    Hide<public>():void =
        set Shown = false

    # 更新しているあいだ成功する
    IsShown<public>()<decides><transacts>:void =
        Shown?

    Refresh<private>(Snapshot:schedule_snapshot):void =
        if (not Shown?):
            return
        Remaining := ToWholeSeconds(Snapshot.GetRemainingSeconds(RemainingKind))
        if (Remaining = LastRemainingSeconds):
            return
        set LastRemainingSeconds = Remaining
        Text := FormatRemaining(Remaining, Format, Prefix)
        if (Text = LastText and LastMessage?):
            return
        set LastText = Text
        Message := ScheduleTextToMessage(Text)
        set LastMessage = option{Message}
        Entity.SendDown(schedule_text_changed_event{Sender := Self, Text := Message, RemainingWholeSeconds := Remaining})
        TextChangedEventInternal.Signal(Message)
