# WidgetSystem

A System that shows widgets (HUDs, menus) on players' screens, one per person. A subclass of the base `player_widget_component` only builds the widget for one person in `CreateWidget`; who sees it (`Audience`), stacking order (`ZOrder`), menu overlap (`MenuConflict`), late joiners and cleanup are handled by the base. Ready-made text, gauge and notification HUDs, choice menus and a part that hides the standard HUD are included.

## Setup (placement)

| component | Where to place | What it does |
|---|---|---|
| a `player_widget_component` subclass | Where the activation signal arrives (for a game sequence, the node's entity or a descendant). Not placed directly (place a subclass). Any number per entity | While activated, shows the widget on the screens of the people chosen by `Audience`. Deactivation removes it from everyone |
| `text_hud_component` (HudKit) | Same as above | Shows one line of text at a fixed screen position (the same text for everyone, or per-person text) |
| `gauge_hud_component` (HudKit) | Same as above | Shows a ratio (0.0-1.0) as a horizontal bar (the same value for everyone, or per-person values) |
| `notification_hud_component` (HudKit) | Same as above (by default shown to everyone from the start) | Shows notifications that disappear after a few seconds, stacked vertically |
| `hud_hide_component` (HudKit) | Where the activation signal arrives | While activated, hides the checked parts of the standard Fortnite HUD per person. When it stops, restores only what it hid |
| `card_menu_component` (MenuKit) | Where the activation signal arrives. Give each child entity a `card_info_component` | Turns the `card_info_components` of child entities into cards sorted by Order and sends an activation signal to the pressed card's entity. The card under the mouse or with focus changes its border color, and a card pressed with the Virtual Pointer sinks in |
| `card_info_component` (CardKit) | The entity to be chosen as a card (a map root, a mode, an item, etc.) | Holds the info shown on the card (Title, Subtitle, Description, Badge, Thumbnail, AccentColor, Order). This component is the only owner of the name and sort order. Besides card screens, PickupSystem's HudKit (the HUD of a picked-up effect) also reads this on the root of the effect prefab (the dependency only points PickupSystem -> WidgetSystem) |
| `choice_menu_component` (MenuKit) | Where the activation signal arrives (to open with an interact, the entity put in the `Targets` of `interact_trigger_component`) | Lines up option buttons under a heading, notifies which option was pressed, and sends an activation signal to `Targets[index]` |
| `widget_show_in_group_component` (ShowKit) | The same entity as the widget | Shows the widgets on the same entity only to people in a player group (PlayerSystem's `player_group_component`). Shows on joining and hides on leaving. "Show that mode's / genre's HUD only to people who chose it in a menu" |
| `widget_show_item_holder_component` (ShowKit) | The item's entity (the same entity as `item_component` and `item_holder_component`) | While the item has a holder, shows every `player_widget_component` on the same entity to that person, and hides when the holder is removed |
| `player_widget_view_component` | Created at runtime by `player_widget_component` under the player's slot (not placed in the editor) | Adds the widget to one person's screen and removes it when it goes away |

Example: show text to everyone while in a node, and hide the minimap etc. of the standard HUD
```
Node (game_node_component)
├ Guide (text_hud_component, Text = "Reach the goal")
└ Hide HUD (hud_hide_component)
```
To show from the start without using a game sequence, turn on `ActiveOnBegin`. To decide who sees it by place or item, set `Audience = Chosen` and place `widget_show_item_holder_component` (ShowKit) or `widget_show_in_volume_component` (VolumeSystem's WidgetKit) on the same entity.

## Settings (@editable)
- Rounds (no setting; cannot be turned off) — always goes through fort_round_manager. Shown only during a round (from OnRoundStarted to OnRoundEnded); outside a round, Activate / ShowFor are not accepted either. ActiveOnBegin screens are shown at OnRoundStarted (also called right after subscribing when placed mid-round) and removed from everyone at OnRoundEnded. No screen is left behind while editing in UEFN. Without a round manager (tests, etc.) it shows at start and can show at any time. Query with `IsOutsideRound[]`.
On every `player_widget_component` subclass:
- `Mode : player_widget_mode = player_widget_mode.Hud` — `Hud` is a display that does not take input (movement and camera controls keep working while shown). `Menu` is a screen that takes input and moves focus the moment it is shown.
- `Audience : player_widget_audience = player_widget_audience.Everyone` — `Everyone` shows to everyone in the area when activated (late joiners too). `Chosen` shows only to people chosen with `ShowFor`.
- `ZOrder : int = 0` — stacking order on the screen (0-100000). Larger is in front. Guide: HUD 0-100, menus 1000, notifications 10000.
- `MenuConflict : player_widget_menu_conflict = player_widget_menu_conflict.CloseOther` — when another menu is already shown to the same person: close the previous one and show this (`CloseOther`), or keep the previous one and do not show this (`KeepOther`). Used only with `Mode = Menu`.
- `ActiveOnBegin : logic = false` — when on, shows from the start of the game (with `Chosen`, starts accepting `ShowFor`). When off, from the activation signal.
- `ForwardReceivedEvents : logic = false` — when on, notifications that reach this entity (scene_events other than activation / deactivation signals) are passed to `widget_view.ReceivedEvent` of everyone it is shown to.

HudKit / MenuKit:
- `text_hud_component.Text : string = ""` — text shown at first. Invisible if empty.
- `text_hud_component.PositionXRatio : float = 0.5` / `PositionYRatio : float = 0.15` — position (screen ratios 0.0-1.0; top-left is 0, 0. Placed centered on that point).
- `gauge_hud_component.WidthPx : float = 300.0` (10-2000) / `HeightPx : float = 16.0` (2-500) — bar width and height (screen pixels).
- `gauge_hud_component.FillColor : color = NamedColors.White` / `BackColor : color = NamedColors.Black` — fill and background colors.
- `gauge_hud_component.PositionXRatio : float = 0.5` / `PositionYRatio : float = 0.9` — position.
- `gauge_hud_component.InitialRatio : float = 1.0` — initial ratio (0.0-1.0).
- `notification_hud_component.DisplaySeconds : float = 3.0` — seconds one notification stays (0.5-60).
- `notification_hud_component.MaxLines : int = 4` — number of notifications shown at once (1-20). Beyond it, the oldest are removed.
- `notification_hud_component.PositionXRatio : float = 0.5` / `PositionYRatio : float = 0.3` — position.
- `notification_hud_component` defaults to `ActiveOnBegin = true`, `ZOrder = 10000`.
- `choice_menu_component.Title : string = ""` — heading. Not shown if empty.
- `choice_menu_component.Options : []string = array{"OK"}` — options to line up (index 0, 1, 2 ... from the top).
- `choice_menu_component.Targets : []entity = array{}` — entity that receives an activation signal per option (same order as `Options`. Missing indices send nothing).
- `choice_menu_component.CloseOnChoice : logic = true` — when on, closes that person's menu after choosing.
- `widget_show_in_group_component.Group : ?entity = false` — the group (an entity with `player_group_component`). Empty means the group of this entity or an ancestor. With neither, nobody sees it.
- `choice_menu_component.ShowCloseButton : logic = true` / `CloseText : string = "Close"` — whether to add a button at the end that closes without choosing, and its text.
- `choice_menu_component.PositionXRatio : float = 0.5` / `PositionYRatio : float = 0.5` — position.
- `choice_menu_component` defaults to `Mode = Menu`, `ZOrder = 1000`.
- `hud_hide_component.ActiveOnBegin : logic = false` — when on, hides from the start of the game. When off, from the activation signal.
- What `hud_hide_component` hides (the ones turned on): `HideMinimap = true` (minimap), `HideBuild = true` (build menu and materials), `HideTeamInfo = true` (team info, player count, eliminations), `HideRoundInfo = true` (round and storm info), `HideExperience = true` (experience), `HideHealth = false` (health and shields), `HideInventory = false` (inventory bar), `HideInteractionPrompts = false` (interaction prompts).

CardKit / MenuKit (cards):
- `card_info_component.Title / Subtitle / Description / Badge : string`, `Thumbnail : ?texture` (an AccentColor band if none), `AccentColor : color`, `Order : int` (smaller comes first).
- `card_menu_component.Title : string`, `Columns : int = 4`, `CloseOnChoice` / `ShowCloseButton` / `CloseText` (same as choice_menu), `PositionXRatio / PositionYRatio`, `PointerFieldOfViewDegrees : float = 90` (the horizontal camera field of view used to convert the Virtual Pointer's pressed position to a screen ratio). The look is `var Style : widget_card_style` (replace it in code).
- `text_hud_component.TextColor : color = white`, `TextSize : float = 0` (0 is the default size), `BackgroundOpacity : float = 0` (0 means no panel), `BackgroundColor : color = black`.

## Events
- `widget_choice_event` (scene_event, SendUp): `Menu : choice_menu_component`, `Agent : agent`, `Index : int` (the index in `Options`, from 0). Sent from the entity to the root when an option is pressed in `choice_menu_component`. Receivers are ancestor components (conditions, game sequence, your components). Not consumed.
- `hud_text_request_event` (scene_event, SendDown): `Agent : ?agent` (`false` means everyone, including people shown later), `Text : message`. Your component sends it to the `text_hud_component`'s entity (or SendDown from an ancestor) to change the text. Not consumed.
- `hud_notification_request_event` (scene_event, SendDown): `Agent : ?agent` (`false` means everyone it is shown to), `Text : message`. Your component sends it to the `notification_hud_component`'s entity (or SendDown from an ancestor) to show a notification. Not consumed.
- listenables (cannot be Signaled from outside)
  - `choice_menu_component.ChoiceEvent : listenable(tuple(agent, int))` — delivered as (the person, the option index) each time someone chooses an option.
  - `widget_view.HiddenEvent : listenable(tuple())` — delivered once when it disappears from that person's screen (`Close`, `HideFor`, `Deactivate`, leaving, menu swap, deactivation).
  - `widget_view.ReceivedEvent : listenable(scene_event)` — delivers notifications passed with `SendToWidgets` / `SendToWidgetFor` (and `ForwardReceivedEvents`), and the contents of `player_events` sent with `SendToPlayer` (PlayerSystem) from the same person's other views.
- Sent: when an option is chosen, `choice_menu_component` sends `SendActivatedBy(Agent)` (`activated_by_agent_event`) to the entity `Targets[index]`.
- Received
  - `player_widget_component` (every subclass) receives `activated_event` (start showing) / `deactivated_event` (remove from everyone). With `ForwardReceivedEvents` on, other notifications are passed to everyone's display.
  - `text_hud_component` receives `hud_text_request_event`; `notification_hud_component` receives `hud_notification_request_event`.
  - `hud_hide_component` receives `activated_event` (hide) / `deactivated_event` (restore).
  - `player_widget_view_component` receives `player_view_source_event` (from the creating component) and `player_event` (from the same person's other views) and passes the contents to `widget_view.ReceivedEvent`.

## Owner
Placed under a player's slot (inside a LoadoutSystem loadout, inside a CharacterSystem character, etc.: anywhere `Entity.FindOwningPlayer[]` succeeds), it affects the owner instead of everyone.
- `player_widget_component` (every subclass): `Audience = Everyone` becomes "show only to the owner" (not to others or late joiners). `Chosen` still shows to the people chosen with `ShowFor`.
- `hud_hide_component`: hides the standard HUD only for the owner (does not look at everyone in the area or late joiners).

## Public API
```verse
player_widget_mode<public> := enum:
    Hud
    Menu

(Mode:player_widget_mode).ToInputMode<public>()<computes>:ui_input_mode     # Hud -> None, Menu -> All

player_widget_audience<public> := enum:
    Everyone
    Chosen

widget_zorder<public> := type{_X:int where 0 <= _X, _X <= 2147483647}
MakePlayerUISlot<public>(ZOrder:int, InputMode:ui_input_mode)<transacts>:player_ui_slot   # out-of-range ZOrder is clamped

player_widget_menu_conflict<public> := enum:
    CloseOther
    KeepOther

player_widget_component<public> := class<abstract><final_super>(component):
    Mode<public>:player_widget_mode
    Audience<public>:player_widget_audience
    ZOrder<public>:int
    MenuConflict<public>:player_widget_menu_conflict
    ActiveOnBegin<public>:logic
    ForwardReceivedEvents<public>:logic
    CreateWidget<protected>(View:widget_view):widget        # implemented by subclasses. Called once each time it is shown (returns the outermost widget)
    Activate<public>():void                                 # start showing (Everyone: to all; Chosen: starts accepting ShowFor)
    Deactivate<public>():void                               # remove from everyone
    ShowFor<public>(Agent:agent):void                       # does nothing if already shown. With Chosen and not activated, activates first
    HideFor<public>(Agent:agent):void
    IsShownFor<public>(Agent:agent)<decides><transacts>:void
    CanShowTo<public>(Agent:agent)<decides><transacts>:void    # succeeds if every widget_audience_filter_component on the same entity allows it
    IsShown<public>()<decides><transacts>:void              # succeeds while activated
    FindView<public>(Agent:agent)<decides><transacts>:widget_view
    SendToWidgets<public>(SceneEvent:scene_event):void      # to the ReceivedEvent of everyone it is shown to
    SendToWidgetFor<public>(Agent:agent, SceneEvent:scene_event):void

(InEntity:entity).GetPlayerWidgets<public>()<reads>:[]player_widget_component   # every subclass attached to InEntity

widget_view<public> := class<internal>:                     # the view for one person. Your code does not create it
    Player<public>:player
    Owner<public>:player_widget_component
    HiddenEvent<public><final>:listenable(tuple())
    ReceivedEvent<public><final>:listenable(scene_event)
    IsShown<public>()<decides><transacts>:void
    Close<public>():void                                    # same as Owner.HideFor(Player)
    Focus<public>(Target:widget):void
    SetDefaultFocus<public>(Target:widget):void             # call inside CreateWidget. Focus is called on the frame after showing
    AwaitClick<public>(OnClick:listenable(widget_message), ?ButtonId:string = "", ?Label:string = "")<suspends>:logic   # true when this person presses (PressButton too), false if closed first
    AwaitChoice<public>(Buttons:[]text_button_base, ?ButtonIds:[]string = array{})<suspends>:?int            # index of the pressed button (PressButton gives the same index). false if closed first
    AwaitButtonGroupChoice<public>(Groups:[][]button, ?ButtonIds, ?Labels)<suspends>:?int     # when one choice is made of several buttons (any of them chooses it)
    AwaitButtonChoice<public>(Buttons:[]button, ?ButtonIds:[]string = array{}, ?Labels:[]string = array{})<suspends>:?int   # version for buttons with free content (cards, etc.). Labels are the text shown in the list
    GetWaitingButtons<public>():[]widget_button_info        # buttons currently waited on by AwaitClick / AwaitChoice (ID, index, text, enabled)
    PressButton<public>(Key:string):widget_press_result     # press from code (ID, button text or index as text). Reaches the wait exactly like a real click

widget_press_result<public> := enum:                       # Pressed / NotShown / NotWaiting / NoButton / Disabled
widget_button_info<public> := struct:
    Id<public>:string
    Index<public>:int
    Label<public>:string
    Enabled<public>:logic

player_widget_view_component<public> := class<final_super><internal>(component):   # created at runtime
    View<public>:widget_view
    Root<public>:widget
    Slot<public>:player_ui_slot

# Layout and text helpers (positions are screen ratios 0.0-1.0, top-left is 0, 0)
MakeScreenSlot<public>(Widget:widget, XRatio:float, YRatio:float)<transacts>:canvas_slot
MakeFullScreenSlot<public>(Widget:widget)<transacts>:canvas_slot
MakeScreenCanvas<public>(Widget:widget, XRatio:float, YRatio:float):canvas
MakeStack<public>(Widgets:[]widget, Orientation:orientation, PaddingPx:float):stack_box
widget_text_style<public> := struct { Color, Size (0 means default), Justification }
MakeStyledText<public>(Text:message, Style:widget_text_style):text_block
MakePanel<public>(Widget:widget, BackColor:color, Opacity:float, PaddingPx:float):widget     # put a panel behind (Opacity 0 returns it as is)
ToOpacity<public>(Value:float)<transacts>:widget_opacity                                       # clamp to 0.0-1.0

# CardKit
widget_card<public> := struct { Id, Title, Subtitle, Description, Badge, Image:?texture, AccentColor, Enabled }   # WithSubtitle / WithBadge / WithEnabled give a copy with one field changed (all through the single CopyWidgetCard; when adding a field, write it only there)
widget_card_style<public> := struct { WidthPx, HeightPx, ImageHeightPx, PaddingPx, BorderPx, BorderColor, BorderOpacity, HighlightColor, HighlightBackgroundOpacity, PressDepthPx, PressShadeOpacity, colors and text sizes ... }
MakeCardView<public>(Card, Style, ?Skin:?widget_card_skin = false):widget_card_button   # one pressable card (Button, SetHighlighted, SetPressed, ClearPressed, TrackHighlight(View))
MakeCardButton<public>(Card, Style):button                                              # button only (when the selected / pressed looks are not needed)
PlayCardChosen<public>(Cards, Chosen, ShineSeconds, ?DimAmount, ?StepsPerSecond)<suspends>   # chosen effect: darken the others, a light (fake light) sweeps diagonally over the chosen card and the tilt follows
PlayCardZoom<public>(Root:canvas, Card, Style, Rect, Seconds, TargetScale, ?Skin, ?StepsPerSecond)<suspends>   # enlarge a copy toward the screen center and fade it out (in front of everything)
MakeCardContent<public>(Card, Style):widget                                             # look only, not pressable
MakeCardGrid<public>(Buttons:[]widget, Columns:int, GapPx:float):widget
CardGridRect<public>(Index, Count, Columns, GapPx, Style, CenterX, CenterY):widget_screen_rect   # the rectangle the Index-th card occupies in that layout (screen ratios; 1080p, 16:9)
widget_card_skin<public> / widget_card_skin_view<public> := interface                  # replaces the background look (material, etc. GetWidget, SetHighlight, SetPress, SetTilt, SetLight, SetFade)
MakeScreenSlot(Widget, X, Y, ?ZOrder)                                                    # ZOrder: bring to the front within the same canvas
card_info_component.GetCard(Id), GetTitle(?Fallback), GetCardId(?Fallback) (CardId -> Title -> Fallback; the button ID in card_menu_component), SortCards(Infos)

# PointerKit (Virtual Pointer; experimental)
(Player:player).PointerToScreenRatio<public>(ViewportPosition:vector3, FieldOfViewDegrees:float)<decides><transacts>:tuple(float, float)
RunCardPointerPress<public>(View:widget_view, Cards:[]widget_card_button, Rects:[]widget_screen_rect, FieldOfViewDegrees:float)<suspends>:void   # sink the pressed card (call with spawn)
IntToMessage<public><localizes>(Value:int):message
PercentToMessage<public><localizes>(Value:int):message      # 75 -> "75%"
StringToMessage<public><localizes>(Text:string):message

# World -> screen (PointerKit. MarkerKit's markers use it too)
widget_screen_projection<public> := struct<computes> { Origin, Forward, Right, Up:vector3, TanH, TanV:float }   # camera eye, directions and extent to the screen edge
(Player:player).GetScreenProjection<public>()<decides><reads>:widget_screen_projection          # that person's current camera (derived from 4 DeprojectViewportToWorld rays. Field of view and aspect ratio not hard-coded. Lags slightly)
MakeScreenProjectionInView<public>(View:transform, FieldOfViewDegrees:float, ?AspectRatio:float = 16:9)<reads>:widget_screen_projection   # a camera you placed (no lag)
MakeScreenProjectionAlong<public>(Origin, Forward:vector3, FieldOfViewDegrees, ?AspectRatio)<decides><reads>:widget_screen_projection
(Projection).ProjectToScreenRatio<public>(WorldPosition:vector3)<decides><reads>:vector2           # fails behind the camera. Off screen gives values outside 0-1
(Projection).ProjectDirectionToScreenRatio<public>(Direction:vector3)<decides><reads>:vector2
(Player:player).ProjectToScreenRatio<public>(WorldPosition:vector3)<decides><reads>:vector2       # GetScreenProjection then project (reuse GetScreenProjection for many points)
(Player:player).ViewportToScreenRatio<public>(ViewportPosition:vector3)<decides><reads>:vector2   # Virtual Pointer coordinate -> screen ratio (from the current camera's rays)
ProjectToScreenRatioInView / ProjectToScreenRatioAlong / ClampScreenRatio                           # shortcuts for projecting a single point

# MarkerKit (markers layered over the 3D view)
widget_bubble_style<public> := struct { BackColor, BackOpacity, BorderPx, BorderColor, BorderOpacity, HighlightColor, PaddingPx, MinWidthPx, MinHeightPx, TailWidthPx, TailHeightPx, TailSteps }
MakeSpeechBubble<public>(Content:widget, Style:widget_bubble_style):widget_bubble_button   # speech bubble with a tail pointing down (pressable. Button, SetHighlighted, TrackHighlight(View), BodyHeightPx, GetTailHeightPx)
MakeScreenMarker<public>(Root:canvas, Widget:widget, ?AlignX:float = 0.5, ?AlignY:float = 1.0, ?ZOrder:int = 0, ?MinMovePx:float = 0.5):widget_screen_marker
widget_screen_marker<public> := class<internal>:
    MoveTo<public>(X:float, Y:float):void                  # align (AlignX, AlignY) to the point. Movement below MinMovePx does not re-place
    HideMarker<public>():void
    IsShown<public>()<decides><transacts>:void
    GetPoint<public>()<transacts>:tuple(float, float)
    DistancePxTo<public>(X, Y, RadiusPx, ?OffsetXPx, ?OffsetYPx)<decides><transacts>:float   # whether a pressed point is near (px at 1080p)
    FollowWorld<public>(Projection:widget_screen_projection, World:vector3, ?MarginRatio:float = 0.05):void   # call every frame. Hides when behind or off screen

# HudKit
hud_text_request_event<public> := class(scene_event):
    Agent<public>:?agent
    Text<public>:message

text_hud_component<public> := class<final_super>(player_widget_component):
    Text<public>:string
    PositionXRatio<public>:float
    PositionYRatio<public>:float
    SetText<public>(Value:message):void                     # everyone's text (per-person text is cleared)
    SetTextFor<public>(Agent:agent, Value:message):void     # that person only (takes priority over everyone's text)
    ClearTextFor<public>(Agent:agent):void                  # back to everyone's text

gauge_hud_component<public> := class<final_super>(player_widget_component):
    WidthPx<public>:float
    HeightPx<public>:float
    FillColor<public>:color
    BackColor<public>:color
    PositionXRatio<public>:float
    PositionYRatio<public>:float
    InitialRatio<public>:float
    SetRatio<public>(Ratio:float):void                      # everyone (clamped to 0.0-1.0. Per-person values are cleared)
    SetRatioFor<public>(Agent:agent, Ratio:float):void
    GetRatioFor<public>(Agent:agent)<transacts>:float

hud_notification_request_event<public> := class(scene_event):
    Agent<public>:?agent
    Text<public>:message

notification_hud_component<public> := class<final_super>(player_widget_component):
    DisplaySeconds<public>:float
    MaxLines<public>:int
    PositionXRatio<public>:float
    PositionYRatio<public>:float
    Notify<public>(Agent:agent, Text:message):void          # does nothing if not shown to that person
    NotifyAll<public>(Text:message):void

hud_hide_component<public> := class<final_super>(component):
    ActiveOnBegin<public>:logic
    HideMinimap<public>:logic
    HideBuild<public>:logic
    HideTeamInfo<public>:logic
    HideRoundInfo<public>:logic
    HideExperience<public>:logic
    HideHealth<public>:logic
    HideInventory<public>:logic
    HideInteractionPrompts<public>:logic
    Activate<public>():void
    Deactivate<public>():void                               # restores only the people it hid
    IsActive<public>()<decides><transacts>:void

# MenuKit
widget_choice_event<public> := class(scene_event):
    Menu<public>:choice_menu_component
    Agent<public>:agent
    Index<public>:int

choice_menu_component<public> := class<final_super>(player_widget_component):
    Title<public>:string
    Options<public>:[]string
    Targets<public>:[]entity
    CloseOnChoice<public>:logic
    ShowCloseButton<public>:logic
    CloseText<public>:string
    PositionXRatio<public>:float
    PositionYRatio<public>:float
    ChoiceEvent<public><final>:listenable(tuple(agent, int))
    OpenFor<public>(Agent:agent):void                       # same as ShowFor

# Base that restricts who may see it (every widget on the same entity shows only to the people this allows, both when showing to everyone and with ShowFor)
widget_audience_filter_component<public> := class<abstract><final_super>(component):
    AllowsWidgetFor<public>(Agent:agent)<decides><transacts>:void

# ShowKit
widget_show_in_group_component<public> := class<final_super>(widget_audience_filter_component):
    Group<public>:?entity

widget_show_item_holder_component<public> := class<final_super>(component):
```

## Requirements, caveats and limits
- Filtering (a `widget_audience_filter_component` subclass such as `widget_show_in_group_component`) stacks with the other ways of showing: with `Audience = Everyone`, activation shows to "everyone in the group"; with `Chosen`, only to "group members" among the people a volume, item, etc. called `ShowFor` on. People not allowed are not shown even with `ShowFor`. Re-showing on joining the group happens only when activated with `Audience = Everyone` (with `Chosen`, it shows when they re-enter the volume etc. after joining the group).
- `player_widget_component` and `hud_hide_component` need one `player_manager_component` (PlayerSystem) in the area (or world).
- Only one widget per person per component (calling `ShowFor` repeatedly still gives one).
- `Mode = Menu` is one at a time per person. Other menus are looked up among the views under the same slot, and `MenuConflict` decides whether to close the previous one or not show this one.
- Pressing buttons from code: `View.PressButton(Key)` (only while `AwaitClick` / `AwaitChoice` is waiting. Exactly like a real click: `AwaitChoice` returns the same index and it goes through the same path as the `widget_choice_handler` signal). The list of waiting buttons is `View.GetWaitingButtons()`. IDs are given with `AwaitClick(?ButtonId := "close")` / `AwaitChoice(Buttons, ?ButtonIds := array{"m01", "m02"})` (without them, the index as text "0", "1", ...). Pressing from MCP is MCPSystem's WidgetKit (opt-in per screen: `mcp_widget_control_component` on the same entity).
- `CreateWidget` is called each time it is shown. To wait for buttons, use `View.AwaitClick` / `View.AwaitChoice` inside `spawn{...}` (it returns false and ends when closed, so no wait is left behind). Subscribe to `View.ReceivedEvent` for notifications that change the display.
- A person removed with `HideFor` under `Audience = Everyone` can be brought back with `ShowFor`.
- `hud_hide_component` does not touch the island-wide settings; it hides per person (when it stops, restores only the people it hid). Also hides for late joiners.
- `gauge_hud_component` does not know where the value comes from. Subscribing to `energy_component.ChangedEvent` (EnergySystem) etc. and calling `SetRatioFor` is your code's job.
- When using `widget_show_item_holder_component`, set the widgets on the same entity to `Audience = Chosen`. To pass notifications that reach the item's entity to the display, turn on `ForwardReceivedEvents` on the widget.
- In `choice_menu_component`, on a gamepad focus moves to the top button (or the close button if there is none).
- When building a level through MCP: a string array (`choice_menu_component.Options`) cannot have its length and contents changed at the same time through MCP. Clear it first, then fill it again. Fortnite's standard `input_action` / `input_mapping` cannot be set as references with MCP's `SetComponentProperty` (using them as code defaults is fine; choose other ones in the editor).

- Cards: when the mouse enters or gamepad focus arrives, the button's HighlightEvent arrives and `TrackHighlight` changes the border color (`HighlightColor`) and background strength. A custom UI that does not do this gives no clue which card is selected.
- Virtual Pointer (PointerKit, experimental): the pointer position arrives only while `PointerSelect` is pressed (BeginDetect -> DetectionOngoing -> EndDetect). There is no API for the screen size, so it is converted to a screen ratio from the difference between the `DeprojectViewportToWorld` ray and the view direction (assumes the horizontal camera field of view and 16:9). While pressed, the press-in takes priority over the selected look. ⚠ Unconfirmed: whether PointerSelect arrives while a menu is shown.
- Card height is padded to `HeightPx` (the same height even when the content is shorter), because `CardGridRect` computes the hit rectangles.
- World -> screen (PointerKit's `widget_screen_projection`): v43.00 has no API for the screen size, so projection uses the camera eye, direction and field of view. `GetScreenProjection` derives that person's current camera from 4 rays (fits any camera, but lags slightly because it is a server value). `MakeScreenProjectionInView` builds from the position, direction and field of view of a camera you placed (assumes 16:9; the same horizontal field of view as perspective_camera_component.FieldOfView). MarkerKit's `FollowWorld` accepts either. Cameras include `player_orbit_camera` (`GetTransform`, `FieldOfViewDegrees`) in CharacterSystem's CameraExperimentalKit.
- `widget_screen_marker` moves by removing and re-adding the canvas part (there is no API to change position). Re-adding every frame makes buttons unpressable, so it re-places only when it moved more than `MinMovePx` (pressable while the camera is still). On a Mode = Hud screen the mouse cannot press buttons, so hit the speech bubble with the Virtual Pointer's pressed point via `DistancePxTo`.

## Verifying
- Test: `widget_system_test_component` in `_Test/WidgetSystemTest/`. Place one entity with `player_manager_component` and one entity with this component, and start with at least 1 player (waits up to 10 seconds for a join. The test creates the screen components at runtime). It checks that the activation signal shows to everyone, that `SendToWidgets` reaches `ReceivedEvent`, that deactivation removes it and `HiddenEvent` arrives once, `ShowFor` / `HideFor` with `Audience = Chosen` (one widget even when called twice) and `FindView`, one menu per person (`CloseOther`), and that the 4 HudKit / MenuKit parts appear. Text, a gauge, a notification and a menu flash briefly during the test. It finishes in a few seconds. Results are in the output log under `[TEST] WidgetSystem`.
- Sample: `_Samples/WidgetSample/`. A HUD (`widget_sample_component`; updates the elapsed time every second with `SendToWidgets`), a menu (`menu_sample_component`; `Mode = Menu`, `Audience = Chosen`, waits for the close button with `View.AwaitClick`), and an input that opens the menu (`widget_sample_opener_component`; opens with C / RT and notifies the same person's HUD with `SendToPlayer`).

## Migration notes (2026-11-08)
- `player_widget_component` always goes through rounds (no setting; cannot be turned off): no screen is shown outside a round, and it closes at the end of the round (OnRoundEnded)
- Added an entry point to `widget_view` for pressing buttons from code (compatible; no change needed): `AwaitClick(OnClick, ?ButtonId, ?Label)`, `AwaitChoice(Buttons, ?ButtonIds)`, `GetWaitingButtons()`, `PressButton(Key)`, `widget_press_result`, `widget_button_info`. Used by MCPSystem's WidgetKit (a press from MCP reaches `AwaitClick` / `AwaitChoice` exactly like a real click)

## Migration notes (2026-11-09)
- Added (compatible): CardKit (`card_info_component`, `widget_card`, `widget_card_style`, `MakeCardView` / `MakeCardButton` / `MakeCardContent` / `MakeCardGrid` / `CardGridRect`, the skin interfaces), MenuKit's `card_menu_component`, PointerKit, `widget_view.AwaitButtonChoice`, `widget_text_style` / `MakeStyledText` / `MakePanel` / `ToOpacity`, text color, size and panel on `text_hud_component`.
- Added `Widgets` to `widget_wait` (internal) to check whether buttons can be pressed. The behavior of `AwaitChoice` does not change.
- Added (compatible): PointerKit's `widget_screen_projection`, `GetScreenProjection`, `MakeScreenProjectionInView` / `MakeScreenProjectionAlong`, `ProjectDirectionToScreenRatio`, `(player).ViewportToScreenRatio` (world -> screen is gathered here. `(player).ProjectToScreenRatio`, `ProjectToScreenRatioInView` / `Along` and `ClampScreenRatio` work as before). MarkerKit (`widget_screen_marker` / `MakeScreenMarker`, `FollowWorld`, `widget_bubble_style` / `MakeSpeechBubble` / `widget_bubble_button`).
