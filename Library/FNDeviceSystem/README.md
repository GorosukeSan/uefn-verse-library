# FNDeviceSystem

A System that gathers everything relying on Fortnite creative devices (`creative_device`). It connects the activation / deactivation signals (ActivationSystem) with things only devices can do (triggers, ending the game, class and team, score, cinematic sequences, audio). It is the only System in the Library that depends on devices. To use a device from another System, place a part of this System.

## Placement

| component | Where to place | What it does |
|---|---|---|
| `device_trigger_component` | the entity where the signal arrives (a node, the `Targets` of an interact, a volume or a menu, ...) | fires the trigger device in `Trigger` on the activation signal (with the agent who caused it when known). Fires `StopTrigger` on the deactivation signal |
| `device_event_component` | anywhere. When `Targets` is empty, this entity and its descendants are the destination | every time the trigger device in `Trigger` fires, sends the activation signal to `Targets` (`activated_by_agent_event` when the firing agent is known) |
| `device_end_game_component` | the entity where the signal arrives (the goal volume, the last node of the flow, ...) | on the activation signal, `Activate`s the end game device for the `Recipients` |
| `device_class_component` | the entity where the signal arrives. May be placed inside a loadout (LoadoutSystem) | on the activation signal, changes the class / team of the `Recipients` with the class and team selector device |
| `device_score_component` | the entity where the signal arrives (coins, goals, ...) | on the activation signal, uses the score manager device on the `Recipients` |
| `device_sequence_component` | the entity where the signal arrives | plays the cinematic sequence device on the activation signal and stops it on the deactivation signal |
| `device_audio_component` | the entity where the signal arrives | plays the audio player device on the activation signal and stops it on the deactivation signal |
| `schedule_sequence_component` (ScheduleKit) | the entity of `schedule_component` (ScheduleSystem) or a descendant | plays the cinematic sequence device while the schedule is Active, aligning to the elapsed time when entering mid-period |

Devices placed in the level are chosen through `@editable`. One part selects one device (an array of devices cannot be written through MCP). To use several devices, place one part on each child entity.

Example: "make the player who enters the goal volume win, and add to their score"
```
Goal (player_volume_component + volume_activation_component)
├ End (device_end_game_component, EndGame = the end game device, Recipients = Activator)
└ Score (device_score_component, ScoreManager = the score manager device, Change = Award)
```
When the first player enters, `volume_activation_component` sends an activation signal identifying that player (`activated_by_agent_event`) to the child entities. The child parts use their devices on that player.

## Settings (@editable)
- `device_trigger_component.Trigger : ?trigger_device = false` — the trigger device fired on the activation signal.
- `device_trigger_component.StopTrigger : ?trigger_device = false` — the trigger device fired on the deactivation signal (fired with no agent).
- `device_event_component.Trigger : ?trigger_device = false` — the trigger device that sends the signal when it fires.
- `device_event_component.Targets : []entity = array{}` — the entities the activation signal is sent to. When empty, this entity and its descendants.
- `device_end_game_component.EndGame : ?end_game_device = false` — the end game device that ends the game (the win / loss setting is on the device).
- `device_end_game_component.Recipients : device_target_agents = Activator` — whom to end the game for.
- `device_class_component.Selector : ?class_and_team_selector_device = false` — the class and team selector device to use (which class / team is set on the device).
- `device_class_component.Change : device_class_change = Class` — what to change (`Class` / `Team` / `TeamAndClass`).
- `device_class_component.Recipients : device_target_agents = Owner` — whom to change.
- `device_score_component.ScoreManager : ?score_manager_device = false` — the score manager device to use (the points are set on the device).
- `device_score_component.Change : device_score_change = Award` — `Award` adds points as configured on the device (`Activate`); `Increment` / `Decrement` move one step up or down.
- `device_score_component.Recipients : device_target_agents = Activator` — whose score to change.
- `device_sequence_component.Sequence : ?cinematic_sequence_device = false` — the cinematic sequence device to play.
- `device_audio_component.AudioPlayer : ?audio_player_device = false` — the audio player device to play.
- `Scope : device_play_scope = Everyone` of `device_sequence_component` / `device_audio_component` — `Everyone` plays for everyone (following the device's Visibility setting); `Activator` plays only for the agent who caused the signal (`Play(Agent)`; set the device's Visibility to Instigator. For everyone when the agent is unknown).
- `StopOnDeactivate : logic = true` of `device_sequence_component` / `device_audio_component` — when on, stops on the deactivation signal.
- `schedule_sequence_component.Sequence : ?cinematic_sequence_device = false` — the device played during the period (one with Visibility = Everyone).
- `schedule_sequence_component.MaxLateStartSeconds : float = 0.0` — does not play if more than this many seconds have passed since the start when the period is entered (0 or more; 0 means no limit).
- `schedule_sequence_component.ResyncOnPlayerJoin : logic = true` — when on, every time a player joins during the period, Plays again and aligns to the elapsed time.

