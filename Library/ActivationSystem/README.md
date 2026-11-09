# ActivationSystem

A System that defines the shared signals for "running and stopping" parts: activation `activated_event` and deactivation `deactivated_event`. It also has an activation signal that tells who triggered it (`activated_by_agent_event`). Parts that wait for activation (countdowns, screens, grants, device bridges, etc.) start and stop on these signals. Entering and leaving a node of the game flow (GameSequenceSystem) also delivers these signals to everything under the node.

## Placement

| component | Where to place | What it does |
|---|---|---|
| `activate_on_begin_component` | the entity of the part to activate, or an ancestor | sends the activation signal once to this entity and its descendants on the frame after the simulation starts |
| `enable_on_activation_component` | where the signal arrives (the entity of the part to activate, or a descendant) | enables on the activation signal and disables on the deactivation signal (reversed with `Invert`). It toggles the components with an enabled state (`enableable`: meshes, lights, interactables, particles, etc.) on `Targets` (this entity when empty) |

Example: "start a countdown and show a door at start, without the game flow"
```
Room (activate_on_begin_component)
├ Timer (countdown_component)
└ Door (mesh + enable_on_activation_component)
```
With `ApplyOnBegin` the door is disabled at start, then enabled (shown) by the activation signal that arrives on the frame after start. The timer starts counting on the same signal.

## Settings (@editable)
- `enable_on_activation_component.Targets : []entity = array{}` — the entities to enable / disable. When empty, toggles the components attached to this entity.
- `enable_on_activation_component.Invert : logic = false` — when on, reverses it (disable on activation, enable on deactivation).
- `enable_on_activation_component.ApplyOnBegin : logic = true` — when on, applies the "deactivated" state at the start of the simulation (e.g. keep hidden until activated).

`activate_on_begin_component` has no settings.

## Events
- `activated_event` (scene_event, SendDown): no fields. Reaches the sending entity and its descendants. Not consumed. Main senders: the game flow (`game_node_entered_event` is a subclass), `activate_on_begin_component`, `interact_trigger_component`, `volume_activation_component`, `schedule_component`, `player_state_trigger_component`, `device_event_component`, the loadout root (`loadout_instance_component`), your code (`SendActivated`).
- `activated_by_agent_event` (a subclass of `activated_event`, SendDown): `Agent : agent` (who triggered it). Being a subclass of `activated_event`, parts waiting for activation run as usual. Not consumed. Senders: parts that know who triggered them (`interact_trigger_component` (with Toggle off), `choice_menu_component`, `volume_activation_component`, `player_motion_trigger_component`, `character_action_trigger_component` (when it has an owner), `device_event_component` (when the triggering player is known)). Receivers that need a player (FNDeviceSystem's `device_trigger_component`, `device_audio_component`, `device_sequence_component`, etc.) read it with `FindActivatingAgent[]`.
- `deactivated_event` (scene_event, SendDown): no fields. Reaches the sending entity and its descendants. Not consumed. In the game flow, `game_node_exited_event` is a subclass. Also sent by `interact_trigger_component` (Toggle), `volume_activation_component`, `schedule_component`, `player_state_trigger_component`, when a loadout is removed, and your code (`SendDeactivated`).
- Received: `enable_on_activation_component` takes `activated_event` (subclasses too) / `deactivated_event`. Not consumed.

## Public API
```verse
activated_event<public> := class(scene_event):
deactivated_event<public> := class(scene_event):

activated_by_agent_event<public> := class(activated_event):
    Agent<public>:agent

(InEntity:entity).SendActivated<public>():void                 # sends activated_event to InEntity and its descendants
(InEntity:entity).SendDeactivated<public>():void               # sends deactivated_event to InEntity and its descendants
(InEntity:entity).SendActivatedBy<public>(Agent:agent):void    # sends activated_by_agent_event to InEntity and its descendants
(SceneEvent:scene_event).FindActivatingAgent<public>()<decides><transacts>:agent   # Agent if it is an activated_by_agent_event, else fails

activate_on_begin_component<public> := class<final_super>(component):

enable_on_activation_component<public> := class<final_super>(component):
    Targets<public>:[]entity
    Invert<public>:logic
    ApplyOnBegin<public>:logic
    Apply<public>(Active:logic):void                # puts it in the activated (true) or deactivated (false) state. Enabled / disabled are reversed with Invert
    SetEnabled<public>(Enabled:logic):void          # toggles the Targets' components directly (does not change IsOn)
    IsOn<public>()<decides><transacts>:void         # succeeds if the last signal received was activation (Apply(true))
```

## Requirements, caveats and limits
- A part that sends the activation signal uses `SendActivatedBy(Agent)` when it knows who triggered it (receivers can take it as an `activated_event`, so no separate sending is needed). Receivers that need a player read it with `FindActivatingAgent[]` and decide what to do when it fails (a plain `activated_event`).
- `activate_on_begin_component` does not send the deactivation signal. To stop, call `SendDeactivated` or each part's `Stop` / `Deactivate`.
- `activate_on_begin_component` waits one frame before sending (`TickEvents.PrePhysics.Await()`, so that every component in the same tree has finished `OnBeginSimulation` first).
- `enable_on_activation_component` does not toggle itself. It does not look at the descendants of the `Targets` entities; it toggles only the components attached to those entities.
- The code of this System has no `⚠ Unverified` items and no `@experimental` API.

## Verifying
- Test: `activation_system_test_component` in `_Test/ActivationSystemTest/`. Just place one entity with this component (no player needed). It checks that `SendActivated` / `SendDeactivated` reach the children and that `activate_on_begin_component` does not send on the same frame but sends the activation signal exactly once after start. It takes under 1 second. Results go to the output log as `[TEST] ActivationSystem`. `activated_by_agent_event` / `SendActivatedBy` / `FindActivatingAgent` and `enable_on_activation_component` are not tested.
- Samples: `AbilitySample`, `InputSampleExperimentalKit`, `VirtualPointerSampleExperimentalKit` and `WidgetSample` in `_Samples/` start on the activation signal (`activated_event`) when `StartOnBegin` is off.

## Rounds (fort_round_manager)
- `activate_on_round_component`: when a Fortnite round starts, sends `round_started_event` (a subclass of `activated_event`, with `RoundNumber`) to `Targets` (this entity and its descendants when empty), and `round_ended_event` (a subclass of `deactivated_event`) when it ends. `FirstRound` / `LastRound` limit which rounds send (0 means no limit). `RoundStartedEvent` / `RoundEndedEvent` (listenable(int)), `IsInRound[]`, `GetRoundNumber()`.
- Place signal-driven parts (countdowns, spawners, widgets, menus, volumes, loadouts, etc.) under it and they run only during the round and restart every round (turn off their ActiveOnBegin / StartOnBegin).
- `round_watcher`: a helper for receiving rounds from code (hold it in a field; `Start(Entity, OnStarted, OnEnded)` / `Stop()`). `OnStarted<suspends>` is canceled when the round ends. If a round is already in progress, it runs right away inside `Start`. `Start` returns false when the round manager is not available.
- ⚠ Unverified: whether Scene Graph entities and components persist across a round change (the per-round restart via signals assumes they do).
