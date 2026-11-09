using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/UI }
using { /Fortnite.com/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { ActivationSystem }
using { WidgetSystem }
using { WidgetSystem.TooltipKit }
using { ScheduleSystem }
using { ScheduleSystem.DisplayKit }
using { ScheduleSystem.TooltipKit }

# 役割：スケジュールの開始の ShowWithinSeconds 秒前から開始まで、区画の全プレイヤー（途中参加も）の画面にカウントダウンの文字を出す。開始したら消す。窓の外では画面に何も出さず、毎秒の処理は残り秒の比較 1 回だけ（UI への書き込みは無い）
# 置き方：エディターで entity に付け、schedule_component の entity の子孫に置く
# 前提：区画（または世界）に player_manager_component が 1 つ
# 前提・注意：スケジュールから届く activated_event / deactivated_event（期間の始まり・終わり）は無視する（表示の切り替えは窓の判定だけで決め、Activate / Deactivate を直接呼ぶ）
schedule_countdown_hud_component<public> := class<final_super>(player_widget_component):

    # 開始の何秒前から画面にカウントダウンを出すか（秒）。既定 300
    @editable_number(float):
        ToolTip := ScheduleHudShowWithinToolTip
        Categories := array{ScheduleDisplayCategory}
        MinValue := option{1.0}
    ShowWithinSeconds<public>:float = 300.0

    # 文字の形（schedule_text_format）。既定 MinutesSeconds
    @editable:
        ToolTip := ScheduleTextFormatToolTip
        Categories := array{ScheduleDisplayCategory}
    Format<public>:schedule_text_format = schedule_text_format.MinutesSeconds

    # 文字の前に付ける固定の文字列。空なら付けない（既定）
    @editable:
        ToolTip := ScheduleTextPrefixToolTip
        Categories := array{ScheduleDisplayCategory}
    Prefix<public>:string = ""

    # 文字の大きさ（8〜200）。既定 48
    @editable_number(float):
        ToolTip := ScheduleHudTextSizeToolTip
        Categories := array{ScheduleDisplayCategory}
        MinValue := option{8.0}
        MaxValue := option{200.0}
    TextSize<public>:float = 48.0

    # 置く位置（画面の横の割合。0 = 左端、0.5 = 中央、1 = 右端。その点を文字の真ん中にする）。既定 0.5。WidgetSystem/HudKit の HUD と同じ名前・同じ意味
    @editable_number(float):
        ToolTip := WidgetPositionXToolTip
        Categories := array{ScheduleDisplayCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionXRatio<public>:float = 0.5

    # 置く位置（画面の縦の割合。0 = 上端、0.5 = 中央、1 = 下端。その点を文字の真ん中にする）。既定 0.15。WidgetSystem/HudKit の HUD と同じ名前・同じ意味
    @editable_number(float):
        ToolTip := WidgetPositionYToolTip
        Categories := array{ScheduleDisplayCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionYRatio<public>:float = 0.15

    Follower<private>:schedule_follower = schedule_follower{}
    var<private> LastRemainingSeconds:int = -1
    var<private> LastMessage:?message = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Attached := Follower.Attach(Entity, Refresh, option{Refresh})
        if (not Attached?):
            Print("[schedule_countdown_hud_component] schedule_component がこの entity にも祖先にも見つかりません")

    OnEndSimulation<override>():void =
        Follower.Detach()
        (super:)OnEndSimulation()

    OnReceive<override>(SceneEvent:scene_event):logic =
        # スケジュールの期間の始まり・終わり（activated / deactivated）では切り替えない
        if (activated_event[SceneEvent] or deactivated_event[SceneEvent]):
            false
        else:
            (super:)OnReceive(SceneEvent)

    CreateWidget<override>(View:widget_view):widget =
        Initial := if (Current := LastMessage?) then Current else ScheduleTextToMessage("")
        Label := text_block{DefaultText := Initial, DefaultTextSize := TextSize}
        spawn{FollowText(View, Label)}
        MakeScreenCanvas(Label, PositionXRatio, PositionYRatio)

    # 閉じるまで、schedule_text_changed_event を受けて文字を変える
    FollowText<private>(View:widget_view, Label:text_block)<suspends>:void =
        Updater := schedule_label_updater{Label := Label}
        Subscription := View.ReceivedEvent.Subscribe(Updater.Handle)
        View.HiddenEvent.Await()
        Subscription.Cancel()

    Refresh<private>(Snapshot:schedule_snapshot):void =
        Remaining := ToWholeSeconds(Snapshot.SecondsToStart)
        ShouldShow := if (Snapshot.State = schedule_state.Before and Remaining > 0 and Snapshot.SecondsToStart <= ShowWithinSeconds) then true else false
        if (not ShouldShow?):
            if (IsShown[]):
                Switch(false)
            return
        if (Remaining <> LastRemainingSeconds):
            set LastRemainingSeconds = Remaining
            Message := ScheduleTextToMessage(FormatRemaining(Remaining, Format, Prefix))
            set LastMessage = option{Message}
            if (IsShown[]):
                SendToWidgets(schedule_text_changed_event{Sender := Self, Text := Message, RemainingWholeSeconds := Remaining})
        if (not IsShown[]):
            Switch(true)

    Switch<private>(Show:logic):void =
        if (Show?):
            Activate()
        else:
            Deactivate()

# schedule_text_changed_event を受けて、1 人分の文字を変える
schedule_label_updater<internal> := class<internal>:
    Label<internal>:text_block

    Handle<internal>(Received:scene_event):void =
        if (Changed := schedule_text_changed_event[Received]):
            Label.SetText(Changed.Text)
