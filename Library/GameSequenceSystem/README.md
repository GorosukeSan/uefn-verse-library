# GameSequenceSystem

A System that builds the game flow (stages such as waiting -> playing -> results) as a tree of node and transition entities. Entering a node sends the activation signal (ActivationSystem) to its descendants; exiting sends the deactivation signal. When a transition's conditions (ConditionSystem) are satisfied, the flow advances to the next node.

## Placement

| component | Where to place | What it does |
|---|---|---|
| `game_sequence_component` | the root entity of the sequence. One per sequence. Any number may be placed in a level (each advances only the nodes directly under it. No zone needed) | advances the sequence from the first node. Ends at a transition without `Target` |
| `game_node_component` | directly under the entity of `game_sequence_component` | one stage of the sequence. On entering, notifies activation to its descendants; on exiting, deactivation. Waits until a child transition can advance |
| `game_transition_component` | directly under the entity of `game_node_component` | advances to the `Target` node when every direct child condition is satisfied (ends the sequence when `Target` is empty). Advances immediately without conditions |

Example: "wait 10 seconds, then play; when the button is pressed, end"
```
Sequence (game_sequence_component)
├ Waiting (game_node_component, Order 0 + countdown_component)
│ └ To Playing (game_transition_component, Target = Playing)
│   └ Time up (countdown_finished_condition_component)
└ Playing (game_node_component, Order 1)
  ├ Platform (spawn_prefab_component; SpawnSystem's PrefabKit)
  └ End (game_transition_component, Target empty)
    └ Pressed (interacted_condition_component)
      └ Button (basic_interactable_component + interact_trigger_component)
```

## Settings (@editable)
- `game_sequence_component.FirstNode : ?entity = false` — the node entered first (an entity with `game_node_component`). Empty picks the direct child node with the smallest `Order`.
- `game_sequence_component.StartOnRoundStart : logic = true` — when on, starts at round start and stops at round end. Every sequence with this on starts at the same time.
- `game_sequence_component.StartOnActivate : logic = false` — when on, starts on the activation signal (`activated_event`) and stops on the deactivation signal (`deactivated_event`). The received signal is consumed and not delivered to the parts under the nodes. Placed under a node of another sequence, it becomes a (nested) sequence that runs only during that node.
- `game_sequence_component.StartOnBegin : logic = false` — when on, starts at simulation start (after waiting one frame).
- `game_node_component.Order : int = 0` — the order used to pick the first node when `FirstNode` is empty (0-1000; smaller first).
- `game_transition_component.Target : ?entity = false` — the node to advance to when the conditions are satisfied. Empty ends the sequence here.
- `game_transition_component.Priority : int = 0` — when several transitions of the same node can advance at once, the larger value wins (0-100).

You may turn off all of `StartOnRoundStart`, `StartOnActivate` and `StartOnBegin` and call `Start` from code. With several games (sequences) in the same level, turn off `StartOnRoundStart` and start with that game's start signal (`StartOnActivate`) or `Start`.

Example: "run a minigame sequence only during the lobby node"
```
Sequence (game_sequence_component, StartOnRoundStart)
├ Lobby (game_node_component, Order 0)
│ ├ Minigame sequence (game_sequence_component, StartOnRoundStart off, StartOnActivate on)
│ │ ├ Ready (game_node_component, Order 0) ...
│ │ └ Play (game_node_component, Order 1) ...
│ └ To Playing (game_transition_component, Target = Playing) ...
└ Playing (game_node_component, Order 1) ...
```

