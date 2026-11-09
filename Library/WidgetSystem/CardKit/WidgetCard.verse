using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Colors }
using { /UnrealEngine.com/Temporary/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /Fortnite.com/UI }
using { WidgetSystem }

# カード 1 枚分のデータ（画面に出す中身）。card_info_component の GetCard で作るか、コードで直接作る
#   人ごとに変わる文字（その人の記録など）は、GetCard で作ったあと WithSubtitle / WithBadge で差し替える
widget_card<public> := struct:
    # コードから押すときの ID（AwaitButtonChoice の ButtonIds に使う。MCPSystem の widget.press でも使える）
    Id<public>:string = ""
    # 名前（大きい文字）
    Title<public>:string = ""
    # 名前の下の 1 行（空なら出さない）
    Subtitle<public>:string = ""
    # 説明（折り返す。空なら出さない）
    Description<public>:string = ""
    # 右上の小さい札（難しさ・新着など。空なら出さない）
    Badge<public>:string = ""
    # 上の画像（無ければ AccentColor の帯）
    Image<public>:?texture = false
    # カードの色（画像が無いときの帯・札の色）
    AccentColor<public>:color = NamedColors.SkyBlue
    # 押せるか（false なら薄くして押せない）
    Enabled<public>:logic = true

# Card の Subtitle を Text にしたカード
(Card:widget_card).WithSubtitle<public>(Text:string)<transacts>:widget_card =
    widget_card{Id := Card.Id, Title := Card.Title, Subtitle := Text, Description := Card.Description, Badge := Card.Badge, Image := Card.Image, AccentColor := Card.AccentColor, Enabled := Card.Enabled}

# Card の Badge を Text にしたカード
(Card:widget_card).WithBadge<public>(Text:string)<transacts>:widget_card =
    widget_card{Id := Card.Id, Title := Card.Title, Subtitle := Card.Subtitle, Description := Card.Description, Badge := Text, Image := Card.Image, AccentColor := Card.AccentColor, Enabled := Card.Enabled}

# Card の Enabled を Value にしたカード
(Card:widget_card).WithEnabled<public>(Value:logic)<transacts>:widget_card =
    widget_card{Id := Card.Id, Title := Card.Title, Subtitle := Card.Subtitle, Description := Card.Description, Badge := Card.Badge, Image := Card.Image, AccentColor := Card.AccentColor, Enabled := Value}

# カードの見た目の決まり（大きさ・色・文字の大きさ）。ゲームごとに 1 つ作り、同じ画面のカードはすべて同じものを使う
widget_card_style<public> := struct:
    # カードの幅（1080p のピクセル。枠を含む）
    WidthPx<public>:float = 320.0
    # カードの高さ（1080p のピクセル。枠を含む）。中身がこれより短くても、この高さにそろえる（ポインターの当たりを決めるため）
    HeightPx<public>:float = 420.0
    # 画像（無ければ色の帯）の高さ
    ImageHeightPx<public>:float = 180.0
    # 中の余白
    PaddingPx<public>:float = 12.0
    # 枠の太さ（0 なら枠なし）
    BorderPx<public>:float = 4.0
    # ふだんの枠の色・不透明度
    BorderColor<public>:color = NamedColors.White
    BorderOpacity<public>:float = 0.0
    # 選ばれている（マウスが乗っている・パッドのフォーカスがある）ときの枠の色
    HighlightColor<public>:color = NamedColors.Gold
    # 選ばれているときの地の不透明度（ふだんより少し濃くして浮かせる）
    HighlightBackgroundOpacity<public>:float = 1.0
    # 押し込み（Virtual Pointer で押しているあいだ）：押した側がどれだけ奥へ沈むか（px）と、影の濃さ
    PressDepthPx<public>:float = 10.0
    PressShadeOpacity<public>:float = 0.18
    # 地（Skin）があるとき、暗くする板をカードの縁からこれだけ内側に収める（px。マテリアルの角丸の本体の内側。外へはみ出さない）
    SkinInsetPx<public>:float = 9.0
    # カードの地の色
    BackgroundColor<public>:color = NamedColors.White
    # 地の不透明度（0.0〜1.0）
    BackgroundOpacity<public>:float = 0.92
    # 名前の色・大きさ
    TitleColor<public>:color = NamedColors.Black
    TitleSize<public>:float = 26.0
    # 名前の下の 1 行の色・大きさ
    SubtitleColor<public>:color = NamedColors.DimGray
    SubtitleSize<public>:float = 18.0
    # 説明の色・大きさ
    DescriptionColor<public>:color = NamedColors.DimGray
    DescriptionSize<public>:float = 16.0
    # 札の文字の色・大きさ（札の地はカードの AccentColor）
    BadgeTextColor<public>:color = NamedColors.White
    BadgeSize<public>:float = 16.0
    # 押せないカードの不透明度
    DisabledOpacity<public>:float = 0.45

