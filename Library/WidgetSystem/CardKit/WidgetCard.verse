using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Colors }
using { /UnrealEngine.com/Temporary/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /Fortnite.com/UI }
using { WidgetSystem }

# Data for one card (the content shown on screen). Built with card_info_component's GetCard or directly in code
#   Per-person text (that person's record, etc.) is swapped in with WithSubtitle / WithBadge after building with GetCard
widget_card<public> := struct:
    # ID used when pressing from code (used in AwaitButtonChoice's ButtonIds. Also usable with MCPSystem's widget.press)
    Id<public>:string = ""
    # Name (large text)
    Title<public>:string = ""
    # One line under the name (not shown if empty)
    Subtitle<public>:string = ""
    # Description (wrapped. Not shown if empty)
    Description<public>:string = ""
    # Small badge at the top right (difficulty, new, etc. Not shown if empty)
    Badge<public>:string = ""
    # Image at the top (an AccentColor band if none)
    Image<public>:?texture = false
    # Card color (the band when there is no image, and the badge color)
    AccentColor<public>:color = NamedColors.SkyBlue
    # Whether it can be pressed (false dims it and makes it unpressable)
    Enabled<public>:logic = true

# A card with Card's Subtitle set to Text
(Card:widget_card).WithSubtitle<public>(Text:string)<transacts>:widget_card =
    CopyWidgetCard(Card, ?Subtitle := option{Text})

# A card with Card's Badge set to Text
(Card:widget_card).WithBadge<public>(Text:string)<transacts>:widget_card =
    CopyWidgetCard(Card, ?Badge := option{Text})

# A card with Card's Enabled set to Value
(Card:widget_card).WithEnabled<public>(Value:logic)<transacts>:widget_card =
    CopyWidgetCard(Card, ?Enabled := option{Value})

# A copy of Card. Only the fields passed are replaced (every With* goes through this)
#   When adding a field to widget_card, add it only here (so fields do not silently vanish from a card that went through With*, the fields are listed in this one place)
CopyWidgetCard<internal>(Card:widget_card, ?Subtitle:?string = false, ?Badge:?string = false, ?Enabled:?logic = false)<transacts>:widget_card =
    widget_card:
        Id := Card.Id
        Title := Card.Title
        Subtitle := if (Value := Subtitle?) then Value else Card.Subtitle
        Description := Card.Description
        Badge := if (Value := Badge?) then Value else Card.Badge
        Image := Card.Image
        AccentColor := Card.AccentColor
        Enabled := if (Value := Enabled?) then Value else Card.Enabled

# Card look rules (size, colors, text sizes). Make one per game; every card on the same screen uses the same one
widget_card_style<public> := struct:
    # Card width (pixels at 1080p, including the border)
    WidthPx<public>:float = 320.0
    # Card height (pixels at 1080p, including the border). Even if the content is shorter, cards are padded to this height (to decide the pointer hit area)
    HeightPx<public>:float = 420.0
    # Height of the image (or the color band if none)
    ImageHeightPx<public>:float = 180.0
    # Inner padding
    PaddingPx<public>:float = 12.0
    # Border thickness (0 for no border)
    BorderPx<public>:float = 4.0
    # Normal border color and opacity
    BorderColor<public>:color = NamedColors.White
    BorderOpacity<public>:float = 0.0
    # Border color while selected (mouse over, or gamepad focus)
    HighlightColor<public>:color = NamedColors.Gold
    # Background opacity while selected (a little stronger than normal, to lift it)
    HighlightBackgroundOpacity<public>:float = 1.0
    # Press-in (while pressed with the Virtual Pointer): how far the pressed side sinks (px) and the shadow strength
    PressDepthPx<public>:float = 10.0
    PressShadeOpacity<public>:float = 0.18
    # With a Skin, keep the darkening panel this far inside the card edge (px; inside the rounded body of the material, never sticking out)
    SkinInsetPx<public>:float = 9.0
    # Card background color
    BackgroundColor<public>:color = NamedColors.White
    # Background opacity (0.0-1.0)
    BackgroundOpacity<public>:float = 0.92
    # Name color and size
    TitleColor<public>:color = NamedColors.Black
    TitleSize<public>:float = 26.0
    # Color and size of the line under the name
    SubtitleColor<public>:color = NamedColors.DimGray
    SubtitleSize<public>:float = 18.0
    # Description color and size
    DescriptionColor<public>:color = NamedColors.DimGray
    DescriptionSize<public>:float = 16.0
    # Badge text color and size (the badge background is the card's AccentColor)
    BadgeTextColor<public>:color = NamedColors.White
    BadgeSize<public>:float = 16.0
    # Opacity of a card that cannot be pressed
    DisabledOpacity<public>:float = 0.45
    # Strength of the black laid over a card that cannot be pressed (also works on a card with a replaced background (Skin). 0 lays nothing)
    DisabledShadeOpacity<public>:float = 0.5

