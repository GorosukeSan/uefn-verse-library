using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Colors }
using { /UnrealEngine.com/Temporary/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { SceneGraphSystem }
using { WidgetSystem }
using { WidgetSystem.TooltipKit }

# 役割：割合（0.0〜1.0）を横棒で見せる HUD（操作は奪わない）。エネルギー・残り時間・進み具合など。全員に同じ値（SetRatio）か、人ごとの値（SetRatioFor）
# 置き方：エディターで entity に付ける。だれに・いつ出すかは player_widget_component の設定
# 外から：SetRatio / SetRatioFor / GetRatioFor
# 前提・注意：値の元（energy_component の ChangedEvent など）を購読して SetRatioFor を呼ぶのは利用者側（この部品は値の出どころを知らない）
gauge_hud_component<public> := class<final_super>(player_widget_component):

    # 棒の幅（画面のピクセル）。既定 300
    @editable_number(float):
        ToolTip := GaugeWidthToolTip
        Categories := array{GaugeHudCategory}
        MinValue := option{10.0}
        MaxValue := option{2000.0}
    WidthPx<public>:float = 300.0
    # 棒の高さ（画面のピクセル）。既定 16
    @editable_number(float):
        ToolTip := GaugeHeightToolTip
        Categories := array{GaugeHudCategory}
        MinValue := option{2.0}
        MaxValue := option{500.0}
    HeightPx<public>:float = 16.0
    # 中身の色
    @editable:
        ToolTip := GaugeFillColorToolTip
        Categories := array{GaugeHudCategory}
    FillColor<public>:color = NamedColors.White
    # 背景の色
    @editable:
        ToolTip := GaugeBackColorToolTip
        Categories := array{GaugeHudCategory}
    BackColor<public>:color = NamedColors.Black
    # 置く位置（画面の横の割合 0.0〜1.0）。既定 0.5
    @editable_number(float):
        ToolTip := WidgetPositionXToolTip
        Categories := array{GaugeHudCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionXRatio<public>:float = 0.5
    # 置く位置（画面の縦の割合 0.0〜1.0）。既定 0.9
    @editable_number(float):
        ToolTip := WidgetPositionYToolTip
        Categories := array{GaugeHudCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionYRatio<public>:float = 0.9
    # 最初の割合。既定 1.0
    @editable_number(float):
        ToolTip := GaugeInitialRatioToolTip
        Categories := array{GaugeHudCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    InitialRatio<public>:float = 1.0

    var<private> SharedRatio:float = -1.0
    var<private> AgentRatios:[agent]float = map{}
    var<private> Fills:[agent]color_block = map{}

    # 全員の割合を Ratio にする（0.0〜1.0 に丸める。人ごとの値は消す）
    SetRatio<public>(Ratio:float):void =
        set SharedRatio = Clamp(Ratio, 0.0, 1.0)
        set AgentRatios = map{}
        for (Agent -> Fill : Fills):
            Apply(Fill, SharedRatio)

    # Agent の割合だけを Ratio にする（0.0〜1.0 に丸める）
    SetRatioFor<public>(Agent:agent, Ratio:float):void =
        Value := Clamp(Ratio, 0.0, 1.0)
        if (set AgentRatios[Agent] = Value) {}
        if (Fill := Fills[Agent]):
            Apply(Fill, Value)

    # Agent に今見せている割合
    GetRatioFor<public>(Agent:agent)<transacts>:float =
        if (Value := AgentRatios[Agent]) then Value
        else if (SharedRatio >= 0.0) then SharedRatio
        else InitialRatio

    CreateWidget<override>(View:widget_view):widget =
        Back := color_block{DefaultColor := BackColor, DefaultDesiredSize := vector2{X := WidthPx, Y := HeightPx}}
        Fill := color_block{DefaultColor := FillColor, DefaultDesiredSize := vector2{X := WidthPx * GetRatioFor(View.Player), Y := HeightPx}}
        Bar := overlay{}
        Bar.AddWidget(overlay_slot{Widget := Back, HorizontalAlignment := horizontal_alignment.Left, VerticalAlignment := vertical_alignment.Center})
        Bar.AddWidget(overlay_slot{Widget := Fill, HorizontalAlignment := horizontal_alignment.Left, VerticalAlignment := vertical_alignment.Center})
        if (set Fills[View.Player] = Fill) {}
        spawn{ForgetWhenHidden(View)}
        MakeScreenCanvas(Bar, PositionXRatio, PositionYRatio)

    Apply<private>(Fill:color_block, Ratio:float):void =
        Fill.SetDesiredSize(vector2{X := WidthPx * Ratio, Y := HeightPx})

    ForgetWhenHidden<private>(View:widget_view)<suspends>:void =
        View.HiddenEvent.Await()
        set Fills = Fills.RemoveKey(View.Player)
