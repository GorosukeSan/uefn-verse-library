# InputSystem

A System that handles player input. It has functions for awaiting input from abilities and views (InputHelpers), `player_input_component` (InputKit) that notifies the whole zone of a press, and `player_ready_component` (ReadyKit) that holds each player's "ready" state.

Dependency direction: the top level of InputSystem (InputHelpers) does not depend on any other System of the Library (it is the foundation used by the abilities of other Systems, etc.). InputKit depends on PlayerSystem and SceneGraphSystem; ReadyKit depends on InputKit, PlayerSystem, SceneGraphSystem and ConditionSystem. The top level does not depend on the Kits.

## Placement

| component | Where to place | What it does |
|---|---|---|
| `player_input_component` (InputKit) | wherever the activation signal arrives (for the game flow, the node's entity or a descendant). Any number per entity | while active, adds `InputMapping` to every player and sends `player_input_triggered_event` to the whole zone when `InputAction` is pressed |
| `player_input_view_component` (InputKit) | created at runtime by `player_input_component` under the slot (not placed in the editor) | one player's key mapping and the notification when pressed (added once the player's input is available) |
| `player_ready_component` (ReadyKit) | wherever the activation signal arrives. Place one `player_input_component` on the same entity (the press action is its `InputAction`) | while active, every time the `player_input_component` on the same entity is pressed, toggles the presser's "ready" state and sends `player_ready_changed_event` to the whole zone. On deactivation everyone's ready state is cleared |
| `player_ready_view_component` (ReadyKit) | created at runtime by `player_ready_component` under the slot (not placed in the editor) | one player's "ready" state and attaching / removing `player_ready_tag` |
| `all_players_ready_condition_component` (ReadyKit) | directly under the entity of `game_transition_component` or `condition_all` / `condition_any` | satisfied when there is at least one participant and everyone is "ready" |

Example: "when everyone has pressed E, go to the next node"
```
Lobby (game_node_component + player_input_component + player_ready_component)
└ Next (game_transition_component)
  └ Everyone ready (all_players_ready_condition_component)
```
Place one `player_manager_component` (PlayerSystem) somewhere in the zone (or the world).

## Settings (@editable)
- `player_input_component.ActiveOnBegin : logic = false` — when on, accepts input from the start of the simulation. When off, from the activation signal until the deactivation signal.
- `player_input_component.InputMapping : input_mapping = MenuNavigationMapping` — the key mapping added to every player while accepting input (the default is the menu mapping: E / Q / C / Z / Esc; RB / LB / RT / LT / Back on gamepad).
- `player_input_component.InputAction : input_action(logic) = NextTab` — the action whose press is notified. Choose one contained in `InputMapping` (the default is the E key, RB on gamepad).
- `player_ready_component.ActiveOnBegin : logic = false` — when on, accepts "ready" from the start of the simulation. When off, from the activation signal until the deactivation signal.

## Events
- `player_input_triggered_event` (InputKit. scene_event, SendScoped: the whole zone; the whole world when there is no zone): `Input : player_input_component`, `Agent : agent`, `Action : input_action(logic)`. Sent by `player_input_component`; received by components that watch for presses. To watch only the presses of one component, filter by `Input` or Subscribe to `TriggeredEvent`. Not consumed.
- `player_ready_changed_event` (scene_event, SendScoped): `PlayerReady : player_ready_component`, `Agent : agent`, `Ready : logic`. Sent by `player_ready_component` (its view); received by `all_players_ready_condition_component`, etc. Not consumed.
- listenable (cannot be Signaled from outside)
  - `player_input_component.TriggeredEvent : listenable(agent)` — fires with the agent who pressed every time `InputAction` is pressed.
  - `player_ready_component.ReadyChangedEvent : listenable(tuple(agent, logic))` — fires with (the agent, whether ready) every time someone's ready state toggles.
- Received: `player_input_component` and `player_ready_component` receive `activated_event` / `deactivated_event` (activate / deactivate). `player_ready_component` Subscribes to `player_input_component.TriggeredEvent` on the same entity (not received as a scene event). `all_players_ready_condition_component` receives `player_ready_changed_event` / `player_added_event` / `player_removed_event`.

## Tags
- `player_ready_tag` (derived from `player_state_tag`, ReadyKit). Attached through `player_tag_holder` by `player_ready_view_component` when the player becomes "ready"; removed when canceled or when accepting stops (the view disappears). The tag is attached to the player's agent.
- Other Systems check with `Agent.HasPlayerTag[player_ready_tag]`.