Meaning of `Recipients` (`device_target_agents`):
- `Activator` — the agent who caused the signal (the `Agent` of `activated_by_agent_event`). Does nothing when unknown.
- `Owner` — the owner (when placed under a slot). The agent who caused the signal when there is none. Does nothing when neither exists.
- `Everyone` — everyone in the slots of the `player_manager_component` of the zone (or the world). Does nothing when it is not found.

## Events
This System defines no scene_event types. What it sends and receives are the activation / deactivation signals of ActivationSystem.
- `device_event_component.TriggeredEvent : listenable(?agent)` — fires with the firing agent (false when unknown) every time `Trigger` fires.
- Sent: every time it fires, `device_event_component` sends `activated_by_agent_event` (when the firing agent is known; `SendActivatedBy`) or `activated_event` (`SendActivated`) downward from `Targets` (its own entity when empty). It never sends the deactivation signal.
- Received: `device_trigger_component` / `device_sequence_component` / `device_audio_component` receive `activated_event` and `deactivated_event`. `device_end_game_component` / `device_class_component` / `device_score_component` receive only `activated_event`. All read the causing agent with `FindActivatingAgent[]`. None consumes.
- `schedule_sequence_component` receives no signal. It receives the state changes (`StateChangedEvent`) of the nearest `schedule_component` through `schedule_follower`.

## Owner
- Parts with `device_target_agents.Owner` selected (the default of `device_class_component`), when placed under a player's slot (inside a LoadoutSystem loadout, etc.), act on the owner (`FindOwningPlayer`). When not under a slot, they act on the agent who caused the signal.
- A loadout sends the activation signal to its descendants the frame after it is created, so a `device_class_component` inside a loadout changes the owner's class when the loadout is attached.
- Parts with `Activator` / `Everyone` selected, and `device_trigger_component` / `device_event_component` / `device_sequence_component` / `device_audio_component` / `schedule_sequence_component`, do not change their behavior when there is an owner.

## Public API
```verse
device_trigger_component<public> := class<final_super>(component):
    Trigger<public>:?trigger_device
    StopTrigger<public>:?trigger_device
    Fire<public>():void                                     # fires Trigger with no agent
    FireFor<public>(Agent:agent):void                       # fires Trigger as caused by Agent

device_event_component<public> := class<final_super>(component):
    Trigger<public>:?trigger_device
    Targets<public>:[]entity
    TriggeredEvent<public><final>:listenable(?agent)

device_target_agents<public> := enum:
    Activator
    Owner
    Everyone

device_end_game_component<public> := class<final_super>(component):
    EndGame<public>:?end_game_device
    Recipients<public>:device_target_agents

device_class_change<public> := enum:
    Class
    Team
    TeamAndClass

device_class_component<public> := class<final_super>(component):
    Selector<public>:?class_and_team_selector_device
    Change<public>:device_class_change
    Recipients<public>:device_target_agents

device_score_change<public> := enum:
    Award
    Increment
    Decrement

device_score_component<public> := class<final_super>(component):
    ScoreManager<public>:?score_manager_device
    Change<public>:device_score_change
    Recipients<public>:device_target_agents

device_play_scope<public> := enum:
    Everyone
    Activator

device_sequence_component<public> := class<final_super>(component):
    Sequence<public>:?cinematic_sequence_device
    Scope<public>:device_play_scope
    StopOnDeactivate<public>:logic
    Play<public>():void                                     # plays (for everyone)
    Stop<public>():void                                     # stops

device_audio_component<public> := class<final_super>(component):
    AudioPlayer<public>:?audio_player_device
    Scope<public>:device_play_scope
    StopOnDeactivate<public>:logic
    Play<public>():void                                     # plays (for everyone)
    Stop<public>():void                                     # stops

# ScheduleKit
schedule_sequence_component<public> := class<final_super>(component):
    Sequence<public>:?cinematic_sequence_device
    MaxLateStartSeconds<public>:float
    ResyncOnPlayerJoin<public>:logic
    IsPlaying<public>()<decides><transacts>:void            # succeeds while playing
    Resync<public>():void                                   # if playing, re-aligns to the current elapsed time. Does nothing when not playing
```

