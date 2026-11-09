# ModeSystem

A System that holds the candidate game modes (ways to play) and picks one of them. The selected mode is announced to the whole scope and can also be used as a transition condition in the game flow (GameSequenceSystem). Add VoteKit to decide by majority vote.

## Placement

| component | Where to place | What it does |
|---|---|---|
| `mode_select_component` | one per scope (or world), where the activation signal arrives (in a game sequence, the node's entity or a descendant) | holds the child modes, remembers the mode decided by `TrySelect` while accepting, and announces it to the whole scope |
| `game_mode_component` | directly under the `mode_select_component` entity, one per mode | represents one mode (`Title` is the name shown on screen, `Order` is the position among the candidates) |
| `mode_vote_component` (VoteKit) | the same entity as `mode_select_component` | collects the players' votes and has `mode_select_component` decide the mode by majority |
| `mode_selected_condition_component` (ConditionKit) | directly under the entity of a `game_transition_component` or `condition_all` / `condition_any` | satisfied when the mode on the `Mode` entity is selected |

Example: "pick a mode by vote, then go to that mode's node"
```
Sequence (game_sequence_component)
├ Vote (game_node_component)
│ ├ Mode select (mode_select_component + mode_vote_component)
│ │ ├ Tag (game_mode_component, Order 0)
│ │ └ Treasure hunt (game_mode_component, Order 1)
│ ├ To tag (game_transition_component, Target = the tag node)
│ │ └ mode_selected_condition_component (Mode = Tag)
│ └ To treasure hunt (game_transition_component, Target = the treasure hunt node)
│   └ mode_selected_condition_component (Mode = Treasure hunt)
├ Tag node (game_node_component)
└ Treasure hunt node (game_node_component)
```
In this layout, leaving the node sends the deactivation signal, which ends accepting and clears the selection. If the next node still needs the selected mode, place `mode_select_component` outside the node and control the accepting period with `ActiveOnBegin` or `Activate` / `Deactivate` from code. The vote buttons and screens are parts you provide that call `TryVote`.

## Settings (@editable)
- `game_mode_component.Title : string = "Mode"` — the mode name shown on screen.
- `game_mode_component.Order : int = 0` — position among the candidates (0–1000, smaller comes first). On a tied vote the smaller one wins.
- `mode_select_component.ActiveOnBegin : logic = false` — when on, accepts from the start of the simulation. When off, from the activation signal.
- `mode_select_component.AllowReselect : logic = false` — when on, `TrySelect` can change the mode after it is decided. When off, the first decided mode stays (later `TrySelect` calls do nothing until cleared).
- `mode_selected_condition_component.Mode : ?entity = false` — satisfied when this mode (an entity with `game_mode_component`) is selected. Never satisfied when empty.
- `mode_vote_component.MajorityEnds : logic = false` — when on, decides as soon as a majority voted for the same mode. When off, waits until everyone voted.

## Events
- `mode_changed_event` (scene_event, SendScoped: the whole scope, or the whole world without a scope): `Selector : mode_select_component`, `Mode : ?game_mode_component` (false when cleared). Sent by `mode_select_component` when a mode is decided, changed or cleared. Receivers are `mode_selected_condition_component`, screens that show the mode, etc. Not consumed.
- `mode_vote_changed_event` (scene_event, SendScoped): `Vote : mode_vote_component`, `Agent : ?agent` (false when all votes were cleared), `Mode : ?game_mode_component` (false when the vote was withdrawn). Sent by `mode_vote_component` when someone's vote changes or all votes are cleared. Receivers are screens that show vote counts, etc. Not consumed.
- listenable (cannot be signaled from outside)
  - `mode_select_component.SelectedEvent : listenable(?game_mode_component)` — when decided or changed (`option{Mode}`) and when the selection is cleared (false).
  - `mode_vote_component.VoteChangedEvent : listenable(tuple(agent, ?game_mode_component))` — each time someone votes or withdraws: (the player, the mode they now vote for; false when withdrawn).
  - `mode_vote_component.VotesClearedEvent : listenable(tuple())` — when all votes are cleared at once (`VoteChangedEvent` does not fire then).
- Received: `mode_select_component` takes `activated_event` (start accepting) and `deactivated_event` (stop accepting and clear the selection). `mode_selected_condition_component` takes `mode_changed_event`. `mode_vote_component` receives no scene_event; it subscribes to `SelectedEvent` on the same entity and to `player_manager_component.PlayerRemovedEvent`.

## Public API
```verse
game_mode_component<public> := class<final_super>(component):
    Title<public>:string
    Order<public>:int

mode_changed_event<public> := class(scene_event):
    Selector<public>:mode_select_component
    Mode<public>:?game_mode_component

mode_select_component<public> := class<final_super>(component):
    ActiveOnBegin<public>:logic
    AllowReselect<public>:logic
    var<private> Selected<public>:?game_mode_component = false
    SelectedEvent<public><final>:listenable(?game_mode_component)
    Activate<public>():void                                     # starts accepting
    Deactivate<public>():void                                   # stops accepting and clears the selection
    IsActive<public>()<decides><transacts>:void
    FindSelected<public>()<decides><transacts>:game_mode_component
    IsSelected<public>(Mode:game_mode_component)<decides><transacts>:void
    GetModes<public>()<transacts>:[]game_mode_component         # direct children by ascending Order (grandchildren ignored)
    TrySelect<public>(Mode:game_mode_component):logic           # true if it took effect
    Clear<public>():void                                        # clears the selection

# ConditionKit
mode_selected_condition_component<public> := class<final_super>(condition_component):
    Mode<public>:?entity

# VoteKit
mode_vote_changed_event<public> := class(scene_event):
    Vote<public>:mode_vote_component
    Agent<public>:?agent
    Mode<public>:?game_mode_component

mode_vote_component<public> := class<final_super>(component):
    MajorityEnds<public>:logic
    VoteChangedEvent<public><final>:listenable(tuple(agent, ?game_mode_component))
    VotesClearedEvent<public><final>:listenable(tuple())
    TryVote<public>(Agent:agent, Mode:game_mode_component):logic   # true if it took effect. A vote can be changed
    Unvote<public>(Agent:agent):void                               # does nothing if the agent has not voted
    GetVoteCount<public>(Mode:game_mode_component)<transacts>:int  # votes of players who left are not counted
    FindVote<public>(Agent:agent)<decides><transacts>:game_mode_component
```

## Requirements, caveats and limits
- There is one `mode_select_component` per scope (or world). `mode_selected_condition_component` and screens find it with `FindScopedComponent` (the condition looks it up at start and when a notification arrives, and remembers it).
- `TrySelect` does nothing and returns false when not accepting, when already decided and `AllowReselect` is off, or when the same mode is already selected. It does not check that the mode passed to `TrySelect` is one of its children.
- When accepting ends (deactivation signal, `Deactivate`, end of the simulation) the selection is cleared and, if a mode was decided, `mode_changed_event{Mode := false}` is sent.
- `mode_vote_component` needs one `player_manager_component` in the scope (or the world) (looked up and remembered at start). Once every player in the scope has voted (or, with `MajorityEnds`, as soon as a majority voted for the same mode), it calls `TrySelect` with the mode that has the most votes. On a tie the mode with the smaller `Order` wins. No votes are accepted after the decision. Votes are cleared when accepting ends or on `Clear`. The vote of a player who leaves is withdrawn and the decision is re-checked with the remaining players.
- `TryVote` returns false when there is no `mode_select_component` on the same entity, when it is not accepting, when a mode is already decided, or when `Mode` is not one of its direct child modes.
- No experimental API is used.

## Verifying
- Test: `mode_system_test_component` in `_Test/ModeSystemTest/`. Place one entity with this component (`mode_select_component` and `mode_vote_component` are created by the test at run time). Do not place another `mode_select_component` in the scope (or world). The vote test needs `player_manager_component` and 1 player (without them the vote test is skipped and only a vote count of 0 is checked). It checks the candidate order by `Order`, accepting (`Activate` / `Deactivate`), how `TrySelect` decides (the first mode stays when `AllowReselect` is off), `Clear`, `SelectedEvent` and `mode_changed_event`, `mode_selected_condition_component`, and voting (decided once everyone voted, votes cleared when accepting ends). It finishes on the frame after start. Results go to the output log as `[TEST] ModeSystem`.
- There is no sample (`_Samples/`).
