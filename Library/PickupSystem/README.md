# PickupSystem

A System for pickups (orbs) and the "effects" they attach to the player who picks them up. An orb (`pickup_component`) only creates an **effect prefab** for the agent who touches it and gives it to them; it knows nothing about the effect's contents. An effect prefab is built from the "effect base" on its root (`pickup_effect_component`: owner, lifetime, stacking) **plus parts driven by the activate signal, stacked on top**. New effects can be made without writing code (buffs, ability grants, stage effects, combinations of other Systems' parts). The pickup and the ongoing effects are shown on the owner's screen by the HudKit's `pickup_effect_hud_component` (on pickup "Got {name}!" and the description; while ongoing, slots at the bottom center of the screen. Name, description, color and image come from the `card_info_component` on the root of the effect prefab).

## Setup (placement)

| component | Where | What it does |
|---|---|---|
| `pickup_component` | Pickup entity (same entity as the look mesh and the parts that detect touching) | Creates the `Effect` prefab for the agent who touches it and gives it to them (under that agent's slot). Hides the look and brings it back after `RespawnSeconds` |
| `pickup_filter_component` subclass | Same entity as `pickup_component` (at most one) | Restricts who can pick up with a condition in code (the only member is `CanPick`) |
| `pickup_effect_component` | Root of the effect prefab | On the frame after creation, sends an activate signal raised by the owner to itself and its descendants, and after `DurationSeconds` sends the deactivate signal and removes itself (the prefab). Stacking of the same effect (`StackMode`). `pickup_effect_tag` on the owner |
| Effect contents (parts driven by the activate signal) | Root or children of the effect prefab | Take effect on the activate signal and revert on the deactivate signal or `OnEndSimulation`. The owner is `FindOwningPlayer` or the signal's Agent |
| `pickup_stage_signal_component` (StageKit) | Root or children of the effect prefab | Sends activate / deactivate signals to targets with the same `Group` within a scope (the picked-up object's top-level entity, its scope, or the world) and reverts when the effect ends |
| `card_info_component` (WidgetSystem's CardKit) | Root of the effect prefab | The effect's look (`Title`, `Description`, `Badge`, `Thumbnail`, `AccentColor`). Read by the HudKit HUD (without it, name = `EffectId`). This is the only owner of the look |
| `pickup_effect_hud_component` (HudKit) | Under the owner's slot (loadout prefab, custom character body). Placed on an ancestor of the slots it shows everyone their own effects | On pickup: pops two lines above the slots ("Got {name}!" (the name in AccentColor) and the description) and fades them out (consecutive pickups in order; the same effect pulses). While ongoing: a row of square slots at the bottom center of the screen (border in AccentColor, a translucent black background that shrinks downward with the remaining time, image from Thumbnail (or a colored square with the first letter of the name), "x2" when stacked, blinking when little time is left). Instant and short effects get the toast only |
| `pickup_stage_target_component` (StageKit) | Entity to drive by signal (hidden platform, hazard, mechanism) | On a signal with the same `Group`, sends the activate / deactivate signal to its own entity and descendants (overlapping signals are counted; reverts once all have ended). Adds `pickup_stage_target_tag` |

Library parts usable as effect contents (all driven by the activate signal; where there is an owner they affect only the owner):
- CharacterSystem / BuffKit: `character_buff_component` (speed, jump and gravity multipliers), `character_move_grant_component` (air jump count, dash permission). Affect the custom character body
- WidgetSystem: widgets such as `text_hud_component` (shown on the owner's screen only while the effect lasts. To show only the effect name, put a `card_info_component` on the root and leave it to the HudKit HUD)
- AbilitySystem: an ability (`ability_component` subclass) + `ability_grant_players_component` (`GrantOnBegin = false`; granted to the owner only while the effect lasts)
- ActivationSystem: `enable_on_activation_component`; SpawnSystem: `spawn_prefab_component` (spawns something at the pickup location; the effect entity is positioned at the picked-up object), etc.

Example: a "speed x1.5 for 8 seconds, show the name on screen" effect and the orb that hands it out
```
Effect prefab PF_Effect_SpeedUp
└ root pickup_effect_component (DurationSeconds = 8, EffectId = "SpeedUp", StackMode = Extend)
       character_buff_component (CharacterSystem/BuffKit, SpeedMultiplier = 1.5)
       card_info_component (WidgetSystem/CardKit, Title = "Speed Up", Description = "Run 1.5x faster for 8 seconds", AccentColor = orange)

Loadout prefab (under the owner's slot)
└ body etc.  pickup_effect_hud_component (HudKit. Shows the pickup toast and the slots of ongoing effects to the owner. Not placed per effect)

Orb (level)
└ Orb  mesh (no collision), character_surface_component (touched by the custom character)
       (for the Fortnite character, player_volume_component (VolumeSystem)),
       pickup_component (Effect = PF_Effect_SpeedUp, RespawnSeconds = 10)
```
For "reveal that map's hidden platforms for 10 seconds", put a `pickup_stage_signal_component` (`Group = "reveal"`, `Signal = Activate`) on the effect root, and on the platforms a `pickup_stage_target_component` (`Group = "reveal"`) plus a part that appears on the activate signal (`enable_on_activation_component` or a game part).

## Making a new effect (no code)
1. Create a prefab in the content browser and attach `pickup_effect_component` to the root entity (`DurationSeconds`, how same effects are handled with `EffectId` / `StackMode`, `Instant` for one-shot effects).
2. Stack the effect's parts on the root or children (see the list above; any part driven by the activate signal works). To use two parts of the same type, split them onto child entities.
3. To show the name on screen, put a `card_info_component` (`Title`, `Description`, `AccentColor`; `Thumbnail` and `Badge` are optional) on the root, and one `pickup_effect_hud_component` (HudKit) under the owner's slot (a loadout etc.) (not per effect).
4. Select the prefab in the orb's `pickup_component.Effect`.

## Settings (@editable)
`pickup_component`
- `Effect : concrete_subtype(entity) = entity` — the effect prefab to give (`pickup_effect_component` on the root). If the root has none, logs to the output log and adds a default base (10 s).
- `RespawnSeconds : float = 10.0` — time until it returns after being picked up (0-3600). 0 means it does not return (`Restore`, the activate signal or a game reset brings it back).
- `Visual : concrete_subtype(entity) = entity` — look prefab. Created as a child of this entity at start and removed together on pickup. Leaving the default adds nothing (you may also replace this entity's mesh).
- `RequireGroupMember : logic = false` — when on, only members of the nearest ancestor `player_group_component` (PlayerSystem) group.
- `ActiveOnBegin : logic = true` — when off, hidden until the activate signal (an orb revealed by a signal).
- `DisplayName : string = ""` — display name (for the log and your HUD).

`pickup_effect_component`
- `DurationSeconds : float = 10.0` — seconds it lasts (0-3600). 0 means forever (until `End`, `EndPickupEffectsFor` or the player leaves).
- `Instant : logic = false` — when on, ends on the frame after the activate signal is sent (one-shot effects).
- `EffectId : string = ""` — identifies the same effect. Empty treats every pickup as a separate effect (always stacks).
- `StackMode : pickup_effect_stack_mode = Extend` — when a player who already has an effect with the same `EffectId` picks it up again. `Extend` (add to the remaining time) / `Refresh` (reset the remaining time) / `Stack` (add another copy) / `Replace` (end the old one and start anew) / `Ignore` (do nothing).
- `MaxStacks : int = 0` — limit for `Stack` (0 means none). When reached, the copy ending soonest is extended.

HudKit
- `pickup_effect_hud_component.ShowToasts : logic = true` — on pickup (including again) shows two lines above the slots: "Got {name}!" and the description.
- `pickup_effect_hud_component.ShowEffectList : logic = true` — lists ongoing effects as square slots at the bottom center of the screen with the remaining time as the background height (the same `EffectId` is merged into one marked "x2").
- `pickup_effect_hud_component` defaults to `ActiveOnBegin = true`, `ZOrder = 100` (`Audience`, `Mode` etc. are the same as WidgetSystem's `player_widget_component`).
- The look is `var Style : pickup_effect_hud_style` (set from code; not shown in the editor; copied when it starts showing). Main fields:
  - Toast: `ToastXRatio / ToastYRatio` (0.5 / 0.72), `ToastFormat` ("Got {0}!"; `{0}` is the name (AccentColor). In a Verse string write `"Got \{0\}!"`), `ToastTitleSize / ToastTitleColor` (44 / white; the color of the text other than the name), `ToastDescriptionColor / Size / WrapPx` (white / 26 / 900), `ToastLineGapPx` (4), `ToastBackColor / ToastBackOpacity / ToastPaddingPx` (panel; default 0 = hidden), `ToastInSeconds / ToastHoldSeconds / ToastOutSeconds` (0.2 / 1.1 / 0.3; about 1.6 s in total), `ToastStartScale / ToastOvershoot` (0.6 / 1.7), `ToastOutSlidePx` (24; slides up while disappearing), `ToastPulseScale / Seconds` (pulse on re-pickup), `ToastQueuedHoldSeconds` (0.5; when the next is waiting), `MaxQueuedToasts` (3).
  - Text shadow (every text in toasts and slots): `TextShadowColor / TextShadowOpacity / TextShadowOffsetPx` (black / 0.75 / 2; opacity 0 hides it).
  - Slots: `SlotXRatio / SlotYRatio` (0.5 / 0.88; the row center), `SlotSizePx / SlotGapPx` (84 / 12), `SlotBorderPx / SlotBorderOpacity` (3 / 1; the border is AccentColor), `SlotFlashColor / SlotFlashSeconds` (white / 0.35; the border flashes on re-pickup), `SlotBackColor / SlotBackOpacity` (black / 0.55; the height shrinks from the bottom with the remaining ratio), `SlotIconScale` (0.72), `SlotIconTintAccent` (false = white (the image's own colors) / true = tinted with AccentColor), `SlotLetterColor / Size` (the first letter when there is no image), `StackPrefix / SlotStackColor / SlotStackSize` ("×"; "×2" at the bottom right for 2 or more), `SlotInSeconds / SlotStartScale / SlotOvershoot` (bounces in), `SlotOutSeconds / SlotEndScale` (shrinks and fades out), `SlotPulseScale` (pulse on re-pickup), `SlotMoveSpeed` (speed of the shift toward the center when slots are added or removed), `SlotWarnSeconds / SlotWarnBlinkPerSecond` (2 / 4; blinks when little time is left), `MinSlotSeconds` (2.0; shorter effects are not listed), `ShowEndlessSlots` (true; endless effects keep a full background), `FallbackAccentColor` (color when there is no `card_info_component`).

StageKit
- `pickup_stage_target_component.Group : string = ""` — signal group. Empty receives nothing.
- `pickup_stage_signal_component.Group : string = ""`, `Signal : pickup_stage_signal = Activate` (`Activate` / `Deactivate`), `Scope : pickup_stage_scope = SourceRoot` (`SourceRoot` = inside the picked-up object's top-level entity / `SourceScope` = the picked-up object's scope (the world if none) / `World`), `RevertOnEnd : logic = true` (revert when the effect ends).

## Events and tags
- `pickup_picked_event` (scene_event, SendUp): `Pickup : pickup_component`, `Agent : agent`, `Effect : ?entity`. From the picked-up object's entity to the root. Not consumed.
- `pickup_effect_changed_event` (scene_event, SendUp): `Effect : pickup_effect_component`, `Agent : agent`, `Started : logic`. From the effect entity (under the slot) to the root. Not consumed.
- `pickup_effect_owner_event` (scene_event, SendDown): `Effect : pickup_effect_component` (the ongoing effect), `Picked : pickup_effect_component` (the picked-up effect; read the look from this one), `Agent : agent`, `Notice : pickup_effect_notice` (`Started` / `Renewed` / `Ended`). From the owner's slot entity downward (loadout, character, widget views, effect prefabs). Not consumed. `Renewed` is sent when the same effect was picked up again without starting a new one (`Extend` / `Refresh` / `Ignore`, or the `Stack` limit); `Effect` is then the one whose remaining time was extended. `Ended` is not delivered when the effect disappeared because the owner left. The HudKit HUD receives this.
- `pickup_component.PickedEvent : listenable(agent)`, `RestoredEvent : listenable(tuple())`.
- `pickup_effect_component.StartedEvent / EndedEvent : listenable(agent)`.
- Signals sent: the effect base sends `activated_by_agent_event{Agent = owner}` at the start and `deactivated_event` at the end to its own entity and descendants (SendDown). `pickup_stage_target_component` sends to its own entity and descendants.
- Signals received: `pickup_effect_hud_component` (HudKit) receives `pickup_effect_owner_event` (when placed under a slot), `pickup_effect_changed_event` (only when placed on an ancestor of the slots) and the activate / deactivate signals (WidgetSystem base). `pickup_component` receives `activated_event` (restore) / `deactivated_event` (hide), the touch notification `character_surface_contact_event` (SurfaceKit; `Touched` on its own entity's surface) and `player_volume_entered_event` (VolumeSystem; its own entity's volume). `pickup_stage_signal_component` receives `activated_event` / `deactivated_event`.

## Tags
- `pickup_effect_tag` (a `player_state_tag` subclass) — on the owner while an effect lasts (one per effect). Which effect it is: the `EffectId` from `GetActivePickupEffects(Agent)`; what is modified: the tags of the parts inside (e.g. BuffKit's `character_speed_modified_tag`).
- `pickup_stage_target_tag` (entity role) — added by `pickup_stage_target_component`. The sender finds targets by this tag.

## Owner
- Effect prefabs are created under the picker's slot, so the parts inside learn the owner (the picker) with `FindOwningPlayer` and affect only the owner (a library rule). The Agent of the activate signal is the owner too.
- The effect base does not start where there is no owner (logs to the output log and disappears). An effect placed in the editor somewhere that has an owner (inside a loadout etc.) starts on the frame after the start.

## Public API
```verse
pickup_effect_stack_mode<public> := enum:
    Extend
    Refresh
    Stack
    Replace
    Ignore

pickup_effect_tag<public> := class(player_state_tag):

pickup_picked_event<public> := class(scene_event):
    Pickup<public>:pickup_component
    Agent<public>:agent
    Effect<public>:?entity

pickup_effect_changed_event<public> := class(scene_event):
    Effect<public>:pickup_effect_component
    Agent<public>:agent
    Started<public>:logic

pickup_effect_notice<public> := enum:
    Started
    Renewed                                  # picked up again without starting (the ongoing effect was extended or left as is)
    Ended

pickup_effect_owner_event<public> := class(scene_event):    # SendDown from the owner's slot
    Effect<public>:pickup_effect_component   # the ongoing effect (for Renewed, the extended one)
    Picked<public>:pickup_effect_component   # the picked-up effect
    Agent<public>:agent
    Notice<public>:pickup_effect_notice

pickup_filter_component<public> := class<abstract><final_super>(component):
    CanPick<public>(Pickup:pickup_component, Agent:agent)<decides><transacts>:void

pickup_component<public> := class<final_super>(component):
    Effect<public>:concrete_subtype(entity)
    RespawnSeconds<public>:float
    Visual<public>:concrete_subtype(entity)
    RequireGroupMember<public>:logic
    ActiveOnBegin<public>:logic
    DisplayName<public>:string
    PickedEvent<public><final>:listenable(agent)
    RestoredEvent<public><final>:listenable(tuple())
    TryPickup<public>(Agent:agent):logic                 # true if picked up (the effect was given)
    Restore<public>():void
    Hide<public>():void
    IsAvailable<public>()<decides><transacts>:void
    CanPick<public>(Agent:agent)<decides><transacts>:void

pickup_effect_component<public> := class<final_super>(component):
    DurationSeconds<public>:float
    Instant<public>:logic
    EffectId<public>:string
    StackMode<public>:pickup_effect_stack_mode
    MaxStacks<public>:int
    StartedEvent<public><final>:listenable(agent)
    EndedEvent<public><final>:listenable(agent)
    End<public>():void
    AddSeconds<public>(Seconds:float):void
    SetRemainingSeconds<public>(Seconds:float):void
    GetRemainingSeconds<public>()<transacts>:float     # -1 for endless effects
    IsActive<public>()<decides><transacts>:void
    FindOwner<public>()<decides><transacts>:agent
    FindSource<public>()<decides><transacts>:entity     # entity of the picked-up object (orb)
    GetOriginTransform<public>()<transacts>:transform

(InEntity:entity).GrantPickupEffect<public>(Agent:agent, Prefab:concrete_subtype(entity), Origin:transform, Source:?entity):?entity
(InEntity:entity).GrantPickupEffectEntity<public>(Agent:agent, Effect:entity, Origin:transform, Source:?entity):?entity
(InEntity:entity).FindPickupEffect<public>()<decides><transacts>:pickup_effect_component        # InEntity or an ancestor
(InEntity:entity).GetActivePickupEffects<public>(Agent:agent)<transacts>:[]pickup_effect_component
(InEntity:entity).EndPickupEffectsFor<public>(Agent:agent):int                                   # number ended

# StageKit
pickup_stage_signal<public> := enum:
    Activate
    Deactivate

pickup_stage_scope<public> := enum:
    SourceRoot
    SourceScope
    World

pickup_stage_target_tag<public> := class(tag):

pickup_stage_target_component<public> := class<final_super>(component):
    Group<public>:string
    Hold<public>(Signal:pickup_stage_signal, Activator:?agent):void
    Release<public>(Signal:pickup_stage_signal):void
    Pulse<public>(Signal:pickup_stage_signal, Activator:?agent):void
    IsHeld<public>(Signal:pickup_stage_signal)<decides><transacts>:void

pickup_stage_signal_component<public> := class<final_super>(component):
    Group<public>:string
    Signal<public>:pickup_stage_signal
    Scope<public>:pickup_stage_scope
    RevertOnEnd<public>:logic
    Apply<public>(Activator:?agent):void
    Revert<public>():void
    GetTargetCount<public>()<transacts>:int

(InEntity:entity).FindTopEntity<public>()<transacts>:entity   # the ancestor directly under the simulation entity (top-level entity)

# HudKit (uses WidgetSystem and WidgetSystem.CardKit. WidgetSystem knows nothing about PickupSystem)
pickup_effect_hud_style<public> := struct:                    # look and motion (HudKit under "Settings" above)
pickup_effect_hud_component<public> := class<final_super>(player_widget_component):
    ShowToasts<public>:logic
    ShowEffectList<public>:logic
    var Style<public>:pickup_effect_hud_style
    ShowToastFor<public>(Agent:agent, Card:widget_card):void                         # show a toast from code
    TrackEffectFor<public>(Agent:agent, Effect:pickup_effect_component):void        # list an effect whose notification does not arrive
(Effect:pickup_effect_component).GetPickupEffectCard<public>(?FallbackColor:color = NamedColors.SkyBlue)<transacts>:widget_card   # the root's card_info_component (without it, name = EffectId)
```

## Migration notes (2026-11-09: tiers, endless effects, single-use)
- Added: `pickup_effect_stack_mode.Tier` (picking the same effect up again raises the tier by 1 and resets the time, up to `MaxTier`), and `MaxTier` / `GetTier` / `RaiseTier` / `TierChangedEvent` / `IsEndless` / `IsPersistent` on `pickup_effect_component`. The parts inside read the tier with `Entity.FindPickupEffect[].GetTier()` (no part changes its strength by tier yet; only the mechanism exists).
- Added: `Entity.GrantPersistentPickupEffect(Agent, Prefab, Origin, Source)` (lasts until `End` / `EndPickupEffectsFor` regardless of the effect's `DurationSeconds`; e.g. an effect held from the start of a stage). `pickup_effect_grant_component.Persistent`.
- Added: when a part inside sends `activation_finished_event` (ActivationSystem) upward, the effect ends on the next frame (sent by the single-use grants of CharacterSystem's CellKit).
- Behavior change: a value was added to `pickup_effect_stack_mode`, so your code that enumerates every value in a `case` must add `Tier`.
- Adding a named optional parameter to an extension method made calls that pass it by name a type error (V3509), so the parameters of `GrantPickupEffect` were left unchanged and a separate function was added.

## Requirements, caveats and limits
- One `player_manager_component` is required in the scope or the world (to create effects under the agent's slot).
- Effect parts must revert both on the deactivate signal and in `OnEndSimulation` (an effect can disappear without a deactivate signal when the owner leaves or through `EndPickupEffectsFor`). The BuffKit and StageKit parts do.
- When the game flow resets (starting a map, clearing it, returning to the lobby), end all of the agent's effects with `EndPickupEffectsFor(Agent)` and bring orbs back with `Restore` (in the author's game, the component that switches the game state calls these, and the orb side implements a restorable interface).
- Stage signals act on the shared stage (other players on the same map see the hidden platforms too). Targets are searched once when the signal is sent.
- At most one part of each type per entity (an editor rule). To use the same part twice in one effect, split them onto child entities.
- ⚠ Unverified (in UEFN):
  - Whether the root's `pickup_effect_component` can read the marker (`pickup_effect_grant_component`) on the next frame when the prefab is created with `Prefab{}` and added under the slot (PickupEffectComponent.verse).
  - Whether a `text_hud_component` inside the effect entity shows only to the owner (WidgetSystem's "where there is an owner, Everyone = the owner").
  - HudKit: whether the toast pop, the slot in / out and the sideways shift animate without flicker using per-frame `SetDesiredSize` / `SetTextSize` / opacity and re-placing the canvas_slot. Whether `canvas_slot`'s `Offsets` (using `Left` / `Top` as a position offset with a point anchor) behave as expected. Whether the slot background (a `color_block` with `VerticalAlignment = Bottom` in an `overlay_slot`, height changed every frame) shrinks from the bottom. `texture_block` cannot be faded, so it is hidden while thinner than half (blinking also toggles the image).
  - HudKit: whether the `text_block` shadow (`DefaultShadowOffset` / `SetShadowOpacity`) shows. The slot's first letter is the first UTF-8 character (continuation bytes 0x80-0xBF are joined); whether katakana shows without garbling.
  - HudKit: whether `pickup_effect_owner_event` reaches a HUD inside a loadout under the slot (SendDown from the slot entity).
  - Whether hiding the orb's look with `mesh_component.Disable` hides it from everyone.

## Verifying
- Test: `pickup_system_test_component` in `_Test/PickupSystemTest/`. Place one entity with `player_manager_component` and one with this component (both top-level) and start with one player. It checks the effect lifetime (activate signal on the next frame, owner, tag, deactivate signal and removal by time, Instant), stacking (Extend, Stack with MaxStacks, Replace, `EndPickupEffectsFor`), the orb (`TryPickup`, returning, not returning, `Restore`, signals, `RequireGroupMember`) and the StageKit (only targets of the Group; with two overlapping effects, revert after both end). About 4 seconds. Results appear in the output log as `[TEST] PickupSystem`.
- The HudKit HUD has no automated test (screen look). Use MCPSystem's PickupKit (`pickup.pick` / `pickup.grant` / `pickup.effects` / `pickup.end_effects`) to pick up and check the screen.
- Custom character buffs: `_Test/CharacterSystemTest/CharacterBuffTest.verse` (`character_buff_test_component`).
