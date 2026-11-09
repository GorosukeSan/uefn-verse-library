# ScheduleSystem

A System for schedules decided by real time (epoch seconds): 10 minutes from 20:00 every day, every hour, once at a fixed date and time, and so on. One `realtime_clock_component` per scope evaluates every schedule once per second; `schedule_component` notifies when its state changes and sends the activate / deactivate signals (`activated_event` / `deactivated_event`) to its descendants on entering / leaving the period (Active). Values are always computed from "the current time", so late joiners and server restarts end up in the same state.

## Placement

| component | Where | What it does |
|---|---|---|
| `realtime_clock_component` | one per scope (under `game_scope_component`) or world | Real-time clock. Evaluates the registered schedules once right after each whole-second boundary and delivers the results |
| `schedule_component` | the parent entity of the things driven by the schedule | Decides the period from `Kind`, the time and the duration. Notifies when the state or the cycle changes, and sends the activate / deactivate signals to itself and its descendants on entering / leaving Active |
| `schedule_active_condition_component` (ConditionKit) | directly under the entity of `game_transition_component` or `condition_all` / `condition_any` (or `ability_grant_condition_component`), itself a descendant of the `schedule_component` entity | Satisfied while the schedule is Active |
| `schedule_text_component` (DisplayKit) | the `schedule_component` entity or a descendant | Turns the remaining time into text such as "MM:SS" and notifies only when it changes |
| `schedule_digit_display_component` (DisplayKit) | a descendant of the `schedule_component` entity. One entity per digit position | Shows one digit of the remaining time by showing / hiding the child digit meshes |
| `schedule_digit_glyph_component` (DisplayKit) | an entity with a digit-shaped mesh. Arrange 0-9 directly under the `schedule_digit_display_component` entity | Marker for the mesh of one digit |
| `schedule_countdown_hud_component` (HudKit) | a descendant of the `schedule_component` entity | From `ShowWithinSeconds` seconds before the start until the start, shows countdown text on the screen of every player in the scope (late joiners too) |

The Kit components follow the `schedule_component` on their own entity or the nearest ancestor (`schedule_follower`).

`schedule_sequence_component`, which plays a Cinematic Sequence device during the period, lives in FNDeviceSystem (`FNDeviceSystem/ScheduleKit/`) because it depends on devices. Its placement is the same: the `schedule_component` entity or a descendant.

Example: "a 10-minute event from 20:00 every day"
```
Scope (game_scope_component)
├ Clock (realtime_clock_component)
└ Night event (schedule_component, Kind = Daily, StartHour = 20, DurationSeconds = 600)
  ├ Sign text (schedule_text_component)
  ├ Countdown (schedule_countdown_hud_component)
  └ Platform (spawner_component etc.; something that starts on the activate signal)
```

