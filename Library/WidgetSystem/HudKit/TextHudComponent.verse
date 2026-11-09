using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Colors }
using { /UnrealEngine.com/Temporary/UI }
using { /Fortnite.com/UI }
using { SceneGraphSystem }
using { WidgetSystem }
using { WidgetSystem.TooltipKit }

# 文字の HUD の文字を変える依頼
# 方向：利用者の component から text_hud_component の entity へ（SendDown か、祖先から SendDown）
# 送り手：利用者の component。受け手：text_hud_component。消費しない
hud_text_request_event<public> := class(scene_event):
    # 変える相手。false なら全員（これから出す人も）
    Agent<public>:?agent = false
    # 出す文字
    Text<public>:message

# 役割：画面の決まった位置に文字を 1 行出す HUD（操作は奪わない）。全員に同じ文字（SetText）か、人ごとの文字（SetTextFor）を出す。空の文字なら見えない
# 置き方：エディターで entity に付ける。だれに・いつ出すかは player_widget_component の設定（Audience・ActiveOnBegin・起動の合図）
# 知らせを受ける：hud_text_request_event で文字を変える（コードを書かずに、ほかの部品から変えるとき）
# 外から：SetText / SetTextFor / ClearTextFor
text_hud_component<public> := class<final_super>(player_widget_component):

    # 最初に出す文字
    @editable:
        ToolTip := TextHudTextToolTip
        Categories := array{TextHudCategory}
    Text<public>:string = ""
    # 置く位置（画面の横の割合 0.0〜1.0）。既定 0.5
    @editable_number(float):
        ToolTip := WidgetPositionXToolTip
        Categories := array{TextHudCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionXRatio<public>:float = 0.5
    # 置く位置（画面の縦の割合 0.0〜1.0）。既定 0.15
    @editable_number(float):
        ToolTip := WidgetPositionYToolTip
        Categories := array{TextHudCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionYRatio<public>:float = 0.15
    # 文字の色。既定 白
    @editable:
        ToolTip := TextHudColorToolTip
        Categories := array{TextHudCategory}
    TextColor<public>:color = NamedColors.White
    # 文字の大きさ（1080p のピクセル）。0 なら Fortnite の既定の大きさ。既定 0
    @editable_number(float):
        ToolTip := TextHudSizeToolTip
        Categories := array{TextHudCategory}
        MinValue := option{0.0}
        MaxValue := option{400.0}
    TextSize<public>:float = 0.0
    # 文字の後ろの板の不透明度（0.0〜1.0）。0 なら板を出さない。既定 0
    @editable_number(float):
        ToolTip := TextHudBackgroundOpacityToolTip
        Categories := array{TextHudCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    BackgroundOpacity<public>:float = 0.0
    # 文字の後ろの板の色。既定 黒
    @editable:
        ToolTip := TextHudBackgroundColorToolTip
        Categories := array{TextHudCategory}
    BackgroundColor<public>:color = NamedColors.Black

    var<private> SharedText:?message = false
    var<private> AgentTexts:[agent]message = map{}
    var<private> Blocks:[agent]text_block = map{}

    # 全員の文字を Value にする（人ごとの文字は消す）。これから出す人にもこの文字を出す
    SetText<public>(Value:message):void =
        set SharedText = option{Value}
        set AgentTexts = map{}
        for (Agent -> Block : Blocks):
            Block.SetText(Value)

    # Agent の文字だけを Value にする（全員の文字より優先）
    SetTextFor<public>(Agent:agent, Value:message):void =
        if (set AgentTexts[Agent] = Value) {}
        if (Block := Blocks[Agent]):
            Block.SetText(Value)

    # Agent の人ごとの文字を消し、全員の文字に戻す
    ClearTextFor<public>(Agent:agent):void =
        set AgentTexts = AgentTexts.RemoveKey(Agent)
        if (Block := Blocks[Agent]):
            Block.SetText(CurrentTextFor(Agent))

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Request := hud_text_request_event[SceneEvent]):
            if (Agent := Request.Agent?):
                SetTextFor(Agent, Request.Text)
            else:
                SetText(Request.Text)
        (super:)OnReceive(SceneEvent)

    CreateWidget<override>(View:widget_view):widget =
        Block := MakeStyledText(CurrentTextFor(View.Player), widget_text_style{Color := TextColor, Size := TextSize})
        if (set Blocks[View.Player] = Block) {}
        spawn{ForgetWhenHidden(View)}
        MakeScreenCanvas(MakePanel(Block, BackgroundColor, BackgroundOpacity, 16.0), PositionXRatio, PositionYRatio)

    CurrentTextFor<private>(Agent:agent):message =
        if (Value := AgentTexts[Agent]) then Value
        else if (Value := SharedText?) then Value
        else StringToMessage(Text)

    ForgetWhenHidden<private>(View:widget_view)<suspends>:void =
        View.HiddenEvent.Await()
        set Blocks = Blocks.RemoveKey(View.Player)
