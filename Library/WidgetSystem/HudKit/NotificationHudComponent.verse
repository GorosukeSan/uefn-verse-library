using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/UI }
using { /Fortnite.com/UI }
using { SceneGraphSystem }
using { WidgetSystem }
using { WidgetSystem.TooltipKit }

# 通知を出す依頼
# 方向：利用者の component から notification_hud_component の entity へ（SendDown か、祖先から SendDown）
# 送り手：利用者の component。受け手：notification_hud_component。消費しない
hud_notification_request_event<public> := class(scene_event):
    # 出す相手。false なら全員
    Agent<public>:?agent = false
    # 出す文字
    Text<public>:message

# 役割：数秒で消える通知を、画面の決まった位置に縦に積んで出す HUD（操作は奪わない。重ね順は手前）。同じ人に続けて出すと下に積み、MaxLines を超えたら古いものから消す
# 置き方：エディターで entity に付ける。既定で開始から全員に出す（ActiveOnBegin）
# 知らせを受ける：hud_notification_request_event で出す（コードを書かずに、ほかの部品から出すとき）
# 外から：Notify / NotifyAll
notification_hud_component<public> := class<final_super>(player_widget_component):

    ActiveOnBegin<override>:logic = true
    ZOrder<override>:int = 10000

    # 1 つの通知を出しておく時間（秒）。既定 3
    @editable_number(float):
        ToolTip := NotificationSecondsToolTip
        Categories := array{NotificationHudCategory}
        MinValue := option{0.5}
        MaxValue := option{60.0}
    DisplaySeconds<public>:float = 3.0
    # 同時に出す通知の数の上限。既定 4
    @editable_number(int):
        ToolTip := NotificationMaxLinesToolTip
        Categories := array{NotificationHudCategory}
        MinValue := option{1}
        MaxValue := option{20}
    MaxLines<public>:int = 4
    # 置く位置（画面の横の割合 0.0〜1.0）。既定 0.5
    @editable_number(float):
        ToolTip := WidgetPositionXToolTip
        Categories := array{NotificationHudCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionXRatio<public>:float = 0.5
    # 置く位置（画面の縦の割合 0.0〜1.0）。既定 0.3
    @editable_number(float):
        ToolTip := WidgetPositionYToolTip
        Categories := array{NotificationHudCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionYRatio<public>:float = 0.3

    var<private> Stacks:[agent]stack_box = map{}
    var<private> Lines:[agent][]text_block = map{}

    # Agent に通知を出す。その人に出していなければ（Audience が Chosen で ShowFor していないなど）何もしない
    Notify<public>(Agent:agent, Text:message):void =
        if (Stack := Stacks[Agent]):
            Line := text_block{DefaultText := Text}
            Stack.AddWidget(stack_box_slot{Widget := Line, HorizontalAlignment := horizontal_alignment.Center})
            Current := if (Found := Lines[Agent]) then Found else array{}
            var Next:[]text_block = Current + array{Line}
            loop:
                if (Next.Length <= MaxLines):
                    break
                if (Oldest := Next[0], Rest := Next.Slice[1]):
                    Stack.RemoveWidget(Oldest)
                    set Next = Rest
                else:
                    break
            if (set Lines[Agent] = Next) {}
            spawn{ExpireLine(Agent, Line)}

    # 出している全員に通知を出す
    NotifyAll<public>(Text:message):void =
        for (Agent -> Stack : Stacks):
            Notify(Agent, Text)

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Request := hud_notification_request_event[SceneEvent]):
            if (Agent := Request.Agent?):
                Notify(Agent, Request.Text)
            else:
                NotifyAll(Request.Text)
        (super:)OnReceive(SceneEvent)

    CreateWidget<override>(View:widget_view):widget =
        Stack := stack_box{Orientation := orientation.Vertical}
        if (set Stacks[View.Player] = Stack) {}
        if (set Lines[View.Player] = array{}) {}
        spawn{ForgetWhenHidden(View)}
        MakeScreenCanvas(Stack, PositionXRatio, PositionYRatio)

    ExpireLine<private>(Agent:agent, Line:text_block)<suspends>:void =
        Sleep(DisplaySeconds)
        if (Stack := Stacks[Agent], Current := Lines[Agent]):
            Stack.RemoveWidget(Line)
            Kept := for (Other : Current, Other <> Line):
                Other
            if (set Lines[Agent] = Kept) {}

    ForgetWhenHidden<private>(View:widget_view)<suspends>:void =
        View.HiddenEvent.Await()
        set Stacks = Stacks.RemoveKey(View.Player)
        set Lines = Lines.RemoveKey(View.Player)