## Events
- `game_node_entered_event` (derived from `activated_event`, SendDown): `Node : game_node_component`. Sent downward from the node's entity by `game_node_component` when the node is entered. Parts waiting for activation start on it. Not consumed.
- `game_node_exited_event` (derived from `deactivated_event`, SendDown): `Node : game_node_component`, `Reason : game_node_exit_reason`. Sent downward from the node's entity by `game_node_component` when the node is exited. Parts waiting for activation stop on it. Not consumed.
- `game_sequence_state_changed_event` (scene_event, SendUp): `Sequence : game_sequence_component`, `State : game_sequence_state`. Sent to the root by `game_sequence_component` when its state changes. Receivers: ancestor components (a director outside the sequence, etc.). Not consumed.
- `game_sequence_component.StateChangedEvent : listenable(game_sequence_state)` — fires with the new state every time the state changes.
- `game_node_component.EnteredEvent : listenable(tuple())` — fires when the node is entered.
- `game_node_component.ExitedEvent : listenable(game_node_exit_reason)` — fires with the reason when the node is exited.
- Exit reasons (the `game_node_exit_reason` enum): `Transitioned` (a transition's conditions were satisfied and the flow advanced or ended), `Stopped` (`Stop`, end of round, end of simulation), `Jumped` (moved to another node by `JumpTo` / `Restart`).
- Received: `game_node_component` receives `condition_changed_event` (re-checks the transitions). With `StartOnActivate`, `game_sequence_component` receives and consumes `activated_event` (`Start`) / `deactivated_event` (`Stop`).

## Public API
```verse
game_sequence_state<public> := enum:
    Idle        # not started yet
    Running     # advancing through nodes
    Stopped     # stopped by Stop or the end of the round
    Finished    # advanced to the last transition (empty Target)
    Failed      # stopped because there is no first node, the Target has no node, etc.
(State:game_sequence_state).ToString<public>()<computes>:string

game_sequence_state_changed_event<public> := class(scene_event):
    Sequence<public>:game_sequence_component
    State<public>:game_sequence_state

game_sequence_component<public> := class<final_super>(component):
    FirstNode<public>:?entity
    StartOnRoundStart<public>:logic
    StartOnActivate<public>:logic
    StartOnBegin<public>:logic
    var<private> State<public>:game_sequence_state
    var<private> CurrentNode<public>:?game_node_component
    var<private> LastError<public>:?game_node_error             # the reason of the last Failed. Stays until the next failure
    StateChangedEvent<public><final>:listenable(game_sequence_state)
    Start<public>():void                                        # starts from the first node. Does nothing when running (right after Stop, starts once stopped)
    Stop<public>():void                                         # stops (the node is exited with Stopped)
    Restart<public>():void                                      # starts over from the first node
    JumpTo<public>(Node:game_node_component):void               # moves to Node (the node is exited with Jumped)
    IsRunning<public>()<decides><transacts>:void                # succeeds while State is Running
    FindFirstNode<public>()<decides><transacts>:game_node_component

game_node_exit_reason<public> := enum:
    Transitioned
    Stopped
    Jumped

game_node_entered_event<public> := class(activated_event):
    Node<public>:game_node_component

game_node_exited_event<public> := class(deactivated_event):
    Node<public>:game_node_component
    Reason<public>:game_node_exit_reason

game_node_component<public> := class<final_super>(component):
    Order<public>:int
    EnteredEvent<public><final>:listenable(tuple())
    ExitedEvent<public><final>:listenable(game_node_exit_reason)
    IsActive<public>()<decides><reads>:void                    # succeeds from entering until exiting
    FindReadyTransition<public>()<decides><transacts>:game_transition_component   # among the transitions that can advance now, the one with the largest Priority

game_transition_component<public> := class<final_super>(component):
    Target<public>:?entity
    Priority<public>:int
    IsReady<public>()<decides><transacts>:void                  # succeeds when every direct child condition is satisfied (always, without conditions)
    IsFinish<public>()<decides><transacts>:void                 # succeeds when Target is empty (this transition ends the sequence)

game_node_error<public> := class<computes>:
game_node_not_found_error<public> := class<computes>(game_node_error):
    Target<public>:entity                                       # the target that did not carry game_node_component
game_node_empty_error<public> := class<computes>(game_node_error):
```

## Requirements, caveats and limits
- One frame is left between nodes (so transitions do not keep cycling within the same frame).
- When `Start` / `Restart` / `JumpTo` arrives after `Stop` before it has fully stopped (in the same frame), they are processed in arrival order. The current node is exited with `Stopped`, the state becomes `Stopped`, and then it starts again (`Start` from the first node, `JumpTo` from that Node). In the order `Start` -> `Stop`, it does not start. When the parent sequence re-enters the node holding a `StartOnActivate` sequence (`JumpTo` / `Restart` to the same node), the child sequence receives the deactivation and activation signals back to back, but it does not stay stopped; it starts again from the first node.
- With `FirstNode` set, only the `game_node_component` of that entity is used (fails when it is not attached; the children are not searched). When empty, only the direct children are searched (not the grandchildren).
- With equal `Order` / `Priority` values, which one is picked is unspecified.
- The `Node` of `JumpTo` need not be directly under this sequence.
- When the target entity has no `game_node_component`, the state becomes `Failed` with `game_node_not_found_error`; when the first node is not found, with `game_node_empty_error`; the reason stays in `LastError`. There is no function returning a transition result (the former `GetResult`). Use `IsFinish` to tell whether a transition ends the sequence.
- `StartOnRoundStart` works only when the round manager (`GetFortRoundManager`) is found.
- `game_sequence_component` is never looked up by other parts (not a target of `FindScopedComponent`). It works without a zone (`game_scope_component`), and any number can coexist without conflict. However, every sequence with `StartOnRoundStart` on starts at the same time at round start.
- That consuming the signal with `StartOnActivate` keeps outside signals from reaching the parts under the nodes relies on a consumed `SendDown` not being distributed further down (⚠ Unverified: in UEFN, that a consumed `SendDown` does not reach the descendants).
- The part that spawns a prefab when a node is entered, `spawn_prefab_component`, lives in SpawnSystem's PrefabKit (`using { SpawnSystem.PrefabKit }`. Placed on the node's entity or a descendant, it spawns `SpawnOnActivate` instances on the activation signal and despawns them on the deactivation signal (`DespawnOnDeactivate` is on by default)).
- The code of this System has no `⚠ Unverified` marks and uses no `@experimental` API.