# Replaces the look of the card background (material glitter, holo, etc.). Pass it as ?Skin of MakeCardView and MakeSkin is called once per card
#   Implemented on the game side (material parameter names differ per game asset, so the Library does not know them)
widget_card_skin<public> := interface:
    # Build the background for one Card
    MakeSkin<public>(Card:widget_card, Style:widget_card_style):widget_card_skin_view

# The background of one card (built by widget_card_skin). Called each time the card's state changes
widget_card_skin_view<public> := interface:
    # The widget layered as the card background (stretched to the full card size)
    GetWidget<public>():widget
    # Entered / left the selected look (mouse over, gamepad focus)
    SetHighlight<public>(Value:logic):void
    # Press-in. Local is the position inside the card (top-left 0,0 to bottom-right 1,1), Amount is 0 (released) to 1 (pressed)
    SetPress<public>(Local:vector2, Amount:float):void
    # Tilt. Tilts toward Local (position inside the card). Amount is 0 (no tilt) to 1
    SetTilt<public>(Local:vector2, Amount:float):void
    # Fake light. Light position (inside this card; outside 0-1 when off the card) and strength (0 turns it off)
    SetLight<public>(Local:vector2, Strength:float):void
    # Fade-out amount (0 = normal, 1 = invisible)
    SetFade<public>(Value:float):void
    # true if the background also draws the card image (widget_card.Image) (the card then places no texture_block and only reserves the space). The background also draws the outline (selected look)
    DrawsImage<public>():logic

