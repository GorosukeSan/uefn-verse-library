# ConditionSystem

The System of conditions ("if ..."): the base class `condition_component`, the combinators `condition_all` / `condition_any` (GroupKit), and `event_received_condition_component`, satisfied by a received scene_event (EventKit). A condition answers whether it is satisfied and notifies upward when that may have changed. Used by the transitions of the game flow (GameSequenceSystem), ability granting (`ability_grant_condition_component`) and swing multipliers (`swing_modifier_condition_component`).

## Setup (placement)

| component | Where to place | What it does |
|---|---|---|
| a `condition_component` subclass | Directly under the entity of a `game_transition_component` or `condition_all` / `condition_any` (also under an `ability_grant_condition_component` / `swing_modifier_condition_component` entity). Never placed directly (place a subclass) | Answers whether it is satisfied; when that may have changed, sends `condition_changed_event` upward and delivers to `ChangedEvent` |
| `condition_all_component` (GroupKit) | Same as above | Satisfied when every condition on its direct children is satisfied (satisfied if there are no children) |
| `condition_any_component` (GroupKit) | Same as above | Satisfied when at least one condition on its direct children is satisfied (not satisfied if there are no children) |
| `event_received_condition_component` (EventKit) | Same as above. Choose the type to wait for in `EventType` | Once activated (after receiving the activation signal `activated_event`; from the start if no signal comes), satisfied when a scene_event of `EventType` (or a subclass) reaches this entity. Returns on the activation signal or `Reset` |

Other condition subclasses live in other Systems: `countdown_finished_condition_component` (CountdownSystem), `player_count_condition_component` / `player_group_count_condition_component` (PlayerSystem / ConditionKit), `player_state_condition_component` (PlayerSystem / MotionKit), `interacted_condition_component` (InteractSystem), `player_in_volume_condition_component` (VolumeSystem), `all_players_ready_condition_component` (InputSystem / ReadyKit), `mode_selected_condition_component` (ModeSystem), `schedule_active_condition_component` (ScheduleSystem), `character_motor_condition_component` (CharacterSystem).

Example: "advance when there are 2 or more players and either the button was pressed or someone entered"
```
Next (game_transition_component)
└ All (condition_all_component)
  ├ 2 or more players (player_count_condition_component)
  └ Any (condition_any_component)
    ├ Pressed (interacted_condition_component)
    └ Inside (player_in_volume_condition_component)
```
Place children one each directly below (order does not matter).

## Settings (@editable)
- `event_received_condition_component.EventType : subtype(scene_event) = no_scene_event` — type of the scene_event to wait for (subclasses match too). The default `no_scene_event` is never sent by anyone, so the condition is not satisfied until you pick a type. From code, create it with `event_received_condition_component{Entity := E, EventType := my_event}`.
- `condition_all_component` / `condition_any_component` have no settings.

## Events
- `condition_changed_event` (scene_event, SendUp): `Condition : condition_component` (the condition that sent it). From the condition's entity to the root. Senders are `condition_component` subclasses (`NotifyChanged`). Receivers are the ancestor `game_node_component` (re-checks its transitions; does not consume) and `condition_all` / `condition_any` (receive and consume the ones not from themselves, then resend their own notification).
- `condition_component.ChangedEvent : listenable(logic)` — delivered with the current result (true if satisfied) when the satisfied state may have changed. Cannot be Signaled from outside. `ability_grant_condition_component` and `swing_modifier_condition_component` subscribe to it.
- Received: `condition_all_component` / `condition_any_component` receive `condition_changed_event` from descendants. `event_received_condition_component` receives every scene_event that reaches this entity (resets on `activated_event`, satisfied when the event matches `EventType`; does not consume).

## Public API
```verse
condition_changed_event<public> := class(scene_event):
    Condition<public>:condition_component

condition_component<public> := class<abstract><final_super>(component):
    IsSatisfied<public>()<decides><transacts>:void         # Implemented by the subclass. Must not change state (no side effects)
    ChangedEvent<public><final>:listenable(logic)
    NotifyChanged<protected>():void                        # Called by the subclass when the result may have changed

(InEntity:entity).AreChildConditionsSatisfied<public>()<decides><transacts>:void    # Succeeds if every direct child condition is satisfied. Succeeds with no children
(InEntity:entity).IsAnyChildConditionSatisfied<public>()<decides><transacts>:void   # Succeeds if at least one is satisfied. Fails with no children

# GroupKit
condition_all_component<public> := class<final_super>(condition_component):
condition_any_component<public> := class<final_super>(condition_component):

# EventKit
no_scene_event<public> := class(scene_event):                 # Default of EventType. Never sent by anyone
event_received_condition_component<public> := class<final_super>(condition_component):
    EventType<public>:subtype(scene_event)                    # Type to wait for (subclasses match too)
    Reset<public>():void                                      # Return to the unsatisfied state
    FindReceivedEvent<public>()<decides><transacts>:scene_event   # The event received when it became satisfied. Fails if none yet
```

## Requirements, caveats and limits
- A subclass writes only `IsSatisfied` and calls `NotifyChanged` when the satisfied state may have changed. `IsSatisfied` is called many times in `<transacts>`, so it must not change state.
- Only the conditions on direct children are looked at (not grandchildren). To nest, put a `condition_all` / `condition_any` in between.
- `NotifyChanged` means "may have changed"; it is fine to send it even when nothing actually changed. Receivers ask `IsSatisfied` again.
- `event_received_condition_component` only sees scene_events that reach this entity (`SendDown` from an ancestor, `SendScoped` to the whole scope, `SendGlobal` to the whole world, `SendUp` from a descendant). Events `SendUp`'d on another branch do not reach it. To wait for an event that does not reach it, have the sender send to the whole scope (`SendScoped`) or write a condition subclass.
- `event_received_condition_component` becomes satisfied on the first matching event since activation and does not resend the notification for the second and later ones (`FindReceivedEvent` returns the first).
- When making the type `@editable`, `castable_subtype` cannot be used (3604), so it is `subtype(scene_event)`. Narrowing (`EventType[SceneEvent]`) is confirmed to work in the standalone type check and when run in the new VM.
- ⚠ Unverified (EventReceivedConditionComponent.verse): whether an `@editable` of `subtype(scene_event)` lets you pick a type in the UEFN editor (`scene_event` is an interface; `subtype(component)` is confirmed to work), and whether narrowing by a type value works in UEFN.
- No `@experimental` API is used.

## Verifying
- Test: `condition_system_test_component` in `_Test/ConditionSystemTest/`. Just place one entity with this component (the test creates the condition entities at runtime; no player needed). It checks the `condition_all` / `condition_any` combinations (independence from order), nesting (a grandchild change reaches the outer `ChangedEvent` exactly once), the count and values of `ChangedEvent`, `AreChildConditionsSatisfied` / `IsAnyChildConditionSatisfied` with no children, and `event_received_condition_component` (not satisfied by other types, satisfied by the matching type and its subclasses, no notification on the second event, returns on `activated_event` and `Reset`, not satisfied with the default `no_scene_event`). It finishes right away. Results are in the output log under `[TEST] ConditionSystem`. `test_condition_component` in the same file (a condition toggled with `SetSatisfied`) is also used by the tests of other Systems.
- There is no sample (`_Samples/`).