## Public API
```verse
# InputHelpers (InputSystem)
(Agent:agent).FindPlayerInput<public>()<decides><transacts>:player_input        # fails when not a player or unavailable
(Agent:agent).AwaitPlayerInput<public>()<suspends>:?player_input                 # waits frame by frame until available. false when not a player or on leaving
(PlayerInput:player_input).AwaitPressed<public>(Action:input_action(logic))<suspends>:void    # awaits BeginDetectEvent
(PlayerInput:player_input).AwaitReleased<public>(Action:input_action(logic))<suspends>:void   # awaits EndDetectEvent
(PlayerInput:player_input).HoldInputMapping<public>(Mapping:input_mapping, RemoveOnEnd:logic)<suspends>:void   # use in a race branch. Never returns

# InputKit
player_input_triggered_event<public> := class(scene_event):
    Input<public>:player_input_component
    Agent<public>:agent
    Action<public>:input_action(logic)

player_input_component<public> := class<final_super>(component):
    ActiveOnBegin<public>:logic
    InputMapping<public>:input_mapping
    InputAction<public>:input_action(logic)
    TriggeredEvent<public><final>:listenable(agent)
    Activate<public>():void                                    # does nothing when already accepting
    Deactivate<public>():void                                  # removes InputMapping from everyone
    IsActive<public>()<decides><transacts>:void

player_input_view_component<public> := class<final_super>(component):
    Source<public>:player_input_component
    Player<public>:player

# ReadyKit
player_ready_changed_event<public> := class(scene_event):
    PlayerReady<public>:player_ready_component
    Agent<public>:agent
    Ready<public>:logic

player_ready_tag<public> := class(player_state_tag):

player_ready_component<public> := class<final_super>(component):
    ActiveOnBegin<public>:logic
    ReadyChangedEvent<public><final>:listenable(tuple(agent, logic))
    Activate<public>():void                                    # everyone starts "not ready"
    Deactivate<public>():void                                  # clears everyone's ready state (no notification)
    IsActive<public>()<decides><transacts>:void
    FindInput<public>()<decides><transacts>:player_input_component   # the input on the same entity whose presses are received. Fails when there is none
    IsReady<public>(Agent:agent)<decides><transacts>:void      # fails when not accepting or there is no view
    SetReady<public>(Agent:agent, Value:logic):void            # does nothing when not accepting or there is no view
    ToggleReady<public>(Agent:agent):void                      # the same toggle as a press
    ResetAll<public>():void
    GetReadyCount<public>()<transacts>:int                     # 0 while inactive

player_ready_view_component<public> := class<final_super>(component):
    Source<public>:player_ready_component
    Player<public>:player
    IsReady<public>()<decides><reads>:void
    SetReady<public>(Value:logic):void                         # notifies only when it changed

all_players_ready_condition_component<public> := class<final_super>(condition_component):
```