# One pressable card (button, border, press-in shadow). Built with MakeCardView. To wait, pass Button to View.AwaitButtonChoice
#   Two visual states: selected (SetHighlighted: mouse over, gamepad focus) and pressed-in (SetPressed: while pressed with the Virtual Pointer)
#   While pressed-in, the press-in takes priority over the selected look (even if the mouse position and the highlight disagree, only the pressed look is shown)
widget_card_button<public> := class<internal>:
    # Content data
    Card<public>:widget_card
    # Look rules
    Style<public>:widget_card_style
    # The pressable part (pass to AwaitButtonChoice)
    Button<public>:button
    Frame<internal>:color_block
    Back<internal>:color_block
    Shade<internal>:color_block
    Content<internal>:widget
    Layers<internal>:overlay
    # The background of this card when replaced (?Skin of MakeCardView)
    SkinView<internal>:?widget_card_skin_view = false

    var<private> Highlighted:logic = false
    var<private> Pressed:logic = false

    # Enter / leave the selected look (while pressed-in, only remember it without changing the look)
    SetHighlighted<public>(Value:logic):void =
        set Highlighted = Value
        if (not Pressed?):
            ApplyFrame()

    # Succeeds if in the selected look
    IsHighlighted<public>()<decides><transacts>:void =
        Highlighted?

    # Press in at Local (position inside the card. Top-left 0,0 to bottom-right 1,1). The pressed side sinks deeper (the content shifts) and the shadow grows stronger
    SetPressed<public>(Local:vector2):void =
        set Pressed = true
        LX := Clamp01(Local.X)
        LY := Clamp01(Local.Y)
        Depth := Style.PressDepthPx
        Inset := margin:
            Left := Style.BorderPx + Depth * (1.0 - LX)
            Right := Style.BorderPx + Depth * LX
            Top := Style.BorderPx + Depth * (1.0 - LY)
            Bottom := Style.BorderPx + Depth * LY
        PlaceContent(Inset)
        # With a background (material), the background shows the press-in darkening (no square panel is used)
        Shade.SetOpacity(ToOpacity(if (SkinView?) then 0.0 else Style.PressShadeOpacity))
        if (Skin := SkinView?):
            Skin.SetPress(vector2{X := LX, Y := LY}, 1.0)
            Skin.SetHighlight(true)
        else:
            Frame.SetColor(Style.HighlightColor)
            Frame.SetOpacity(ToOpacity(1.0))

    # Stop the press-in (return to the selected look)
    ClearPressed<public>():void =
        if (Pressed?):
            set Pressed = false
            PlaceContent(BaseInset())
            Shade.SetOpacity(ToOpacity(RestShadeOpacity()))
            if (Skin := SkinView?):
                Skin.SetPress(vector2{X := 0.5, Y := 0.5}, 0.0)
            ApplyFrame()

    # Succeeds if pressed in
    IsPressed<public>()<decides><transacts>:void =
        Pressed?

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

    # Normal darkness (Style.DisabledShadeOpacity for a card that cannot be pressed, 0 if it can)
    RestShadeOpacity<internal>()<transacts>:float =
        if (Card.Enabled?) then 0.0 else Style.DisabledShadeOpacity

    # Darken (when another card was chosen, etc. 0 restores). Uses the same panel as the press-in shadow
    SetDimmed<public>(Amount:float):void =
        Shade.SetOpacity(ToOpacity(Amount))

    # Chosen effect: over Seconds, a light sweeps diagonally from outside the top-left to outside the bottom-right and the tilt follows the light (without a background (Skin), only the border lights up). Advances every frame
    PlayShine<public>(Seconds:float)<suspends>:void =
        SetHighlighted(true)
        Start := GetSimulationElapsedTime()
        loop:
            T := if (Seconds > 0.0) then Min((GetSimulationElapsedTime() - Start) / Seconds, 1.0) else 1.0
            Eased := T * T * (3.0 - 2.0 * T)
            Light := vector2{X := -0.3 + 1.6 * Eased, Y := -0.2 + 1.4 * Eased}
            if (Skin := SkinView?):
                Skin.SetLight(Light, 1.0)
                Skin.SetTilt(vector2{X := Clamp01(Light.X), Y := Clamp01(Light.Y)}, 0.8)
            if (T >= 1.0):
                break
            Sleep(0.0)
        if (Skin := SkinView?):
            Skin.SetLight(vector2{X := 0.5, Y := 0.5}, 0.0)
            Skin.SetTilt(vector2{X := 0.5, Y := 0.5}, 0.0)

    ApplyFrame<private>():void =
        if (Skin := SkinView?):
            # The background (material, etc.) draws the outline, so no square border is shown
            Skin.SetHighlight(Highlighted)
            Frame.SetOpacity(ToOpacity(0.0))
            Back.SetOpacity(ToOpacity(0.0))
        else if (Highlighted?):
            Frame.SetColor(Style.HighlightColor)
            Frame.SetOpacity(ToOpacity(1.0))
            Back.SetOpacity(ToOpacity(if (SkinView?) then 0.0 else Style.HighlightBackgroundOpacity))
        else:
            Frame.SetColor(Style.BorderColor)
            Frame.SetOpacity(ToOpacity(Style.BorderOpacity))
            Back.SetOpacity(ToOpacity(if (SkinView?) then 0.0 else if (Card.Enabled?) then Style.BackgroundOpacity else Style.BackgroundOpacity * Style.DisabledOpacity))

    # Put the content and the shadow at their normal position (from MakeCardView)
    PlaceBase<internal>():void =
        PlaceContent(BaseInset())

    BaseInset<private>():margin =
        margin{Left := Style.BorderPx, Top := Style.BorderPx, Right := Style.BorderPx, Bottom := Style.BorderPx}

    PlaceContent<private>(Inset:margin):void =
        # With a background (material), keep the darkening panel inside the rounded body
        ShadeInset := if (SkinView?) then margin{Left := Max(Inset.Left, Style.SkinInsetPx), Top := Max(Inset.Top, Style.SkinInsetPx), Right := Max(Inset.Right, Style.SkinInsetPx), Bottom := Max(Inset.Bottom, Style.SkinInsetPx)} else Inset
        Layers.RemoveWidget(Content)
        Layers.RemoveWidget(Shade)
        Layers.AddWidget(overlay_slot{Widget := Content, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill, Padding := Inset})
        Layers.AddWidget(overlay_slot{Widget := Shade, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill, Padding := ShadeInset})