## Requirements, caveats and limits
- Devices are placed in the level and chosen through the component's `@editable`. Device-side settings (win / loss, class, points, Visibility, ...) are decided on the device.
- Every device `@editable` takes one device (`?device_type`), because an array of devices cannot be written through MCP. To use several devices, place one part on each child entity (e.g. to fire three trigger devices, place three `device_trigger_component`, each on its own child entity of the entity where the signal arrives).
- When building the level through MCP: Fortnite's standard `input_action` / `input_mapping` (`Character.Jump`, `TraversalMapping`, ...) cannot be set as references with MCP's `SetComponentProperty`. Using them as code defaults is fine. To choose a different one, select it in the editor. An array of strings (`choice_menu_component.Options`, etc.) cannot have its length and contents changed at once through MCP, so clear it first and then fill it again.
- The deactivation signal (`StopTrigger`) and `Fire` of `device_trigger_component` fire with no agent. For device settings that need a causing agent, use `FireFor` or a signal that identifies the agent.
- `device_event_component` sends only the activation signal. To deactivate, send the deactivation signal from another part.
- `Recipients = Activator` on `device_end_game_component` etc. does nothing for a signal that does not identify the agent (plain `activated_event`, e.g. when a node of the game flow is entered). To affect anyone, use `Everyone`. `Everyone` needs a `player_manager_component` in the zone (or the world).
- `Play` / `Stop` of `device_sequence_component` / `device_audio_component` (called from code) act on everyone regardless of `Scope`.
- A part with no device selected (left `false`) does nothing when it receives a signal (no Print either).
- `schedule_sequence_component` (`FNDeviceSystem/ScheduleKit/ScheduleSequenceComponent.verse`) moved here from ScheduleSystem. Through ScheduleSystem's `schedule_follower` it watches the `schedule_component` on its own entity or the nearest ancestor. When none is found it Prints and does nothing. Tooltips and categories come from ScheduleSystem's TooltipKit (`ScheduleCategory`, etc.).
- `schedule_sequence_component` has points not yet confirmed in UEFN (the `Requirements (to be confirmed in UEFN)` in the code):
  - Whether late joiners see the video in sync depends on the device. When `ResyncOnPlayerJoin` is on, Play + `SetPlaybackTime` are redone on every join, so everyone's playback may jump for a moment. If it does not sync, change to one device per player (Visibility = Instigator) and `Play(Agent)`.
  - `SetPlaybackTime` is called right after Play. Not called when the elapsed time is under 0.5 s.
  - When the sequence is shorter than the Active length, it stays stopped after it ends (no loop is set).
  - `ResyncOnPlayerJoin` needs a `player_manager_component` in the zone (or the world) (without one, no re-alignment on join).
- This System uses no `@experimental` API.

## Verifying
- There is no `_Test/FNDeviceSystemTest/` (devices are chosen from those placed in the level, so a test cannot create them at runtime). No test in `_Test` uses the components of this System either. There is no sample in `_Samples/` either.
- To verify, place devices in the level in UEFN, place the components of this System under a signal sender (`interact_trigger_component`, `volume_activation_component`, a node of the game flow, ...) and run.
- Related: the schedule side watched by `schedule_sequence_component` can be checked with `_Test/ScheduleSystemTest/`; the zone lookup used by `Everyone` etc. (`FindScopedComponent[player_manager_component]`) with `_Samples/ScopeSample/`. There is currently no test for signals identifying the agent (`activated_by_agent_event` / `FindActivatingAgent`).
