using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Colors }
using { /UnrealEngine.com/Temporary/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /Fortnite.com/UI }
using { PlayerSystem }
using { SceneGraphSystem }
using { WidgetSystem }
using { WidgetSystem.CardKit }
using { PickupSystem }
using { PickupSystem.TooltipKit }

# Look and motion of the pickup effect HUD (pickup_effect_hud_component). Make one per game theme and put it in Style (from code; not shown in the editor)
#   Sizes are 1080p pixels, positions are screen ratios (top-left 0, 0), times are seconds. Per-effect color, name, description and image belong to the effect prefab's card_info_component (not here)
pickup_effect_hud_style<public> := struct:
    # ---- Pickup toast (two lines of text shown one at a time above the slots. Line 1 "Got {name}!", line 2 the description) ----
    # Position of the toast center (screen width / height ratio)
    ToastXRatio<public>:float = 0.5
    ToastYRatio<public>:float = 0.72
    # Format of line 1. {0} is replaced by the effect name (the card's Title, in AccentColor). Without {0} only the format text is shown. Empty hides line 1
    ToastFormat<public>:string = "Got \{0\}!"
    # Size of line 1 and the color of the text other than the name
    ToastTitleSize<public>:float = 44.0
    ToastTitleColor<public>:color = NamedColors.White
    # Color, size and wrap width of line 2 (the card's Description) (0 means no wrapping)
    ToastDescriptionColor<public>:color = NamedColors.White
    ToastDescriptionSize<public>:float = 26.0
    ToastDescriptionWrapPx<public>:float = 900.0
    # Gap between line 1 and line 2
    ToastLineGapPx<public>:float = 4.0
    # Color and opacity of the panel behind the text (0 hides it), and the panel's inner padding
    ToastBackColor<public>:color = NamedColors.Black
    ToastBackOpacity<public>:float = 0.0
    ToastPaddingPx<public>:float = 16.0
    # Seconds to appear (grows while fading in), seconds to hold, seconds to disappear (slides up while fading out)
    ToastInSeconds<public>:float = 0.2
    ToastHoldSeconds<public>:float = 1.1
    ToastOutSeconds<public>:float = 0.3
    # Initial scale when appearing (1.0 = normal) and the overshoot strength (0 means no overshoot; 1.7 overshoots by about 10%)
    ToastStartScale<public>:float = 0.6
    ToastOvershoot<public>:float = 1.7
    # Distance to slide up when disappearing
    ToastOutSlidePx<public>:float = 24.0
    # Pulse applied to the visible toast when the same effect is picked up again (0.08 = grows 8% and back) and its duration
    ToastPulseScale<public>:float = 0.08
    ToastPulseSeconds<public>:float = 0.22
    # When the next toast is waiting, the hold time is shortened to this
    ToastQueuedHoldSeconds<public>:float = 0.5
    # Maximum number of queued toasts (older ones are dropped beyond it)
    MaxQueuedToasts<public>:int = 3

    # ---- Text shadow (every text in toasts and slots; improves readability) ----
    # Shadow color, opacity (0 hides it) and offset toward the bottom right
    TextShadowColor<public>:color = NamedColors.Black
    TextShadowOpacity<public>:float = 0.75
    TextShadowOffsetPx<public>:float = 2.0

    # ---- Slots of ongoing effects (squares in a row at the bottom center of the screen. The same EffectId is merged into one) ----
    # Position of the row center (screen width / height ratio). When slots are added or removed, the row shifts sideways to stay centered
    SlotXRatio<public>:float = 0.5
    SlotYRatio<public>:float = 0.88
    # Slot side length and the gap between slots
    SlotSizePx<public>:float = 84.0
    SlotGapPx<public>:float = 12.0
    # Border (AccentColor) thickness and opacity (thickness 0 hides it)
    SlotBorderPx<public>:float = 3.0
    SlotBorderOpacity<public>:float = 1.0
    # Color and duration of the border flash when extended by picking up again
    SlotFlashColor<public>:color = NamedColors.White
    SlotFlashSeconds<public>:float = 0.35
    # Color and opacity of the remaining-time background. Its height shrinks with the remaining ratio from the bottom (the top edge moves down)
    SlotBackColor<public>:color = NamedColors.Black
    SlotBackOpacity<public>:float = 0.55
    # Side length of the image (the card's Thumbnail) as a ratio of the border's inner size (same for the colored square shown without an image)
    SlotIconScale<public>:float = 0.72
    # When on, the image is tinted with AccentColor. When off, white (the image's own colors)
    SlotIconTintAccent<public>:logic = false
    # Without an image: color and size of the first letter of the name shown on the AccentColor square
    SlotLetterColor<public>:color = NamedColors.White
    SlotLetterSize<public>:float = 36.0
    # Prefix, color and size of the stack count ("x2"; shown at the bottom right only for 2 or more)
    StackPrefix<public>:string = "×"
    SlotStackColor<public>:color = NamedColors.White
    SlotStackSize<public>:float = 20.0
    # Seconds to appear (from a small scale, overshooting slightly while fading in), initial scale and overshoot strength
    SlotInSeconds<public>:float = 0.25
    SlotStartScale<public>:float = 0.4
    SlotOvershoot<public>:float = 1.7
    # Seconds to disappear (shrinks while fading out) and the scale at the end
    SlotOutSeconds<public>:float = 0.25
    SlotEndScale<public>:float = 0.4
    # Pulse applied to the slot when extended by picking up again (0.12 = grows 12% and back). Duration is SlotFlashSeconds
    SlotPulseScale<public>:float = 0.12
    # Speed of the sideways shift when other slots are added or removed (fraction caught up per second; larger is faster)
    SlotMoveSpeed<public>:float = 12.0
    # Blink the slot when the remaining time drops below this many seconds (0 means no blinking), and blinks per second
    SlotWarnSeconds<public>:float = 2.0
    SlotWarnBlinkPerSecond<public>:float = 4.0
    # Effects whose DurationSeconds is shorter than this are not listed in slots (toast only). Instant effects are never listed
    MinSlotSeconds<public>:float = 2.0
    # Whether endless effects (DurationSeconds = 0) are listed too (the background stays full)
    ShowEndlessSlots<public>:logic = true

    # ---- When there is no look ----
    # Color for effects without card_info_component (the name is the EffectId)
    FallbackAccentColor<public>:color = NamedColors.SkyBlue