# Build one pressable card (border, background, image, name, badge, description, press-in shadow). Size is Style's WidthPx x HeightPx
#   Passing ?Skin lays the widget built by Skin (material, etc.) instead of the background (color panel), and tells Skin about the selected look and press-in too
MakeCardView<public>(Card:widget_card, Style:widget_card_style, ?Skin:?widget_card_skin = false):widget_card_button =
    Frame := color_block{DefaultColor := Style.BorderColor, DefaultOpacity := ToOpacity(Style.BorderOpacity), DefaultDesiredSize := vector2{X := Style.WidthPx, Y := Style.HeightPx}}
    Back := color_block:
        DefaultColor := Style.BackgroundColor
        DefaultOpacity := ToOpacity(if (Card.Enabled?) then Style.BackgroundOpacity else Style.BackgroundOpacity * Style.DisabledOpacity)
    Shade := color_block{DefaultColor := NamedColors.Black, DefaultOpacity := ToOpacity(0.0)}
    # The inside of option{...} is a failable context, so MakeSkin (no_rollback) is called outside and then wrapped
    var SkinView:?widget_card_skin_view = false
    if (Found := Skin?):
        Made := Found.MakeSkin(Card, Style)
        set SkinView = option{Made}
    Inner := overlay{}
    if (Found := SkinView?):
        Inner.AddWidget(overlay_slot{Widget := Found.GetWidget(), HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill})
    else:
        Inner.AddWidget(overlay_slot{Widget := Back, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill})
    SkinDrawsImage := if (Found := SkinView?) then Found.DrawsImage() else false
    Inner.AddWidget(overlay_slot{Widget := MakeCardContent(Card, Style, ?ImageSpaceOnly := SkinDrawsImage), HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Top})
    Layers := overlay{}
    Layers.AddWidget(overlay_slot{Widget := Frame, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill})
    ButtonMade := button{Slot := button_slot{Widget := Layers, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill}}
    if (not Card.Enabled?):
        ButtonMade.SetEnabled(false)
    View := widget_card_button{Card := Card, Style := Style, Button := ButtonMade, Frame := Frame, Back := Back, Shade := Shade, Content := Inner, Layers := Layers, SkinView := SkinView}
    View.ClearPressed()
    View.PlaceBase()
    # Keep a card that cannot be pressed darkened (on a card with a replaced background, Back is transparent, so DisabledOpacity alone does not distinguish it)
    View.SetDimmed(View.RestShadeOpacity())
    View

# Build a pressable card (button only). Use MakeCardView if you need the selected look and press-in
MakeCardButton<public>(Card:widget_card, Style:widget_card_style):button =
    MakeCardView(Card, Style).Button

