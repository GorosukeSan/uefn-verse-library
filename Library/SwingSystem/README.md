# SwingSystem

A swing ability (an `ability_component` subclass from AbilitySystem). A granted player presses fire (`GrabAction`) to attach a rope to the object beyond the reticle and grab it, then swings as a pendulum until jump (`ReleaseAction`) is pressed to release. The scope registry (`swing_registry_component`), strength modifiers (`swing_modifier_component` and the ModifierKit) and the behaviors of grabbable objects (`swing_target_component` and the TargetKit) live here too.

## Setup (placement)

| component | Where | What it does |
|---|---|---|
| `swing_ability_component` | Same entity as the granting component (AbilitySystem's GrantKit). For an item, the item entity | Runs a swing for each granted agent. While grabbing, attaches a `swinging_tag` subclass to the agent (`swing_anchored_tag` while waiting on the ground, `swing_pendulum_tag` while swinging). Sends notifications under the slot and upward |
| `swing_registry_component` | One per scope (under a `game_scope_component`; the world if there is none) | Remembers each agent's swing and the modifier sources. Needed for rope pulling and modifiers (does not track who is swinging; look at the tags) |
| `swing_anchor_component` | Not placed (attached at runtime to the entity of the grabbed point) | `Break` cuts every swing holding that point |
| `swing_target_component` | Entity of the object to grab (same entity as a mesh with collision). One per entity. Objects are grabbable without it | Notifies grabbed / launched / released and remembers the rope points currently attached. `Shatter` breaks it |
| `swing_modifier_component` | Entity that defines a modifier. At most one per entity | The modifier values that change the swing strength. Who it applies to is decided by the ModifierKit or code |
| `swing_modifier_all_component` (ModifierKit) | Same entity as `swing_modifier_component` | Applies the modifier to every player (late joiners too) (from the start, or from the activate signal to the deactivate signal) |
| `swing_modifier_grant_component` (ModifierKit) | Same entity as `swing_modifier_component` | Applies the modifier for `DurationSeconds` to agents that receive `swing_modifier_request_event`. The deactivate signal removes it from everyone |
| `swing_modifier_condition_component` (ModifierKit) | Same entity as `swing_modifier_component`. Condition on a direct child | Applies the modifier to every player while the condition is satisfied |
| `swing_life_component` (TargetKit) | Same entity as `swing_target_component` | Breaks it `LifeSeconds` after the first grab. Notifies the remaining time and the final blinking |
| `swing_lift_component` (TargetKit) | Same entity as `swing_target_component` (not together with a mover) | When launched from, moves straight by `TravelCm` and breaks on arrival |

How `swing_ability_component` is granted is chosen by the component placed on the same entity.
- Everyone from the start / while activated -> `ability_grant_players_component`
- As an item (while equipped) -> place together with `item_component`, `item_holder_component` and `ability_grant_item_component`
- While a condition is satisfied -> `ability_grant_condition_component` (condition on a direct child)
- From code -> `Grant` / `Revoke`

Example: everyone can swing, and there is a cube that breaks 5 seconds after being grabbed
```
Scope (or the world)
├ Players (player_manager_component)
├ Swing registry (swing_registry_component)
├ Swing (swing_ability_component + ability_grant_players_component)
└ Lifetime cube (mesh + swing_target_component + swing_life_component)
```

## Settings (@editable)
`swing_ability_component` (lengths in cm, speeds in cm/s, accelerations in cm/s^2, times in seconds):

Input (input mappings are added when granted and kept, not removed):
- `GrabAction : input_action(logic) = Character.WeaponPrimary` — press to grab. While swinging, pressing again reels in (and attaches to another point if there is room).
- `GrabMapping : input_mapping = Character.RangedWeaponMapping` — mapping that contains `GrabAction`.
- `ReleaseAction : input_action(logic) = Character.Jump` — hold while swinging to accelerate, let go to release the rope. While waiting on the ground, press to launch.
- `ReleaseMapping : input_mapping = Character.TraversalMapping` — mapping that contains `ReleaseAction`.
- `ReelOutAction : input_action(logic) = Character.WeaponSecondary` — hold while swinging to reel out. While waiting on the ground, press to release the rope.
- `ReelOutMapping : input_mapping = Character.RangedWeaponMapping` — mapping that contains `ReelOutAction`.

Grab:
- `MaxRangeCm : float = 4000.0` — grab range (100-20000). Also the rope length limit when reeling out.
- `GrabRadiusCm : float = 50.0` — radius of the grab test sphere (0-500). 0 uses a point test.
- `GrabGraceSeconds : float = 0.5` — time the last point found can still be grabbed after the reticle leaves it (0-3).
- `GrabBufferSeconds : float = 0.3` — a press made while grabbing is used for a grab right after release if the release follows within this time (0-1).
- `GrabLiftHeightCm : float = 20.0` — height the body is lifted by moving its position directly before launching from the ground (0-300).
- `GrabKickSpeedCmPerSecond : float = 300.0` — speed added in the direction of motion at the moment of launch (0-3000).
- `GroundLaunchMultiplier : float = 2.0` — multiplier for the launch momentum (launch speed and start speed) when grabbing on the ground and launching with jump (1-10).
- `LandingGraceSeconds : float = 1.0` — time after launch during which touching the ground does not count as landing (0-5).

Rope:
- `MinRopeLengthCm : float = 200.0` — shortest length the rope can be reeled in to (50-5000).
- `ReelSpeedCmPerSecond : float = 500.0` — reel-in / reel-out speed by input (0-5000).
- `RopeCorrectionRate : float = 5.0` — fraction of the excess pulled back per second (0-50; larger is stiffer).
- `AutoReelSeconds : float = 1.0` — time after the pendulum starts during which the rope reels in automatically (0-5; 0 disables it).
- `AutoReelRatio : float = 0.67` — how far the rope reels in automatically, as a ratio of its length at launch (0.1-1; 1 disables it).
- `MaxRopeCorrectionSpeedCmPerSecond : float = 1000.0` — upper limit of the pull-back speed (0-5000).

Release / boost:
- `ReleaseBoostCmPerSecond : float = 600.0` — speed added in the direction of motion on release (0-5000).
- `HoldAccelerationCmPerSecondSquared : float = 1000.0` — acceleration while `ReleaseAction` is held during a swing (0-10000).
- `MaxHoldSpeedCmPerSecond : float = 4500.0` — speed limit while accelerating with hold (100-15000; if smaller than `MaxSwingSpeedCmPerSecond`, that one is used).

Pendulum:
- `SwingStartSpeedCmPerSecond : float = 400.0` — total speed added over `SwingEaseSeconds` after launch (0-5000).
- `SwingEaseSeconds : float = 0.3` — time until the start speed has been fully added (0.05-3).
- `SwingGravityCmPerSecondSquared : float = 980.0` — gravity used by the pendulum calculation (0-6000).
- `SwingSteerAccelerationCmPerSecondSquared : float = 300.0` — acceleration added toward the look direction (0-5000).
- `SwingDrag : float = 0.15` — air drag (0-5; this fraction of the speed is lost per second).
- `MaxSwingSpeedCmPerSecond : float = 2500.0` — pendulum speed limit (100-10000).

Multi swing / pull:
- `MaxRopes : int = 1` — number of ropes that can be attached at the same time (1-5).
- `PullerCorrectionRatio : float = 0.5` — multiplier for how strongly you are pulled back while your rope is attached to another agent (0-1).
- `ReelPullSpeedCmPerSecond : float = 800.0` — speed at which a player pulled by a rope pull is dragged toward you (0-6000).
- `ReelPullLengthCm : float = 1000.0` — distance a rope pull drags the other player (0-20000).
- `FollowDistanceRatio : float = 0.25` — while waiting on the ground with a rope on another agent, follow once they are this many times `MaxRangeCm` away (0.05-1).

`swing_modifier_component` (every default leaves the value unchanged):
- `RangeMultiplier` / `SpeedMultiplier` / `AccelerationMultiplier` / `BoostMultiplier` / `ReelMultiplier : float = 1.0` — multipliers for the grab range, the speed limit (and the hold limit), the acceleration (launch, steering, hold), the release boost and the reel speed (0-10).
- `ExtraRopes : int = 0` — number added to the ropes that can be attached at the same time (-4 to 4; the total never goes below 1).
- `AllowGrab : logic = true` — false forbids new grabs (ropes already attached are kept).

ModifierKit / TargetKit:
- `swing_modifier_all_component.ApplyOnBegin : logic = false` — true applies to everyone from the start. false applies from the activate signal to the deactivate signal.
- `swing_modifier_grant_component.DurationSeconds : float = 10.0` — how long the modifier stays applied after a request (seconds; 0-600). The same agent receiving it again restarts the timer. 0 means until the deactivate signal.
- `swing_life_component.LifeSeconds : float = 5.0` — time from the first grab until it breaks (seconds; 0.5-120; releasing does not extend it; includes the blinking time).
- `swing_life_component.BlinkCount : int = 3` / `BlinkSeconds : float = 0.9` — number (1-10) and duration (0.1-10 seconds) of the blinks just before it breaks.
- `swing_lift_component.TravelCm : vector3 = vector3{Up := 4000.0}` — direction and distance to move when launched (cm).
- `swing_lift_component.SpeedCmPerSecond : float = 800.0` — move speed (50-6000). If faster than the swing's max rope correction speed, the holder detaches easily.

## Events and tags
From the ability (`swing_ability_component` wraps them in a `player_event` and SendDowns them under the agent's slot, and also SendUps them from the ability entity. Receivers are views such as the HUD. Not consumed):
- `swing_target_changed_event` (scene_event): `Ability : swing_ability_component`, `Agent : agent`, `CanGrab : logic` — while idle, whether the object beyond the reticle can be grabbed changed (checked every 0.1 s).
- `swing_state_changed_event` (scene_event): `Ability`, `Agent`, `State : swing_state` — the state changed.
- `swing_grabbed_event` (scene_event): `Ability`, `Agent`, `Anchor : entity` — one rope attached (`Anchor` is the point with `swing_anchor_component`).
- `swing_rope_detached_event` (scene_event): `Ability`, `Agent`, `Anchor : entity` — one rope detached (the point broke, got too far away, or the grabbed object disappeared).
- `swing_released_event` (scene_event): `Ability`, `Agent` — all ropes removed and released (by the player, the point breaking, or `Release`).
- `swing_reel_hint_event` (scene_event): `Ability`, `Agent`, `Holder : ?agent` — while on the ground, started / stopped (`false`) looking at a player whose rope is attached to you. For the "pull the rope" hint.
- `swing_stats_changed_event` (scene_event): `Ability`, `Agent`, `Stats : swing_stats` — the modifiers applied to the agent changed.

To the grabbed object (the swing SendDowns them to the hit entity. Receivers are that entity's `swing_target_component` and looks on its descendants. Not consumed):
- `swing_attached_event` (a rope was attached), `swing_pulled_event` (a swing was launched from that point; arrives on every launch; not while waiting on the ground), `swing_detached_event` (the rope at that point detached). All carry `Ability : swing_ability_component`, `Agent : agent`, `Anchor : entity`.

From the TargetKit (SendDown to its own entity. Receivers are looks on the same entity / descendants. Not consumed):
- `swing_life_changed_event` (scene_event): `Life : swing_life_component`, `RemainingRatio : float` (1 -> 0), `Visible : logic` (false while blinking). Arrives every 0.1 s and during the final blinking.
- `swing_lift_changed_event` (scene_event): `Lift : swing_lift_component`, `Active : logic` — when it starts moving (`Active := true`).

listenable (cannot be Signaled from outside):
- `swing_ability_component.StateChangedEvent : listenable(tuple(agent, swing_state))` — each time someone's state changes.
- `swing_ability_component.GrabbedEvent : listenable(tuple(agent, entity))` — each time one rope is attached (entity of the grabbed point).
- `swing_ability_component.RopeDetachedEvent : listenable(tuple(agent, entity))` — each time one rope detaches.
- `swing_ability_component.ReleasedEvent : listenable(agent)` — when all ropes are removed and released.
- `swing_target_component.AttachedEvent` / `PulledEvent` / `DetachedEvent : listenable(agent)`, `ShatteredEvent : listenable(tuple())` (once, on `Shatter`).
- `swing_anchor_component.BrokenEvent : listenable(tuple())` (once, on `Break`).
- `swing_modifier_component.ChangedEvent : listenable(tuple())` — when the targets change.

Received:
- `swing_modifier_request_event` (scene_event): `Sender : entity`, `Agent : agent` — when the sender (a power-up item, a touchable object, etc.) SendDowns / SendUps it to the entity of `swing_modifier_grant_component`, the modifier is applied to that agent with an expiry. Not consumed.
- `swing_modifier_all_component` receives `activated_event` / `deactivated_event`. `swing_modifier_grant_component` receives `deactivated_event` (removes from everyone).
- `swing_target_component` receives `swing_attached_event` / `swing_pulled_event` / `swing_detached_event`.

## Querying the state (tags)
The only entry point for checking the current swing state is the tag on the agent (the ability and the registry have no query functions).
- `swinging_tag` (a `controlled_movement_tag` subclass): attached while grabbing (waiting on the ground or swinging; any state other than `Idle`). What is actually attached is a subclass, `swing_anchored_tag` (`Anchored`: waiting on the ground with only a rope attached) or `swing_pendulum_tag` (`Swinging`: swinging as a pendulum); both are found as `swinging_tag`. It is swapped when the state changes and removed on returning to `Idle` or when the ability is revoked. The ability adds and removes it through `player_tag_holder` (PlayerSystem).
- From code, read it with `Agent.IsSwinging[]` (succeeds while swinging) or `Agent.GetSwingState()` (`swing_state`). Both only look at the tags.
- Other Systems that know nothing about SwingSystem check `Agent.HasPlayerTag[swinging_tag]` (or `controlled_movement_tag` to ask whether the movement is being controlled). Gravity (GravitySystem) and hover (HoverSystem) do not overwrite the velocity of an agent with this tag.
- To be notified when the state changes, use `swing_ability_component.StateChangedEvent` or `swing_state_changed_event` (delivered under the slot and upward from the ability entity).

## Public API
```verse
swing_state<public> := enum:
    Idle         # no rope attached
    Anchored     # waiting on the ground with only a rope attached
    Swinging     # swinging as a pendulum

swinging_tag<public> := class(controlled_movement_tag):
swing_anchored_tag<public> := class(swinging_tag):         # while Anchored
swing_pendulum_tag<public> := class(swinging_tag):         # while Swinging
(Agent:agent).IsSwinging<public>()<decides><reads>:void    # succeeds if swinging_tag is attached
(Agent:agent).GetSwingState<public>()<reads>:swing_state   # read from the tags. Idle if none

swing_ability_component<public> := class<final_super>(ability_component):
    # for the @editable fields see "Settings" (Name<public>:type)
    StateChangedEvent<public><final>:listenable(tuple(agent, swing_state))
    GrabbedEvent<public><final>:listenable(tuple(agent, entity))
    RopeDetachedEvent<public><final>:listenable(tuple(agent, entity))
    ReleasedEvent<public><final>:listenable(agent)
    Release<public>(Agent:agent):void                       # forces a release if grabbing (no boost added)
    # Grant / Revoke / RevokeAll / IsGranted / GetGrantedAgents / GrantedEvent / RevokedEvent come from ability_component

swing_registry_component<public> := class<final_super>(component):
    GetStats<public>(Agent:agent)<transacts>:swing_stats     # every applied modifier, combined

swing_anchor_component<public> := class<final_super>(component):
    var<private> Broken<public>:logic = false
    BrokenEvent<public><final>:listenable(tuple())
    Break<public>():void                                     # does nothing from the second call on

swing_target_component<public> := class<final_super>(component):
    AttachedEvent<public><final>:listenable(agent)
    PulledEvent<public><final>:listenable(agent)
    DetachedEvent<public><final>:listenable(agent)
    ShatteredEvent<public><final>:listenable(tuple())
    WasAttached<public>()<decides><transacts>:void
    WasPulled<public>()<decides><transacts>:void
    IsShattered<public>()<decides><transacts>:void
    GetAnchorCount<public>()<transacts>:int
    Shatter<public>()<suspends>:void                         # cuts the ropes and removes the entity one frame later

swing_modifier<public> := struct:
    RangeMultiplier<public>:float = 1.0
    SpeedMultiplier<public>:float = 1.0
    AccelerationMultiplier<public>:float = 1.0
    BoostMultiplier<public>:float = 1.0
    ReelMultiplier<public>:float = 1.0
    ExtraRopes<public>:int = 0
    AllowGrab<public>:logic = true

swing_stats<public> := struct:
    RangeScale<public>:float = 1.0
    SpeedScale<public>:float = 1.0
    AccelerationScale<public>:float = 1.0
    BoostScale<public>:float = 1.0
    ReelScale<public>:float = 1.0
    ExtraRopes<public>:int = 0
    CanGrab<public>:logic = true

(Stats:swing_stats).Apply<public>(Modifier:swing_modifier)<transacts>:swing_stats   # multipliers multiplied, rope counts added, grabbing allowed only when both are true

swing_modifier_component<public> := class<final_super>(component):
    RangeMultiplier<public>:float
    SpeedMultiplier<public>:float
    AccelerationMultiplier<public>:float
    BoostMultiplier<public>:float
    ReelMultiplier<public>:float
    ExtraRopes<public>:int
    AllowGrab<public>:logic
    ChangedEvent<public><final>:listenable(tuple())
    GetModifier<public>()<transacts>:swing_modifier
    IsAppliedTo<public>(Agent:agent)<decides><transacts>:void
    ApplyToAll<public>():void           # counted. Removed after the same number of RemoveFromAll calls
    RemoveFromAll<public>():void
    ApplyTo<public>(Agent:agent):void   # counted. Removed after the same number of RemoveFrom calls
    RemoveFrom<public>(Agent:agent):void

swing_target_changed_event<public> := class(scene_event):
    Ability<public>:swing_ability_component
    Agent<public>:agent
    CanGrab<public>:logic
swing_state_changed_event<public> := class(scene_event):
    Ability<public>:swing_ability_component
    Agent<public>:agent
    State<public>:swing_state
swing_grabbed_event<public> := class(scene_event):     # swing_rope_detached_event, swing_attached_event, swing_pulled_event and swing_detached_event have the same shape
    Ability<public>:swing_ability_component
    Agent<public>:agent
    Anchor<public>:entity
swing_released_event<public> := class(scene_event):
    Ability<public>:swing_ability_component
    Agent<public>:agent
swing_reel_hint_event<public> := class(scene_event):
    Ability<public>:swing_ability_component
    Agent<public>:agent
    Holder<public>:?agent
swing_stats_changed_event<public> := class(scene_event):
    Ability<public>:swing_ability_component
    Agent<public>:agent
    Stats<public>:swing_stats
swing_modifier_request_event<public> := class(scene_event):
    Sender<public>:entity
    Agent<public>:agent

# ModifierKit
swing_modifier_all_component<public> := class<final_super>(component):
    ApplyOnBegin<public>:logic
    IsApplying<public>()<decides><transacts>:void
swing_modifier_grant_component<public> := class<final_super>(component):
    DurationSeconds<public>:float
    IsApplyingTo<public>(Agent:agent)<decides><transacts>:void
    Request<public>(Agent:agent):void   # same as receiving swing_modifier_request_event
swing_modifier_condition_component<public> := class<final_super>(component):
    IsApplying<public>()<decides><transacts>:void

# TargetKit
swing_life_component<public> := class<final_super>(component):
    LifeSeconds<public>:float
    BlinkCount<public>:int
    BlinkSeconds<public>:float
swing_life_changed_event<public> := class(scene_event):
    Life<public>:swing_life_component
    RemainingRatio<public>:float
    Visible<public>:logic
swing_lift_component<public> := class<final_super>(component):
    TravelCm<public>:vector3
    SpeedCmPerSecond<public>:float
swing_lift_changed_event<public> := class(scene_event):
    Lift<public>:swing_lift_component
    Active<public>:logic
```

## Requirements, caveats and limits
- Place a `player_manager_component` (to send to the slot) and a `swing_registry_component` (optional) in the scope (or the world). The ability looks for both until found and then remembers them.
- Swings work without `swing_registry_component`, but rope pulling and modifiers (`swing_modifier_component`) are unavailable. Querying the state (tags) works without a registry.
- The grab test sweeps a sphere of radius `GrabRadiusCm` in the reticle direction and grabs the hit point. Anything with collision can be grabbed; `swing_target_component` is not required (attach it only when you need behaviors such as breaking or moving). Objects between the camera and the character, and your own items, are excluded.
- Ropes can also be attached to other agents (a participant's character or their items). You then follow them when they move away (`FollowDistanceRatio`), and when they look at you through the reticle from the ground and press fire, you are dragged toward them by "pull the rope". A rope on another agent does not detach beyond `MaxRangeCm`.
- The pendulum is computed by the System and applied every frame (`TickEvents.PrePhysics`) with `SetLinearVelocity`. When launching from the ground, the position is lifted directly by `GrabLiftHeightCm` (MovementSystem's `LiftBy`).
- The ground, landing, the distance to the other agent and what the reticle points at have no notification (event), so they are checked every 0.1 s. Modifiers are re-read only when the registry reports a change.
- Input mappings (`GrabMapping` / `ReleaseMapping` / `ReelOutMapping`) are added when granted and not removed on revoke.
- Effects: if the ability entity has a `fort_item_ability_component`, its `ItemEquippedAbilities` are used on the agent while swinging.
- `RunFor` starts with `AwaitPlayerInput` and waits until input is available. It does nothing for non-player agents (the output log shows `[swing_ability_component] Granted to a non-player agent...`).
- The ability itself does not look at the owner. Granting only the owner when placed under a slot (a loadout etc.) is the work of the granting component (`ability_grant_players_component` / `ability_grant_condition_component`) (AbilitySystem).
- `swing_lift_component` moves the position every frame with `SetGlobalTransform`, so it is not placed on the same entity as a mover. `swing_life_component` may share an entity with a mover.
- Attaching tags to an agent relies on PlayerSystem's `⚠ Unverified` item (`PlayerTags.verse`: whether adding / removing tags on an agent and `ContainsTag` work in UEFN).
- The code in this folder uses no `⚠ Unverified` or `@experimental` API. The movement details are in the header comment of `SwingRunner.verse`.

## Verifying
- Test: `swing_system_test_component` in `_Test/SwingSystemTest/`. Place one entity with `player_manager_component` and one with `swing_registry_component` (in the same scope), and attach `swing_system_test_component` and `swing_ability_component` to the test entity (no granting component; the test calls `Grant` / `Revoke` from code). It checks modifier stacking, `Grant` and the idle state, the state tags (`swing_anchored_tag` / `swing_pendulum_tag` with `IsSwinging` / `GetSwingState`; the test adds and removes the tags), modifier registration and the expiry of `swing_modifier_grant_component`, the lifetime and lift targets (created at runtime by the test, which sends `swing_attached_event` / `swing_pulled_event`), and `Revoke`. With `RunHumanTests` (default true), follow the log prompts: aim the reticle at a mesh within `MaxRangeCm` and press fire (`HumanTimeoutSeconds` default 30 s; `[SKIP]` if not reached). For the human checks, place a mesh with collision where the player can see it. About 6 seconds excluding the human part. Results appear in the output log as `[TEST] SwingSystem`.
- Sample: `ability_sample_component` in `_Samples/AbilitySample/`. Attached to the entity with `swing_ability_component`, each player can toggle their own grant with `ToggleAction` (default E / RB). Log prefix `[ability_sample]`.

## Migration notes (2026-11-08)
State queries were unified on the tag (`swinging_tag`).
- `swing_ability_component.GetState(Agent)` -> `Agent.GetSwingState()`, `swing_ability_component.IsSwinging[Agent]` -> `Agent.IsSwinging[]`.
- `swing_registry_component.GetState(Agent)` / `IsSwinging[Agent]` -> same as above. `GetSwingingAgents()` is gone (iterate the participants and filter with `Agent.IsSwinging[]`).
- `swing_registry_component.StateChangedEvent` is gone -> `swing_ability_component.StateChangedEvent` or `swing_state_changed_event` (upward from the ability entity and under the slot).
- The attached tag is not `swinging_tag` itself but a subclass, `swing_anchored_tag` / `swing_pendulum_tag`. `HasPlayerTag[swinging_tag]` succeeds as before (subclasses are found too).