# Look of Effect (name, description, badge, image, color). Built from the card_info_component on the root of the effect prefab (the Effect's entity) (EffectId if Title is empty)
#   Without card_info_component, a card with name = EffectId and color = FallbackColor (the name is empty too if EffectId is empty)
(Effect:pickup_effect_component).GetPickupEffectCard<public>(?FallbackColor:color = NamedColors.SkyBlue)<transacts>:widget_card =
    if (Info := Effect.Entity.GetComponent[card_info_component]):
        Info.GetCard(Effect.EffectId)
    else:
        widget_card{Id := Effect.EffectId, Title := Effect.EffectId, AccentColor := FallbackColor}

# Role: HUD that shows picked-up effects on the owner's screen (does not take over input)
#   On pickup: shows two lines of text above the slots (line 1 "Got {name}!" (the name in AccentColor; format is Style.ToastFormat), line 2 the description), growing in, then fading out upward after a while
#     Consecutive pickups are shown in order (cut short while the next is waiting). Picking the same effect up again pulses the visible toast and restarts its hold time
#   While ongoing: square slots in a row at the bottom center of the screen. Each has a border (AccentColor), a translucent black background and an image (Thumbnail; or a colored square with the first letter of the name)
#     The background height shrinks every frame with the remaining ratio, from the bottom. Stacked effects show "x2" at the bottom right. Blinks when little time is left; flashes the border and pulses when extended by picking up again
#     Slots bounce in from a small scale, shrink and fade out when done, and the remaining slots shift sideways to stay centered
#     Instant effects and effects whose DurationSeconds is shorter than Style.MinSlotSeconds are not listed (toast only)
#   The only owner of the look is the card_info_component (WidgetSystem's CardKit) on the root of the effect prefab (GetPickupEffectCard). Without it, name = EffectId
# Placement: placed under the owner's slot (loadout prefab, custom character body, etc.) it shows only to the owner (Audience stays Everyone)
#   Place it on a prefab (or entity) in the editor. Added with AddComponents at runtime, the effect notifications (scene events) do not reach OnReceive (UEFN v43.00; nothing is shown because no notification arrives)
#   Placed on an ancestor of the slots (the player_manager_component entity etc.) it shows everyone their own effects (Renewed is not delivered there, so an extension is visible only through the background height)
# When: shown from the start by default (ActiveOnBegin; or only during part of the round). Effects already ongoing when it starts showing are listed too
# Receives: pickup_effect_owner_event (SendDown from the owner's slot. Started / Renewed / Ended), pickup_effect_changed_event (only when placed on an ancestor of the slots)
# From outside: ShowToastFor / TrackEffectFor, var Style (the look. Copied when it starts showing, so set it before that)
pickup_effect_hud_component<public> := class<final_super>(player_widget_component):

    ActiveOnBegin<override>:logic = true
    ZOrder<override>:int = 100

    # When on, picking up an effect (including again) shows "Got {name}!" and the description above the slots. Default on
    @editable:
        ToolTip := PickupHudShowToastsToolTip
        Categories := array{PickupHudCategory}
    ShowToasts<public>:logic = true
    # When on, ongoing effects are listed as slots at the bottom center of the screen with the remaining time as the background height. Default on
    @editable:
        ToolTip := PickupHudShowListToolTip
        Categories := array{PickupHudCategory}
    ShowEffectList<public>:logic = true

    # Look and motion (colors, sizes, positions, seconds, format). Not shown in the editor. Make it per game theme and set it with Style := at creation or set Hud.Style =
    var Style<public>:pickup_effect_hud_style = pickup_effect_hud_style{}

    var<private> Screens:[agent]pickup_effect_hud_screen = map{}

    # Show a toast for Card on Agent's screen (the same two lines as on pickup; for showing from code). Does nothing if not showing to that agent
    ShowToastFor<public>(Agent:agent, Card:widget_card):void =
        if (Screen := Screens[Agent]):
            Screen.PushToast(Card)

    # List Effect in the slots on Agent's screen (e.g. when the effect was granted from somewhere the notification does not reach). Does nothing if the effect is not ongoing, is not listable, or the HUD is not showing to that agent
    TrackEffectFor<public>(Agent:agent, Effect:pickup_effect_component):void =
        if (Screen := Screens[Agent]):
            Screen.Track(Effect, false)

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Notice := pickup_effect_owner_event[SceneEvent]):
            Handle(Notice.Agent, Notice.Effect, Notice.Picked, Notice.Notice)
        else if (Changed := pickup_effect_changed_event[SceneEvent]):
            # Placed on an ancestor of the slots (the owner-side notification does not arrive). Under a slot the same thing arrives as pickup_effect_owner_event
            if (not Entity.FindOwningSlot[]):
                Kind := if (Changed.Started?) then pickup_effect_notice.Started else pickup_effect_notice.Ended
                Handle(Changed.Agent, Changed.Effect, Changed.Effect, Kind)
        (super:)OnReceive(SceneEvent)

    CreateWidget<override>(View:widget_view):widget =
        Root := canvas{}
        Screen := pickup_effect_hud_screen{Root := Root, Style := Style}
        if (set Screens[View.Player] = Screen) {}
        # List effects that were already ongoing before showing started (no toast)
        if (ShowEffectList?):
            for (Effect : Entity.GetActivePickupEffects(View.Player)):
                Screen.Track(Effect, false)
        spawn{RunScreen(View, Screen)}
        Root

    Handle<private>(Agent:agent, Effect:pickup_effect_component, Picked:pickup_effect_component, Notice:pickup_effect_notice):void =
        if (Screen := Screens[Agent]):
            if (Notice = pickup_effect_notice.Started or Notice = pickup_effect_notice.Renewed):
                if (ShowToasts?):
                    Screen.PushToast(Picked.GetPickupEffectCard(?FallbackColor := Screen.Style.FallbackAccentColor))
                if (ShowEffectList?):
                    Screen.Track(Effect, if (Notice = pickup_effect_notice.Renewed) then true else false)
            # Slots of ended effects disappear through the per-frame check (Ended only wakes the loop)
            Screen.Wake()

    RunScreen<private>(View:widget_view, Screen:pickup_effect_hud_screen)<suspends>:void =
        race:
            View.HiddenEvent.Await()
            Screen.Run()
        # When re-shown (ShowFor) a new screen is already in place, so do not remove it
        if (Current := Screens[View.Player], Current = Screen):
            set Screens = Screens.RemoveKey(View.Player)