# Only the look of a card (not pressable, no border. For list displays, results, etc.)
#   With ?ImageSpaceOnly, a transparent space of the same size is placed instead of the image (when the background draws the image)
MakeCardContent<public>(Card:widget_card, Style:widget_card_style, ?ImageSpaceOnly:logic = false):widget =
    Inner := Style.WidthPx - Style.BorderPx * 2.0 - Style.PaddingPx * 2.0
    var Rows:[]widget = array{}
    if (ImageSpaceOnly?):
        set Rows += array{color_block{DefaultColor := NamedColors.White, DefaultOpacity := ToOpacity(0.0), DefaultDesiredSize := vector2{X := Inner, Y := Style.ImageHeightPx}}}
    else:
        set Rows += array{MakeCardImage(Card, Style, Inner)}
    set Rows += array{MakeCardText(Card.Title, Style.TitleColor, Style.TitleSize, Inner)}
    if (Card.Subtitle <> ""):
        set Rows += array{MakeCardText(Card.Subtitle, Style.SubtitleColor, Style.SubtitleSize, Inner)}
    if (Card.Description <> ""):
        set Rows += array{MakeCardText(Card.Description, Style.DescriptionColor, Style.DescriptionSize, Inner)}
    Column := stack_box{Orientation := orientation.Vertical}
    for (Row : Rows):
        Column.AddWidget(stack_box_slot{Widget := Row, HorizontalAlignment := horizontal_alignment.Fill, Padding := margin{Left := Style.PaddingPx, Top := Style.PaddingPx * 0.5, Right := Style.PaddingPx, Bottom := Style.PaddingPx * 0.5}})
    Layers := overlay{}
    Layers.AddWidget(overlay_slot{Widget := Column, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Top})
    if (Card.Badge <> ""):
        Layers.AddWidget(overlay_slot{Widget := MakeCardBadge(Card, Style), HorizontalAlignment := horizontal_alignment.Right, VerticalAlignment := vertical_alignment.Top, Padding := margin{Top := Style.PaddingPx * 1.5, Right := Style.PaddingPx * 1.5}})
    Layers

# Lay Buttons out in rows of Columns each (GapPx between rows and between columns). Columns below 1 means 1 column
MakeCardGrid<public>(Buttons:[]widget, Columns:int, GapPx:float):widget =
    PerRow := Max(Columns, 1)
    Grid := stack_box{Orientation := orientation.Vertical}
    var Row:stack_box = stack_box{Orientation := orientation.Horizontal}
    var InRow:int = 0
    for (Button : Buttons):
        if (InRow >= PerRow):
            Grid.AddWidget(stack_box_slot{Widget := Row, HorizontalAlignment := horizontal_alignment.Center, Padding := margin{Top := GapPx * 0.5, Bottom := GapPx * 0.5}})
            set Row = stack_box{Orientation := orientation.Horizontal}
            set InRow = 0
        Row.AddWidget(stack_box_slot{Widget := Button, VerticalAlignment := vertical_alignment.Fill, Padding := margin{Left := GapPx * 0.5, Right := GapPx * 0.5}})
        set InRow += 1
    if (InRow > 0):
        Grid.AddWidget(stack_box_slot{Widget := Row, HorizontalAlignment := horizontal_alignment.Center, Padding := margin{Top := GapPx * 0.5, Bottom := GapPx * 0.5}})
    Grid

# The rectangle of the Index-th card (screen ratios: top-left X,Y and bottom-right X,Y) when Count cards are laid out with MakeCardGrid and their center is placed at screen ratio (CenterX, CenterY)
#   Computed for 1080p (16:9). It drifts slightly when the screen aspect differs
CardGridRect<public>(Index:int, Count:int, Columns:int, GapPx:float, Style:widget_card_style, CenterX:float, CenterY:float)<transacts>:widget_screen_rect =
    PerRow := Max(Columns, 1)
    Rows := CardIntDiv(Count + PerRow - 1, PerRow)
    RowIndex := CardIntDiv(Index, PerRow)
    ColIndex := Index - RowIndex * PerRow
    InThisRow := if (RowIndex = Rows - 1) then Count - RowIndex * PerRow else PerRow
    CellW := Style.WidthPx + GapPx
    CellH := Style.HeightPx + GapPx
    RowW := CellW * (InThisRow * 1.0)
    GridH := CellH * (Rows * 1.0)
    Left := CenterX * 1920.0 - RowW * 0.5 + CellW * (ColIndex * 1.0) + GapPx * 0.5
    Top := CenterY * 1080.0 - GridH * 0.5 + CellH * (RowIndex * 1.0) + GapPx * 0.5
    widget_screen_rect{MinX := Left / 1920.0, MinY := Top / 1080.0, MaxX := (Left + Style.WidthPx) / 1920.0, MaxY := (Top + Style.HeightPx) / 1080.0}

