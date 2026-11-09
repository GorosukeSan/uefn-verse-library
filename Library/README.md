# Library — a UEFN Scene Graph component library

Parts built with Scene Graph (entity / component) that you combine. Targets UEFN v43.00 and later.

## Folders and modules
- `<Name>System/` ... one mechanism (e.g. `CountdownSystem`). The central component and its events live at the top of the folder.
- `<Name>System/<Name>Kit/` ... swappable parts of that mechanism (e.g. `ConditionKit`). Kits are made `<public>` in `<Name>SystemKits.verse` (folder modules are internal by default).
- `<Name>System/TooltipKit/` ... descriptions shown in the editor (`message`).
- `<Name>System/README.md` ... how to use that System (overview / placement / settings / events / tags / public API / requirements and caveats / verifying).
- `_Test/<Name>SystemTest/` ... tests that check the behavior (a folder named the same as a System would clash with its module name) (`_Test/README.md`).
- `<Name>ExperimentalKit/` (under a System or under `_Samples`) ... a folder holding only code that uses `@experimental` APIs. Code outside a folder whose name ends in `ExperimentalKit` uses neither experimental APIs nor the types inside such a folder. VerseShare distributes this folder only to projects with "include experimental" turned on (projects with it off are not touched whether or not the folder exists).
- A new System adds `<Name>System<public> := module {}` to `LibraryModules.verse`.