# One player's screen (created each time pickup_effect_hud_component shows). Holds the toast queue, the visible toast and the slots, and animates them every frame (sleeps while there is nothing to do)
pickup_effect_hud_screen<internal> := class<unique><internal>:
    Root<internal>:canvas
    Style<internal>:pickup_effect_hud_style
    WakeEvent<internal>:event() = event(){}
    var Queue<internal>:[]widget_card = array{}
    var Current<internal>:?pickup_effect_hud_toast = false
    # In display order (from the left). Items that are disappearing stay until they are gone
    var Items<internal>:[]pickup_effect_hud_item = array{}

    # Show a toast (append to the queue). If a toast for the same effect (same Id) is visible, pulse it instead of showing again. Not shown if both name and description are empty
    PushToast<internal>(Card:widget_card):void =
        if (Card.Title = "" and Card.Description = ""):
            return
        Now := GetSimulationElapsedTime()
        # Do not append if the same effect is already queued
        AlreadyQueued := if (Card.Id <> "", IsQueued[Card.Id]) then true else false
        if (Toast := Current?, Toast.OutStart < 0.0, Card.Id <> "", Toast.Card.Id = Card.Id):
            set Toast.HoldFrom = Max(Now, Toast.StartTime + Style.ToastInSeconds)
            set Toast.PulseStart = Now
        else if (not AlreadyQueued?):
            set Queue += array{Card}
            Limit := Max(Style.MaxQueuedToasts, 1)
            if (Queue.Length > Limit, Rest := Queue.Slice[Queue.Length - Limit]):
                set Queue = Rest
        Wake()

    # List Effect in the slots (added to the existing slot with the same EffectId if any). With Renewed, flash the border and pulse (extended by picking up again)
    Track<internal>(Effect:pickup_effect_component, Renewed:logic):void =
        if (not Effect.IsActive[]):
            return
        Now := GetSimulationElapsedTime()
        Remaining := Effect.GetRemainingSeconds()
        if (Item := FindItemFor(Effect)?):
            if (not Item.Effects.Find[Effect]):
                set Item.Effects += array{Effect}
            if (Remaining > Item.TotalSeconds):
                set Item.TotalSeconds = Remaining
            if (Renewed?):
                set Item.FlashStart = Now
        else if (ShouldList(Effect)?):
            Card := Effect.GetPickupEffectCard(?FallbackColor := Style.FallbackAccentColor)
            Item := MakePickupHudItem(Card, Effect.EffectId, Style, Now)
            set Item.Effects = array{Effect}
            set Item.TotalSeconds = Max(Effect.DurationSeconds, Remaining)
            # A new slot appears bouncing in at the right end of the row (the other slots shift toward the center every frame)
            Staying := CountStaying()
            X := SlotOffsetX(Staying, Staying + 1)
            set Item.CurrentX = X
            set Item.PlacedX = X
            Item.Apply(Style.SlotStartScale, 0.0, 0.0)
            Root.AddWidget(MakePickupHudSlot(Item.Layers, Style.SlotXRatio, Style.SlotYRatio, 0.5, 0.5, X, 0.0, 0))
            set Items += array{Item}
        Wake()

    # Start animating if sleeping
    Wake<internal>():void =
        WakeEvent.Signal()

    # Animate the toast and the slots every frame. Sleeps until Wake while there is nothing to do
    Run<internal>()<suspends>:void =
        var PreviousTime:float = GetSimulationElapsedTime()
        loop:
            if (IsIdle[]):
                WakeEvent.Await()
                set PreviousTime = GetSimulationElapsedTime()
            Now := GetSimulationElapsedTime()
            Dt := Clamp(Now - PreviousTime, 0.0, 0.1)
            set PreviousTime = Now
            StepToast(Now)
            StepItems(Now, Dt)
            Sleep(0.0)

    IsIdle<private>()<decides><transacts>:void =
        not Current?
        Queue.Length = 0
        Items.Length = 0

    IsQueued<private>(Id:string)<decides><transacts>:void =
        Matches := for (Each : Queue, Each.Id = Id):
            Each
        Matches.Length > 0

    # Whether the effect is listed (Instant is not. Endless effects follow Style.ShowEndlessSlots, others need MinSlotSeconds or more)
    ShouldList<private>(Effect:pickup_effect_component)<transacts>:logic =
        if (Effect.Instant?) then false
        else if (Effect.DurationSeconds <= 0.0) then Style.ShowEndlessSlots
        else if (Effect.DurationSeconds < Style.MinSlotSeconds) then false
        else true

    # The slot that holds Effect (disappearing ones excluded)
    FindItemFor<private>(Effect:pickup_effect_component)<transacts>:?pickup_effect_hud_item =
        var Found:?pickup_effect_hud_item = false
        for (Item : Items):
            if (not Found?, Item.LeaveStart < 0.0, Item.Matches(Effect)?):
                set Found = option{Item}
        Found

    # Number of slots that are not disappearing
    CountStaying<private>()<transacts>:int =
        Staying := for (Item : Items, Item.LeaveStart < 0.0):
            Item
        Staying.Length

    # Horizontal offset (px) of the center of slot Index (from 0, left to right) when Count slots are centered
    SlotOffsetX<private>(Index:int, Count:int)<transacts>:float =
        (Index * 1.0 - (Count * 1.0 - 1.0) * 0.5) * (Style.SlotSizePx + Style.SlotGapPx)

    StepToast<private>(Now:float):void =
        if (not Current?):
            if (Next := Queue[0]):
                set Queue = if (Rest := Queue.Slice[1]) then Rest else array{}
                Made := MakePickupHudToast(Next, Style, Now)
                Made.Apply(Style.ToastStartScale, 0.0)
                Root.AddWidget(MakePickupHudSlot(Made.Layers, Style.ToastXRatio, Style.ToastYRatio, 0.5, 0.5, 0.0, 0.0, 10))
                set Current = option{Made}
        if (Toast := Current?):
            Finished := StepToastOf(Toast, Now)
            if (Finished?):
                Root.RemoveWidget(Toast.Layers)
                set Current = false

    # Advance one toast by one frame. true once it has disappeared
    StepToastOf<private>(Toast:pickup_effect_hud_toast, Now:float):logic =
        InSeconds := Max(Style.ToastInSeconds, 0.01)
        T := Now - Toast.StartTime
        if (Toast.OutStart < 0.0):
            Hold := if (Queue.Length > 0) then Min(Style.ToastHoldSeconds, Style.ToastQueuedHoldSeconds) else Style.ToastHoldSeconds
            if (T >= InSeconds and Now - Toast.HoldFrom >= Hold):
                set Toast.OutStart = Now
        var Scale:float = 1.0
        var Alpha:float = 1.0
        var OffsetY:float = 0.0
        var Done:logic = false
        if (T < InSeconds):
            # Appear: grows (overshooting slightly) while fading in
            P := Clamp(T / InSeconds, 0.0, 1.0)
            set Scale = Style.ToastStartScale + (1.0 - Style.ToastStartScale) * PickupHudEaseBack(P, Style.ToastOvershoot)
            set Alpha = PickupHudEaseOut(P)
        if (Toast.PulseStart >= 0.0):
            Q := (Now - Toast.PulseStart) / Max(Style.ToastPulseSeconds, 0.01)
            if (Q < 1.0):
                set Scale = Scale * (1.0 + Style.ToastPulseScale * Sin(Q * PiFloat))
            else:
                set Toast.PulseStart = -1.0
        if (Toast.OutStart >= 0.0):
            # Disappear: slides up while fading out
            Q := Clamp((Now - Toast.OutStart) / Max(Style.ToastOutSeconds, 0.01), 0.0, 1.0)
            E := Q * Q
            set Alpha = Alpha * (1.0 - E)
            set OffsetY = -Style.ToastOutSlidePx * E
            if (Q >= 1.0):
                set Done = true
        Toast.Apply(Scale, Alpha)
        Moved := OffsetY - Toast.PlacedOffsetY
        if (not Done?, Moved > 0.25 or Moved < -0.25):
            Root.RemoveWidget(Toast.Layers)
            Root.AddWidget(MakePickupHudSlot(Toast.Layers, Style.ToastXRatio, Style.ToastYRatio, 0.5, 0.5, 0.0, OffsetY, 10))
            set Toast.PlacedOffsetY = OffsetY
        Done

    StepItems<private>(Now:float, Dt:float):void =
        # Check the remaining time and the end first, then center the slots that are not disappearing
        for (Item : Items):
            UpdateItem(Item, Now, Dt)
        Count := CountStaying()
        var Index:int = 0
        var Kept:[]pickup_effect_hud_item = array{}
        for (Item : Items):
            # Disappearing slots shrink away in place (not counted in the row)
            TargetX := if (Item.LeaveStart < 0.0) then SlotOffsetX(Index, Count) else Item.CurrentX
            if (Item.LeaveStart < 0.0):
                set Index += 1
            Finished := AnimateItem(Item, Now, Dt, TargetX)
            if (Finished?):
                Root.RemoveWidget(Item.Layers)
            else:
                set Kept += array{Item}
        set Items = Kept

    # Check one slot's ongoing effects, remaining time and stack count. Starts disappearing when all have ended
    UpdateItem<private>(Item:pickup_effect_hud_item, Now:float, Dt:float):void =
        Active := for (Effect : Item.Effects, Effect.IsActive[]):
            Effect
        set Item.Effects = Active
        if (Item.LeaveStart < 0.0 and Active.Length = 0):
            set Item.LeaveStart = Now
        if (Item.LeaveStart >= 0.0):
            return
        # Remaining (the longest if stacked. Endless if any is endless)
        var Remaining:float = 0.0
        var Endless:logic = false
        for (Effect : Active):
            Seconds := Effect.GetRemainingSeconds()
            if (Seconds < 0.0):
                set Endless = true
            else if (Seconds > Remaining):
                set Remaining = Seconds
        if (Remaining > Item.TotalSeconds):
            set Item.TotalSeconds = Remaining
        set Item.Remaining = Remaining
        set Item.Endless = Endless
        Ratio := if (Endless?) then 1.0 else if (Item.TotalSeconds > 0.0) then Clamp(Remaining / Item.TotalSeconds, 0.0, 1.0) else 0.0
        # When extended, grow over a few frames; when shrinking, follow directly (shrinks every frame)
        if (Ratio > Item.ShownRatio + 0.002):
            set Item.ShownRatio = Item.ShownRatio + (Ratio - Item.ShownRatio) * Min(Dt * 14.0, 1.0)
        else:
            set Item.ShownRatio = Ratio
        Count := Active.Length
        if (Count <> Item.ShownCount):
            set Item.ShownCount = Count
            Item.StackText.SetText(StringToMessage(if (Count > 1) then "{Style.StackPrefix}{Count}" else ""))

    # Animate one slot by one frame (TargetX is the horizontal offset from the row center). true once it has disappeared
    AnimateItem<private>(Item:pickup_effect_hud_item, Now:float, Dt:float, TargetX:float):logic =
        Leaving := if (Item.LeaveStart >= 0.0) then true else false
        # Appear: from a small scale, overshooting slightly while fading in
        InP := Clamp((Now - Item.AppearStart) / Max(Style.SlotInSeconds, 0.01), 0.0, 1.0)
        var Scale:float = Style.SlotStartScale + (1.0 - Style.SlotStartScale) * PickupHudEaseBack(InP, Style.SlotOvershoot)
        var Alpha:float = PickupHudEaseOut(InP)
        var Done:logic = false
        # Extended by picking up again: flash the border and pulse
        var Flash:float = 0.0
        if (Item.FlashStart >= 0.0):
            F := (Now - Item.FlashStart) / Max(Style.SlotFlashSeconds, 0.01)
            if (F < 1.0):
                set Flash = 1.0 - F
                set Scale = Scale * (1.0 + Style.SlotPulseScale * Sin(F * PiFloat))
            else:
                set Item.FlashStart = -1.0
        if (Leaving?):
            # Disappear: shrinks while fading out
            Q := Clamp((Now - Item.LeaveStart) / Max(Style.SlotOutSeconds, 0.01), 0.0, 1.0)
            E := Q * Q
            set Scale = Scale * (1.0 - (1.0 - Style.SlotEndScale) * E)
            set Alpha = Alpha * (1.0 - E)
            if (Q >= 1.0):
                set Done = true
        else if (not Item.Endless?, Style.SlotWarnSeconds > 0.0, Item.Remaining < Style.SlotWarnSeconds):
            # Little time left: blink
            Pulse := 0.5 + 0.5 * Sin(Now * 2.0 * PiFloat * Style.SlotWarnBlinkPerSecond)
            set Alpha = Alpha * (0.25 + 0.75 * Pulse)
        Item.Apply(Scale, Alpha, Flash)
        # Horizontal position (shifts to stay centered when other slots are added or removed)
        Diff := TargetX - Item.CurrentX
        if (Diff > 0.5 or Diff < -0.5):
            set Item.CurrentX = Item.CurrentX + Diff * Min(Dt * Style.SlotMoveSpeed, 1.0)
        else:
            set Item.CurrentX = TargetX
        Moved := Item.CurrentX - Item.PlacedX
        if (not Done?, Moved > 0.25 or Moved < -0.25):
            Root.RemoveWidget(Item.Layers)
            Root.AddWidget(MakePickupHudSlot(Item.Layers, Style.SlotXRatio, Style.SlotYRatio, 0.5, 0.5, Item.CurrentX, 0.0, 0))
            set Item.PlacedX = Item.CurrentX
        Done

