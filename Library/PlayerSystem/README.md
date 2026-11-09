# PlayerSystem

The System that deals with participating players. `player_manager_component` creates a slot entity for every player who joins, and the other Systems create one view per player under that slot (`player_view_set`) for per-player processing. It also provides the base class and attach / remove helpers for player state tags (PlayerTags), `FindOwningPlayer`, which decides "whose is it" from the entity tree (PlayerOwner), conversion between a body entity and its player (PlayerBody), `player_attach_component`, which attaches things to a player's body, and reactions to Fortnite character motion (MotionKit).

## Setup (placement)

| component | Where to place | What it does |
|---|---|---|
| `player_manager_component` | One per scope (or world). Other parts find it with `FindScopedComponent` | Creates a slot entity as a child for every player who joins and removes it when they leave. Notifies the whole scope of joins and leaves |
| `player_slot_component` | Created at runtime by `player_manager_component` (not placed in the editor) | Represents one participating player. Views and loadouts are created as children of this entity |
| `player_attach_component` | Wherever the activation signal reaches (anywhere if `ActiveOnBegin`). Placed inside a loadout prefab, it attaches only to the owner | Creates a `Prefab` on the player's body and moves it with the body. Reattaches when the body changes on respawn |
| `player_group_component` | Anywhere. Mutually exclusive groups (one per player) are placed as siblings under the same parent | On an activation signal that tells who caused it (a selection menu's `Targets` etc.), adds that player to the group. On join, sends that player's activation signal to `Targets`. The place that records "who chose" (showing UI only to those who chose is WidgetSystem's `widget_show_in_group_component`) |
| `player_count_condition_component` (ConditionKit) | Directly under the entity of a `game_transition_component` or `condition_all` / `condition_any` | Satisfied when the number of participants is `MinPlayerCount` or more |
| `player_group_count_condition_component` (ConditionKit) | Same as above. Choose the group to count in `Group` (if empty, the group on this entity or its ancestors) | Satisfied when the member count of the group (`player_group_component`) is between `MinMemberCount` and `MaxMemberCount` (someone in the group, everyone gathered, nobody left) |
| `player_motion_trigger_component` (MotionKit) | Anywhere. Inside a loadout prefab it watches only the owner; somewhere without an owner it watches everyone in the scope | Each time a momentary character motion (jump, landing, etc.) happens, sends the activation signal (with who caused it) to `Targets` and sends `player_motion_event` upward |
| `player_state_trigger_component` (MotionKit) | Inside a loadout prefab (somewhere with an owner). Does nothing without an owner | Sends the activation signal to `Targets` when the owner's character enters `State` and the deactivation signal when it leaves |
| `player_state_condition_component` (MotionKit) | Inside a loadout prefab, directly under the entity of an `ability_grant_condition_component` / `game_transition_component` / `condition_all` / `condition_any` | Satisfied while the owner's character is in `State` |

`player_view_set` and `player_tag_holder` are not components but classes held in a component's field.

Example: "start when 2 players have gathered" and "show a marker above the head on every jump"
```
Game (player_manager_component)
└ Waiting (game_node_component)
  └ Next (game_transition_component)
    └ 2 or more players (player_count_condition_component, MinPlayerCount = 2)

Loadout prefab (loadout_component's Prefab)
└ Jump (player_motion_trigger_component, Motion = Jumped)
  └ Marker (player_attach_component, AttachToEveryone = on)
```
At runtime, one slot (`player_slot_component`) per player is created under the `player_manager_component` entity, and the views and loadouts of each System are created under it.

## Settings (@editable)
- `player_count_condition_component.MinPlayerCount : int = 2` — satisfied when at least this many players participate (1-100).
- `player_group_count_condition_component.Group : ?entity = false` — the group whose members are counted (an entity with `player_group_component`). If empty, the group on this entity or its ancestors (`FindAncestorGroup`).
- `player_group_count_condition_component.MinMemberCount : int = 1` — satisfied when the group has at least this many members (0-100).
- `player_group_count_condition_component.MaxMemberCount : int = 100` — satisfied when the group has at most this many members (0-100; the default 100 means no upper limit). `Min 0, Max 0` means "nobody in the group".
- `player_attach_component.Prefab : concrete_subtype(entity) = entity` — the entity (prefab) attached to the body. Left at the default, an empty entity.
- `player_attach_component.OffsetCm : vector3 = vector3{Up := 200.0}` — offset from the body's origin (centimeters; Forward, Left, Up).
- `player_attach_component.Visibility : player_attach_visibility = Everyone` — whom it is shown to. `Everyone`: all players, `OwnerOnly`: only the player it is attached to, `OthersOnly`: everyone except that player.
- `player_attach_component.AttachToEveryone : logic = true` — when on, attaches to everyone on activation (including later joins). Somewhere with an owner, only the owner. When off, only to players chosen with `AttachTo`.
- `player_attach_component.ActiveOnBegin : logic = false` — when on, attaches from the start of the game. When off, from the activation signal.
- `player_attach_component.RefreshSeconds : float = 1.0` — interval of the patrol that checks whether the body changed (respawn etc.) (0.1-10 seconds).
- `player_group_component.LeaveOthers : logic = true` — when on, joining leaves the other groups under the same parent (choosing again cancels the previous choice).
- `player_group_component.Targets : []entity = array{}` — entities that receive the activation signal (`activated_by_agent_event`) of a player who joined. When a member chooses again, only the signal is resent (warping each round etc.).
- `player_motion_trigger_component.Motion : player_motion = Jumped` — the motion to watch.
- `player_motion_trigger_component.Targets : []entity = array{}` — entities that receive the activation signal (reaches the entity and its descendants). If empty, sent to this entity and its descendants.
- `player_motion_trigger_component.CooldownSeconds : float = 0.0` — time during which the same player's next motion is ignored (0-60 seconds). 0 ignores nothing.
- `player_state_trigger_component.State : player_motion_state = InAir` — the state to watch.
- `player_state_trigger_component.Targets : []entity = array{}` — entities that receive the signals. If empty, sent to the child entities of this entity (not to its own entity).
- `player_state_condition_component.State : player_motion_state = Crouching` — the state that satisfies.

Values of `player_motion`: `Jumped` / `Landed` / `LeftGround` / `CrouchStarted` / `CrouchEnded` / `SprintStarted` / `SprintEnded` / `Eliminated` / `Damaged`.
Values of `player_motion_state`: `OnGround` / `InAir` / `Falling` / `Crouching` / `Sprinting` / `Gliding` / `InWater` / `Flying` / `Down` (downed but not out).

## Events
- `player_added_event` (scene_event, SendScoped: the whole scope, or the whole world if there is no scope): `Manager : player_manager_component`, `Agent : agent`. Sent by `player_manager_component` after a player joins and the slot is created (`FindSlot` succeeds on the receiving side). Not consumed.
- `player_removed_event` (scene_event, SendScoped): `Manager : player_manager_component`, `Agent : agent`. Sent after a player leaves and the slot is removed (`FindSlot` fails on the receiving side). Not consumed.
- `player_event` (scene_event, SendDown): `Sender : component`, `Event : scene_event`. Wrapper that passes a notification between the views of the same player. Sent down from the slot's entity with `SendToPlayer`. Receivers are the views under the same player's slot. Not consumed.
- `player_view_source_event` (scene_event, SendDown): `Event : scene_event`. Wrapper that passes a notification from the component that created the view to the view. Sent with `player_view_set.SendToViews`. Not consumed.
- `player_motion_event` (scene_event, SendUp): `Trigger : player_motion_trigger_component`, `Agent : agent`, `Motion : player_motion`. From the `player_motion_trigger_component` entity to the root. Receivers are ancestor components. Not consumed.
- listenables (cannot be Signaled from outside)
  - `player_manager_component.PlayerAddedEvent : listenable(player)` — delivered after a player joins and the slot is created.
  - `player_manager_component.PlayerRemovedEvent : listenable(player)` — delivered after a player leaves and the slot is removed.
  - `player_attach_component.AttachedEvent : listenable(tuple(agent, entity))` — delivered with (the player, the attached entity) on attach.
  - `player_attach_component.DetachedEvent : listenable(agent)` — delivered with the player on detach.
  - `player_group_component.JoinedEvent : listenable(agent)` / `LeftEvent : listenable(agent)` — delivered with the player on joining / leaving the group (chose another group, `Leave`, `Clear`, left the game).
  - `player_motion_trigger_component.MotionEvent : listenable(tuple(agent, player_motion))` — delivered with (the player, the motion) each time `Motion` happens.
- Sent: `player_motion_trigger_component` sends `activated_by_agent_event` (`SendActivatedBy`) to `Targets` (its own entity if empty). `player_state_trigger_component` sends `activated_event` / `deactivated_event` (without who) to `Targets` (the child entities if empty).
- `player_group_joined_event` / `player_group_left_event` (scene_event, SendDown: from the group's entity downward): `Group : player_group_component`, `Agent : agent`. When a player joins / leaves the group. Not consumed.
- Received: `player_view_set.HandleActivation` and `player_attach_component` receive `activated_event` / `deactivated_event`. `player_group_component` adds the player on an `activated_event` that tells who, and removes that player (everyone if unknown) on `deactivated_event`. `player_count_condition_component` receives `player_added_event` / `player_removed_event`. `player_group_count_condition_component` subscribes to the group's `JoinedEvent` / `LeftEvent` rather than a scene_event (reaches it even when the group is not an ancestor).

## Tags
- `player_state_tag` — abstract base of tags that represent player state. A System that holds a state creates a subclass. A tag attached via a subclass is also found by the base type (`Agent.HasPlayerTag[player_state_tag]` means "in some state").
- `controlled_movement_tag` — tag attached while an ability or similar directly controls the player's movement (velocity / position) (a `player_state_tag` subclass). Other forces (gravity, hover, etc.) do not overwrite the velocity of someone carrying this. Attach a subclass when you write your own movement-controlling ability.
- `player_tag_holder` — the attach / remove helper. On entering the state `Tags.Add(Agent, xxx_tag{})` (or `Set`), on leaving `Tags.Remove(Agent)`, when stopping (`OnEndSimulation`, an ability's `defer`) `Tags.RemoveAll()`. It remembers the `tag_key` returned by `AddTag` per player and removes only what it attached, so tags of the same type attached by other parts are left alone. If the same holder already attached a tag to the same player, `Add` does nothing.
- Tags go on the agent, not the character's entity (they survive before spawn, while downed and after respawn).
- Checkers use `Agent.HasPlayerTag[tag type]` (`ContainsTag` inside). PlayerSystem itself attaches no tags.

## Owners
- Entities under a player's slot (the entity of a `player_slot_component`) belong to that player (they have an owner). `InEntity.FindOwningPlayer[]` returns the player of the first slot found on itself or its ancestors, and fails when not under a slot. `FindOwningSlot[]` returns the slot component.
- The main way to put parts under a slot is LoadoutSystem's `loadout_component` (creates a prefab per player and places it under the slot). `player_view_set` views are also created under the slot.
- Where `FindOwningPlayer[]` succeeds, some parts affect only the owner instead of everyone: ability granting (AbilitySystem), widgets and the part that hides the standard HUD (WidgetSystem), `item_grant_component` (ItemSystem), custom characters (CharacterSystem), the `Owner` of device bridges (FNDeviceSystem), and the following parts of this System.
  - `player_attach_component` — somewhere with an owner, attaches only to the owner on activation (when `AttachToEveryone` is on). Not to everyone, not to later joins.
  - `player_motion_trigger_component` — somewhere with an owner, watches only the owner. Without an owner, watches everyone in the scope (including later joins).
  - `player_state_trigger_component` / `player_state_condition_component` — do not work without an owner ("No owner" appears in the output log).
- New parts should follow the same rule: when `FindOwningPlayer[]` succeeds, affect only the owner.

## Public API
```verse
# PlayerManagerComponent / PlayerSlotComponent
player_added_event<public> := class(scene_event):
    Manager<public>:player_manager_component
    Agent<public>:agent

player_removed_event<public> := class(scene_event):
    Manager<public>:player_manager_component
    Agent<public>:agent

player_manager_component<public> := class<final_super>(component):
    PlayerAddedEvent<public><final>:listenable(player)
    PlayerRemovedEvent<public><final>:listenable(player)
    GetPlayerCount<public>()<reads>:int                                   # Number of direct-child slots
    GetSlots<public>()<reads>:[]player_slot_component                     # Order is undefined
    FindSlot<public>(Player:player)<decides><reads>:player_slot_component # Fails before the join is processed and after leaving

player_slot_component<public> := class<final_super>(component):
    Player<public>:player

# PlayerViewSet
player_event<public> := class(scene_event):
    Sender<public>:component
    Event<public>:scene_event

player_view_source_event<public> := class(scene_event):
    Event<public>:scene_event

player_view_set<public> := class<unique>:
    IsActive<public>()<decides><transacts>:void
    GetViews<public>()<transacts>:[]entity                                # Only views in the world (excludes players who left and HideFor)
    Activate<public>(Owner:entity, MakeView:type{_(:entity, :player_slot_component):component}, ?Everyone:logic = true, ?ViewFilter:?player_view_filter = false):void   # Everyone = false: only players chosen with ShowFor. Creates only for players the ViewFilter allows
    Deactivate<public>():void
    HandleActivation<public>(SceneEvent:scene_event, Owner:entity, MakeView:type{_(:entity, :player_slot_component):component}):void
    FindViewFor<public>(Agent:agent)<decides><transacts>:entity
    HideFor<public>(Agent:agent):void
    ShowFor<public>(Agent:agent):void                                     # While active, creates the view if there is none
    SendToViews<public>(SceneEvent:scene_event):void                      # Wrapped in player_view_source_event

(View:component).SendToPlayer<public>(SceneEvent:scene_event):void        # Wrapped in player_event, down from the same player's slot
(View:component).FindViewSlot<public>()<decides><transacts>:player_slot_component

# PlayerSubscription
(InEntity:entity).SubscribePlayers<public>(OnAdded:type{_(:player):void}, OnRemoved:type{_(:player):void}):?cancelable

# PlayerOwner
(InEntity:entity).FindOwningPlayer<public>()<decides><transacts>:player              # The player of the slot on itself or an ancestor
(InEntity:entity).FindOwningSlot<public>()<decides><transacts>:player_slot_component

# PlayerBody
(Agent:agent).FindPlayerEntity<public>()<decides><transacts>:entity       # Fails when there is no character
(Body:entity).FindPossessingAgent<public>()<decides><transacts>:agent     # The Agent of the possessable_component
(Body:entity).FindPlayer<public>()<decides><transacts>:player             # Fails when the controller is not a player
(Body:entity).FindFortCharacter<public>()<decides><transacts>:fort_character

# PlayerTags
player_state_tag<public> := class<abstract>(tag):
controlled_movement_tag<public> := class(player_state_tag):
(Agent:agent).HasPlayerTag<public>(TagType:castable_subtype(tag))<decides><reads>:void

player_tag_holder<public> := class:
    Add<public>(Agent:agent, Tag:tag)<transacts>:void
    Remove<public>(Agent:agent)<transacts>:void
    Set<public>(Agent:agent, On:logic, Tag:tag)<transacts>:void
    Has<public>(Agent:agent)<decides><reads>:void
    RemoveAll<public>()<transacts>:void

# PlayerAttachComponent
player_attach_visibility<public> := enum:
    Everyone
    OwnerOnly
    OthersOnly

player_attach_component<public> := class<final_super>(component):
    Prefab<public>:concrete_subtype(entity)
    OffsetCm<public>:vector3
    Visibility<public>:player_attach_visibility
    AttachToEveryone<public>:logic
    ActiveOnBegin<public>:logic
    RefreshSeconds<public>:float
    AttachedEvent<public><final>:listenable(tuple(agent, entity))
    DetachedEvent<public><final>:listenable(agent)
    Activate<public>():void                                     # Does nothing if already active
    Deactivate<public>():void                                   # Detaches from everyone
    AttachTo<public>(Agent:agent):entity                        # Returns the entity if already attached. Activates if not active
    DetachFrom<public>(Agent:agent):void
    DetachAll<public>():void
    FindAttached<public>(Agent:agent)<decides><transacts>:entity
    IsAttachedTo<public>(Agent:agent)<decides><transacts>:void

# ConditionKit
player_count_condition_component<public> := class<final_super>(condition_component):
    MinPlayerCount<public>:int

player_group_count_condition_component<public> := class<final_super>(condition_component):
    Group<public>:?entity                                       # If empty, the group on this entity or its ancestors
    MinMemberCount<public>:int
    MaxMemberCount<public>:int
    FindTargetGroup<public>()<decides><transacts>:player_group_component   # The group being counted. Fails before start or when not found

# MotionKit
player_motion<public> := enum:
    Jumped
    Landed
    LeftGround
    CrouchStarted
    CrouchEnded
    SprintStarted
    SprintEnded
    Eliminated
    Damaged

player_motion_state<public> := enum:
    OnGround
    InAir
    Falling
    Crouching
    Sprinting
    Gliding
    InWater
    Flying
    Down

player_motion_event<public> := class(scene_event):
    Trigger<public>:player_motion_trigger_component
    Agent<public>:agent
    Motion<public>:player_motion

player_motion_trigger_component<public> := class<final_super>(component):
    Motion<public>:player_motion
    Targets<public>:[]entity
    CooldownSeconds<public>:float
    MotionEvent<public><final>:listenable(tuple(agent, player_motion))

player_view_filter<public> := interface:                       # Whom a player_view_set may create a view for
    AllowsView<public>(Agent:agent)<decides><transacts>:void

player_group_joined_event<public> := class(scene_event):
    Group<public>:player_group_component
    Agent<public>:agent
player_group_left_event<public> := class(scene_event):
    Group<public>:player_group_component
    Agent<public>:agent

player_group_component<public> := class<final_super>(component):
    LeaveOthers<public>:logic
    Targets<public>:[]entity
    JoinedEvent<public><final>:listenable(agent)
    LeftEvent<public><final>:listenable(agent)
    Join<public>(Agent:agent):void                               # Leaves the sibling groups, joins, signals Targets. If already a member, only the signal
    Leave<public>(Agent:agent):void
    Clear<public>():void
    IsMember<public>(Agent:agent)<decides><transacts>:void
    GetMembers<public>()<transacts>:[]agent                      # In join order
    GetMemberCount<public>()<transacts>:int
    GetMemberPlayerEntities<public>()<transacts>:[]entity       # Bodies of members who currently have a character (FindPlayerEntity). Members without a body are excluded

(InEntity:entity).FindAncestorGroup<public>()<decides><transacts>:player_group_component   # The nearest group on InEntity or its ancestors

player_state_trigger_component<public> := class<final_super>(component):
    State<public>:player_motion_state
    Targets<public>:[]entity
    IsActive<public>()<decides><transacts>:void                 # Succeeds if the owner is currently in State

player_state_condition_component<public> := class<final_super>(condition_component):
    State<public>:player_motion_state
```

## Requirements, caveats and limits
- `player_view_set`, `player_count_condition_component`, `player_attach_component` (with `AttachToEveryone` and no owner), `player_motion_trigger_component` (without an owner) and the other Systems that use them need one `player_manager_component` in the scope (or world). If none is found, `player_view_set.Activate` counts as activated but creates no views (and does not wait for joins; `[player_view_set] No player_manager_component found...` appears once in the output log).
- On leaving, `player_manager_component` removes the slot entity and the views under it leave the world too (the view's component goes through `OnEndSimulation`). `player_view_set` looks only at views in the world in `GetViews` / `FindViewFor` / `SendToViews` and drops the views of players who left on the manager's `PlayerRemovedEvent`. A view component resets its per-player state when stopping (`OnEndSimulation`) (the "ready" of `player_ready_view_component` etc.). ⚠ Unverified: that `GetSimulationEntity` fails for a view under a removed slot (the digest says "fails when not in the scene").
- Slots of players present when the simulation starts are created inside `player_manager_component`'s `OnBeginSimulation`, and the notifications at that time (both scene event and event) do not reach anyone not yet subscribed. Code that subscribes later should first look at who is present with `GetSlots`, then wait for `PlayerAddedEvent`.
- `SubscribePlayers` calls `OnAdded` for players already present inside the function (before it returns). On an entity whose playspace cannot be obtained it returns false and calls nothing. Cancel the return value in `OnEndSimulation`. If you only want one slot per world, use `player_manager_component`.
- `player_attach_component` does not parent to the body entity; it creates the entity as a child of its own entity and bases it on the body with `SetOrigin(entity_origin{Entity := body})` (the body's contents are not touched). Only one per player. Hidden while there is no body, and reattached by the patrol every `RefreshSeconds`. `OthersOnly` shows to the participants of the scope's `player_manager_component` minus the player.
- `player_count_condition_component`, `player_attach_component` and `player_view_set` all remember the first `player_manager_component` found in the scope and keep using it (SceneGraphSystem's `ResolveScopedComponent`). `player_attach_component` forgets it when stopping, `player_view_set` on `Deactivate`.
- `player_group_count_condition_component` finds and subscribes to the group at start. If no group is found, "No player_group_component found" appears in the output log and the condition is never satisfied. To count a group created at runtime, create the group first and then add the condition.
- The MotionKit parts inspect the character every frame (`TickEvents.PrePhysics`). When the character changes on respawn they resubscribe. `Landed` / `LeftGround` are decided from the change in being on the ground, and the `Sprinting` state is remembered from the `SprintedEvent` notification. `player_state_trigger_component` sends the activation signal right away if already in `State` at start, and the deactivation signal if in `State` when stopping.
- ⚠ Unverified (PlayerTags.verse): whether adding / removing tags on an agent and `ContainsTag` work in UEFN 43.00 (in the digest, agent derives from entity and entity is has_tags). Checked by `_Test/PlayerSystemTest`.
- ⚠ Unverified (PlayerAttachComponent.verse): whether an entity attached to the body with `entity_origin` follows the body's facing and crouching.

## Verifying
- Test: `player_system_test_component` in `_Test/PlayerSystemTest/`. Place one entity with `player_manager_component` and one with this component, and start with at least one player (waits up to 10 seconds for a join; finishes on the next frame if players are present). It checks slots (`GetPlayerCount` / `GetSlots` / `FindSlot`), `player_count_condition_component`, `player_view_set` (`Activate` / `Deactivate` / `GetViews` / `FindViewSlot`), `SubscribePlayers`, tags (`player_tag_holder` / `HasPlayerTag`; finding a subclass tag by the base type, tags of another holder remain), groups (`Join` / `Leave` / `GetMemberCount` / `GetMemberPlayerEntities` / `FindAncestorGroup`) and `player_group_count_condition_component` (counting an ancestor group, at least one / nobody, the count of `ChangedEvent`). Results are in the output log under `[TEST] PlayerSystem`.
- `player_attach_component`, MotionKit, `FindOwningPlayer`, PlayerBody and the signals of `player_group_component` (`Targets`, `LeaveOthers`) are not checked by this test. `FindOwningPlayer` is used by `_Test/LoadoutSystemTest/`.
- Samples: `_Samples/ScopeSample/` (what `FindScopedComponent[player_manager_component]` finds). For how to use `player_view_set`, see `_Samples/AbilitySample/`, `_Samples/WidgetSample/` (also `SendToPlayer`), `_Samples/InputSampleExperimentalKit/` and `_Samples/VirtualPointerSampleExperimentalKit/`. Samples whose name ends in `ExperimentalKit` are distributed only to projects with "include experimental" turned on in VerseShare.
