using { /Verse.org/Simulation }
using { /Verse.org/Colors }
using { /UnrealEngine.com/Temporary/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /Fortnite.com/UI }

# Layout helpers for parts placed on a canvas. Positions are ratios of the screen (0.0-1.0; top-left is 0, 0)

# canvas_slot that places Widget at screen ratio (XRatio, YRatio), centered on that point, sized to its content
#   ZOrder is the stacking order within this canvas (larger is in front; default 0)
MakeScreenSlot<public>(Widget:widget, XRatio:float, YRatio:float, ?ZOrder:int = 0)<transacts>:canvas_slot =
    canvas_slot:
        Anchors := anchors{Minimum := vector2{X := XRatio, Y := YRatio}, Maximum := vector2{X := XRatio, Y := YRatio}}
        Alignment := vector2{X := 0.5, Y := 0.5}
        SizeToContent := true
        ZOrder := if (Z := slot_zorder[ZOrder]) then Z else 0
        Widget := Widget

# canvas_slot that stretches Widget over the whole screen (full-screen blackout, background, etc.)
MakeFullScreenSlot<public>(Widget:widget)<transacts>:canvas_slot =
    canvas_slot:
        Anchors := anchors{Minimum := vector2{X := 0.0, Y := 0.0}, Maximum := vector2{X := 1.0, Y := 1.0}}
        Offsets := margin{Left := 0.0, Top := 0.0, Right := 0.0, Bottom := 0.0}
        Widget := Widget

# Build a canvas with a single Widget centered at screen ratio (XRatio, YRatio) (when CreateWidget shows just one thing)
MakeScreenCanvas<public>(Widget:widget, XRatio:float, YRatio:float):canvas =
    Root := canvas{}
    Root.AddWidget(MakeScreenSlot(Widget, XRatio, YRatio))
    Root

# stack_box with Widgets lined up along Orientation. PaddingPx of space between parts
MakeStack<public>(Widgets:[]widget, Orientation:orientation, PaddingPx:float):stack_box =
    Stack := stack_box{Orientation := Orientation}
    for (Widget : Widgets):
        Slot := stack_box_slot:
            Widget := Widget
            HorizontalAlignment := horizontal_alignment.Fill
            Padding := margin{Left := PaddingPx, Top := PaddingPx, Right := PaddingPx, Bottom := PaddingPx}
        Stack.AddWidget(Slot)
    Stack

# Text look (color, size). Make one per game theme and reuse it
widget_text_style<public> := struct:
    # Text color
    Color<public>:color = NamedColors.White
    # Text size (pixels at 1080p). 0 uses Fortnite's default size
    Size<public>:float = 0.0
    # Justification
    Justification<public>:text_justification = text_justification.Center

# text_block with the color and size of Style (if Size is 0 the size stays at the default)
MakeStyledText<public>(Text:message, Style:widget_text_style):text_block =
    if (Style.Size > 0.0):
        text_block{DefaultText := Text, DefaultTextColor := Style.Color, DefaultTextSize := Style.Size, DefaultJustification := Style.Justification}
    else:
        text_block{DefaultText := Text, DefaultTextColor := Style.Color, DefaultJustification := Style.Justification}

# Put a panel (BackColor, opacity Opacity) behind Widget. If Opacity is 0 or less, returns Widget as is. PaddingPx is the inner padding of the panel
MakePanel<public>(Widget:widget, BackColor:color, Opacity:float, PaddingPx:float):widget =
    if (Opacity <= 0.0):
        return Widget
    Back := color_block{DefaultColor := BackColor, DefaultOpacity := ToOpacity(Opacity)}
    Panel := overlay{}
    Panel.AddWidget(overlay_slot{Widget := Back, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill})
    Panel.AddWidget(overlay_slot{Widget := Widget, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Center, Padding := margin{Left := PaddingPx, Top := PaddingPx * 0.5, Right := PaddingPx, Bottom := PaddingPx * 0.5}})
    Panel

# Opacity in 0.0-1.0 (the type of color_block's DefaultOpacity)
widget_opacity<public> := type{_X:float where 0.0 <= _X, _X <= 1.0}

# Value clamped to 0.0-1.0 as an opacity
ToOpacity<public>(Value:float)<transacts>:widget_opacity =
    if (Clamped := widget_opacity[Value]) then Clamped else if (Value < 0.0) then 0.0 else 1.0

# Type of canvas_slot's ZOrder (0 or more)
slot_zorder<public> := type{_X:int where 0 <= _X, _X <= 2147483647}