# One pickup toast (created by MakePickupHudToast)
pickup_effect_hud_toast<internal> := class<unique><internal>:
    Card<internal>:widget_card
    Style<internal>:pickup_effect_hud_style
    Layers<internal>:overlay
    Back<internal>:color_block
    # Text of line 1 (before the format, the name, after the format. Empty pieces are omitted)
    TitleTexts<internal>:[]text_block
    Description<internal>:?text_block
    StartTime<internal>:float
    # When the hold time started counting (when it finished appearing. Reset to now on re-pickup)
    var HoldFrom<internal>:float = 0.0
    # When it started disappearing (negative if not yet)
    var OutStart<internal>:float = -1.0
    # When the pulse started (negative if not pulsing)
    var PulseStart<internal>:float = -1.0
    var PlacedOffsetY<internal>:float = 0.0

    # Apply scale Scale (1.0 = as in Style) and opacity Alpha to the look
    Apply<internal>(Scale:float, Alpha:float):void =
        Back.SetOpacity(ToOpacity(Style.ToastBackOpacity * Alpha))
        for (Text : TitleTexts):
            PickupHudApplyText(Text, Style.ToastTitleSize * Scale, Alpha, Style)
        if (Found := Description?):
            PickupHudApplyText(Found, Style.ToastDescriptionSize * Scale, Alpha, Style)

