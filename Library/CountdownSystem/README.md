# CountdownSystem

A System that counts down a given number of seconds (fractions allowed) and notifies each time the remaining seconds (rounded up to a whole number) change and when the count ends. Usable both as the "after N seconds, go to the next node" condition of the game flow (GameSequenceSystem) and as a timer outside the flow.

## Placement

| component | Where to place | What it does |
|---|---|---|
| `countdown_component` | an entity where the activation signal arrives (in a game sequence, the node's entity or a descendant; a descendant of `schedule_component`, etc.). Also usable outside the flow | counts `DurationSeconds` seconds and notifies the descendants (and the ancestors too with `AlsoSendUp`) of changes in the remaining seconds and of the end |
| `countdown_finished_condition_component` (ConditionKit) | directly under the entity of a `game_transition_component` or `condition_all` / `condition_any`, and also a descendant of the `countdown_component` entity | satisfied when the countdown reaches 0. Re-activating or restarting makes it unsatisfied again |

Example: "10 seconds after entering the node, go to the next"
```
Node (game_node_component + countdown_component, DurationSeconds = 10)
└ Next (game_transition_component)
  └ Time is up (countdown_finished_condition_component)
```
Transitions must be placed directly under the node, so the timer goes on the same entity as the node (`countdown_component` notifies its descendants, so the condition is among them).

To receive the remaining seconds and the end in a HUD or a part outside (above) the node, turn on `AlsoSendUp` (also sends upward from the parent).

## Settings (@editable)
- `countdown_component.DurationSeconds : float = 5.0` — seconds to count (0.1–3600 seconds, fractions allowed). For a different length this once, use `Restart(?Seconds := option{...})`.
- `countdown_component.StartOnActivated : logic = true` — when on, restarts from the beginning on the activation signal (even while counting) and stops on the deactivation signal (in a game sequence, from entering the node to leaving it). When off, ignores the signals.
- `countdown_component.StartOnBegin : logic = false` — when on, starts counting at the start of the simulation (when the game flow is not used).
- `countdown_component.AlsoSendUp : logic = false` — when on, sends the notifications (`countdown_remaining_changed_event` / `countdown_finished_event`) upward from the parent to the ancestors (SendUp) in addition to the descendants. Its own entity receives them only once.

You may turn off both `StartOnActivated` and `StartOnBegin` and call `Start` / `Restart` / `Stop` from code. `countdown_finished_condition_component` has no settings.

## Events
- `countdown_remaining_changed_event` (scene_event, SendDown; also SendUp from the parent with `AlsoSendUp`): `Countdown : countdown_component`, `RemainingWholeSeconds : int` (rounded up; 1 or more). Arrives when the value changes: at the start, every second, on `AddSeconds` and `Resume` (not when it reaches 0). Sent by `countdown_component`, received by descendant `countdown_finished_condition_component`s etc. Not consumed.
- `countdown_finished_event` (scene_event, SendDown; also SendUp from the parent with `AlsoSendUp`): `Countdown : countdown_component`. Arrives when the remaining time reaches 0. Not sent when stopped by `Stop` or the deactivation signal. Not consumed.
- `countdown_component.RemainingChangedEvent : listenable(int)` — fires with the value each time the remaining seconds (rounded up) change (every second).
- `countdown_component.FinishedEvent : listenable(tuple())` — fires when the count ends.
- Received: `countdown_component` takes `activated_event` (restart from the beginning) / `deactivated_event` (stop) (with `StartOnActivated`; not consumed). `countdown_finished_condition_component` takes `activated_event` and `countdown_remaining_changed_event` (back to unsatisfied) and `countdown_finished_event` (satisfied). None are consumed.

## Public API
```verse
countdown_remaining_changed_event<public> := class(scene_event):
    Countdown<public>:countdown_component
    RemainingWholeSeconds<public>:int

countdown_finished_event<public> := class(scene_event):
    Countdown<public>:countdown_component

countdown_component<public> := class<final_super>(component):
    DurationSeconds<public>:float
    StartOnActivated<public>:logic
    StartOnBegin<public>:logic
    AlsoSendUp<public>:logic
    RemainingChangedEvent<public><final>:listenable(int)
    FinishedEvent<public><final>:listenable(tuple())
    Start<public>():void                                    # starts from DurationSeconds if not counting. Does nothing while counting (including paused)
    Restart<public>(?Seconds:?float = false):void           # restarts from the beginning (even while counting, paused or after the end). Seconds sets the length this once
    Stop<public>():void                                     # stops (FinishedEvent does not fire). Does nothing if not counting
    IsRunning<public>()<decides><transacts>:void            # succeeds while counting (not paused)
    IsPaused<public>()<decides><transacts>:void             # succeeds while counting and paused
    Pause<public>():void
    Resume<public>():void
    AddSeconds<public>(DeltaSeconds:float):void             # adds to the remaining time (subtracts when negative). Ends on the spot at 0 or less
    GetRemainingSeconds<public>()<transacts>:float          # remaining time (fraction). 0.0 if not counting
    GetRemainingWholeSeconds<public>()<transacts>:int       # remaining time rounded up. 0 if not counting

# ConditionKit
countdown_finished_condition_component<public> := class<final_super>(condition_component):
```

## Naming
- Second values are named `...Seconds` for fractions (float) and `...WholeSeconds` for rounded-up whole numbers (int; the value shown on screen). This matches ScheduleSystem (`schedule_snapshot.GetRemainingSeconds` is a fraction, `schedule_text_component.GetRemainingWholeSeconds` a whole number).

## Requirements, caveats and limits
- The remaining time is "end time minus the current simulation time". It is not counted by frames or accumulated waits, so it does not drift. It does not decrease while paused.
- `Start` does nothing while counting (the same split as GameSequenceSystem's `Start` / `Restart`). To restart mid-way, use `Restart` or the activation signal. Calling `Stop` and then `Restart` in the same frame loses nothing.
- `AddSeconds` works only while counting (including paused). If the remaining time becomes 0 or less while paused, the count ends on resume.
- With `AlsoSendUp` on, the notifications also reach `countdown_finished_condition_component`s on the ancestors (ones placed for other countdowns). Leave it off when there are other conditions on the ancestors.
- `countdown_finished_condition_component` is a ConditionSystem condition. Its placement follows the ConditionSystem rules (directly under a transition or `condition_all` / `condition_any`).
- The code of this System has no `⚠ Unverified` items and no `@experimental` API.

## Verifying
- Test: `countdown_system_test_component` in `_Test/CountdownSystemTest/`. Just place one entity with this component (the `countdown_component` is created by the test at run time; no player needed). It checks the real time from `Start` to `FinishedEvent`, the count and values of the remaining-seconds notifications, `Pause` / `Resume`, `AddSeconds` (adding, and subtracting more than the remaining time), `Stop`, start / stop / mid-way restart on the activation and deactivation signals, `Restart` (mid-way, with a given length, under 1 second) and `AlsoSendUp` (received on the parent entity). It takes about 20 seconds. Results go to the output log as `[TEST] CountdownSystem`.
- There is no sample (`_Samples/`).

## Migration notes (2026-11-08)
- `countdown_component.Seconds : int` → `DurationSeconds : float` (re-enter the value on instances placed in the editor).
- `GetRemainingTimeSeconds():float` → `GetRemainingSeconds():float`, `GetRemainingSeconds():int` → `GetRemainingWholeSeconds():int` (the same name changed type, so code that used it as an int fails to compile).
- `countdown_remaining_changed_event.RemainingSeconds` → `RemainingWholeSeconds`.
- `Start()` now does nothing while counting (it used to restart from the beginning). To restart, use `Restart()`. The activation signal still restarts from the beginning as before.
