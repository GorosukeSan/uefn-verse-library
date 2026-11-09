# MCPSystem

English | [日本語](README.ja.md)

A System that lets MCP (Python running outside the editor) send commands to the **game running in a session** and read the replies. It relies on UEFN **live edit** (changing an `@editable` in the editor reaches the running session in about 0.1 s). It does not drive the screen (no mouse or keyboard input).

- The sender (Python) writes a **list of commands (JSON)** into a string `@editable` on the inbox component → the inbox hands each command to the addressed **toolset** → the reply is `Print`ed → the sender reads it through MCP's `GetVerseOutput`.
- Commands are addressed as "toolset.tool" (the same idea as the toolsets of UEFN's own MCP). Toolsets exist for entities, players, custom characters, screens (UI), game flow, spawning, pickups, movers, countdowns, energy, state snapshot / restore and debugging (13 toolsets, 112 tools). Your own game parts can add their own toolset by implementing the `mcp_controllable` interface.
- UI is **opt-in per screen**: only screens that carry `mcp_widget_control_component` are visible and pressable from MCP. A press reaches `AwaitClick` / `AwaitChoice` exactly like a real click (the author's code does not change).

Verified against **UEFN v43.00** (2026-11-08). MCPSystem version: **1.0.0** (`MCPSystemVersion`; bumped when the contract with the sender changes).

> **Language note:** the tool table below is a manual translation of the table that `gen_tool_docs.py` generates into `README.ja.md` from the Verse sources. Tool names and arguments are identical; the one-line descriptions that `help` / `describe` return at runtime (the `McpTool(...)` doc strings in the `.verse` files) and the header comments of the components are in Japanese.

## Folders and dependencies
| Location | Contents | Depends on |
|---|---|---|
| top level | inbox `mcp_inbox_component` (the Core toolset), interface `mcp_controllable` and tag `mcp_controllable_tag`, command `mcp_call`, reply `mcp_reply`, tool descriptions `mcp_tool` / `mcp_arg`, JSON helpers, names `mcp_name_component`, tag-name table `mcp_tag_entry` / `mcp_tag_provider`, snapshot / restore base `mcp_session_restorable`, `mcp_role_tags` | only the Verse / UnrealEngine / Fortnite standard modules (**no other System**) |
| `EntityKit` | `mcp_entity_toolset_component` ("entity"), `mcp_restore_transform_component` | ActivationSystem |
| `PlayerKit` | `mcp_player_toolset_component` ("player") | PlayerSystem |
| `CharacterKit` | `mcp_character_toolset_component` ("character") | CharacterSystem, PlayerSystem, MovementSystem |
| `WidgetKit` | `mcp_widget_toolset_component` ("widget"), opt-in `mcp_widget_control_component` | WidgetSystem |
| `GameSequenceKit` | `mcp_flow_toolset_component` ("flow") | GameSequenceSystem |
| `SpawnKit` | `mcp_spawn_toolset_component` ("spawn") | SpawnSystem |
| `PickupKit` | `mcp_pickup_toolset_component` ("pickup") | PickupSystem |
| `MoverKit` | `mcp_mover_toolset_component` ("mover") | MoverSystem |
| `CountdownKit` | `mcp_countdown_toolset_component` ("countdown") | CountdownSystem |
| `EnergyKit` | `mcp_energy_toolset_component` ("energy") | EnergySystem, PlayerSystem |
| `SessionKit` | `mcp_session_toolset_component` ("session") | top level only |
| `DebugKit` | `mcp_debug_toolset_component` ("debug") | top level only |
| `TooltipKit` | descriptions shown in the editor | — |

- Dependencies point only "Kit → top level" and "Kit → the target System". The target Systems never depend on MCPSystem (every System works in a project that does not use MCPSystem). You can take only the Kits for the Systems you use (the top level alone gives you the Core toolset and your own receivers).
- The Python sender (`mcp.py`, `mcpsystem\`) lives outside the Library as a separate package (the MCPSystem package). It is kept apart so that no non-`.verse` file ends up in a UEFN project's Content when the Library is distributed (`VerseToolset.Delete` refuses to remove a folder that contains non-`.verse` files).

## Setup (placement)
1. Create one top-level entity (e.g. `MCP_Inbox`) and attach `mcp_inbox_component`. Live edit only ever writes `Inbox` on this component, so Lore locking / saving is limited to this entity's package (when "Save entities as external files" is on).
2. Attach the components of the toolsets you use to the same entity (they are collected by tag, so any entity works).
3. On the entity of each screen (a `player_widget_component` subclass) you want to drive from MCP, attach `mcp_widget_control_component` and choose a `ScreenId` (e.g. `map_select`).
4. Verse cannot read entity names, so attach `mcp_name_component` (`McpName`) to any entity you want to address by name from MCP.
5. To use game-specific tags by name from MCP, implement `mcp_tag_provider` on a game component (see "Adding a toolset for your game" below).
6. Start the session (**components added while a session is running do not reach it**; you need `PushChanges(bVerseOnly=false)` (about 90 s) or a new `StartSession`).

```
MCP_Inbox (top level)
  mcp_inbox_component
  mcp_entity_toolset_component, mcp_player_toolset_component, mcp_character_toolset_component, mcp_widget_toolset_component,
  mcp_flow_toolset_component, mcp_spawn_toolset_component, mcp_pickup_toolset_component, mcp_mover_toolset_component,
  mcp_countdown_toolset_component, mcp_energy_toolset_component, mcp_session_toolset_component, mcp_debug_toolset_component
Lobby (entity of the lobby screen)
  map_select_component (player_widget_component subclass)
  mcp_widget_control_component (ScreenId = map_select)  ← opt-in
```

## Settings (@editable)
- `mcp_inbox_component.Inbox : string = ""` — the command JSON written by MCP. Leave it empty in the editor.
- `mcp_inbox_component.RunInboxAtStart : logic = false` — when on, commands already in the inbox are executed when the inbox starts (round start, reset, Verse reload), so you can start from commands written before the session. When off, the contents at start are ignored (so a rebuilt inbox does not repeat commands it already ran).
- `mcp_inbox_component.MaxPerFrame : int = 50` (1–1000) — commands executed per frame.
- `mcp_inbox_component.MaxLineChars : int = 12000` (2000–15000) — characters per reply line (`GetVerseOutput` truncates a line at 16384 characters).
- `mcp_inbox_component.Quiet : logic = false` — when on, replies are not printed (for the published version).
- `mcp_inbox_component.LogLevel : int = 1` (0–3) — initial verbosity of the inbox log (changeable with `debug.set_level`).
- `mcp_inbox_component.ScreenSeconds : float = 0.0` — seconds to show reply lines on the client screen as well. **0 means log only** (`Print` shows on screen for 2 s by default and gets in the way of play; confirmed in v43.00).
- `InstanceId : string = ""` on every toolset — the name used when the same toolset is placed more than once (the `door_a` in "mover@door_a").
- `mcp_widget_control_component.ScreenId : string = ""` (empty means "screen"), `AllowPress : logic = true`, `AllowShowHide : logic = true`.
- `mcp_name_component.McpName : string = ""`.
- `mcp_session_toolset_component.RestoreOnRoundStart : string = ""` (state restored at every round start; empty does nothing), `RestoreDelaySeconds : float = 1.5`, `MinSeparationCm : float = 120.0`.
- `mcp_restore_transform_component.Key : string = ""`.

## Command and reply format (the contract between sender and receiver)
**What goes into the inbox** (`Inbox`)
```json
{"n": 17, "cmds": [
  {"seq": 1794137895018, "to": "widget", "tool": "press", "args": {"player": 0, "screen": "map_select", "button": "m01"}},
  {"seq": 1794137895019, "to": "mover@door_a", "tool": "play", "args": [12]}
]}
```
- `cmds` holds **only the commands whose reply has not been seen yet**. The sender removes a command once it sees the reply and rewrites the inbox (so writing several times within one frame never loses an earlier command to an overwrite). `n` changes on every write (change the string even when resending the same contents).
- `seq` only increases. The sender starts from the current time in milliseconds (so it never overlaps a previous run). The inbox does not execute a seq at or below the last processed one; instead it re-emits the remembered reply (the last 256), at most once per second and only 1 s after it was first emitted.
- `to` is "toolset" or "toolset@instance". `"*"` means every receiver (tools that are not declared return unknown_tool). `"core"` (or `"inbox"`) is the inbox itself.
- `tool` may also be written `cmd` (compatibility with the prototype). `args` is either named (an object) or positional (an array, in the order of the tool's argument list). It may be omitted.
- Argument types: int / float are JSON numbers or numeric strings; bool is **"true" / "false" / 1 / 0** (Verse's JSON in v43.00 has no `AsBool` and cannot read true / false; the Python sender converts automatically); vector3 is `{"left","up","forward"}`, `{"x","y","z"}` (UE axes: x = forward, y = right = −left, z = up) or `[left, up, forward]`; entity is a number (the `id` returned by `entity.find` etc.; stable within the session) or an `mcp_name_component` name; player is the index from `core.players` (from 0, in the order of the playspace's `GetPlayers`; changes as players join and leave).
- The inbox answers undeclared tools (`unknown_tool`) and missing required arguments (`bad_args missing <name>`) before handing the command to the toolset. Every toolset has `help` (its own description).

**Replies** (lines of `GetVerseOutput`, prefixed `[MCPC]`)
```
[MCPC] {"seq":1794137895018,"ok":true,"to":"widget","tool":"press","hits":1,"reply":"pressed m01","f":224,"t":3433.15}
[MCPC] [{"seq":..,"ok":true,...},{"seq":..,"ok":false,"error":"no_button","reply":"no_button zzz",...}]
[MCPC] ~5:0:6:{"seq":1794138365,"ok":true,"to":"debug","tool":"payload",...
[MCPC] {"event":"move_done","seq":1794137956928,"data":{"ok":true,"reason":"reached",...},"f":2659,"t":3515.6}
[MCPC] {"seq":0,"hello":true,"v":"1.0.0","boot":138243801,"skipped_len":18,"f":0,"t":3777.93}
```
- `ok` / `reply` (human-readable text) / `error` (the error kind when ok=false; the first word of reply) / `data` (structured reply, a JSON value) / `hits` (number of receivers; with 2 or more, `results` holds one result per receiver) / `f` (inbox frame) / `t` (simulation seconds).
- Error kinds: `no_target` (no such destination) / `unknown_tool` / `bad_args` / `no_entity` / `no_player` / `not_shown` / `no_button` / `disabled` / `not_waiting` / `not_in_round` / `failed` / `bad_json` / `bad_command` / `too_large`.
- The replies of one frame are packed into a single array line (`GetVerseOutput` throttles to about 100 lines per second). Up to `MaxLineChars` per line; the rest goes to the next frame.
- A reply that does not fit in one line is split into `~<chunk_id>:<part>:<parts>:<raw JSON fragment>` lines (no escaping; reply JSON contains no newlines). The sender joins the parts in `part` order and calls `json.loads`. Splits never fall inside a UTF-8 character (only before an ASCII character). A reply above 600,000 characters returns `too_large`.
- Long-running tools (`character.move` with seconds, `move_world`, `move_to`, `play`, `debug.frames`, `debug.wait`) reply `reply:"accepted"` immediately and emit an `event` line when done.
- When the inbox starts it emits `hello` (`boot` changes every start). On seeing it, the sender rewrites its pending commands (a rebuilt inbox forgets processed seqs, so a command whose reply was not yet seen may run again → **make every tool idempotent**).
- Python uses `json.loads(line, strict=False)` (only `"`, `\`, newline, tab and carriage return are escaped).

## Toolsets and tools
Auto-generated into `README.ja.md` from the Verse sources (works without a session):
```
python -I <MCPSystem package>\tools\gen_tool_docs.py <Library>\MCPSystem --readme <Library>\MCPSystem\README.ja.md --python <MCPSystem package>\mcpsystem\toolsets_table.py
```
From the inbox of a running session (includes your game's toolsets): `python -I mcp.py describe --markdown` (in the MCPSystem package folder). Declare tools as a single line `McpTool("name", "description", array{McpArg(...), McpOptArg(...)})` so the generator can read them. The table below was translated by hand from the generated one.

| Toolset (destination) | Tool | Arguments | What it does |
|---|---|---|---|
| `core` | `ping` | — | Is the inbox alive (returns pong) |
| `core` | `echo` | text:string? | Returns the arguments (text, or the positional arguments joined with spaces) |
| `core` | `describe` | toolset:string? | List of toolsets and tools with argument descriptions. JSON in data |
| `core` | `list` | — | List of receivers (toolsets). data: [{toolset,id,tools}] |
| `core` | `status` | — | Inbox status (last processed seq, pending, frame, receiver count, log level) |
| `core` | `time` | — | Simulation seconds, UTC Unix time, frame |
| `core` | `round` | — | Whether a round is in progress, and its number |
| `core` | `players` | — | List of players (index, has character, position in cm). The player argument of other tools is this index |
| `core` | `tags` | — | List of named tags (usable in entity.find / player.has_tag etc.) |
| `core` | `batch` | cmds:json | Runs an array of commands in order within the same frame. data: array of replies |
| `character` | `list` | — | Players driving a custom character. data: [{player,pos,velocity,grounded}] |
| `character` | `state` | player:player | Body state (position, velocity cm/s, grounded, state, gravity scale, modifier scale, dashing, side-input style `side_style` (with buffs) / `side_style_base` (walk's base; side_style is omitted without walk), moving floor `ground_velocity` (velocity of the floor being stood on) / `inherited_velocity` (horizontal velocity inherited when leaving the floor; 0 on landing) / `riding` (only when the body has `character_ride_component`; true while being carried)) |
| `character` | `move` | player:player, input:json, seconds:float? | Sets the move input (same as walk's SetMoveInput; forward = ahead, left = left; length up to 1). With seconds, resets to 0 after that time (move_done at the end) |
| `character` | `move_world` | player:player, dir:vector3, seconds:float?, scale:float? | Walks in a world direction (cm direction; length ignored). Converted to input every frame according to walk's Space. Stops after seconds (default 1) (move_done) |
| `character` | `move_to` | player:player, pos:vector3, tolerance:float?, timeout:float? | Walks to a world position (stops when the horizontal distance is at most tolerance; move_done on arrival. If the game moves the body elsewhere, reason = moved_away) |
| `character` | `stop` | player:player, brake:bool? | Zeroes the input and stops move / play (brake = true also zeroes horizontal velocity) |
| `character` | `jump` | player:player | Jumps (failed if it cannot) |
| `character` | `dash` | player:player | Dashes (failed if it cannot) |
| `character` | `teleport` | player:player, pos:vector3, keep_velocity:bool? | Moves the feet to pos (no collision check). With keep_velocity false (default) the velocity is zeroed |
| `character` | `set_velocity` | player:player, velocity:vector3 | Sets the velocity (cm/s, world axes) |
| `character` | `add_velocity` | player:player, delta:vector3 | Adds to the velocity (cm/s) |
| `character` | `set_gravity_scale` | player:player, scale:float | Gravity scale (1 = default, 0 = weightless) |
| `character` | `set_side_style` | player:player, style:string | Changes the side-input style (walk's base; same as `SetSideStyle`). `turn` = turn toward the movement direction, `strafe` = sidestep while facing forward, `tank_turn` = turn in place, `toggle` = same as the toggle button (`SwitchSideStyle`). While a buff (`character_modifier.SideStyle`) decides the style, the buff wins. reply gives the current and base styles |
| `character` | `play` | player:player, motion:json | Plays a motion JSON (play_done at the end). steps: [{t,move,world,jump,dash,teleport,stop}] (input at t seconds) / points: [{pos,jump,dash,wait,teleport}] (walks through them in order) |
| `character` | `record_start` | player:player, interval:float? | Starts recording the motion (position, velocity and grounded every interval seconds, plus events such as jumps and dashes) |
| `character` | `record_stop` | player:player | Stops recording and returns it. data: {interval,samples:[{t,pos,velocity,grounded}],actions:[{t,action}],points:[{pos}]} (points can be passed to play as is) |
| `countdown` | `list` | — | List of countdowns. data: [{id,name,running,paused,remaining,duration}] |
| `countdown` | `state` | countdown:entity | State of one countdown |
| `countdown` | `start` | countdown:entity | Starts it if not counting |
| `countdown` | `restart` | countdown:entity, seconds:float? | Counts again from the start (seconds overrides the duration for this run only) |
| `countdown` | `stop` | countdown:entity | Stops it (no finished notification) |
| `countdown` | `pause` | countdown:entity | Pauses |
| `countdown` | `resume` | countdown:entity | Resumes |
| `countdown` | `add_seconds` | countdown:entity, seconds:float | Adds to the remaining time (negative subtracts) |
| `debug` | `log` | text:string | Writes "[MCP] text" to the log (a marker in the same timeline as the game log) |
| `debug` | `get_level` | — | Inbox log verbosity (0–3) |
| `debug` | `set_level` | level:int | Changes the inbox log verbosity (0 = replies only, 1 = start-up and broken commands, 2 = every command, 3 = verbose) |
| `debug` | `dump` | toolset:string? | Calls every receiver that has an argument-less "state" tool. data: [{to,ok,reply,data}] |
| `debug` | `counts` | — | Number of entities in the world, receivers, and named entities |
| `debug` | `frames` | seconds:float? | Measures the frame count and the seconds per frame (average, max) over seconds (frames at the end) |
| `debug` | `wait` | seconds:float | Waits seconds, then notifies (a sample long-running tool; waited at the end) |
| `debug` | `payload` | chars:int | Returns a string of chars characters in data (to exercise the split-reply mechanism) |
| `energy` | `list` | — | List of energies. data: [{id,name,owner,amount,max,ratio}] (owner is the owning player's index, −1 if none) |
| `energy` | `get` | energy:entity?, player:player? | Amount (either energy or player) |
| `energy` | `set` | energy:entity?, player:player?, amount:float | Sets the amount (clamped to 0–max) |
| `energy` | `restore` | energy:entity?, player:player?, amount:float | Adds (the part above max is discarded) |
| `energy` | `consume` | energy:entity?, player:player?, amount:float | Uses (stops at 0 even if short) |
| `energy` | `spend` | energy:entity?, player:player?, amount:float | Uses only if enough (otherwise failed and nothing changes) |
| `energy` | `fill` | energy:entity?, player:player? | Fills to max |
| `energy` | `set_max` | energy:entity?, player:player?, max:float | Sets the maximum |
| `entity` | `find` | tag:string?, name:string?, root:entity?, limit:int? | Finds entities (by tag, name or root; root alone means all descendants). data: [{id,name,pos}] |
| `entity` | `info` | entity:entity | Entity info (parent, child count, component count, named tags present, position) |
| `entity` | `children` | entity:entity | Direct children. data: [{id,name}] |
| `entity` | `parent` | entity:entity | Parent (the simulation entity's id for a top-level entity) |
| `entity` | `get_transform` | entity:entity, space:string? | Position (cm), rotation (degrees), scale |
| `entity` | `set_transform` | entity:entity, pos:vector3?, rot:json?, scale:vector3?, space:string? | Changes position, rotation and scale (only the ones given) |
| `entity` | `move_by` | entity:entity, delta:vector3 | Offsets the position (world axes, cm) |
| `entity` | `enable` | entity:entity, recursive:bool? | Enables the entity's enableable components (mesh etc.) |
| `entity` | `disable` | entity:entity, recursive:bool? | Disables the entity's enableable components |
| `entity` | `has_tag` | entity:entity, tag:string | Whether the tag is present (reply is true / false) |
| `entity` | `add_tag` | entity:entity, tag:string | Adds a tag (`<concrete>` tags only; removed when this toolset stops) |
| `entity` | `remove_tag` | entity:entity, tag:string, all:bool? | Removes a tag added from MCP (all = true removes every tag of that type) |
| `entity` | `activate` | entity:entity, player:player? | Sends the activation signal (activated_event; with player, activated_by_agent_event) to the entity and its descendants |
| `entity` | `deactivate` | entity:entity | Sends the deactivation signal (deactivated_event) to the entity and its descendants |
| `entity` | `components` | entity:entity | List of components (type names cannot be read, so: index, enabled, and the name if it is an MCP receiver) |
| `entity` | `state` | — | State of this toolset (number of tags added from MCP, number of ids) |
| `flow` | `list` | — | List of sequences. data: [{id,name,state,current,nodes:[{id,name,order,active}]}] |
| `flow` | `state` | sequence:entity? | Sequence state (same as list; with sequence, that one only) |
| `flow` | `start` | sequence:entity? | Starts from the first node (no-op if already running) |
| `flow` | `stop` | sequence:entity? | Stops |
| `flow` | `restart` | sequence:entity? | Restarts from the first node |
| `flow` | `jump` | sequence:entity?, node:entity?, order:int? | Jumps to a node (either node or order) |
| `mover` | `list` | — | List of movers. data: [{id,name,moving,finished,speed,pos,target}] |
| `mover` | `state` | mover:entity | State of one mover |
| `mover` | `play` | mover:entity | Starts moving, or resumes from where it stopped |
| `mover` | `pause` | mover:entity | Pauses in place |
| `mover` | `restart` | mover:entity, return_to_start:bool? | Restarts the path from the beginning |
| `mover` | `set_speed` | mover:entity, speed:float | Speed (cm/s; below 1 becomes 1) |
| `pickup` | `list` | — | List of pickups. data: [{id,name,display_name,available,pos}] |
| `pickup` | `pick` | pickup:entity, player:player | Makes the player pick it up (same as a real pickup: grants the effect and hides it) |
| `pickup` | `grant` | pickup:entity, player:player | Grants only the pickup's effect (the pickup stays) |
| `pickup` | `restore` | pickup:entity | Restores it (can be picked up again) |
| `pickup` | `hide` | pickup:entity | Hides it (cannot be picked up) |
| `pickup` | `effects` | player:player | Effects the player currently has. data: [{id,effect_id,remaining}] |
| `pickup` | `end_effects` | player:player | Ends all of the player's effects |
| `player` | `list` | — | List of players. data: [{index,has_character,pos,tags,groups}] (tags = the named tags present, groups = ids of the groups joined) |
| `player` | `get_position` | player:player | Position (cm), facing and velocity (cm/s) of the Fortnite character |
| `player` | `teleport` | player:player, pos:vector3, yaw:float? | Moves the Fortnite character (writes the body entity's transform) |
| `player` | `has_tag` | player:player, tag:string | Whether the agent has the tag (reply is true / false) |
| `player` | `add_tag` | player:player, tag:string | Adds a tag to the agent (`<concrete>` tags only; removed when this toolset stops) |
| `player` | `remove_tag` | player:player, tag:string, all:bool? | Removes a tag added from MCP (all = true removes every tag of that type) |
| `player` | `groups` | — | List of groups (player_group_component). data: [{id,name,members}] |
| `player` | `join_group` | player:player, group:entity | Joins the group (player_group_component.Join; also leaves sibling groups if so configured) |
| `player` | `leave_group` | player:player, group:entity | Leaves the group |
| `player` | `state` | — | Number of players and of tags added from MCP |
| `session` | `keys` | — | List of keys of the parts that can be snapshotted |
| `session` | `snapshot` | keys:string[]? | Snapshots the state. data: {v,t,players,items:{key:JSON}} |
| `session` | `restore` | state:json, keys:string[]? | Restores the state (pass the data of snapshot as is). reply gives the result per key |
| `spawn` | `list` | — | List of spawners. data: [{id,name,kind,count,max,running,pos}] (kind is prefab or spawner) |
| `spawn` | `spawn` | spawner:entity, count:int? | Spawns count instances at the places decided by spawn_prefab_component. data: [{id}] of the spawned entities |
| `spawn` | `spawn_at` | spawner:entity, pos:vector3, yaw:float? | Spawns one instance at an arbitrary position with spawn_prefab_component |
| `spawn` | `despawn` | spawner:entity, entity:entity | Removes one entity the spawner spawned |
| `spawn` | `despawn_all` | spawner:entity | Removes everything the spawner spawned |
| `spawn` | `start` | spawner:entity | Starts the spawner_component |
| `spawn` | `stop` | spawner:entity | Stops the spawner_component (spawned instances disappear) |
| `spawn` | `refill` | spawner:entity | Refills the spawner_component once, right now |
| `spawn` | `spawned` | spawner:entity | What the spawner currently has out. data: [{id,pos}] |
| `widget` | `list` | — | List of opted-in screens (whether shown or not). data: [{screen,entity,widgets:[{widget,mode,audience,shown_to}]}] |
| `widget` | `screens` | player:player? | Screens currently shown and the buttons waiting. data: [{player,screen,widget,mode,buttons:[{id,index,label,enabled}]}] |
| `widget` | `press` | player:player, screen:string, button:string, widget:int? | Presses a button (by id, label or index; reaches AwaitClick / AwaitChoice like a real click) |
| `widget` | `show` | player:player, screen:string, widget:int? | Shows the screen (ShowFor) |
| `widget` | `close` | player:player, screen:string, widget:int? | Closes the screen (HideFor) |
| `widget` | `state` | — | Number of opted-in screens and of screens currently shown |

## The Python sender (the MCPSystem package, outside the Library)
```python
import sys; sys.path.insert(0, r"<MCPSystem package folder>")
from mcpsystem import connect
mcp = connect()                                            # finds the inbox (mcp_inbox_component on the top-level MCP_Inbox)
mcp.core.ping()                                            # "pong"
screens = mcp.widget.screens()                             # [{"player":0,"screen":"map_select","buttons":[{"id":"m01","label":"Stage 1",...}]}]
mcp.widget.press(0, "map_select", "Stage 1")                # id, label or index
goal = mcp.entity.find(tag="goal_tag")[0]["pos"]
mcp.character.move_to(player=0, pos=goal, wait=True)      # waits for the completion event (move_done)
snap = mcp.session.snapshot(); mcp.session.restore(state=snap)
replies = mcp.channel.batch([("debug", "log", {"text": str(i)}) for i in range(300)])   # batched send
```
CLI: `python -I mcp.py core.ping`, `python -I mcp.py widget.press "[0,\"map_select\",\"m01\"]"`, `python -I mcp.py character.move_to "{\"player\":0,\"pos\":[0,100,500]}" --wait`, `python -I mcp.py describe --markdown`, `python -I mcp.py tools` (list without a session). Tests: `python -I tests\test_channel.py` (fake inbox; no UEFN needed). See the README of the MCPSystem package for details.

## Use cases
- **Automated tests**: start a session, press screen buttons (`widget.press`), drive the custom character (`character.play` / `move_to`) and wait for a game log line (such as `[my_game] cleared`) to decide the result. The author's game runs lobby → map select → clear → results → lobby with a script written this way.
- **Start from a saved state**: save the state you are working on as JSON with `session.snapshot` and write it into `mcp_session_toolset_component.RestoreOnRoundStart` before the next session (repeat trials under the same conditions). During a session just send `session.restore` (no PushChanges or reset needed).
- **Tuning values**: try `entity.set_transform` / `mover.set_speed` / `countdown.add_seconds` and so on without stopping the session.
- **Record and replay motion**: `character.record_start` → a human plays → pass the `points` of `record_stop` straight to `character.play`.
- **Log markers**: put markers such as "[MCP] measurement starts here" into the same timeline as the game log with `debug.log`.
- **Adding a toolset for your game**: implement `mcp_controllable` on a game component and add `mcp_controllable_tag` to its entity in `OnBeginSimulation` (`mcp_role_tags` makes sure you do not forget to remove it).
```verse
my_game_mcp_component := class<final_super>(component, mcp_controllable, mcp_tag_provider):
    RoleTags<private>:mcp_role_tags = mcp_role_tags{}
    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        RoleTags.Add(Entity, mcp_controllable_tag{})
    OnEndSimulation<override>():void =
        RoleTags.RemoveAll()
        (super:)OnEndSimulation()
    McpToolset<override>()<transacts>:string = "mygame"
    McpId<override>()<transacts>:string = ""
    McpTagEntries<override>()<transacts>:[]mcp_tag_entry = array{McpFindOnlyTagEntry("my_goal_tag", my_goal_tag)}
    McpTools<override>()<transacts>:[]mcp_tool =
        array{McpTool("restart", "Restart the game", array{McpOptArg("player", "player", "index")})}
    McpHandle<override>(Call:mcp_call):mcp_reply =
        if (Call.Tool = "restart"):
            # read arguments with the <decides> helpers Call.FindPlayer[] / FindInt[] etc. (they fail on out-of-range or broken values instead of raising a runtime error)
            McpOk("restarted")
        else:
            McpFail("unknown_tool", Call.Tool)
```
The author's game has one game-specific toolset in this form (state / maps, and the names of the game's tags).

## Events and tags
- Tags: `mcp_controllable_tag` (entities of receivers and of tag-name providers), `mcp_name_tag` (`mcp_name_component`), `mcp_session_restorable_tag` (parts that can be snapshotted), `mcp_widget_control_tag` (screen opt-in). Each part adds and removes its own tag (MCP cannot write tags). All are `<concrete>` (so they can be added from MCP with `entity.add_tag`).
- No scene_event or listenable (commands are the live-edited string, replies are Print).

## Public API (top level; for the Kit components see the table above and the header comment of each file)
```verse
MCPSystemVersion<public>:string = "1.0.0"
mcp_controllable_tag<public> := class<concrete>(tag)
mcp_controllable<public> := interface:
    McpToolset<public>()<transacts>:string
    McpId<public>()<transacts>:string
    McpTools<public>()<transacts>:[]mcp_tool
    McpHandle<public>(Call:mcp_call):mcp_reply
mcp_arg<public> := struct{Name, Type, Doc:string; Required:logic}
mcp_tool<public> := struct{Name, Doc:string; Args:[]mcp_arg}
McpArg / McpOptArg(Name, Type, Doc)<transacts>:mcp_arg ; McpTool(Name, Doc, Args)<transacts>:mcp_tool ; (Tool:mcp_tool).ToJson()
FindMcpTool<public>(Tools:[]mcp_tool, Name:string)<transacts><decides>:mcp_tool
mcp_reply<public> := struct{Ok:logic; Text:string; Data:string}
McpOk(Text) / McpOkData(Text, Data) / McpFail(Code, Detail) / McpBadArg(Name)
mcp_call<public> := class<internal>:                       # created by the inbox
    Seq, Toolset, Id, Tool, Inbox
    FindArg / HasArg / FindString / FindInt / FindFloat / FindLogic / FindVector / FindObject / FindArray / FindEntity / FindPlayer / FindAgent  # <decides>
    GetStringOr / GetIntOr / GetFloatOr / GetLogicOr
    Notify(EventName:string, Data:string)                  # completion event of a long-running tool
mcp_inbox_component<public> := class<final_super>(component):
    Inbox, RunInboxAtStart, MaxPerFrame, MaxLineChars, Quiet, LogLevel, ScreenSeconds
    ExecuteJson(CommandJson:string):string                 # executes one command right away and returns the reply JSON (no Print; for game code and tests)
    GetHandle(Target:entity):int ; FindHandleEntity(Handle:int)<decides>:entity ; FindNamed(Name:string):[]entity ; ResolveEntity(V:value)<decides>:entity
    GetTagEntries():[]mcp_tag_entry ; FindTagEntry(Name:string)<decides>:mcp_tag_entry ; GetControllables():[]mcp_controllable
    Notify(EventName, Seq, Data) ; Log(Level, Text) ; GetLogLevel() / SetLogLevel(Level) ; IsInRound()<decides> ; GetRoundNumber() ; GetFrame()
mcp_name_component<public> := class<final_super>(component): McpName:string
(InEntity:entity).GetMcpName()<reads>:string ; (InEntity:entity).GetMcpKey()<transacts>:string ; McpPositionKey(Position:vector3):string
mcp_tag_entry<public> := class<final>{Name:string; TagType:castable_subtype(tag); Concrete:?castable_concrete_subtype(tag)}
McpTagEntry(Name, TagType:castable_concrete_subtype(tag)) ; McpFindOnlyTagEntry(Name, TagType:castable_subtype(tag)) ; (Entry:mcp_tag_entry).MakeTag()<decides>:tag
mcp_tag_provider<public> := interface: McpTagEntries()<transacts>:[]mcp_tag_entry
mcp_session_restorable_tag<public> := class<concrete>(tag)
mcp_session_restorable<public> := interface:
    McpSessionKey()<transacts>:string ; McpSessionSave(Context:mcp_session_context):string ; McpSessionRestore(Context:mcp_session_context, State:value):string
mcp_session_context<public> := class<internal>: Players:[]player ; MinSeparationCm:float ; ClaimPosition(Desired:vector3):vector3 ; FindPlayer(Index:int)<decides>:player
MakeMcpSessionContext(Players:[]player, MinSeparationCm:float):mcp_session_context
mcp_role_tags<public> := class: Add(Target, Tag) ; Remove(Target, TagType)<decides> ; RemoveAll() ; GetCount()
# JSON helpers
McpEscape / McpQuote / McpNumber (null unless finite) / McpInteger / McpLogic / McpVector / McpRotation / McpField / McpObject / McpArray / McpStringArray / McpJoin / McpJoinTree
McpParseInt / McpParseFloat / McpDigit / McpFloatToInt (up to ±9.0e15) / McpFindChar / McpSlice           # the ones that can fail are <decides>
McpValueToString / McpValueToInt / McpValueToFloat / McpValueToLogic / McpValueToVector                      # from a JSON value; <decides>
(InEntity:entity).McpGetPlayers():[]player ; (InEntity:entity).McpGetPlayerIndex(Agent:agent):int
McpReadCommand(V:value)<decides>:mcp_command ; McpToolsetJson(Controllable):string
```

## Requirements, caveats and limits
- **Does nothing without live edit (on a published island)**: `Inbox` keeps its cooked value and never changes. Turn `Quiet` on in the published version (keeps the log clean).
- **Components and entities added to a running session do not reach it** (`PushChanges(bVerseOnly=false)`, about 90 s, or StartSession is needed). Changing an `@editable`, `SetEntityTransform` and removing an existing component do reach it.
- **The receiver must never stop on a runtime error**: every conversion that can fail is `<decides>` (`McpFloatToInt` up to ±9.0e15, vectors and floats up to ±1.0e15, `McpParseInt` up to 18 digits). `Floor[]` / `Int[]` on a large float raises a runtime error (`ErrRuntime_IntegerBoundsExceeded`) rather than failing and stops the whole `OnSimulate`, so check ranges inside your tools as well.
- **Rebuilds**: when the inbox is rebuilt at round start or by `PushChanges`, it forgets the processed seqs. A command whose reply was not yet seen before the rebuild may run twice (make tools idempotent). Entity ids (`id`) also change on a rebuild.
- Use a single sender per inbox (two senders writing at the same time overwrite each other's commands).
- Concatenating a string one character at a time with `+=` is O(n²) for long strings (seconds for 100,000 characters). The standard `Concatenate` recurses internally and hits a **runtime error (`ErrRuntime_InfiniteLoop`)** with 100,000 fragments, which stops the inbox (v43.00). Build replies with `McpJoin` / `McpJoinTree` (pairwise). Too much computation in one frame raises the same runtime error, so one reply is limited to 600,000 characters (`too_large` above that) and `debug.payload` to 300,000.
- A Verse runtime error shows the "An unrecoverable Verse runtime error occurred!" dialog in the editor, and MCP does not respond (times out) until it is closed. The inbox's `OnSimulate` stops as well, so fix the code and reload with `PushChanges`.
- Verse cannot read entity names or component type names (as of v43.00). `entity.components` returns only the index, enabled flag and whether it is an MCP receiver. Give names with `mcp_name_component`.
- Only tag names announced through the table (`mcp_tag_provider`) can be used. Adding and removing (`add_tag`) works only for `<concrete>` tags (Verse cannot construct a tag of a non-concrete type). Announce game tags with `McpFindOnlyTagEntry` (find / check only).
- Screens are shown only inside a round (a WidgetSystem rule). Outside a round `widget.screens` is empty, `press` returns `not_shown` and `show` returns `not_in_round`.
- `character`'s `move_world` / `move_to` / `play` convert world directions to input according to walk's current walking basis (`GetWalkBasis`: `Space` and the side-input style) (`View` is the Fortnite character's view direction; `TankTurn` treats the body's facing as forward and turns before moving sideways). If the game moves the body elsewhere (800 cm or more in one frame), walking stops (`moved_away`). CharacterSystem has no step-up handling.
- Snapshot / restore in multiplayer: players are matched by "index in that run" (if fewer players than saved, the extras are dropped; if more, the missing ones are left as they are). Restored positions closer than `MinSeparationCm` to each other are shifted left (no collision sweep). Movers (MoverSystem) are not included because there is no API to put them back at an intermediate position. Runtime-created things (spawned prefabs) are not included.
- ⚠ Unverified: indices in multiplayer (2 or more players), per-player `widget` presses, overlapping restores (`ClaimPosition` was checked only in tests). Tools not yet exercised in the editor: `spawn` spawn / despawn, `flow` jump, `countdown` / `energy` writes (the game used for verification has no such parts), `pickup.pick` / `grant`, `entity.enable` / `disable` / `add_tag` / `remove_tag` / `activate` / `deactivate`, `player.teleport` / `join_group` / `leave_group` / `add_tag`. Exercised in the editor: reads (list / state / find / info / get_transform / components / has_tag / screens etc.), `widget.press` / `close` / `show`, `character.teleport` / `move_world` / `move_to` / `jump` / `play` (points) / `record_start` / `record_stop`, `session.snapshot` / `restore`, `entity.move_by` / `set_transform`, `mover.pause` / `play` / `set_speed`, `pickup.hide` / `restore`, all of `debug`. The cast by type in `mcp_role_tags.Remove` (`TagType[Tag]`) passed in tests.
- An earlier record said "`@editable` values do not arrive" (around 2026-11-01 on v43.00). The condition under which they do not arrive is unconfirmed.

## Measurements (UEFN v43.00, 2026-11-08, test project, 1 player, session on Epic's servers)
| Item | Result |
|---|---|
| One at a time (`core.ping`, round trip) | 0.111–0.118 s on average (0.084–0.153), about 8–9 per second |
| Batched (`core.echo`, `batch`) | 30 in 0.20 s, 100 in 0.38 s, 300 in 1.08 s, 1000 in 4.2 s (0 errors). Slower than the prototype (30 in 0.2, 300 in 0.55, 1000 in 2.8 s), presumably because each reply is longer (to / tool / hits / f / t) and arguments are checked against the tool descriptions |
| Large replies (`debug.payload`; what does not fit a line is split into `~` lines) | 10,000 characters 0.18 s, 30,000 0.77 s, 100,000 3.7 s (the one-character `+=` version: 100,000 in 9.0 s; the `Concatenate` version: runtime error at 100,000) |
| `core.describe` (14 toolsets, 114 tools, about 21,000 characters) | 0.8–3.3 s |
| `widget.press` (a button) → the start line appears in the game log | 0.16–0.17 s (3 runs) |
| Other tools (reads in entity / player / character / widget / pickup / mover / session / debug) | 0.11–0.16 s |
| Server frames (`debug.frames`) | 30 frames per second (0.0334 s per frame) |
| `session.snapshot` / `restore` (characters, pickups, countdowns, energies) | 0.13 s / 0.11 s. The custom character's position returned to the saved value |
| `PushChanges(bVerseOnly=false)` (Verse and component changes into the running session) | 91–109 s |

## Verifying
- Type check: verse-standalone's `verse_check.py <Library> --profile fortnite --runtime runtime-uefn43` (0 apart from the known false positives).
- Tests: place one `mcp_system_test_component` from `_Test/MCPSystemTest/` on an entity and start (no player needed, 1 s). It checks the JSON helpers (escaping, number parsing, range checks), dispatch through `ExecuteJson` (Core, destinations, instances, multiple receivers, tool existence, required arguments, positional arguments, data checks, batch, help, describe), the tag-name table, `mcp_role_tags` and `ClaimPosition`. Results appear as `[TEST] MCPSystem` (44 passed, 0 failed on v43.00).
- The live-edit path: `python -I mcp.py core.ping` during a session. Python tests: `python -I tests\test_channel.py` (fake inbox; no UEFN needed; both in the MCPSystem package folder).

## Migration notes (2026-11-08)
- New System (no change needed for existing users).
- Added to WidgetSystem (compatible): `widget_view.AwaitClick(OnClick, ?ButtonId:string = "", ?Label:string = "")`, `AwaitChoice(Buttons, ?ButtonIds:[]string = array{})`, `GetWaitingButtons():[]widget_button_info`, `PressButton(Key:string):widget_press_result`, `widget_press_result`, `widget_button_info` (see "Migration" in WidgetSystem's README).
- From the prototype (before it entered the Library): `McpName()` → `McpToolset()` / `McpId()`, `McpHandle(Cmd:string, Args:[]string)` → `McpHandle(Call:mcp_call)` (arguments via `Call.Find*`), `McpDescribe():string` → `McpTools():[]mcp_tool`, `Data` added to the reply `mcp_reply{Ok, Text}`, command key `cmd` became `tool` (`cmd` still accepted), destination `inbox` became `core` (`inbox` still accepted).