## Settings (@editable)
- `realtime_clock_component.TimeZoneOffsetSeconds : int = DefaultTimeZoneOffsetSeconds (32400)` — offset between local time and UTC (seconds; -50400 to 50400). Japan Standard Time is +9 hours. Daylight saving time is not considered.
- `realtime_clock_component.WakeMarginSeconds : float = 0.02` — how long after the whole-second boundary to wake (seconds; 0-0.5). Too small may drift by 1 second.
- `schedule_component.Kind : schedule_kind = Daily` — kind of repetition. `Daily` = at the same time every day, `FixedInterval` = at a fixed interval from an anchor time, `OneShot` = once.
- `schedule_component.StartHour : int = 20` / `StartMinute : int = 0` / `StartSecond : int = 0` — Daily start time (local time; hour 0-23, minute and second 0-59).
- `schedule_component.DurationSeconds : float = 600.0` — length of the period (Active) in seconds (0 or more). Keep under 86400 for Daily and under the interval for FixedInterval (otherwise always Active).
- `schedule_component.IntervalSeconds : float = 3600.0` — FixedInterval interval (seconds). 0 or less means once (same as OneShot).
- `schedule_component.EpochAnchorSeconds : float = 0.0` — anchor time of FixedInterval, start time of OneShot (epoch seconds).
- `schedule_component.SendActivation : logic = true` — when on, sends `activated_event` to itself and its descendants on entering Active, and `deactivated_event` on leaving.
- `schedule_text_component.Format : schedule_text_format = MinutesSeconds` — text format.
- `schedule_text_component.RemainingKind : schedule_remaining_kind = UntilEnd` — `UntilStart` is until the next start; `UntilEnd` is until the end during the period, otherwise until the next start.
- `schedule_text_component.Prefix : string = ""` — fixed string put before the text.
- `schedule_text_component.OnlyWhileShown : logic = false` — when on, updated only between `Show` and `Hide`.
- `schedule_digit_display_component.Digit : int = 1` — digit position (1 = ones; 1-9).
- `schedule_digit_display_component.Field : schedule_time_field = Seconds` — which part of the remaining time the digit belongs to.
- `schedule_digit_display_component.RemainingKind : schedule_remaining_kind = UntilEnd`.
- `schedule_digit_display_component.BlankLeadingZero : logic = false` — when on, no digit is shown when the higher positions are 0 (all digit meshes are hidden).
- `schedule_digit_glyph_component.Value : int = 0` — the digit (0-9) this mesh represents. Any number of meshes may share the same value.
- `schedule_countdown_hud_component.ShowWithinSeconds : float = 300.0` — how many seconds before the start to show (seconds; 1 or more).
- `schedule_countdown_hud_component.Format : schedule_text_format = MinutesSeconds` / `Prefix : string = ""`.
- `schedule_countdown_hud_component.TextSize : float = 48.0` — text size (8-200).
- `schedule_countdown_hud_component.PositionXRatio : float = 0.5` / `PositionYRatio : float = 0.15` — screen position (0-1. 0 = left / top edge, 1 = right / bottom edge; the text is centered on that point). Same name and meaning as the WidgetSystem/HudKit HUDs (`text_hud_component` etc.), and the ToolTips are WidgetSystem's (`WidgetPositionXToolTip` / `WidgetPositionYToolTip`).
- `schedule_countdown_hud_component` is a `player_widget_component` (WidgetSystem) subclass, so it also has `Mode` / `Audience` / `ZOrder` / `MenuConflict` / `ActiveOnBegin` / `ForwardReceivedEvents`. Leave `Audience` at the default `Everyone` (with `Chosen`, nobody sees it until `ShowFor` is called for someone).

## Events
- `schedule_state_changed_event` (scene_event, SendDown): `Schedule : schedule_component`, `Previous : ?schedule_snapshot` (false on the first evaluation), `Current : schedule_snapshot`. Sent by `schedule_component`. Only when the state (Before / Active / After) or the cycle changes. Arrives once on the first evaluation too. Receivers are that entity and its descendants. Not consumed.
- On entering / leaving Active, `schedule_component` sends `activated_event` / `deactivated_event` to itself and its descendants right after this notification (when `SendActivation` is on). When the server starts in the middle of a period, the first evaluation is Active and `activated_event` arrives.
- `schedule_text_changed_event` (scene_event, SendDown): `Sender : component`, `Text : message` (with Prefix), `RemainingWholeSeconds : int` (rounded-up integer). `schedule_text_component` sends it down from its own entity. `schedule_countdown_hud_component` passes it to its own widgets (`SendToWidgets`). Only when the text changes. Receivers are widgets, signs and the like that show the text. Not consumed.
- `schedule_component.StateChangedEvent : listenable(schedule_snapshot)` — fires with the new value only when the state or the cycle changes. Once on the first evaluation too.
- `schedule_component.SecondEvent : listenable(schedule_snapshot)` — once per second. After the same second's `StateChangedEvent`. Each subscriber adds per-second work, so use `StateChangedEvent` when only the state matters.
- `realtime_clock_component.SecondEvent : listenable(float)` — once per second, with the time used for evaluation (`GetNowEpochSeconds`). After every schedule's notifications are delivered.
- `schedule_text_component.TextChangedEvent : listenable(message)` — when the text changes.
- `schedule_digit_display_component.DigitChangedEvent : listenable(int)` — when the digit value (0-9; -1 when showing nothing) changes. To show digits through material parameters, subscribe to this and write to your own MI.
- Received: `schedule_countdown_hud_component` ignores the `activated_event` / `deactivated_event` from the schedule (showing is decided only by the pre-start window check, calling `Activate` / `Deactivate` itself). Other scene_events are handled like `player_widget_component`.

