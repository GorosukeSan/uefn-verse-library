using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Colors }
using { /UnrealEngine.com/Temporary/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { SceneGraphSystem }
using { WidgetSystem }
using { WidgetSystem.TooltipKit }

# Role: HUD that shows a ratio (0.0-1.0) as a horizontal bar (does not take input). Energy, time left, progress, etc. The same value for everyone (SetRatio) or a per-person value (SetRatioFor)
# Placement: in the editor, attach to an entity. Who sees it and when is set on player_widget_component
# From outside: SetRatio / SetRatioFor / GetRatioFor
# Requirements: subscribing to the source of the value (energy_component's ChangedEvent, etc.) and calling SetRatioFor is your code's job (this part does not know where the value comes from)
gauge_hud_component<public> := class<final_super>(player_widget_component):

    # Bar width (screen pixels). Default 300
    @editable_number(float):
        ToolTip := GaugeWidthToolTip
        Categories := array{GaugeHudCategory}
        MinValue := option{10.0}
        MaxValue := option{2000.0}
    WidthPx<public>:float = 300.0
    # Bar height (screen pixels). Default 16
    @editable_number(float):
        ToolTip := GaugeHeightToolTip
        Categories := array{GaugeHudCategory}
        MinValue := option{2.0}
        MaxValue := option{500.0}
    HeightPx<public>:float = 16.0
    # Fill color
    @editable:
        ToolTip := GaugeFillColorToolTip
        Categories := array{GaugeHudCategory}
    FillColor<public>:color = NamedColors.White
    # Background color
    @editable:
        ToolTip := GaugeBackColorToolTip
        Categories := array{GaugeHudCategory}
    BackColor<public>:color = NamedColors.Black
    # Position (horizontal screen ratio 0.0-1.0). Default 0.5
    @editable_number(float):
        ToolTip := WidgetPositionXToolTip
        Categories := array{GaugeHudCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionXRatio<public>:float = 0.5
    # Position (vertical screen ratio 0.0-1.0). Default 0.9
    @editable_number(float):
        ToolTip := WidgetPositionYToolTip
        Categories := array{GaugeHudCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionYRatio<public>:float = 0.9
    # Initial ratio. Default 1.0
    @editable_number(float):
        ToolTip := GaugeInitialRatioToolTip
        Categories := array{GaugeHudCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    InitialRatio<public>:float = 1.0

    var<private> SharedRatio:float = -1.0
    var<private> AgentRatios:[agent]float = map{}
    var<private> Fills:[agent]color_block = map{}

    # Set everyone's ratio to Ratio (clamped to 0.0-1.0. Per-person values are cleared)
    SetRatio<public>(Ratio:float):void =
        set SharedRatio = Clamp(Ratio, 0.0, 1.0)
        set AgentRatios = map{}
        for (Agent -> Fill : Fills):
            Apply(Fill, SharedRatio)

    # Set only Agent's ratio to Ratio (clamped to 0.0-1.0)
    SetRatioFor<public>(Agent:agent, Ratio:float):void =
        Value := Clamp(Ratio, 0.0, 1.0)
        if (set AgentRatios[Agent] = Value) {}
        if (Fill := Fills[Agent]):
            Apply(Fill, Value)

    # The ratio currently shown to Agent
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