# A rectangle on the screen (screen ratios. Top-left 0,0 to bottom-right 1,1)
widget_screen_rect<public> := struct:
    MinX<public>:float = 0.0
    MinY<public>:float = 0.0
    MaxX<public>:float = 0.0
    MaxY<public>:float = 0.0

# If point (X, Y) (screen ratios) is inside Rect, return the position inside Rect (top-left 0,0 to bottom-right 1,1). Fails if outside
(Rect:widget_screen_rect).LocalOf<public>(X:float, Y:float)<decides><transacts>:vector2 =
    X >= Rect.MinX
    X <= Rect.MaxX
    Y >= Rect.MinY
    Y <= Rect.MaxY
    W := Rect.MaxX - Rect.MinX
    H := Rect.MaxY - Rect.MinY
    W > 0.0
    H > 0.0
    vector2{X := (X - Rect.MinX) / W, Y := (Y - Rect.MinY) / H}

# Chosen-card effect (the Library's fixed sequence): darken the other cards and sweep a light over the chosen card. Waits until it ends
PlayCardChosen<public>(Cards:[]widget_card_button, Chosen:int, ShineSeconds:float, ?DimAmount:float = 0.55)<suspends>:void =
    for (Index -> Card : Cards, Index <> Chosen):
        Card.ClearPressed()
        Card.SetHighlighted(false)
        Card.SetDimmed(DimAmount)
    if (Card := Cards[Chosen]):
        Card.ClearPressed()
        Card.PlayShine(ShineSeconds)

# Enlarge the chosen card while moving it to the center of the screen, then fade it out (a copy is made on top of the Root canvas). Rect is the original card's rectangle (screen ratios). Waits until it ends
#   The copy is: the Skin's background (newly built) if there is a Skin, plus the image and the name. Over Seconds it grows to TargetScale and moves to the screen center, fading out in the second half
PlayCardZoom<public>(Root:canvas, Card:widget_card, Style:widget_card_style, Rect:widget_screen_rect, Seconds:float, TargetScale:float, ?Skin:?widget_card_skin = false)<suspends>:void =
    var SkinView:?widget_card_skin_view = false
    if (Found := Skin?):
        Made := Found.MakeSkin(Card, Style)
        set SkinView = option{Made}
    Spacer := color_block{DefaultColor := Style.BackgroundColor, DefaultOpacity := ToOpacity(if (SkinView?) then 0.0 else Style.BackgroundOpacity), DefaultDesiredSize := vector2{X := Style.WidthPx, Y := Style.HeightPx}}
    ImageW := Style.WidthPx - Style.BorderPx * 2.0 - Style.PaddingPx * 2.0
    SkinDrawsImage := if (Found := SkinView?) then Found.DrawsImage() else false
    Image:?texture_block = if (not SkinDrawsImage?, Texture := Card.Image?) then option{texture_block{DefaultImage := Texture, DefaultDesiredSize := vector2{X := ImageW, Y := Style.ImageHeightPx}}} else false
    Title := text_block{DefaultText := StringToMessage(Card.Title), DefaultTextColor := Style.TitleColor, DefaultTextSize := Style.TitleSize}
    Layers := overlay{}
    Layers.AddWidget(overlay_slot{Widget := Spacer, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill})
    if (Found := SkinView?):
        Layers.AddWidget(overlay_slot{Widget := Found.GetWidget(), HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill})
    if (Found := Image?):
        Layers.AddWidget(overlay_slot{Widget := Found, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Top, Padding := margin{Top := Style.BorderPx + Style.PaddingPx}})
    Layers.AddWidget(overlay_slot{Widget := Title, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Center})
    StartX := (Rect.MinX + Rect.MaxX) * 0.5
    StartY := (Rect.MinY + Rect.MaxY) * 0.5
    var Slot:canvas_slot = MakeScreenSlot(Layers, StartX, StartY, ?ZOrder := 1000)
    Root.AddWidget(Slot)
    Start := GetSimulationElapsedTime()
    loop:
        T := if (Seconds > 0.0) then Min((GetSimulationElapsedTime() - Start) / Seconds, 1.0) else 1.0
        Eased := T * T * (3.0 - 2.0 * T)
        Scale := 1.0 + (TargetScale - 1.0) * Eased
        Spacer.SetDesiredSize(vector2{X := Style.WidthPx * Scale, Y := Style.HeightPx * Scale})
        if (Found := Image?):
            Found.SetDesiredSize(vector2{X := ImageW * Scale, Y := Style.ImageHeightPx * Scale})
            if (T > 0.6):
                Found.SetVisibility(widget_visibility.Hidden)
        Title.SetTextSize(Style.TitleSize * Scale)
        Fade := if (T < 0.4) then 0.0 else (T - 0.4) / 0.6
        Title.SetTextOpacity(ToOpacity(1.0 - Fade))
        if (Found := SkinView?):
            Found.SetFade(Fade)
            Found.SetLight(vector2{X := 0.5, Y := 0.35}, 1.0)
        else:
            Spacer.SetOpacity(ToOpacity(Style.BackgroundOpacity * (1.0 - Fade)))
        # Move toward the screen center (re-place)
        Root.RemoveWidget(Layers)
        set Slot = MakeScreenSlot(Layers, StartX + (0.5 - StartX) * Eased, StartY + (0.5 - StartY) * Eased, ?ZOrder := 1000)
        Root.AddWidget(Slot)
        if (T >= 1.0):
            break
        Sleep(0.0)
    Root.RemoveWidget(Layers)