# カードの地の見た目を差し替える（マテリアルのラメ・ホロなど）。MakeCardView の ?Skin に渡すと、カード 1 枚ごとに MakeSkin が呼ばれる
#   ゲームの側で実装する（マテリアルのパラメータの名前はゲームのアセットごとに違うので、Library は知らない）
widget_card_skin<public> := interface:
    # Card 1 枚分の地を作る
    MakeSkin<public>(Card:widget_card, Style:widget_card_style):widget_card_skin_view

# カード 1 枚分の地（widget_card_skin が作る）。カードの状態が変わるたびに呼ばれる
widget_card_skin_view<public> := interface:
    # カードの地として重ねる widget（カードの大きさいっぱいに広げる）
    GetWidget<public>():widget
    # 選ばれている表示（マウスが乗る・パッドのフォーカス）になった / 外れた
    SetHighlight<public>(Value:logic):void
    # 押し込み。Local はカードの中の位置（左上 0,0 〜 右下 1,1）、Amount は 0（離した）〜 1（押している）
    SetPress<public>(Local:vector2, Amount:float):void
    # 傾き。Local（カードの中の位置）へ向かって傾く。Amount は 0（傾かない）〜 1
    SetTilt<public>(Local:vector2, Amount:float):void
    # 擬似ライト。ライトの位置（このカードの中の位置。外なら 0〜1 の外）と強さ（0 で消す）
    SetLight<public>(Local:vector2, Strength:float):void
    # 消えていく度合い（0 = ふつう、1 = 見えない）
    SetFade<public>(Value:float):void
    # 地がカードの画像（widget_card.Image）も描くなら true（そのときカードは texture_block を置かず、場所だけ空ける）。地は輪郭（選ばれている表示）も描く
    DrawsImage<public>():logic

