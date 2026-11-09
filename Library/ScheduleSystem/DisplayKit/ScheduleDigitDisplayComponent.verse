using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SceneGraphSystem }
using { ScheduleSystem }
using { ScheduleSystem.TooltipKit }

# 残り時間のどの部分を出すか
schedule_time_field<public> := enum:
    # 丸 1 日の数（残り秒 ÷ 86400 の切り捨て）
    Days
    # 日を除いた時（0〜23）
    Hours
    # 分（0〜59）
    Minutes
    # 秒（0〜59）
    Seconds
    # 分けない合計の秒
    TotalSeconds
    # 分けない合計の分（切り捨て）
    TotalMinutes

# 残り秒数 RemainingWholeSeconds（切り上げた整数）から Field の値を取り出す
GetTimeField<public>(RemainingWholeSeconds:int, Field:schedule_time_field)<transacts>:int =
    Split := SplitSeconds(RemainingWholeSeconds)
    case (Field):
        schedule_time_field.Days => Split.Days
        schedule_time_field.Hours => Split.Hours
        schedule_time_field.Minutes => Split.Minutes
        schedule_time_field.Seconds => Split.Seconds
        schedule_time_field.TotalSeconds => Max(RemainingWholeSeconds, 0)
        schedule_time_field.TotalMinutes => Quotient[Max(RemainingWholeSeconds, 0), SecondsPerMinute] or 0

# 役割：数字 1 つ分のメッシュの目印。schedule_digit_display_component が、この entity のメッシュ（mesh_component）の Visible を切り替える
# 置き方：エディターで、数字の形のメッシュを持つ entity に付ける（0〜9 の 10 個を、schedule_digit_display_component の entity の直下に並べる）
# 親：schedule_digit_display_component の entity
schedule_digit_glyph_component<public> := class<final_super>(component):

    # このメッシュが表す数字（0〜9）。同じ値のメッシュが何個あってもよい。既定 0
    @editable_number(int):
        ToolTip := ScheduleGlyphValueToolTip
        Categories := array{ScheduleDisplayCategory}
        MinValue := option{0}
        MaxValue := option{9}
    Value<public>:int = 0

    # この entity のメッシュを見せる／隠す。同じ値を続けて書かない（複製されるプロパティなので、変わったときだけ書く）
    var<private> LastVisible:?logic = false

    SetVisible<internal>(Visible:logic):void =
        if (Previous := LastVisible?, Previous = Visible):
            return
        set LastVisible = option{Visible}
        if (Mesh := Entity.GetComponent[mesh_component]):
            set Mesh.Visible = Visible

# 役割：スケジュールの残り時間の 1 桁を、子の数字メッシュ（schedule_digit_glyph_component）の表示・非表示で出す。桁の値が変わったときだけメッシュに書く（秒の一の位は毎秒、十の位は 10 秒ごと、分は毎分…）
# 置き方：エディターで entity に付ける。schedule_component の entity の子孫に置く。桁ごとに 1 entity（「分の十の位」「分の一の位」…）
# 子：schedule_digit_glyph_component を付けた、数字 0〜9 のメッシュの entity（直下。並び順は関係ない。無い数字は何も出ない）
# 知らせ：DigitChangedEvent（桁の値が変わったとき。-1 = 何も出さない）。マテリアルのパラメータで数字を出す島では、これを購読して自分の MI（アセットのクラス）に書く（マテリアルは単精度なので、エポック秒ではなく桁の値のような小さい数だけ渡す）
# 前提・注意：毎秒 1 回、桁の値の計算だけはする（メッシュへの書き込みは変わったときだけ）
schedule_digit_display_component<public> := class<final_super>(component):

    # 何桁目を出すか（1 = 一の位、2 = 十の位、3 = 百の位。1〜9）。既定 1
    @editable_number(int):
        ToolTip := ScheduleDigitToolTip
        Categories := array{ScheduleDisplayCategory}
        MinValue := option{1}
        MaxValue := option{9}
    Digit<public>:int = 1

    # 残り時間のどの部分の桁か（schedule_time_field）。既定 Seconds
    @editable:
        ToolTip := ScheduleDigitFieldToolTip
        Categories := array{ScheduleDisplayCategory}
    Field<public>:schedule_time_field = schedule_time_field.Seconds

    # 残りの選び方（UntilStart / UntilEnd）。既定 UntilEnd
    @editable:
        ToolTip := ScheduleRemainingKindToolTip
        Categories := array{ScheduleDisplayCategory}
    RemainingKind<public>:schedule_remaining_kind = schedule_remaining_kind.UntilEnd

    # オンなら上の桁が 0 のとき数字を出さない（全部の数字のメッシュを隠す）。既定オフ
    @editable:
        ToolTip := ScheduleBlankLeadingZeroToolTip
        Categories := array{ScheduleDisplayCategory}
    BlankLeadingZero<public>:logic = false

    Follower<private>:schedule_follower = schedule_follower{}
    # 最後に出した桁の値（-1 = 何も出していない、-2 = まだ 1 回も出していない）
    var<private> LastDigit:int = -2

    DigitChangedEventInternal<private><final>:event(int) = event(int){}

    # 桁の値（0〜9。何も出さないときは -1）が変わったときに届く（Await / Subscribe する。外から Signal はできない）
    DigitChangedEvent<public><final>:listenable(int) = MakeProxyListenable(DigitChangedEventInternal)

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Attached := Follower.Attach(Entity, Refresh, option{Refresh})
        if (not Attached?):
            Print("[schedule_digit_display_component] schedule_component がこの entity にも祖先にも見つかりません")

    OnEndSimulation<override>():void =
        Follower.Detach()
        (super:)OnEndSimulation()

    # 今出している桁の値（0〜9。何も出していなければ -1）
    GetDigitValue<public>()<transacts>:int =
        Max(LastDigit, -1)

    Refresh<private>(Snapshot:schedule_snapshot):void =
        Remaining := ToWholeSeconds(Snapshot.GetRemainingSeconds(RemainingKind))
        Value := GetTimeField(Remaining, Field)
        NewDigit := if (BlankLeadingZero? and IsLeadingZero[Value, Digit]) then -1 else GetDigit(Value, Digit)
        if (NewDigit = LastDigit):
            return
        set LastDigit = NewDigit
        for (Glyph : Entity.GetChildComponents(schedule_digit_glyph_component)):
            Glyph.SetVisible(if (Glyph.Value = NewDigit) then true else false)
        DigitChangedEventInternal.Signal(NewDigit)
