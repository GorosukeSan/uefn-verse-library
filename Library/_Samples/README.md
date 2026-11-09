# _Samples — "place and try" samples of the Library

A home for components that let you place the Library's mechanisms in a level and try them by hand right away. They show instructions on screen and in the output log and react to player input. Written with the public API only, so they also serve as usage examples.

## Difference from _Test
- `_Test` is automated verification. It logs whether things behave as expected as `[PASS]` / `[FAIL]`, and a person only reads the result.
- `_Samples` are samples a person operates and watches. They give no pass / fail; they show "this is what is happening now" on screen and with `Print`. They are for learning the mechanisms while playing and as a base for your own code.
- Both ship with the distribution, but place them in your level only while checking.

## Usage
1. Place one entity with `player_manager_component` in the level (or the scope) (most samples require it).
2. Attach the component of the sample you want to see to an entity (placement is in the header comment of each file).
3. Start the session. Operate while watching the on-screen text and the output log (prefixes such as `[input_sample]`).

## List of samples

| Folder | component | What it shows | Placement |
|---|---|---|---|
| `InputSampleExperimentalKit/` | `input_sample_component` | Shows the standard input actions / Mappings (all of `/Fortnite.com/Input` and `/Verse.org/Input`) on screen one at a time every `StepSeconds`; pressing shows "detected". logic inputs at the moment of the press (`BeginDetectEvent`), vector3 inputs (Move, PointerSelect, PointerZoom) with `TriggerActivationEvent`. In the PointerSelect / PointerZoom steps, `TouchMapping` shows the Virtual Pointer. The `button_loud` at the left gets the same input as `TriggeringInputAction`, to check that a Click happens even without focus | Attach to an empty entity. With `StartOnBegin` off, starts on the activate signal (`activated_event`) |
| `VirtualPointerSampleExperimentalKit/` | `virtual_pointer_sample_component` | Virtual Pointer: `TouchMapping` + `PointerSelect` -> a ray with `DeprojectViewportToWorld` -> Prints the hit location found with `FindSweepHits` (LUF cm). `TeleportOnClick` teleports there; `UseOverheadCamera` adds a `perspective_camera_component` straight above with `camera_director_component.AddCamera`. Other components can subscribe to `ClickedEvent` (player, world position) | Attach to an empty entity. The camera is @experimental, so it is off by default |
| `Platformer2DSampleExperimentalKit/` | `platformer_2d_sample_component` | Side-scrolling 2D sample (movement, jumping, goal). Creates a custom character (CharacterSystem `character_motor_component` (`AxisLock = Left`), walk, jump, body_link, camera) under the slot of every player who joins. Move left / right and jump (double jump; a short press jumps lower). Entering the goal box (at `GoalOffsetCm`, size `GoalSizeCm`) Prints and returns you to the start. The move input `Character.Move` and the orthographic camera (CameraExperimentalKit) are @experimental | Attach to an empty entity above a floor (that is the start). Arrange floors and platforms forward, and make a landable place beyond the goal. Needs `player_manager_component` in the scope (or the world) |
| `AbilitySample/` | `ability_sample_component` | Lists the abilities (`ability_component` subclasses) and grant components on the same entity at start and Prints `GrantedEvent` / `RevokedEvent`. `ToggleAction` (default E / RB, `MenuNavigationMapping`) toggles your own Grant / Revoke | Attach to an entity with ability components (swing / jetpack / hover / gravity_point). Grant components are optional |
| `WidgetSample/` | `widget_sample_component` (Hud), `menu_sample_component` (Menu, Chosen), `widget_sample_opener_component` | How to write a `player_widget_component` subclass (only `CreateWidget(View)` is written). The HUD shows the name, the elapsed time (`SendToWidgets` every second) and the last `player_event` received, subscribing to `View.ReceivedEvent` to change the display. The menu is `Mode = Menu`, `Audience = Chosen` (shown only to the opener), awaits a `button_loud` with `View.AwaitClick` and closes with `View.Close`. The opener `ShowFor`s only the player who pressed C (RT) and notifies the same player's HUD with `SendToPlayer` | `widget_sample_component` + `activate_on_begin_component` on the HUD entity. `menu_sample_component` on another entity. Attach the opener to any entity and set the menu entity in `MenuEntity` |
| `ScopeSample/` | `scope_sample_component` | Scopes (`game_scope_component`): Prints which scope it belongs to and whether `FindScopedComponent[player_manager_component]` finds one inside the scope, in the world, or nothing. Also tells whether the search from `OtherEntity` finds the same manager | Place inside and outside a scope and compare |

## Conventions (when adding a sample)
- A sample that uses an `@experimental` API ends its folder name with `ExperimentalKit` (e.g. `InputSampleExperimentalKit`). VerseShare distributes such folders only to projects with "includes experimental" on. Using them prevents publishing the island.
- One sample per folder. Put `<name>_sample_component` in `_Samples/<Name>Sample/<Name>Sample.verse` (naming the folder the same as the System itself makes `using` ambiguous).
- Write `Role` / `Placement` / `Try it` in the header comment. Text shown to players is human-readable.
- Per-player work uses `player_view_set` (PlayerSystem) or `player_widget_component` (WidgetSystem) (no base class inheritance).
- Starting follows `@editable StartOnBegin` (default on) or the activate signal (`activated_event`). `player_widget_component` subclasses only use the activate signal, so place `activate_on_begin_component` alongside.
- On stop (`OnEndSimulation`, the deactivate signal), always remove the Mappings, screens, cameras and subscriptions you added. Never remove character-control Mappings.
- Do not write `<suspends>` calls (`X.Await()` etc.) in an `if (...)` condition (bind them first). Do not use `Log` as a variable name.
- Use the public API (`<public>`) only. If you need internals, add a public API on the Library side.