# Value rounded up to an int (0 if 0 or less)
CardRoundUp<internal>(Value:float)<transacts>:int =
    if (Value <= 0.0) then 0 else if (Up := Ceil[Value]) then Up else 0

# Quotient of A divided by B (rounded down. 0 if B is 0 or less)
CardIntDiv<internal>(A:int, B:int)<transacts>:int =
    if (B > 0, Q := Floor[(A * 1.0) / (B * 1.0)]) then Q else 0

Clamp01<internal>(Value:float)<transacts>:float =
    if (Value < 0.0) then 0.0 else if (Value > 1.0) then 1.0 else Value

# Image (an AccentColor band if none)
MakeCardImage<internal>(Card:widget_card, Style:widget_card_style, WidthPx:float):widget =
    Size := vector2{X := WidthPx, Y := Style.ImageHeightPx}
    if (Image := Card.Image?):
        texture_block{DefaultImage := Image, DefaultDesiredSize := Size}
    else:
        color_block{DefaultColor := Card.AccentColor, DefaultDesiredSize := Size}

MakeCardText<internal>(Text:string, TextColor:color, Size:float, WrapWidthPx:float):widget =
    Made := text_block:
        DefaultText := StringToMessage(Text)
        DefaultTextColor := TextColor
        DefaultTextSize := Size
        DefaultJustification := text_justification.Left
    set Made.AutoWrap = true
    set Made.WrapWidth = WrapWidthPx
    Made

MakeCardBadge<internal>(Card:widget_card, Style:widget_card_style):widget =
    Label := text_block:
        DefaultText := StringToMessage(Card.Badge)
        DefaultTextColor := Style.BadgeTextColor
        DefaultTextSize := Style.BadgeSize
    Back := color_block{DefaultColor := Card.AccentColor, DefaultOpacity := 0.95}
    Badge := overlay{}
    Badge.AddWidget(overlay_slot{Widget := Back, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill})
    Badge.AddWidget(overlay_slot{Widget := Label, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Center, Padding := margin{Left := 10.0, Top := 4.0, Right := 10.0, Bottom := 4.0}})
    Badge