## Owner
- `schedule_countdown_hud_component` is a `player_widget_component` subclass, so when placed under a player's slot (inside a loadout, for example) it shows only on the owner's screen rather than for everyone in the scope. The other components do not change behavior by owner.

## Public API
```verse
# ScheduleTime.verse (stateless helpers)
SecondsPerDay<public>:int = 86400
SecondsPerHour<public>:int = 3600
SecondsPerMinute<public>:int = 60
DefaultTimeZoneOffsetSeconds<public>:int = 32400
ToWholeSeconds<public>(Seconds:float)<transacts>:int             # 0 or less gives 0, otherwise rounded up (the integer used for display)
GetDayIndex<public>(EpochSeconds:float, TimeZoneOffsetSeconds:int)<transacts>:int
GetSecondsOfDay<public>(EpochSeconds:float, TimeZoneOffsetSeconds:int)<transacts>:float
GetDayStartSeconds<public>(DayIndex:int, TimeZoneOffsetSeconds:int)<computes>:float
DaysBetween<public>(FromSeconds:float, ToSeconds:float)<transacts>:int
MakeSecondsOfDay<public>(Hour:int, Minute:int, Second:int)<computes>:int
split_seconds<public> := struct:
    Days<public>:int = 0
    Hours<public>:int = 0
    Minutes<public>:int = 0
    Seconds<public>:int = 0
SplitSeconds<public>(TotalSeconds:int)<transacts>:split_seconds
FormatHoursMinutesSeconds<public>(TotalSeconds:int)<transacts>:string      # "HH:MM:SS"
FormatMinutesSeconds<public>(TotalSeconds:int)<transacts>:string           # "MM:SS"
FormatDaysHoursMinutesSeconds<public>(TotalSeconds:int)<transacts>:string  # "Dd HH:MM:SS"
FormatDays<public>(TotalSeconds:int)<transacts>:string
GetDigit<public>(Value:int, Digit:int)<transacts>:int
IsLeadingZero<public>(Value:int, Digit:int)<decides><transacts>:void

realtime_clock_component<public> := class<final_super>(component):
    TimeZoneOffsetSeconds<public>:int
    WakeMarginSeconds<public>:float
    var<private> DebugOffsetSeconds<public>:float
    SecondEvent<public><final>:listenable(float)
    GetNowEpochSeconds<public>()<transacts>:float             # Same value within one transaction. Never goes backward even if the OS clock does
    GetTimeZoneOffsetSeconds<public>()<computes>:int
    GetDayIndex<public>(EpochSeconds:float)<transacts>:int
    GetSecondsOfDay<public>(EpochSeconds:float)<transacts>:float
    SetDebugOffsetSeconds<public>(OffsetSeconds:float):void   # For debugging. Re-evaluates immediately
    JumpTo<public>(EpochSeconds:float):void                   # For debugging
    GetSchedules<public>()<transacts>:[]schedule_component    # Registration order

schedule_kind<public> := enum:
    Daily
    FixedInterval
    OneShot

schedule_component<public> := class<final_super>(component):
    Kind<public>:schedule_kind
    StartHour<public>:int
    StartMinute<public>:int
    StartSecond<public>:int
    DurationSeconds<public>:float
    IntervalSeconds<public>:float
    EpochAnchorSeconds<public>:float
    SendActivation<public>:logic
    StateChangedEvent<public><final>:listenable(schedule_snapshot)
    SecondEvent<public><final>:listenable(schedule_snapshot)
    FindClock<public>()<decides><transacts>:realtime_clock_component
    GetTimeZoneOffsetSeconds<public>()<transacts>:int                  # DefaultTimeZoneOffsetSeconds without a clock
    FindLastSnapshot<public>()<decides><transacts>:schedule_snapshot   # Fails until the first evaluation
    GetCurrentSnapshot<public>()<transacts>:schedule_snapshot
    IsActive<public>()<decides><transacts>:void
    Evaluate<public>(T:float)<transacts>:schedule_snapshot             # Pure computation that changes no state
    EvaluateWithOffset<public>(T:float, TimeZoneOffsetSeconds:int)<transacts>:schedule_snapshot

schedule_state<public> := enum:
    Before
    Active
    After      # One-shot only

schedule_snapshot<public> := struct:
    NowSeconds<public>:float = 0.0
    State<public>:schedule_state = schedule_state.Before
    CycleIndex<public>:int = 0
    CycleStartSeconds<public>:float = 0.0
    ElapsedSeconds<public>:float = 0.0
    SecondsToEnd<public>:float = 0.0
    SecondsToStart<public>:float = 0.0
    HasNextStart<public>:logic = false
(Snapshot:schedule_snapshot).IsActive<public>()<decides><computes>:void
(Snapshot:schedule_snapshot).IsSameStateAndCycle<public>(Other:schedule_snapshot)<decides><computes>:void
(Snapshot:schedule_snapshot).GetRemainingSeconds<public>(Kind:schedule_remaining_kind)<computes>:float   # Fraction. Use ToWholeSeconds for an integer

schedule_remaining_kind<public> := enum:
    UntilStart
    UntilEnd

schedule_state_changed_event<public> := class(scene_event):
    Schedule<public>:schedule_component
    Previous<public>:?schedule_snapshot
    Current<public>:schedule_snapshot

# Helper that finds and subscribes to the schedule_component on its own entity or an ancestor (held as one field)
schedule_follower<public> := class<unique>:
    FindSchedule<public>()<decides><transacts>:schedule_component
    Attach<public>(Owner:entity, OnChanged:type{_(:schedule_snapshot):void}, OnSecond:?type{_(:schedule_snapshot):void}):logic   # false when not found
    Detach<public>():void

# ConditionKit
schedule_active_condition_component<public> := class<final_super>(condition_component):

# DisplayKit
schedule_time_field<public> := enum:
    Days
    Hours
    Minutes
    Seconds
    TotalSeconds
    TotalMinutes
GetTimeField<public>(RemainingWholeSeconds:int, Field:schedule_time_field)<transacts>:int

schedule_digit_glyph_component<public> := class<final_super>(component):
    Value<public>:int

schedule_digit_display_component<public> := class<final_super>(component):
    Digit<public>:int
    Field<public>:schedule_time_field
    RemainingKind<public>:schedule_remaining_kind
    BlankLeadingZero<public>:logic
    DigitChangedEvent<public><final>:listenable(int)
    GetDigitValue<public>()<transacts>:int        # -1 when showing nothing

schedule_text_format<public> := enum:
    HoursMinutesSeconds
    MinutesSeconds
    DaysHoursMinutesSeconds
    Days
    TotalSeconds
FormatRemaining<public>(RemainingWholeSeconds:int, Format:schedule_text_format, Prefix:string)<transacts>:string
ScheduleTextToMessage<public><localizes>(Text:string):message

schedule_text_changed_event<public> := class(scene_event):
    Sender<public>:component
    Text<public>:message
    RemainingWholeSeconds<public>:int

schedule_text_component<public> := class<final_super>(component):
    Format<public>:schedule_text_format
    RemainingKind<public>:schedule_remaining_kind
    Prefix<public>:string
    OnlyWhileShown<public>:logic
    TextChangedEvent<public><final>:listenable(message)
    GetText<public>():message
    GetRemainingWholeSeconds<public>()<transacts>:int  # The remaining seconds the text was made from (rounded-up integer). -1 until then
    Show<public>():void
    Hide<public>():void
    IsShown<public>()<decides><transacts>:void

# HudKit
schedule_countdown_hud_component<public> := class<final_super>(player_widget_component):
    ShowWithinSeconds<public>:float
    Format<public>:schedule_text_format
    Prefix<public>:string
    TextSize<public>:float
    PositionXRatio<public>:float
    PositionYRatio<public>:float
```