# One slot (created by MakePickupHudItem). Holds every effect with the same EffectId (only that effect if EffectId is empty)
pickup_effect_hud_item<internal> := class<unique><internal>:
    Key<internal>:string
    Card<internal>:widget_card
    Style<internal>:pickup_effect_hud_style
    Layers<internal>:overlay
    # Remaining-time background (shrinks from the bottom)
    Back<internal>:color_block
    # Border (top, bottom, left, right)
    BorderTop<internal>:color_block
    BorderBottom<internal>:color_block
    BorderLeft<internal>:color_block
    BorderRight<internal>:color_block
    # Image (Thumbnail). Without one, a colored square (Chip) and the first letter (Letter)
    Icon<internal>:?texture_block
    Chip<internal>:?color_block
    Letter<internal>:?text_block
    StackText<internal>:text_block
    AppearStart<internal>:float
    var Effects<internal>:[]pickup_effect_component = array{}
    # Seconds that count as a full background (grows when extended by picking up again)
    var TotalSeconds<internal>:float = 0.0
    var Remaining<internal>:float = 0.0
    var Endless<internal>:logic = false
    var ShownRatio<internal>:float = 1.0
    var ShownCount<internal>:int = 1
    # When it started disappearing (negative if not yet)
    var LeaveStart<internal>:float = -1.0
    # When the flash started (negative if not flashing)
    var FlashStart<internal>:float = -1.0
    var CurrentX<internal>:float = 0.0
    var PlacedX<internal>:float = 0.0

    # true if this slot holds Effect (already holds it, or same EffectId)
    Matches<internal>(Effect:pickup_effect_component)<transacts>:logic =
        if (Effects.Find[Effect]) then true
        else if (Key <> "", Effect.EffectId = Key) then true
        else false

    # Apply scale Scale (1.0 = as in Style), opacity Alpha, border flash amount Flash (0-1) and the background height from ShownRatio to the look
    Apply<internal>(Scale:float, Alpha:float, Flash:float):void =
        Size := Max(Style.SlotSizePx * Scale, 0.0)
        Border := Clamp(Style.SlotBorderPx * Scale, 0.0, Size * 0.5)
        Inner := Max(Size - Border * 2.0, 0.0)
        Lit := PickupHudMix(Card.AccentColor, Style.SlotFlashColor, Flash)
        BorderAlpha := if (Style.SlotBorderPx > 0.0) then Style.SlotBorderOpacity * Alpha else 0.0
        for (Bar : array{BorderTop, BorderBottom}):
            Bar.SetDesiredSize(vector2{X := Size, Y := Border})
            Bar.SetColor(Lit)
            Bar.SetOpacity(ToOpacity(BorderAlpha))
        for (Bar : array{BorderLeft, BorderRight}):
            Bar.SetDesiredSize(vector2{X := Border, Y := Size})
            Bar.SetColor(Lit)
            Bar.SetOpacity(ToOpacity(BorderAlpha))
        # The background extends from behind the bottom border (up to the inner top edge when full)
        Back.SetDesiredSize(vector2{X := Inner, Y := Border + Inner * Clamp(ShownRatio, 0.0, 1.0)})
        Back.SetOpacity(ToOpacity(Style.SlotBackOpacity * Alpha))
        Side := Inner * Style.SlotIconScale
        if (Found := Icon?):
            Found.SetDesiredSize(vector2{X := Side, Y := Side})
            if (Style.SlotIconTintAccent?):
                Found.SetTint(PickupHudMix(Card.AccentColor, Style.SlotFlashColor, Flash))
            # The image cannot be faded, so hide it while thinner than half
            Found.SetVisibility(if (Alpha >= 0.5) then widget_visibility.Visible else widget_visibility.Hidden)
        if (Found := Chip?):
            Found.SetDesiredSize(vector2{X := Side, Y := Side})
            Found.SetOpacity(ToOpacity(Alpha))
        if (Found := Letter?):
            PickupHudApplyText(Found, Style.SlotLetterSize * Scale, Alpha, Style)
        PickupHudApplyText(StackText, Style.SlotStackSize * Scale, Alpha, Style)