# 押せるカード 1 枚（button・枠・押し込みの影）。MakeCardView で作る。待つときは Button を View.AwaitButtonChoice に渡す
#   見た目の状態は 2 つ：選ばれている（SetHighlighted。マウスが乗る・パッドのフォーカス）と、押し込み（SetPressed。Virtual Pointer で押しているあいだ）
#   押し込みのあいだは選ばれている表示より押し込みを優先する（マウスの位置とハイライトが食い違っても、押し込みの見た目だけを出す）
widget_card_button<public> := class<internal>:
    # 中身のデータ
    Card<public>:widget_card
    # 見た目の決まり
    Style<public>:widget_card_style
    # 押せる部分（AwaitButtonChoice に渡す）
    Button<public>:button
    Frame<internal>:color_block
    Back<internal>:color_block
    Shade<internal>:color_block
    Content<internal>:widget
    Layers<internal>:overlay
    # 地を差し替えたとき（MakeCardView の ?Skin）の、カード 1 枚分の地
    SkinView<internal>:?widget_card_skin_view = false

    var<private> Highlighted:logic = false
    var<private> Pressed:logic = false

    # 選ばれている表示にする / 戻す（押し込みのあいだは見た目を変えず、覚えておくだけ）
    SetHighlighted<public>(Value:logic):void =
        set Highlighted = Value
        if (not Pressed?):
            ApplyFrame()

    # 選ばれている表示なら成功する
    IsHighlighted<public>()<decides><transacts>:void =
        Highlighted?

    # Local（カードの中の位置。左上 0,0 〜 右下 1,1）を押し込む。押した側ほど奥へ沈み（中身がずれ）、影が濃くなる
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
        # 地（マテリアル）があれば押し込みの暗さは地が出す（四角い板は使わない）
        Shade.SetOpacity(ToOpacity(if (SkinView?) then 0.0 else Style.PressShadeOpacity))
        if (Skin := SkinView?):
            Skin.SetPress(vector2{X := LX, Y := LY}, 1.0)
            Skin.SetHighlight(true)
        else:
            Frame.SetColor(Style.HighlightColor)
            Frame.SetOpacity(ToOpacity(1.0))

    # 押し込みをやめる（選ばれている表示に戻す）
    ClearPressed<public>():void =
        if (Pressed?):
            set Pressed = false
            PlaceContent(BaseInset())
            Shade.SetOpacity(ToOpacity(0.0))
            if (Skin := SkinView?):
                Skin.SetPress(vector2{X := 0.5, Y := 0.5}, 0.0)
            ApplyFrame()

    # 押し込んでいるなら成功する
    IsPressed<public>()<decides><transacts>:void =
        Pressed?

    # この人の画面に出ているあいだ、マウスが乗る・フォーカスが来るのに合わせて選ばれている表示を変える（閉じたら終わる。spawn で呼ぶ）
    TrackHighlight<public>(View:widget_view)<suspends>:void =
        race:
            View.HiddenEvent.Await()
            loop:
                Button.HighlightEvent().Await()
                SetHighlighted(true)
            loop:
                Button.UnhighlightEvent().Await()
                SetHighlighted(false)

    # 暗くする（ほかのカードが選ばれたときなど。0 で戻す）。押し込みの影と同じ板を使う
    SetDimmed<public>(Amount:float):void =
        Shade.SetOpacity(ToOpacity(Amount))

    # 選ばれた演出：Seconds かけて、ライトが左上の外から右下の外へ斜めに走り、傾きがライトを追う（地（Skin）が無ければ枠が光るだけ）。毎フレーム進める
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
            # 地（マテリアルなど）が輪郭を描くので、四角い枠は出さない
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

    # 中身と影をふだんの位置に置く（MakeCardView から）
    PlaceBase<internal>():void =
        PlaceContent(BaseInset())

    BaseInset<private>():margin =
        margin{Left := Style.BorderPx, Top := Style.BorderPx, Right := Style.BorderPx, Bottom := Style.BorderPx}

    PlaceContent<private>(Inset:margin):void =
        # 地（マテリアル）があるとき、暗くする板は角丸の本体の内側に収める
        ShadeInset := if (SkinView?) then margin{Left := Max(Inset.Left, Style.SkinInsetPx), Top := Max(Inset.Top, Style.SkinInsetPx), Right := Max(Inset.Right, Style.SkinInsetPx), Bottom := Max(Inset.Bottom, Style.SkinInsetPx)} else Inset
        Layers.RemoveWidget(Content)
        Layers.RemoveWidget(Shade)
        Layers.AddWidget(overlay_slot{Widget := Content, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill, Padding := Inset})
        Layers.AddWidget(overlay_slot{Widget := Shade, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill, Padding := ShadeInset})