## Requirements, caveats and limits
- `player_input_component`, `player_ready_component` and `all_players_ready_condition_component` need one `player_manager_component` (PlayerSystem) in the zone (or the world). `all_players_ready_condition_component` also needs one `player_ready_component` (both are looked up at start and when a notification arrives, then remembered).
- The ready count (`GetReadyCount`) and `all_players_ready_condition_component` only look at views that are in the world. On leaving, the whole slot with its views is removed from the world, and `player_ready_view_component` goes back to "not ready" when it stops (`OnEndSimulation`) (no notification; the condition re-checks on `player_removed_event`). The views of players who left are dropped from the list by `player_view_set` on the manager's `PlayerRemovedEvent`.
- `player_ready_component` learns of presses only from the `player_input_component` on the same entity (its `TriggeredEvent`). The press action is decided solely by its `InputAction` (the ready side has no action setting). With two or more `player_input_component` on the same entity, which one is used is unspecified, so put other inputs on another entity. Without one, pressing does not toggle (drive it only through `SetReady` / `ToggleReady`). `player_input_component` is looked up at start, on the activation signal and in `Activate` (check with `FindInput`).
- `player_input_component` notifies when the value of `TriggerActivationEvent` is true. On deactivation it removes `InputMapping` from everyone. Choosing a character-control mapping as `InputMapping` makes players unable to move once deactivated.
- `player_input_view_component` waits frame by frame until the player's input (`player_input`) is available (`AwaitPlayerInput`) before adding `InputMapping` and subscribing. Even a view created right after joining or right after the start accepts input from the moment it becomes available.
- Two or more `player_input_component` using the same `InputMapping` may be placed. When one stops, after removing `InputMapping` from the player, it re-adds the `InputMapping`s of other `player_input_view_component`s still running for the same player (under the same slot) (`input_mapping` cannot be compared for equality, so all are re-added without telling whether they are the same). Assumes the engine does not count `AddInputMapping` (same as the note on `HoldInputMapping`). ⚠ Unverified: if the engine does count, the re-added ones stay; whether an input mid-press is cut when a mapping is removed and re-added in the same frame. It is not counted together with an ability's `HoldInputMapping` (`RemoveOnEnd` true), so when that one removes the mapping the input is cut.
- `AwaitPressed` / `AwaitReleased` do not arrive unless an `input_mapping` containing `Action` has been added to the player. `AwaitReleased` called while not pressed does not return until the next press and release.
- Set `RemoveOnEnd` of `HoldInputMapping` to true only for a mapping dedicated to that ability. Removing a mapping that weapons or movement also use (`RangedWeaponMapping` / `TraversalMapping`, ...) makes the player unable to shoot or move. Removal is not counted, so do not set it to true either when another feature (another ability, `player_input_component`, ...) uses the same mapping.
- At the top of an ability's `RunFor`, use `AwaitPlayerInput` instead of `FindPlayerInput` (right after the start or right after joining the input may not be available yet. Trying only once leaves the ability "granted" but not running for players whose input was unavailable).
- The code of this System uses no experimental API. The related samples `_Samples/InputSampleExperimentalKit/` and `_Samples/VirtualPointerSampleExperimentalKit/` use experimental APIs (`InteractMapping`, cameras, ...), so they are distributed only to projects with "include experimental" turned on in VerseShare.

## Verifying
- Test: `input_system_test_component` in `_Test/InputSystemTest/`. Place one entity with `player_manager_component` and one entity with this component (the input and ready components are created by the test at runtime). Do not place another `player_ready_component` in the zone (or the world). Start with one player (waits up to 10 s for the join). First, from code, it checks `player_ready_component` (`Activate` / `FindInput` / `SetReady` / `ToggleReady` / `IsReady` / `GetReadyCount` / `ResetAll` / `Deactivate`), `ReadyChangedEvent`, `player_ready_changed_event` and `all_players_ready_condition_component`. Instead of leaving, it detaches the player's slot from the manager and also checks that the detached view's ready state does not stay in the count, that the ready state resets, and that the count is recomputed when the slot is put back (a real leave is checked by a person with two or more players). Next, when the log says "press E", press the E key (RB on gamepad) within 10 s. Checks `TriggeredEvent` and that the press toggles the ready state (only that step fails if you do not press). About 20 s at most. The result is `[TEST] InputSystem` in the output log.
- Samples: `input_sample_component` in `_Samples/InputSampleExperimentalKit/` (shows the standard input actions one at a time every `StepSeconds` and reports whether they were pressed with `AwaitPressed`, etc.). `_Samples/VirtualPointerSampleExperimentalKit/` (uses the on-screen cursor with `TouchMapping` and `PointerSelect`). Both exist only in projects with "include experimental" turned on. `_Samples/AbilitySample/` (`FindPlayerInput` / `HoldInputMapping` / `AwaitPressed`) and `_Samples/WidgetSample/` (`AwaitPlayerInput` / `HoldInputMapping` / `AwaitPressed`) also serve as usage examples.

## Migration notes (2026-11-08)
- `player_ready_component.ReadyAction` was removed. The press action is decided solely by `player_input_component.InputAction` on the same entity. If you had `player_ready_component` and `player_input_component` on different entities, put them on the same entity. The ToolTip `ReadyActionToolTip` is gone too.
- `player_ready_view_component` no longer receives `player_input_triggered_event` (the toggle is done by `player_ready_component` from `TriggeredEvent`).
- `player_input_triggered_event` moved from the top level of InputSystem to InputKit (so the top level does not depend on the Kits). Code that used it with only `using { InputSystem }` adds `using { InputSystem.InputKit }`.
- `player_input_triggered_event.Source` → `Input`, `player_ready_changed_event.Source` → `PlayerReady` (the sender field name was unified across the Library; `PlayerReady` because `Source` would clash with `Ready : logic`). The views' `player_input_view_component.Source` / `player_ready_view_component.Source` are not scene_events and stay as they are.