# Make a toast (still transparent; Apply shows it)
MakePickupHudToast<internal>(Card:widget_card, Style:pickup_effect_hud_style, Now:float):pickup_effect_hud_toast =
    # Line 1: replace {0} in the format with the name (AccentColor); before and after use ToastTitleColor
    TitleLine := stack_box{Orientation := orientation.Horizontal}
    var TitleTexts:[]text_block = array{}
    if (Card.Title <> "", Style.ToastFormat <> ""):
        Pieces := if (Parts := PickupHudSplitFormat(Style.ToastFormat)?):
            array{(Parts(0), Style.ToastTitleColor), (Card.Title, Card.AccentColor), (Parts(1), Style.ToastTitleColor)}
        else:
            array{(Style.ToastFormat, Style.ToastTitleColor)}
        for (Piece : Pieces, Piece(0) <> ""):
            Made := MakePickupHudText(Piece(0), Piece(1), Style.ToastTitleSize, Style)
            TitleLine.AddWidget(stack_box_slot{Widget := Made, VerticalAlignment := vertical_alignment.Bottom})
            set TitleTexts += array{Made}
    Column := stack_box{Orientation := orientation.Vertical}
    if (TitleTexts.Length > 0):
        Column.AddWidget(stack_box_slot{Widget := TitleLine, HorizontalAlignment := horizontal_alignment.Center})
    # Line 2: description
    var Description:?text_block = false
    if (Card.Description <> ""):
        MadeDescription := MakePickupHudText(Card.Description, Style.ToastDescriptionColor, Style.ToastDescriptionSize, Style)
        # Wrap at a fixed width (AutoWrap wraps at the width of its container, which is narrow inside a content-sized column)
        if (Style.ToastDescriptionWrapPx > 0.0):
            set MadeDescription.WrapWidth = Style.ToastDescriptionWrapPx
        Gap := if (TitleTexts.Length > 0) then Style.ToastLineGapPx else 0.0
        Column.AddWidget(stack_box_slot{Widget := MadeDescription, HorizontalAlignment := horizontal_alignment.Center, Padding := margin{Top := Gap}})
        set Description = option{MadeDescription}
    # Panel (grows with the text size. Invisible when ToastBackOpacity is 0)
    Back := color_block{DefaultColor := Style.ToastBackColor, DefaultOpacity := ToOpacity(0.0), DefaultDesiredSize := vector2{X := 0.0, Y := 0.0}}
    Pad := Style.ToastPaddingPx
    Layers := overlay{}
    Layers.AddWidget(overlay_slot{Widget := Back, HorizontalAlignment := horizontal_alignment.Fill, VerticalAlignment := vertical_alignment.Fill})
    Layers.AddWidget(overlay_slot{Widget := Column, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Center, Padding := margin{Left := Pad, Top := Pad * 0.5, Right := Pad, Bottom := Pad * 0.5}})
    pickup_effect_hud_toast:
        Card := Card
        Style := Style
        Layers := Layers
        Back := Back
        TitleTexts := TitleTexts
        Description := Description
        StartTime := Now
        HoldFrom := Now + Style.ToastInSeconds

