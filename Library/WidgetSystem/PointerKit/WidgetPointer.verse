using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Input }
using { /Verse.org/Input/UI }
using { /Fortnite.com/Characters }
using { MovementSystem }
using { WidgetSystem }
using { WidgetSystem.CardKit }

# Virtual Pointer（入力の割り当て TouchMapping の PointerSelect）と画面の部品をつなぐ（実験的。v43.00）
#   ・ポインターの位置が届くのは押しているあいだ（BeginDetect → DetectionOngoing → EndDetect）だけ。押していないときの位置（ホバー）は取れない
#   ・届く位置は「viewport の座標」。画面の大きさを取る API が無いので、DeprojectViewportToWorld の光線と視点の向きの差から画面の割合（左上 0,0 〜 右下 1,1）に直す。
#     カメラの水平の画角（FieldOfViewDegrees）と 16:9 を前提にするので、違う画角・画面の比では少しずれる
#   ⚠ 未確認：メニュー（Mode = Menu）を出しているあいだに PointerSelect が届くか。届かなければ何も起きない（ボタンはふだんどおり押せる）

# Player の viewport の座標 ViewportPosition（PointerSelect の値）を、画面の割合 (横, 縦)（左上 0,0 〜 右下 1,1）に直す。視点の後ろなど直せなければ失敗する
#   FieldOfViewDegrees は今のカメラの水平の画角（度）
(Player:player).PointerToScreenRatio<public>(ViewportPosition:vector3, FieldOfViewDegrees:float)<decides><transacts>:tuple(float, float) =
    Ray := Player.DeprojectViewportToWorld(ViewportPosition)
    Forward := Player.GetFortCharacter[].GetViewDirection()
    Left := CrossProduct(vector3{Up := 1.0}, Forward).MakeUnitVector()
    Up := CrossProduct(Forward, Left)
    Depth := DotProduct(Ray.Direction, Forward)
    Depth > 0.01
    TanH := Tan(FieldOfViewDegrees * PiFloat / 360.0)
    TanV := TanH * 9.0 / 16.0
    TanH > 0.0
    X := -DotProduct(Ray.Direction, Left) / Depth / TanH
    Y := DotProduct(Ray.Direction, Up) / Depth / TanV
    (0.5 + 0.5 * X, 0.5 - 0.5 * Y)

# View が出ているあいだ、その人の Virtual Pointer で押したカードを押し込む（Cards[i] の範囲は Rects[i]。CardGridRect で作る）。閉じたら終わる（spawn で呼ぶ）
#   押した位置のカードが沈み、ドラッグに合わせて沈む位置が動き、離すと戻る。押しているあいだは選ばれている表示（マウスが乗る）より押し込みを優先する
#   この人に TouchMapping を足し、終わると外す（ほかの部品が同じ人に TouchMapping を足していると、それも外れる）
RunCardPointerPress<public>(View:widget_view, Cards:[]widget_card_button, Rects:[]widget_screen_rect, FieldOfViewDegrees:float)<suspends>:void =
    defer:
        for (Card : Cards):
            Card.ClearPressed()
    if (PlayerInput := GetPlayerInput[View.Player]):
        PlayerInput.AddInputMapping(TouchMapping)
        defer:
            PlayerInput.RemoveInputMapping(TouchMapping)
        Events := PlayerInput.GetInputEvents(PointerSelect)
        race:
            View.HiddenEvent.Await()
            RunFedPointer(View, Cards, Rects)
            loop:
                Began := Events.BeginDetectEvent.Await()
                PressCardAt(View.Player, Began(1), Cards, Rects, FieldOfViewDegrees)
                race:
                    Events.EndDetectEvent.Await()
                    loop:
                        Ongoing := Events.DetectionOngoingEvent.Await()
                        PressCardAt(View.Player, Ongoing(1), Cards, Rects, FieldOfViewDegrees)
                for (Card : Cards):
                    Card.ClearPressed()
    else:
        race:
            View.HiddenEvent.Await()
            RunFedPointer(View, Cards, Rects)

# コードから差し込んだポインター（widget_view.InjectPointer。MCP の widget.pointer など）を、押下と同じに扱う
RunFedPointer<internal>(View:widget_view, Cards:[]widget_card_button, Rects:[]widget_screen_rect)<suspends>:void =
    loop:
        Fed := View.PointerFed.Await()
        if (Fed(2)?):
            PressCardAtRatio(Fed(0), Fed(1), Cards, Rects)
        else:
            for (Card : Cards):
                Card.ClearPressed()

# ViewportPosition の下のカードを押し込み、ほかのカードの押し込みを戻す
PressCardAt<internal>(Player:player, ViewportPosition:vector3, Cards:[]widget_card_button, Rects:[]widget_screen_rect, FieldOfViewDegrees:float):void =
    if (Point := Player.PointerToScreenRatio[ViewportPosition, FieldOfViewDegrees]):
        PressCardAtRatio(Point(0), Point(1), Cards, Rects)

# 画面の割合 (X, Y) の下のカードを押し込み、ほかのカードの押し込みを戻す
PressCardAtRatio<public>(X:float, Y:float, Cards:[]widget_card_button, Rects:[]widget_screen_rect):void =
    for (Index -> Card : Cards):
        if (Rect := Rects[Index], Local := Rect.LocalOf[X, Y]):
            Card.SetPressed(Local)
        else:
            Card.ClearPressed()
