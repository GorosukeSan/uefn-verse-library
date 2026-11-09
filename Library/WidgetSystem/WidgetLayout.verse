using { /Verse.org/Simulation }
using { /Verse.org/Colors }
using { /UnrealEngine.com/Temporary/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /Fortnite.com/UI }

# canvas に置く部品の配置の補助。位置は画面に対する割合（0.0〜1.0。左上が 0, 0）

# Widget を、画面の割合 (XRatio, YRatio) の位置に、その点を中心にして中身の大きさで置く canvas_slot
#   ZOrder はこの canvas の中で重ねる順（大きいほど手前。既定 0）
MakeScreenSlot<public>(Widget:widget, XRatio:float, YRatio:float, ?ZOrder:int = 0)<transacts>:canvas_slot =
    canvas_slot:
        Anchors := anchors{Minimum := vector2{X := XRatio, Y := YRatio}, Maximum := vector2{X := XRatio, Y := YRatio}}
        Alignment := vector2{X := 0.5, Y := 0.5}
        SizeToContent := true
        ZOrder := if (Z := slot_zorder[ZOrder]) then Z else 0
        Widget := Widget

# Widget を画面いっぱいに置く canvas_slot（全面の暗幕・背景など）
MakeFullScreenSlot<public>(Widget:widget)<transacts>:canvas_slot =
    canvas_slot:
        Anchors := anchors{Minimum := vector2{X := 0.0, Y := 0.0}, Maximum := vector2{X := 1.0, Y := 1.0}}
        Offsets := margin{Left := 0.0, Top := 0.0, Right := 0.0, Bottom := 0.0}
        Widget := Widget

# Widget 1 つを、画面の割合 (XRatio, YRatio) を中心に置いた canvas を作る（CreateWidget で 1 つだけ出すとき）
MakeScreenCanvas<public>(Widget:widget, XRatio:float, YRatio:float):canvas =
    Root := canvas{}
    Root.AddWidget(MakeScreenSlot(Widget, XRatio, YRatio))
    Root

# Widgets を縦（Orientation）に並べた stack_box。部品のあいだに PaddingPx の余白
MakeStack<public>(Widgets:[]widget, Orientation:orientation, PaddingPx:float):stack_box =
    Stack := stack_box{Orientation := Orientation}
    for (Widget : Widgets):
        Slot := stack_box_slot:
            Widget := Widget
            HorizontalAlignment := horizontal_alignment.Fill
            Padding := margin{Left := PaddingPx, Top := PaddingPx, Right := PaddingPx, Bottom := PaddingPx}
        Stack.AddWidget(Slot)
    Stack

# 文字の見た目（色・大きさ）。ゲームのテーマで 1 つずつ作って使い回す
widget_text_style<public> := struct:
    # 文字の色
    Color<public>:color = NamedColors.White
    # 文字の大きさ（1080p のピクセル）。0 なら Fortnite の既定の大きさ
    Size<public>:float = 0.0
    # 揃え
    Justification<public>:text_justification = text_justification.Center

# Style の色・大きさの text_block（Size が 0 なら大きさは既定のまま）
MakeStyledText<public>(Text:message, Style:widget_text_style):text_block =
    if (Style.Size > 0.0):
        text_block{DefaultText := Text, DefaultTextColor := Style.Color, DefaultTextSize := Style.Size, DefaultJustification := Style.Justification}
    else:
        text_block{DefaultText := Text, DefaultTextColor := Style.Color, DefaultJustification := Style.Justification}

# Widget の後ろに板（BackColor、不透明度 Opacity）を敷く。Opacity が 0 以下なら Widget をそのまま返す。PaddingPx は板の内側の余白
MakePanel<public>(Widget:widget, BackColor:color, Opacity:float, PaddingPx:float):widget =
    if (Opacity <= 0.0):
        return Widget
    Back := color_block{DefaultColor := BackColor, DefaultOpacity := ToOpacity(Opacity)}
    Panel := overlay{}
    Panel.AddWidget(overlay_slot{Widget := Back, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill})
    Panel.AddWidget(overlay_slot{Widget := Widget, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Center, Padding := margin{Left := PaddingPx, Top := PaddingPx * 0.5, Right := PaddingPx, Bottom := PaddingPx * 0.5}})
    Panel

# 0.0〜1.0 の不透明度（color_block の DefaultOpacity の型）
widget_opacity<public> := type{_X:float where 0.0 <= _X, _X <= 1.0}

# Value を 0.0〜1.0 に収めた不透明度
ToOpacity<public>(Value:float)<transacts>:widget_opacity =
    if (Clamped := widget_opacity[Value]) then Clamped else if (Value < 0.0) then 0.0 else 1.0

# canvas_slot の ZOrder の型（0 以上）
slot_zorder<public> := type{_X:int where 0 <= _X, _X <= 2147483647}