# 押せるカード 1 枚を作る（枠・地・画像・名前・札・説明・押し込みの影）。大きさは Style の WidthPx × HeightPx
#   ?Skin を渡すと、地（色の板）の代わりに Skin が作る widget（マテリアルなど）を敷き、選ばれている表示・押し込みを Skin にも知らせる
MakeCardView<public>(Card:widget_card, Style:widget_card_style, ?Skin:?widget_card_skin = false):widget_card_button =
    Frame := color_block{DefaultColor := Style.BorderColor, DefaultOpacity := ToOpacity(Style.BorderOpacity), DefaultDesiredSize := vector2{X := Style.WidthPx, Y := Style.HeightPx}}
    Back := color_block:
        DefaultColor := Style.BackgroundColor
        DefaultOpacity := ToOpacity(if (Card.Enabled?) then Style.BackgroundOpacity else Style.BackgroundOpacity * Style.DisabledOpacity)
    Shade := color_block{DefaultColor := NamedColors.Black, DefaultOpacity := ToOpacity(0.0)}
    # option{...} の中は失敗しうる文脈なので、MakeSkin（no_rollback）は外で呼んでから包む
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
    View

# 押せるカード（button だけ）を作る。選ばれている表示・押し込みが要るなら MakeCardView を使う
MakeCardButton<public>(Card:widget_card, Style:widget_card_style):button =
    MakeCardView(Card, Style).Button

# カードの見た目だけ（押せない・枠なし。一覧の表示やリザルトなど）
#   ?ImageSpaceOnly なら画像の代わりに同じ大きさの透明な場所を置く（地が画像を描くとき）
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

# Buttons を Columns 列ずつの行に並べる（行も列も GapPx あける）。Columns が 1 未満なら 1 列
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

# MakeCardGrid で Count 枚を並べ、その真ん中を画面の割合 (CenterX, CenterY) に置いたときの、Index 枚目のカードの範囲（画面の割合。左上 X,Y・右下 X,Y）
#   1080p（16:9）を基準にした計算。画面の比が違うと少しずれる
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

# 画面の中の長方形（画面の割合。左上 0,0 〜 右下 1,1）
widget_screen_rect<public> := struct:
    MinX<public>:float = 0.0
    MinY<public>:float = 0.0
    MaxX<public>:float = 0.0
    MaxY<public>:float = 0.0

# 点 (X, Y)（画面の割合）が Rect の中なら、Rect の中の位置（左上 0,0 〜 右下 1,1）を返す。外なら失敗する
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

# 選ばれたカードの演出（Library の決まった流れ）：ほかのカードを暗くし、選ばれたカードにライトを走らせる。終わるまで待つ
PlayCardChosen<public>(Cards:[]widget_card_button, Chosen:int, ShineSeconds:float, ?DimAmount:float = 0.55)<suspends>:void =
    for (Index -> Card : Cards, Index <> Chosen):
        Card.ClearPressed()
        Card.SetHighlighted(false)
        Card.SetDimmed(DimAmount)
    if (Card := Cards[Chosen]):
        Card.ClearPressed()
        Card.PlayShine(ShineSeconds)

# 選ばれたカードを画面の真ん中へ寄せながら拡大して消す（Root の canvas の上に写しを作る）。Rect は元のカードの範囲（画面の割合）。終わるまで待つ
#   写しは、Skin があれば Skin の地（新しく作る）＋画像＋名前。Seconds かけて TargetScale 倍・画面の真ん中へ、後半で消える
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
        # 画面の真ん中へ寄せる（置き直す）
        Root.RemoveWidget(Layers)
        set Slot = MakeScreenSlot(Layers, StartX + (0.5 - StartX) * Eased, StartY + (0.5 - StartY) * Eased, ?ZOrder := 1000)
        Root.AddWidget(Slot)
        if (T >= 1.0):
            break
        Sleep(0.0)
    Root.RemoveWidget(Layers)

# Value を切り上げた int（0 以下なら 0）
CardRoundUp<internal>(Value:float)<transacts>:int =
    if (Value <= 0.0) then 0 else if (Up := Ceil[Value]) then Up else 0

# A を B で割った商（切り捨て。B が 0 以下なら 0）
CardIntDiv<internal>(A:int, B:int)<transacts>:int =
    if (B > 0, Q := Floor[(A * 1.0) / (B * 1.0)]) then Q else 0

Clamp01<internal>(Value:float)<transacts>:float =
    if (Value < 0.0) then 0.0 else if (Value > 1.0) then 1.0 else Value

# 画像（無ければ AccentColor の帯）
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
