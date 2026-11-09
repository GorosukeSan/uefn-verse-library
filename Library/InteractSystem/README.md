# InteractSystem

A System that connects things you "press to use" on the spot (buttons, levers, chests, etc.) to the library's activation signals (ActivationSystem) and conditions (ConditionSystem). The pressing itself is handled by Epic's standard `interactable_component` (`basic_interactable_component`, etc.); this System sits on the same entity and receives the result.

## Placement

| component | Where to place | What it does |
|---|---|---|
| `interact_trigger_component` | the same entity as `interactable_component` | each time a press completes, sends `interacted_event` upward and the activation signal (with who pressed) to the `Targets` entities. With `Toggle`, alternates the activation and deactivation signals (switch, lever) |
| `interacted_condition_component` (ConditionKit) | directly under the entity of a `game_transition_component` or `condition_all` / `condition_any` | satisfied once pressed. Receiving the activation signal (re-entering the node) makes it unsatisfied again |
| `interact_gate_component` (GateKit) | the same entity as `interactable_component`, where the activation signal arrives (it may also be an entity chosen in `interact_trigger_component`'s `Targets`) | pressable only while open. Opens on the activation signal and closes on the deactivation signal (open from the start with `OpenOnBegin`; `Open` / `Close` from code) |

Example: "press the button to go to the next node"
```
Node (game_node_component)
└ Next (game_transition_component)
  └ Pressed (interacted_condition_component)
    └ Button (basic_interactable_component + interact_trigger_component + interact_gate_component + mesh)
```
Entering the node delivers the activation signal down to the button and opens the gate; leaving the node closes it. When the button cannot be placed under the condition, pick the button's entity in the condition's `Trigger`.

## Settings (@editable)
- `interact_trigger_component.Targets : []entity = array{}` — entities that receive the activation signal each time a press completes (the entity and its descendants receive it). When empty, only notifies upward.
- `interact_trigger_component.Toggle : logic = false` — when on, alternates the activation and deactivation signals to `Targets` on each press. When off, only the activation signal.
- `interacted_condition_component.Trigger : ?entity = false` — the button to watch (an entity with `interact_trigger_component`). Buttons placed among the descendants count without being picked.
- `interact_gate_component.OpenOnBegin : logic = false` — when on, pressable from the start of the simulation (when the game flow is not used). When off, from the activation signal.

The number of presses, the cooldown and the hold duration are set on `basic_interactable_component`.

## Events
- `interacted_event` (scene_event, SendUp): `Trigger : interact_trigger_component`, `Agent : agent`. Sent by `interact_trigger_component` from its entity to the root each time a press completes. Receivers are ancestor `interacted_condition_component`s etc. Not consumed.
- listenables of `interact_trigger_component` (all `listenable(agent)`; cannot be signaled from outside)
  - `InteractedEvent` — fires with the presser each time a press completes.
  - `StartedEvent` — fires each time a press starts (for a hold, when the hold starts; with a hold time of 0, at the same time as `InteractedEvent`).
  - `CanceledEvent` — fires each time a hold is canceled mid-way.
- Sent: `interact_trigger_component` sends to `Targets`: with `Toggle` off, `activated_by_agent_event` (`SendActivatedBy`; receivers read the presser with `FindActivatingAgent[]`). With `Toggle` on, `activated_event` / `deactivated_event` (`SendActivated` / `SendDeactivated`; no presser attached).
- Received: `interacted_condition_component` takes `activated_event` (reset) and `interacted_event` (satisfied). `interact_gate_component` takes `activated_event` (open) / `deactivated_event` (close).

## Public API
```verse
interacted_event<public> := class(scene_event):
    Trigger<public>:interact_trigger_component
    Agent<public>:agent

interact_trigger_component<public> := class<final_super>(component):
    Targets<public>:[]entity
    Toggle<public>:logic
    InteractedEvent<public><final>:listenable(agent)   # press completed
    StartedEvent<public><final>:listenable(agent)      # press started
    CanceledEvent<public><final>:listenable(agent)     # hold canceled mid-way
    IsOn<public>()<decides><transacts>:void            # with Toggle, succeeds if on now. Fails without Toggle
    SetOn<public>(Value:logic):void                    # sets on / off and signals Targets. Does nothing if unchanged

# ConditionKit
interacted_condition_component<public> := class<final_super>(condition_component):
    Trigger<public>:?entity
    Reset<public>():void                               # back to unsatisfied

# GateKit
interact_gate_component<public> := class<final_super>(component):
    OpenOnBegin<public>:logic
    Open<public>():void
    Close<public>():void
    IsOpen<public>()<decides><transacts>:void
```
From run-time code, `Trigger.InteractedEvent.Await()` waits for the presser.

## Requirements, caveats and limits
- An `interactable_component` (`basic_interactable_component`, etc.) is needed on the same entity. Without it, neither the trigger nor the gate does anything.
- `StartedEvent` fires when the press starts as of v43.00 (according to the code comments).
- The on / off of `IsOn` / `SetOn` is the state for `Toggle`. Without `Toggle`, `IsOn` fails. `SetOn` works without `Toggle` too and sends the activation / deactivation signal to `Targets` (no presser attached).
- Outside the game flow, turn on `interact_gate_component.OpenOnBegin` (without a gate it is always pressable) or call `Open` / `Close` from code.
- `interact_gate_component` syncs the `interactable_component`'s Enable / Disable twice: at start and on the first frame (to sync again after the start processing of the `interactable_component` on the same entity).
- `interacted_condition_component` is satisfied both by the `InteractedEvent` of the button picked in `Trigger` and by `interacted_event`s coming up from descendant buttons.
- No experimental API is used.

## Verifying
- Test: `interact_system_test_component` in `_Test/InteractSystemTest/`. Place a button entity (mesh + `basic_interactable_component` + `interact_trigger_component` + `interact_gate_component`, `OpenOnBegin` off) near the player, and put the button entity into `Button` on the entity with the test component. It checks the gate's `Open` / `Close` / `IsOpen`, `InteractedEvent`, `interacted_condition_component` (picked with `Trigger`) and `Reset`. When the log says "interact", press the button within 15 seconds (otherwise only that item fails). About 16 seconds at most. Results go to the output log as `[TEST] InteractSystem`.
- There is no sample (`_Samples/`).
