using { /Verse.org/Simulation }
using { /Verse.org/Colors }
using { /UnrealEngine.com/Temporary/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/UI }
using { WidgetSystem }
using { WidgetSystem.PointerKit }

# Role: a part that places its "tip" on a given screen point (widget_screen_marker), and a speech bubble with a pointed tail (MakeSpeechBubble)
#   Used for markers layered over the 3D view (a "?" above a stage, name tags over people, etc.). The point is moved every frame with FollowWorld (world position -> screen ratio via PointerKit's widget_screen_projection)
# Placement: code only. Add with MakeScreenMarker on top of the canvas built in CreateWidget
# Requirements: canvas parts have no API to change position, so moving means removing and re-adding. Re-adding every frame makes buttons unpressable (it becomes a different part the moment it is pressed), so
#   MoveTo re-places only when it moved at least MinMovePx (pixels at 1080p) from the previous position. With the camera still, it can be pressed

# Speech bubble look
widget_bubble_style<public> := struct:
    # Background color and opacity
    BackColor<public>:color = NamedColors.Black
    BackOpacity<public>:float = 0.85
    # Border thickness (px) and the normal border color and opacity (0 hides the border)
    BorderPx<public>:float = 3.0
    BorderColor<public>:color = NamedColors.White
    BorderOpacity<public>:float = 0.0
    # Border color while selected (mouse over, focus, SetHighlighted)
    HighlightColor<public>:color = NamedColors.Gold
    # Padding around the content (px)
    PaddingPx<public>:float = 8.0
    # Minimum size of the body (excluding the tail) (px). Used even when the content is smaller
    MinWidthPx<public>:float = 56.0
    MinHeightPx<public>:float = 56.0
    # Base width and height of the bottom tail (triangle) (px). Verse UI has no triangles, so it is built from TailSteps stacked horizontal bars of decreasing width. Height 0 means no tail
    TailWidthPx<public>:float = 24.0
    TailHeightPx<public>:float = 14.0
    TailSteps<public>:int = 5

# One pressable speech bubble (built with MakeSpeechBubble). To wait, pass Button to View.AwaitButtonChoice / AwaitClick
widget_bubble_button<public> := class<internal>:
    # Look rules
    Style<public>:widget_bubble_style
    # The pressable part
    Button<public>:button
    # Body height (px, excluding the tail. Off when the content is taller than MinHeightPx). Used to check whether a pressed point is over the body
    BodyHeightPx<public>:float
    Frame<internal>:color_block

    var<private> Highlighted:logic = false

    # Enter / leave the selected look (sets the border to HighlightColor)
    SetHighlighted<public>(Value:logic):void =
        set Highlighted = Value
        if (Value?):
            Frame.SetColor(Style.HighlightColor)
            Frame.SetOpacity(ToOpacity(1.0))
        else:
            Frame.SetColor(Style.BorderColor)
            Frame.SetOpacity(ToOpacity(Style.BorderOpacity))

    # Succeeds if in the selected look
    IsHighlighted<public>()<decides><transacts>:void =
        Highlighted?

    # While shown on this person's screen, change the selected look as the mouse enters or focus arrives (ends when closed. Call with spawn)
    TrackHighlight<public>(View:widget_view)<suspends>:void =
        race:
            View.HiddenEvent.Await()
            loop:
                Button.HighlightEvent().Await()
                SetHighlighted(true)
            loop:
                Button.UnhighlightEvent().Await()
                SetHighlighted(false)

    # Tail height (px)
    GetTailHeightPx<public>()<transacts>:float =
        if (Style.TailHeightPx > 0.0, Style.TailSteps > 0) then Style.TailHeightPx else 0.0

# A pressable speech bubble holding Content, with the tail pointing down. The tip of the tail is at the bottom center of the part (it points at that point with MakeScreenMarker's default alignment 0.5, 1.0)
MakeSpeechBubble<public>(Content:widget, Style:widget_bubble_style):widget_bubble_button =
    Frame := color_block:
        DefaultColor := Style.BorderColor
        DefaultOpacity := ToOpacity(Style.BorderOpacity)
        DefaultDesiredSize := vector2{X := Style.MinWidthPx, Y := Style.MinHeightPx}
    Back := color_block{DefaultColor := Style.BackColor, DefaultOpacity := ToOpacity(Style.BackOpacity)}
    Body := overlay{}
    Body.AddWidget(overlay_slot{Widget := Frame, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill})
    Inset := Max(Style.BorderPx, 0.0)
    Body.AddWidget(overlay_slot{Widget := Back, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill, Padding := margin{Left := Inset, Top := Inset, Right := Inset, Bottom := Inset}})
    Pad := Inset + Max(Style.PaddingPx, 0.0)
    Body.AddWidget(overlay_slot{Widget := Content, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Center, Padding := margin{Left := Pad, Top := Pad, Right := Pad, Bottom := Pad}})
    Column := stack_box{Orientation := orientation.Vertical}
    Column.AddWidget(stack_box_slot{Widget := Body, HorizontalAlignment := horizontal_alignment.Center})
    if (Style.TailHeightPx > 0.0, Style.TailSteps > 0):
        Steps := Style.TailSteps
        StepH := Style.TailHeightPx / (Steps * 1.0)
        for (Index := 0..Steps - 1):
            # Upper steps are wider (base width -> the tip is 1/Steps of the width)
            W := Max(Style.TailWidthPx * ((Steps - Index) * 1.0) / (Steps * 1.0), 1.0)
            Step := color_block{DefaultColor := Style.BackColor, DefaultOpacity := ToOpacity(Style.BackOpacity), DefaultDesiredSize := vector2{X := W, Y := StepH}}
            Column.AddWidget(stack_box_slot{Widget := Step, HorizontalAlignment := horizontal_alignment.Center})
    Made := button{Slot := button_slot{Widget := Column, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Bottom}}
    Bubble := widget_bubble_button{Style := Style, Button := Made, BodyHeightPx := Style.MinHeightPx, Frame := Frame}
    Bubble.SetHighlighted(false)
    Bubble