# Make one slot (still transparent; Apply shows it)
MakePickupHudItem<internal>(Card:widget_card, Key:string, Style:pickup_effect_hud_style, Now:float):pickup_effect_hud_item =
    Size := Style.SlotSizePx
    Border := Style.SlotBorderPx
    Inner := Max(Size - Border * 2.0, 0.0)
    Side := Inner * Style.SlotIconScale
    Back := color_block{DefaultColor := Style.SlotBackColor, DefaultOpacity := ToOpacity(0.0), DefaultDesiredSize := vector2{X := Inner, Y := Border + Inner}}
    BorderTop := color_block{DefaultColor := Card.AccentColor, DefaultOpacity := ToOpacity(0.0), DefaultDesiredSize := vector2{X := Size, Y := Border}}
    BorderBottom := color_block{DefaultColor := Card.AccentColor, DefaultOpacity := ToOpacity(0.0), DefaultDesiredSize := vector2{X := Size, Y := Border}}
    BorderLeft := color_block{DefaultColor := Card.AccentColor, DefaultOpacity := ToOpacity(0.0), DefaultDesiredSize := vector2{X := Border, Y := Size}}
    BorderRight := color_block{DefaultColor := Card.AccentColor, DefaultOpacity := ToOpacity(0.0), DefaultDesiredSize := vector2{X := Border, Y := Size}}
    Layers := overlay{}
    # Bottom to top: background (bottom-aligned, variable height) -> image or colored square with the first letter -> border -> stack count
    Layers.AddWidget(overlay_slot{Widget := Back, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Bottom})
    var Icon:?texture_block = false
    var Chip:?color_block = false
    var Letter:?text_block = false
    if (Image := Card.Image?):
        Tint := if (Style.SlotIconTintAccent?) then Card.AccentColor else NamedColors.White
        MadeIcon := texture_block{DefaultImage := Image, DefaultTint := Tint, DefaultDesiredSize := vector2{X := Side, Y := Side}}
        MadeIcon.SetVisibility(widget_visibility.Hidden)
        Layers.AddWidget(overlay_slot{Widget := MadeIcon, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Center})
        set Icon = option{MadeIcon}
    else:
        MadeChip := color_block{DefaultColor := Card.AccentColor, DefaultOpacity := ToOpacity(0.0), DefaultDesiredSize := vector2{X := Side, Y := Side}}
        Layers.AddWidget(overlay_slot{Widget := MadeChip, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Center})
        set Chip = option{MadeChip}
        Glyph := PickupHudFirstGlyph(Card.Title)
        if (Glyph <> ""):
            MadeLetter := MakePickupHudText(Glyph, Style.SlotLetterColor, Style.SlotLetterSize, Style)
            Layers.AddWidget(overlay_slot{Widget := MadeLetter, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Center})
            set Letter = option{MadeLetter}
    Layers.AddWidget(overlay_slot{Widget := BorderTop, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Top})
    Layers.AddWidget(overlay_slot{Widget := BorderBottom, HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Bottom})
    Layers.AddWidget(overlay_slot{Widget := BorderLeft, HorizontalAlignment := horizontal_alignment.Left, VerticalAlignment := vertical_alignment.Center})
    Layers.AddWidget(overlay_slot{Widget := BorderRight, HorizontalAlignment := horizontal_alignment.Right, VerticalAlignment := vertical_alignment.Center})
    StackText := MakePickupHudText("", Style.SlotStackColor, Style.SlotStackSize, Style)
    Layers.AddWidget(overlay_slot{Widget := StackText, HorizontalAlignment := horizontal_alignment.Right, VerticalAlignment := vertical_alignment.Bottom, Padding := margin{Right := Border + 4.0, Bottom := Border + 1.0}})
    pickup_effect_hud_item:
        Key := Key
        Card := Card
        Style := Style
        Layers := Layers
        Back := Back
        BorderTop := BorderTop
        BorderBottom := BorderBottom
        BorderLeft := BorderLeft
        BorderRight := BorderRight
        Icon := Icon
        Chip := Chip
        Letter := Letter
        StackText := StackText
        AppearStart := Now

