using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Input }
using { /Verse.org/Input/UI }
using { /Fortnite.com/Characters }
using { MovementSystem }
using { InputSystem }
using { WidgetSystem }
using { WidgetSystem.CardKit }

# Connects the Virtual Pointer (PointerSelect of the TouchMapping input mapping) to screen parts (experimental; v43.00)
#   - The pointer position arrives only while pressed (BeginDetect -> DetectionOngoing -> EndDetect). The position while not pressed (hover) is not available
#   - The position arrives in "viewport coordinates". There is no API for the screen size, so it is converted to a screen ratio (top-left 0,0 to bottom-right 1,1) from the difference between the DeprojectViewportToWorld ray and the view direction.
#     It assumes the horizontal camera field of view (FieldOfViewDegrees) and 16:9, so it drifts slightly with a different field of view or aspect ratio
#   ⚠ Unconfirmed: whether PointerSelect arrives while a menu (Mode = Menu) is shown. If not, nothing happens (buttons can still be pressed as usual)

# Convert Player's viewport coordinate ViewportPosition (the PointerSelect value) to a screen ratio (horizontal, vertical) (top-left 0,0 to bottom-right 1,1). Fails if it cannot be converted, e.g. behind the view
#   FieldOfViewDegrees is the current horizontal camera field of view (degrees)
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

# While View is shown, press in the card that person presses with the Virtual Pointer (the rectangle of Cards[i] is Rects[i]; build them with CardGridRect). Ends when closed (call with spawn)
#   The card at the pressed position sinks, the sunken point follows the drag, and releasing restores it. While pressed, the press-in takes priority over the selected look (mouse over)
#   Leases the TouchMapping for this person (InputSystem's LeaseInputMapping, name "touch") and returns it when done (it stays if another part leased it under the same name)
#   Only when ?AddTouchMapping is true does it add the TouchMapping to this person and receive the Virtual Pointer (default false).
#   ⚠ Adding the TouchMapping can make the mouse captured by the pointer so the view (camera) cannot be turned (reported as "cannot move the camera" in UEFN v43.00).
#   When false, only injections from code (widget_view.InjectPointer; MCP's widget.pointer) are received
RunCardPointerPress<public>(View:widget_view, Cards:[]widget_card_button, Rects:[]widget_screen_rect, FieldOfViewDegrees:float, ?AddTouchMapping:logic = false)<suspends>:void =
    defer:
        for (Card : Cards):
            Card.ClearPressed()
    if (AddTouchMapping?, PlayerInput := GetPlayerInput[View.Player]):
        MaybeLease := View.Player.LeaseInputMapping(TouchMappingLeaseKey, TouchMapping)
        defer:
            if (Lease := MaybeLease?):
                Lease.Release()
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

# Treat a pointer injected from code (widget_view.InjectPointer; MCP's widget.pointer, etc.) the same as a press
RunFedPointer<internal>(View:widget_view, Cards:[]widget_card_button, Rects:[]widget_screen_rect)<suspends>:void =
    loop:
        Fed := View.PointerFed.Await()
        if (Fed(2)?):
            PressCardAtRatio(Fed(0), Fed(1), Cards, Rects)
        else:
            for (Card : Cards):
                Card.ClearPressed()

# Press in the card under ViewportPosition and release the press-in of the other cards
PressCardAt<internal>(Player:player, ViewportPosition:vector3, Cards:[]widget_card_button, Rects:[]widget_screen_rect, FieldOfViewDegrees:float):void =
    if (Point := Player.PointerToScreenRatio[ViewportPosition, FieldOfViewDegrees]):
        PressCardAtRatio(Point(0), Point(1), Cards, Rects)

# Press in the card under screen ratio (X, Y) and release the press-in of the other cards
PressCardAtRatio<public>(X:float, Y:float, Cards:[]widget_card_button, Rects:[]widget_screen_rect):void =
    for (Index -> Card : Cards):
        if (Rect := Rects[Index], Local := Rect.LocalOf[X, Y]):
            Card.SetPressed(Local)
        else:
            Card.ClearPressed()