## Naming rules
- Second values are written `...Seconds` when fractional (float) and `...WholeSeconds` when rounded up to an integer (int; the value shown on screen). Aligned with CountdownSystem (`GetRemainingSeconds():float` / `GetRemainingWholeSeconds():int`).

## Requirements, caveats and limits
- One `realtime_clock_component` is needed in the scope (or the world). Without it, `schedule_component` is not evaluated (it waits one frame and looks again, and if still none, keeps looking every second until found (`AwaitScopedComponent`; also picks up a clock added later by a prefab). If none after 1 s, it Prints once). A Kit Prints and does nothing when `schedule_component` is on neither its own entity nor an ancestor.
- Real time cannot be stopped (there is no Pause). For things that need pausing, use simulation-time Systems such as CountdownSystem.
- A "day" is always 86400 seconds (calendar months and years are not used). Daylight saving time is not considered.
- `GetNowEpochSeconds` never goes backward even if the OS clock does. When the time is jumped for debugging, the intermediate changes collapse into one change (the state at the destination). Whether to leave the debug `SetDebugOffsetSeconds` / `JumpTo` on a published island is up to you.
- No per-frame work. The clock wakes once per second and computes once per schedule. The display Kits (text, digits, HUD) subscribe to `SecondEvent`, so they compute once per second (writes only when the value changes).
- `schedule_countdown_hud_component` needs a `player_manager_component` in the scope (or the world) (a `player_widget_component` requirement). Outside the pre-start window nothing is shown on screen (only the per-second comparison of the remaining seconds continues).
- `message` cannot be concatenated, so the leading text is held as `Prefix` (string).
- `schedule_sequence_component` moved to FNDeviceSystem (`FNDeviceSystem/ScheduleKit/`). Its usage and the points not confirmed in UEFN are in the FNDeviceSystem README. Its tooltips (`ScheduleSequencesToolTip` etc.) remain in this System's TooltipKit.
- This System's code has no `⚠ Unverified` marks and uses no `@experimental` API.