# One marker that places the (AlignX, AlignY) point of part Widget (position inside the part, top-left 0,0 to bottom-right 1,1) on a screen-ratio point on canvas Root. Built with MakeScreenMarker
#   Hidden when created (MoveTo shows it)
widget_screen_marker<public> := class<internal>:
    # The canvas to place on
    Root<public>:canvas
    # The part to place
    Widget<public>:widget
    # The position inside the part that is aligned to the point (default 0.5, 1.0 = bottom center; the tail of a speech bubble)
    AlignX<public>:float
    AlignY<public>:float
    # Stacking order within Root (larger is in front)
    ZOrder<public>:int
    # Movement smaller than this (pixels at 1080p) does not re-place
    MinMovePx<public>:float

    var<private> Shown:logic = false
    var<private> X:float = 0.0
    var<private> Y:float = 0.0

    # Place at point (InX, InY) (screen ratios). Shows it if hidden. Does nothing if it moved less than MinMovePx from the previous position
    MoveTo<public>(InX:float, InY:float):void =
        if (Shown?, Abs(InX - X) * 1920.0 < MinMovePx, Abs(InY - Y) * 1080.0 < MinMovePx):
            return
        if (Shown?):
            Root.RemoveWidget(Widget)
        set X = InX
        set Y = InY
        set Shown = true
        Root.AddWidget(MakeMarkerSlot(Widget, InX, InY, AlignX, AlignY, ZOrder))

    # Hide (remove from Root). Does nothing if already hidden
    HideMarker<public>():void =
        if (Shown?):
            Root.RemoveWidget(Widget)
            set Shown = false

    # Succeeds if shown
    IsShown<public>()<decides><transacts>:void =
        Shown?

    # The current point (screen ratios). The last placed point if hidden
    GetPoint<public>()<transacts>:tuple(float, float) =
        (X, Y)

    # If shown and the screen-ratio point (PX, PY) is within RadiusPx of the current point offset by (OffsetXPx, OffsetYPx) (pixels at 1080p; up is negative), returns that distance (px). Fails otherwise
    #   For a speech bubble, offset from the tail (the point) to the center of the body with OffsetYPx = -(tail height + body height / 2) to check whether the pressed point is near the body
    DistancePxTo<public>(PX:float, PY:float, RadiusPx:float, ?OffsetXPx:float = 0.0, ?OffsetYPx:float = 0.0)<decides><transacts>:float =
        Shown?
        DX := (PX - X) * 1920.0 - OffsetXPx
        DY := (PY - Y) * 1080.0 - OffsetYPx
        Away := Sqrt(DX * DX + DY * DY)
        Away <= RadiusPx
        Away

# Place Marker at the position of World as seen from Projection's camera (call every frame). Hides it if behind the camera or more than MarginRatio outside the screen
#   Projection is PointerKit's GetScreenProjection (that person's current camera) or MakeScreenProjectionInView (a camera you placed). Re-places only when it moved from the previous position (MoveTo)
(Marker:widget_screen_marker).FollowWorld<public>(Projection:widget_screen_projection, World:(/Verse.org/SpatialMath:)vector3, ?MarginRatio:float = 0.05):void =
    if:
        Point := Projection.ProjectToScreenRatio[World]
        Point.X >= -MarginRatio
        Point.X <= 1.0 + MarginRatio
        Point.Y >= -MarginRatio
        Point.Y <= 1.0 + MarginRatio
    then:
        Marker.MoveTo(Point.X, Point.Y)
    else:
        Marker.HideMarker()

# Build a marker to add to Root (not shown yet. MoveTo / FollowWorld shows it)
MakeScreenMarker<public>(Root:canvas, Widget:widget, ?AlignX:float = 0.5, ?AlignY:float = 1.0, ?ZOrder:int = 0, ?MinMovePx:float = 0.5):widget_screen_marker =
    widget_screen_marker{Root := Root, Widget := Widget, AlignX := AlignX, AlignY := AlignY, ZOrder := ZOrder, MinMovePx := MinMovePx}

# canvas_slot that aligns Widget's (AlignX, AlignY) to screen ratio (X, Y), sized to its content
MakeMarkerSlot<internal>(Widget:widget, X:float, Y:float, AlignX:float, AlignY:float, ZOrder:int)<transacts>:canvas_slot =
    canvas_slot:
        Anchors := anchors{Minimum := vector2{X := X, Y := Y}, Maximum := vector2{X := X, Y := Y}}
        Alignment := vector2{X := AlignX, Y := AlignY}
        SizeToContent := true
        ZOrder := if (Z := slot_zorder[ZOrder]) then Z else 0
        Widget := Widget