# A text_block for Text (Color, Size, centered, Style's text shadow). Still transparent (PickupHudApplyText shows it)
MakePickupHudText<internal>(Text:string, Color:color, Size:float, Style:pickup_effect_hud_style):text_block =
    Offset := Style.TextShadowOffsetPx
    text_block:
        DefaultText := StringToMessage(Text)
        DefaultTextColor := Color
        DefaultTextSize := Max(Size, 1.0)
        DefaultTextOpacity := ToOpacity(0.0)
        DefaultJustification := text_justification.Center
        DefaultShadowOffset := if (Style.TextShadowOpacity > 0.0) then option{vector2{X := Offset, Y := Offset}} else false
        DefaultShadowColor := Style.TextShadowColor
        DefaultShadowOpacity := ToOpacity(0.0)

# Set Text's size to Size and the opacity of the text and its shadow to Alpha (the shadow is multiplied by Style.TextShadowOpacity)
PickupHudApplyText<internal>(Text:text_block, Size:float, Alpha:float, Style:pickup_effect_hud_style):void =
    Text.SetTextSize(Max(Size, 1.0))
    Text.SetTextOpacity(ToOpacity(Alpha))
    Text.SetShadowOpacity(ToOpacity(Style.TextShadowOpacity * Alpha))

# A canvas_slot that places Widget at screen ratio (XRatio, YRatio) offset by (OffsetX, OffsetY) pixels, aligned at (AlignX, AlignY) (top-left 0, 0; center 0.5, 0.5), sized to its content
MakePickupHudSlot<internal>(Widget:widget, XRatio:float, YRatio:float, AlignX:float, AlignY:float, OffsetX:float, OffsetY:float, ZOrder:int)<transacts>:canvas_slot =
    canvas_slot:
        Anchors := anchors{Minimum := vector2{X := XRatio, Y := YRatio}, Maximum := vector2{X := XRatio, Y := YRatio}}
        Offsets := margin{Left := OffsetX, Top := OffsetY, Right := 0.0, Bottom := 0.0}
        Alignment := vector2{X := AlignX, Y := AlignY}
        SizeToContent := true
        ZOrder := if (Z := slot_zorder[ZOrder]) then Z else 0
        Widget := Widget

# Split Format before and after "{0}" ("Got {0}!" -> ("Got ", "!")). Fails (false) if there is no "{0}"
PickupHudSplitFormat<internal>(Format:string)<transacts>:?tuple(string, string) =
    Mark := "\{0\}"
    var Found:?tuple(string, string) = false
    var Index:int = 0
    loop:
        if (Found? or Index + Mark.Length > Format.Length):
            break
        if (Format.Slice[Index, Index + Mark.Length] = Mark, Before := Format.Slice[0, Index], After := Format.Slice[Index + Mark.Length]):
            set Found = option{(Before, After)}
        set Index += 1
    Found

# First character of Text (one UTF-8 character. "Slime" -> "S"; a multi-byte first character such as a kana is kept whole). Empty if empty
#   A string is a sequence of UTF-8 bytes, so the continuation bytes (0x80-0xBF) are joined to the first byte
PickupHudFirstGlyph<internal>(Text:string)<transacts>:string =
    if (not Text[0]):
        return ""
    var Count:int = 1
    loop:
        if (Next := Text[Count], PickupHudContinuationBytes.Find[Next]):
            set Count += 1
        else:
            break
    if (Glyph := Text.Slice[0, Count]) then Glyph else ""

# UTF-8 continuation bytes (0x80-0xBF)
PickupHudContinuationBytes<internal>:[]char = array{0o80, 0o81, 0o82, 0o83, 0o84, 0o85, 0o86, 0o87, 0o88, 0o89, 0o8A, 0o8B, 0o8C, 0o8D, 0o8E, 0o8F, 0o90, 0o91, 0o92, 0o93, 0o94, 0o95, 0o96, 0o97, 0o98, 0o99, 0o9A, 0o9B, 0o9C, 0o9D, 0o9E, 0o9F,
    0oA0, 0oA1, 0oA2, 0oA3, 0oA4, 0oA5, 0oA6, 0oA7, 0oA8, 0oA9, 0oAA, 0oAB, 0oAC, 0oAD, 0oAE, 0oAF, 0oB0, 0oB1, 0oB2, 0oB3, 0oB4, 0oB5, 0oB6, 0oB7, 0oB8, 0oB9, 0oBA, 0oBB, 0oBC, 0oBD, 0oBE, 0oBF}

# Map 0->1 to a 0->1 that starts fast and stops slowly (cubic)
PickupHudEaseOut<internal>(T:float)<computes>:float =
    U := 1.0 - Clamp(T, 0.0, 1.0)
    1.0 - U * U * U

# Map 0->1 to a 0->1 that overshoots slightly and comes back (Overshoot is the strength. 0 gives the same shape as EaseOut)
PickupHudEaseBack<internal>(T:float, Overshoot:float)<computes>:float =
    U := Clamp(T, 0.0, 1.0) - 1.0
    1.0 + (Overshoot + 1.0) * U * U * U + Overshoot * U * U

# Mix colors From and To by Amount (0-1)
PickupHudMix<internal>(From:color, To:color, Amount:float)<computes>:color =
    T := Clamp(Amount, 0.0, 1.0)
    color{R := From.R + (To.R - From.R) * T, G := From.G + (To.G - From.G) * T, B := From.B + (To.B - From.B) * T}