## Verifying
- Test: `game_sequence_system_test_component` in `_Test/GameSequenceSystemTest/`. Just place one entity with this component (the sequence, nodes, transitions and conditions are created by the test at runtime. No player needed). Checks the first node chosen by `Order`, transitions (with two conditions, no advance until both are satisfied), `Finished`, `Restart`, `JumpTo`, `Stop`, exit reasons, a nested `StartOnActivate` sequence, and `Stop` -> `Start` in the same frame (starts again at the first node once stopped; the child sequence when the parent re-enters the same node). About 2 s. The result is `[TEST] GameSequenceSystem` in the output log.
- For the nested sequence, it checks that the sequence under node C starts when C is entered and stops when C is exited. There is no GameSequenceSystem sample in `_Samples/`.

## Rounds
- `StartOnRoundStart` uses `round_watcher` (ActivationSystem) to `Start` at round start and `Stop` at round end. To align parts inside the sequence with rounds, the nodes' activation / deactivation signals can be used as they are. To align with rounds without the game flow, use `activate_on_round_component`.

## Migration notes (2026-11-08)
- FeatureKit is gone. `spawn_prefab_component` moved to `SpawnSystem.PrefabKit` and gained placement, count and despawn features (`Spawn(Count)` / `TrySpawnAt` / `Despawn(Spawned)` / `DespawnAll`, etc. See the SpawnSystem README). `using { GameSequenceSystem.FeatureKit }` → `using { SpawnSystem.PrefabKit }`.
- The ToolTips `SpawnCategory` / `SpawnPrefabToolTip` were removed from GameSequenceSystem.TooltipKit.
- `game_sequence_component.StartOnActivate` was added (off by default, so existing placements keep working).