## Verifying
- Test: `schedule_system_test_component` in `_Test/ScheduleSystemTest/`. Just place one entity with this component (the test creates the clock, the schedule and the children at runtime). Do not place another `realtime_clock_component` in the level (with two in the world, which one is used is undefined). No player needed. Checks the `Evaluate` computation (daily / fixed interval / one-shot, day boundaries), `ToWholeSeconds`, the day count / text format (`Format*`) / digit (`GetDigit` / `IsLeadingZero`) helpers, that the clock never goes backward and the debug time jump, that `StateChangedEvent` fires only on change, `activated_event` / `deactivated_event` to the children, and the condition Kit. About 12 s. Results go to the output log as `[TEST] ScheduleSystem`.
- The DisplayKit and HudKit components themselves (mesh toggling, screen display) are not tested.
- There is no ScheduleSystem sample in `_Samples/`.

## Migration notes (2026-11-08)
- `ToDisplaySeconds` -> `ToWholeSeconds`.
- `schedule_text_component.GetRemainingSeconds():int` -> `GetRemainingWholeSeconds():int`.
- `schedule_text_changed_event.RemainingSeconds` -> `RemainingWholeSeconds`.
- The first parameter of `GetTimeField` / `FormatRemaining` renamed `RemainingSeconds` -> `RemainingWholeSeconds` (no change needed when passed by position).
- Removed the ToolTips `ScheduleHudPositionXToolTip` / `ScheduleHudPositionYToolTip` (the HUD position uses WidgetSystem's `WidgetPositionXToolTip` / `WidgetPositionYToolTip`). The setting names `PositionXRatio` / `PositionYRatio` were already the same as WidgetSystem/HudKit and are unchanged.
- `schedule_state_changed_event.Sender` -> `Schedule` (the sender field name was aligned across the Library. `schedule_text_changed_event.Sender : component` stays because it has two kinds of sender).
- `schedule_follower` (used by the Kits and FNDeviceSystem's `schedule_sequence_component`) now always picks the nearest schedule when nested (previously, when its own entity had none, it used the first of `FindAncestorComponents`, whose order is undefined). Name and usage are unchanged.