## List of Systems
| System | What it does |
|---|---|
| SceneGraphSystem | scopes (`game_scope_component`), finding one thing in the scope / finding and remembering it (`ResolveScopedComponent` / `AwaitScopedComponent`) / sending, finding from the nearest ancestor (`FindNearestAncestorComponent`), cancelable, map helpers |
| ActivationSystem | activation / deactivation signals (including `activated_by_agent_event`, which tells who triggered it), activate on begin, enable / disable on the signal |
| ConditionSystem | condition base, all / any, satisfied by a received scene_event (EventKit's `event_received_condition_component`) |
| PlayerSystem | participant slots, per-player views, tags, owner (`FindOwningPlayer`), body (`possessable_component`), things attached to a player, reactions to Fortnite character motion (MotionKit), conditions on the player count / group count (ConditionKit's `player_count_condition_component` / `player_group_count_condition_component`) |
| LoadoutSystem | creates and attaches one player's worth of parts (a prefab) per player. The parts inside affect only the owner |
| PickupSystem | pickups (orbs) and the effects attached to whoever picks them up (an effect prefab = the `pickup_effect_component` base + parts driven by the activation signal; lifetime, stacking, owner), signals to stages (StageKit), a HUD on the owner's screen that shows pickup notifications and the list of ongoing effects (HudKit; the look comes from the `card_info_component` at the root of the effect prefab) |
| CharacterSystem | custom characters (own physics, capsule sweeps, input_action controls) with movement / reaction / condition parts, parts for touching surfaces and riding moving platforms (SurfaceKit), buffs and ability grants (BuffKit; `AddModifier` stacks multipliers, air jumps and dash permission on the body) |
| InputSystem | input helpers (`AwaitPlayerInput`, etc.), input parts, ready-up |
| WidgetSystem | per-player screens (HUD, menus), text, gauges, notifications, choice menus, hiding the standard HUD |
| VolumeSystem | players entering / leaving a volume, player-count conditions, activation parts |
| InteractSystem | things you press to use, connected to activation and conditions |
| GameSequenceSystem / ModeSystem / CountdownSystem / ScheduleSystem | game flow, mode selection, countdowns, real-time schedules |
| AbilitySystem / EnergySystem / ItemSystem | abilities and how they are granted, energy, items |
| HoverSystem / JetpackSystem / SwingSystem / GravitySystem / MovementSystem | movement abilities and helpers for Fortnite characters |
| CheckpointSystem / SpawnSystem / GridSystem / MoverSystem | platforms (including EnergyKit's `checkpoint_energy_refill_component`, which refills energy when stepped on), automatic spawning and removal (`spawner_component`, which keeps spawning in a band; PrefabKit's `spawn_prefab_component` and the `SpawnPrefab` function, which spawn any number at chosen places), grid reservations, movers |
| MCPSystem | lets MCP (Python outside the editor) send commands to the game running in a session through live edit and read the replies (inbox, toolset interface, Core; toolsets for the other Systems are Kits; UI is opt-in per screen) |
| FNDeviceSystem | processing that relies on Creative devices (device bridges, game end, classes, score, cinematics, audio). The other Systems do not depend on devices |

## Design rules

### 1. Compose by attaching and removing components instead of inheriting
- Components are normally concrete `class<final_super>(component)`. Settings are `@editable`.
- Separate "what it does" from "when, to whom, in which situation" into different components. Example: an ability (`AbilitySystem`) is an `ability_component` subclass that holds only its contents; how it is granted is chosen by `ability_grant_players` / `ability_grant_item` / `ability_grant_condition` on the same entity. The contents component knows nothing about how it is granted.
- Inheritance is allowed only to "have exactly one piece of content written" (one step: abstract base → concrete). Never build chains like abstract → abstract → concrete. Avoid writing the flow in the base and having subclasses fill many holes (protected hooks); use event subscriptions or another component on the same entity instead.
- Do not use the "implement an interface to receive" (listener) form. Pass a callback (function) or a `listenable`.
- For per-player processing, the component holds a `player_view_set` (PlayerSystem) and creates views of ordinary components under the slot (no base class inheritance).
- Parts placed under a player's slot (inside a LoadoutSystem loadout, etc.) "have an owner". Parts for which `Entity.FindOwningPlayer[]` succeeds affect only the owner, not everyone (ability grants, widgets, attached things, items, the standard HUD, custom characters). New parts follow the same rule.

### 2. Public events have the same shape as Epic's standard components
- State changes are `XxxEventInternal<private><final>:event(t)` + `XxxEvent<public><final>:listenable(t) = MakeProxyListenable(XxxEventInternal)`. They cannot be signaled from outside.
- For delivery within the entity tree, also send `scene_event` subclasses. Names: something happened = past tense (`*_reached_event`), a change = `*_changed_event`, a request = `*_request_event`. Fields carry the sender (component or entity), and a player is held as `Agent:agent`. Above the type, write "direction, sender, receivers, whether it is consumed".
- Sender field name: the sending component, as its concrete type, placed first among the fields and named by its role (the noun from the type name without `_component` and the System prefix: `player_group_component` → `Group`, `countdown_component` → `Countdown`). Events sent from an ability (`*_ability_component`) use `Ability`. When the role name clashes with another field, use the whole type name without `_component` (`player_ready_component` → `PlayerReady`, because it clashes with `Ready:logic`). Only when the sender can be of various types (`component` / `entity` type) use `Sender` (entity only when the sender is not a component). Never use `Source`. The player (`Agent:agent`, or `?agent` when there may be none) comes right after the sender. The activation / deactivation signal family, requests from anyone (`hud_*_request_event`) and wrappers that reach only the creating side's view (`player_view_source_event`) need no sender.
- To find "the one in the world", use `FindScopedComponent` (inside the scope `game_scope_component`, or the world without one). To send to everything, use `SendScoped`.
- To remember what you found: `set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)` (store it in your own field. Inside `<decides>` checks such as a condition's `IsSatisfied`, do not look it up; read `Manager?`. Reset it to `false` when stopping). To wait until it exists, `Entity.AwaitScopedComponent(...)`. For the nearest on itself or an ancestor, `Entity.FindNearestAncestorComponent[...]` (the engine's `FindAncestorComponents` has no defined order).
- A part that sends the activation signal uses `SendActivatedBy(Agent)` (`activated_by_agent_event`; a subclass of `activated_event`, so receivers run as usual) when it knows who triggered it. Receivers that need a player (device bridges, etc.) read it with `FindActivatingAgent[]`.
- Do not use module-level `var` `weak_map`s (per-session / per-player records) (they have a count limit). Keep per-player records in component fields (`[agent]t`) and find them from the entity under the slot.

### 3. Player state is announced with tags
- A System that holds "this player is currently doing X" (hovering, swinging, on a checkpoint, ready, etc.) attaches a Verse tag (a `tag` subclass) to the player (`agent`; in v43 an `agent` is also an entity, so it can carry tags) for that time and removes it afterwards. Because it goes on the agent rather than the character entity, it survives before spawning, while downed and after a respawn (⚠ Unverified: tagging agents in UEFN. Check with `_Test/PlayerSystemTest`).
- Attach and remove through `player_tag_holder` (PlayerSystem/PlayerTags.verse). It remembers the `tag_key` returned by `AddTag` and only `RemoveTag`s its own, so tags of the same type attached by other parts are kept. Always remove when stopping (`OnEndSimulation`, an ability's `defer`).
- The checking side uses `Agent.HasPlayerTag[tag type]` (internally `ContainsTag`). It does not look up or `using` the other component.
- Tag types live in the System that holds the state and all derive from `player_state_tag`. States that control movement (velocity, position) derive from `controlled_movement_tag`, and other forces (gravity, hover) leave players carrying one alone.
- Current tags: `pickup_effect_tag` (Pickup; while under an effect), `character_modified_tag` subclasses (Character / BuffKit; speed, jump, gravity, air jump, dash), `hovering_tag` (Hover), `swinging_tag` (Swing; controlled_movement. What is actually attached is a subclass, `swing_anchored_tag` (waiting on the ground) / `swing_pendulum_tag` (swinging). `HasPlayerTag[swinging_tag]` succeeds for either), `jetpack_boosting_tag` (Jetpack; controlled_movement), `on_checkpoint_tag` (Checkpoint), `player_ready_tag` (Input / ReadyKit), `in_volume_tag` (Volume), `custom_character_tag` (Character; while driving a custom character).

### 4. Real-time processing
- `Sleep(0.0)` is the usual way to wait one frame. When you need the seconds since the previous frame, or want a per-frame callback, use the component's `TickEvents.PrePhysics.Await()` (returns the seconds since the previous frame) or `TickEvents.PrePhysics.Subscribe` (subscribe in OnBeginSimulation, Cancel in OnEndSimulation). Library code uses the latter.
- Run-time classes that are not components (runners) receive a `listenable(float)` (pass `TickEvents.PrePhysics`) from the owning component and wait on it.
- Measure elapsed time by summing DeltaTime or by the difference of `GetSimulationElapsedTime()`, not by counting frames.
- When the same calculation applies to many things, one component computes them all at a fixed interval (e.g. every second). Make the result "a value determined by the time elapsed since the start" so that late joins, pauses and restarts do not drift (no per-object loops).
- Do not search the whole world every frame. Remember what you found. Prefer waiting for an event over polling at a fixed interval.
- Prefer engine-driven movement such as `keyframed_movement_component` over moving positions from Verse every frame.

- To follow Fortnite rounds (`fort_round_manager`), do not subscribe to rounds directly in parts. Place signal-driven parts under `activate_on_round_component` (`round_started_event` on round start, `round_ended_event` on round end; both are subclasses of the activation / deactivation signals) and turn off their ActiveOnBegin / StartOnBegin. When code needs it, hold a `round_watcher` (ActivationSystem) in a field (the `SubscribeRoundStarted` handler is canceled at the end of the round). Clean up per-round state at both the start and the end.

- Per-player choices (the mode, genre, role, etc. chosen in a menu) go into `player_group_component` (PlayerSystem) and affect only that player. Unless a screen (widget) is shown to everyone, put a filter such as `widget_show_in_group_component` on the same entity (do not have each part remember who chose what).

### 5. Names and values
- Queries that may fail are `<decides>` (`Find*` / `Is*` / `Has*`). `Get*` never fails. Only those with side effects that cannot be `<decides>` are `Try*` returning `logic`, with the reason in a comment.
- State that is only read from outside is `var<private> X<public>`; state that need not be readable is `<private>`. State queries are functions such as `IsActive[]`.
- Public numbers carry their unit in the name: length `Cm`, time `Seconds`, angle `Degrees`, speed `CmPerSecond`. Ratios and multipliers (`Ratio` / `Multiplier`) have no unit. Lengths are in centimeters like the engine.
- Child order carries no meaning. When an order is needed, use `@editable Order:int`.
- Internal helpers are `<internal>` (visible from Kits too). Classes created only at run time are `class<internal>` so the constructor is internal.
- Shared helpers used across Systems are functions. Using a generic class (a container like `scoped_lookup(t)`) in a field of a module that sorts before that module by name gives V3502 (Can't access a function from a preceding type) (reproduced with the standalone type checker; SceneGraphSystem's `ScopedLookup.verse`).

### 6. Descriptions
- Public types, functions and events get a 1-2 line description right above them (what it does, when it fails, units, requirements).
- A component starts with whichever of `Role` / `Placement` / `Parent` / `Children` / `Same entity` / `When` / `Notifies` / `Tags` / `From outside` / `Requirements` apply.
- Behavior not confirmed in UEFN is marked `⚠ Unverified:` (removed once confirmed). `@experimental` APIs are used only inside `...ExperimentalKit` folders and noted in the README and the component's `Requirements` (an island using them cannot be published).
- Logs (Print) have the form `[snake_case component name] what happened`. When a requirement is missing, Print instead of failing silently.
- `@editable`s get a `ToolTip` (a TooltipKit message) and `Categories`.
- Everything in the library is written in English: comments, tooltips, log messages, test names and READMEs (the public repository is English only).

## Verifying
- Type check: verse-standalone (a Verse type checker you build yourself from the UE source; distribution kit: https://github.com/GorosukeSan/verse-standalone-kit ) with `verse_check.py --profile fortnite --runtime runtime-uefn43`. The "internal" / "Unknown member" errors on `Await` of listenable / event / TickEvents, and the `race` / `loop` errors that follow them (V3538 / V3579), are known false positives of the checker (the UEFN build passes).
- Any other V3512 (effects not allowed) is a real error. Example: calling a `<suspends>` function inside an `if` condition (`if (AwaitWithin(...)?)`). Receive it in a variable first, then `if (X?)`.
- Behavior: run the `_Test` tests in UEFN.
- Some errors appear only in the UEFN build (not in the standalone type checker). Example: passing a function received as an argument straight to `Subscribe` (V3502) → go through a small class that wraps it in a method. Build in UEFN before distributing.
- Changing the kind of a public type (class → enum, etc.) can leave a 9002 because the open editor still remembers the old type. Restarting the editor clears it (do not try to fix it by rewriting the editor's types with Python etc.; it crashes).
- Check that no experimental API is used: compare the `@experimental` names in the digest against the code outside `ExperimentalKit` folders (move any use into an `...ExperimentalKit`).
