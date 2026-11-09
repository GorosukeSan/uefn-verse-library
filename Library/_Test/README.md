# _Test — Library verification tests

A home for the components that exercise each System of the Library for real in UEFN. They are written against the public API only, so they also serve as usage samples.

## How to use
1. In a test level (or a test scope), place the parts of the System you want to check together with the test component from `_Test/<System>Test/` (placement is described in the header comment of each test component).
2. Start the session. The test runs automatically from the start of simulation (or from the activate signal).
3. Search the output log for `[TEST]` / `[FAIL]`.
   - `[PASS] TestName: item` ... as expected
   - `[FAIL] TestName: item (detail)` ... not as expected
   - `[TEST] TestName: n passed, m failed` ... summary of that test

## List of tests

Detailed placement and the items checked are in the header comment of each file and in "Verifying" in each System's README. The result log is `[TEST] <System name>` (e.g. `[TEST] CountdownSystem`).

| Folder | component | What it checks | Player / human input |
|---|---|---|---|
| `AbilitySystemTest/` | `ability_system_test_component` | Grant / Revoke from code and the reference counting, events, the grant component | needed |
| `ActivationSystemTest/` | `activation_system_test_component` | `SendActivated` / `SendDeactivated` reach descendants; `activate_on_begin_component` sends exactly once on the frame after begin | not needed |
| `CharacterSystemTest/` | `character_system_test_component`, `character_surface_test_component` (SurfaceKit), `character_buff_test_component` (modifiers / BuffKit; no player needed) | An ownerless body (`character_motor_component`) falls under gravity and lands, `AxisLock`, `SetVelocity`, `TeleportTo`. SurfaceKit touched / stepped on / left, being carried by a moving surface, `GetBox` | needed (standing on a flat floor) |
| `CheckpointSystemTest/` | `checkpoint_system_test_component` | Reached / left notifications and `IsStanding`, platform disposed, hand-over when watched together, EnergyKit refill (`checkpoint_energy_refill_component`) | needed (stand still on the floor; passing through from below is checked by a human following the `[HUMAN]` steps in the log) |
| `ConditionSystemTest/` | `condition_system_test_component` | Combinations and nesting of `condition_all` / `condition_any`, `ChangedEvent`, `event_received_condition_component` | not needed |
| `CountdownSystemTest/` | `countdown_system_test_component` | Real time until the count ends, remaining-seconds notifications, `Pause` / `Resume`, `AddSeconds`, `Stop`, start and restart on the activate signal, `Restart`, `AlsoSendUp` | not needed |
| `EnergySystemTest/` | `energy_system_test_component` | `energy_component` changes and notifications (`Spend[]`, `SetAmount`, `StartFull`), `FindEnergy` / `FindEnergyFor`, `energy_restore_ability_component` | needed (press the fire button at the end) |
| `GameSequenceSystemTest/` | `game_sequence_system_test_component` | First node, transitions, end, `Restart`, `JumpTo`, `Stop`, exit reasons, nested `StartOnActivate` sequence | not needed |
| `GravitySystemTest/` | `gravity_system_test_component` | `gravity_well_component` pulls; `gravity_point_ability_component` granting, place / remove, expiry | needed (keep 3 m above the head clear; press the fire button) |
| `GridSystemTest/` | `grid_system_test_component` | `grid_box` math, position / cell conversion, borrow / return, GridPath paths | not needed |
| `HoverSystemTest/` | `hover_system_test_component` | `hover_ability_component` grant / revoke, energy drain, hover events | needed (hold jump in the air) |
| `InputSystemTest/` | `input_system_test_component` | Driving `player_ready_component` (`FindInput`, `ToggleReady` too), `ReadyChangedEvent` / `player_ready_changed_event` / `all_players_ready_condition_component`, pressing toggles ready | needed (press the E key) |
| `InteractSystemTest/` | `interact_system_test_component` | `interact_gate_component` open / close, notification on press, `interacted_condition_component` | needed (press the button) |
| `ItemSystemTest/` | `item_system_test_component` | Finding the player's inventory, getting the input, etc. | needed |
| `JetpackSystemTest/` | `jetpack_system_test_component` | `jetpack_ability_component` grant / revoke, gauge, energy while charging and flying | needed (hold jump in the air) |
| `LoadoutSystemTest/` | `loadout_system_test_component` | `ApplyTo` creates a loadout under the slot, a second call does not add another, swapping within the same `Group`, `RemoveFrom` | needed |
| `MCPSystemTest/` | `mcp_system_test_component` (sample receiver `mcp_test_echo_component`) | JSON helpers (escaping, long strings, reading numbers, range checks), dispatch through `ExecuteJson` (Core, toolset, instance, unknown tool, required args, positional args, data validation, batch, help, describe), tag-name table, `mcp_role_tags`, `ClaimPosition` | not needed |
| `ModeSystemTest/` | `mode_system_test_component` | Candidate order, accepting, how `Select` decides, `Clear`, selected notification, voting | not needed |
| `MovementSystemTest/` | `movement_system_test_component` | Reading the position, `LiftBy`, view direction and origin | needed (keep 3 m above the head clear) |
| `MoverSystemTest/` | `mover_system_test_component`, `mover_spline_test_component` (curved routes) | Route traversal, waypoint `Order`, time to arrive, `Pause` / `Play`, route `Reset`, `Restart` (back to the start / from the current position), `AlsoSendUp`. Curve length, length table, loop seam, PingPong turnaround, constant speed, `FaceTravelDirection` | not needed |
| `PickupSystemTest/` | `pickup_system_test_component` | Effect lifetime (activate signal on the next frame, owner, `pickup_effect_tag`, expiry, Instant), stacking (Extend / Stack with MaxStacks / Replace), `EndPickupEffectsFor`, orb pickup / respawn / `RequireGroupMember`, StageKit signals and overlap counting | needed (just be present) |
| `PlayerSystemTest/` | `player_system_test_component` | Slots, `player_count_condition_component`, `player_view_set`, `SubscribePlayers`, player tags, groups and `player_group_count_condition_component` | needed |
| `SceneGraphSystemTest/` | `scene_graph_system_test_component` | Finding inside a scope (`game_scope_component`) / in the world, direct children only, nearest ancestor (`FindNearestAncestorComponent`), `ResolveScopedComponent` | not needed |
| `ScheduleSystemTest/` | `schedule_system_test_component` | Time math, clock and debug time travel, state change notifications, signals to children | not needed |
| `SpawnSystemTest/` | `spawn_system_test_component` | `spawner_component` spawns and keeps `Count`, inside the band, grid borrows, spawned / despawned notifications, `spawn_prefab_component` (spawn point order, activate signal, `MaxCount`, `TrySpawnAt`, `Despawn` / `DespawnAll`), the `SpawnPrefab` function | not needed |
| `SwingSystemTest/` | `swing_system_test_component` | Stacking of multipliers, `Grant` / `Revoke` from code, modifier registration, lifetime / lift targets, state tags (`Agent.IsSwinging[]`, `Agent.GetSwingState()`, subclass tags), swinging by human input | needed (human input only when `RunHumanTests`) |
| `VolumeSystemTest/` | `volume_system_test_component` | Entered / exited (`PlayerEnteredEvent`, `IsInside`, `in_volume_tag`) and signals | needed (standing on the ground) |
| `WidgetSystemTest/` | `widget_system_test_component` | Shown to everyone on activation, `SendToWidgets`, `ShowFor` / `HideFor` with `Audience = Chosen`, one menu per player, HudKit / MenuKit | needed |

There is no test for FNDeviceSystem (devices are chosen from those placed in the level, so a test cannot create them at runtime). The shared counting is in `TestLog.verse` (`test_log`).

## Writing a test
- One file per System. Put `<system>_test_component` in `_Test/<System>Test/<System>Test.verse` (a folder named `_Test/<System>/` would make the module name clash with the System itself and the `using` ambiguous).
- Do not name a variable `Log` (it clashes with Verse's built-in `Log`). Use `Results := test_log{Name := "..."}`.
- Do not write a `<suspends>` call (`Task.Await()` etc.) inside an `if (...)` condition (error 3512 in UEFN; take it first with `Got := Task.Await()`, then `if (Got?)`). `<suspends>` and `<decides>` cannot be on the same function.
- Count results with `test_log` (`_Test/TestLog.verse`). For "a notification arrives within N seconds" use `AwaitWithin(Event, Seconds)`.
- Use the public API (`<public>`) only. If something cannot be checked without internals (`<internal>`), that is a sign the public API is missing something; add it to the Library.
- Do not place the test components in a Library user's level (`_Test` ships with the distribution, but it is only used when verifying).
