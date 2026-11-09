# CheckpointSystem

A System that makes platforms (checkpoints) you can pass through from below and stand on, but cannot drop down from. It notifies the whole zone who stepped on and who left, and tags the player while they stand on one. Use it for waypoints and respawn points in games where you climb upward. A part that fills energy (EnergySystem) when stepped on (EnergyKit) is included.

## Placement

| component | Where to place | What it does |
|---|---|---|
| `checkpoint_component` | the platform's entity (the same entity as a mesh with collision) | passes players moving upward from right below onto the top face, checks every frame whether they stand on it, and notifies stepping on / leaving |
| `checkpoint_presence_component` (PresenceKit) | one anywhere inside the zone (the entity of `game_scope_component`) (anywhere in the world when there is no zone) | aggregates the "stepped on / left" of every checkpoint in the zone and answers who is standing where and which one they reached last |
| `checkpoint_energy_refill_component` (EnergyKit) | an entity inside the zone. The same entity as the energy to fill (`energy_component`; e.g. an ability's entity), or a separate entity without energy | every time someone steps onto any checkpoint of the zone, fills energy to full (the `energy_component` of this entity or a child; otherwise the `energy_component`s of the agent who stepped on and their items) |
| `checkpoint_factory_component` (SpawnKit) | the same entity as `spawner_component` (SpawnSystem) | makes what the spawner spawns a checkpoint the size of the reserved area |

Example: hand-placed checkpoints and the aggregator
```
Zone (game_scope_component)
├ Players (player_manager_component)
├ Presence (checkpoint_presence_component)
└ Platform (checkpoint_component + a 750 x 750 x 250 cm mesh)
```
Example: fill hover energy when stepped on (HoverSystem)
```
Zone (game_scope_component)
├ Players (player_manager_component)
├ Platform (checkpoint_component + mesh) ...
└ Hover (hover_ability_component + ability_grant_players_component + energy_component + checkpoint_energy_refill_component)
```
When the energy lives on an item or on the player (agent), place only `checkpoint_energy_refill_component` on a separate entity inside the zone (it fills the energy of the agent who stepped on and of their items. Do not place it on the item: an item's entity is inside an inventory, where zone notifications do not arrive).
To spawn through a spawner, also place a `grid_component` (GridSystem) in the zone and attach `spawner_component` + `checkpoint_factory_component` (plus `players_origin_component` to base positions on the players) to the spawner's entity. With the spawner's size set by `FootprintX` / `FootprintY` / `FootprintZ` (e.g. 3 x 3 x 1), height per level (`LevelIntervalCells`, e.g. 50) and look filling the area (`FitToArea`), you get one platform per level.

## Settings (@editable)
- `checkpoint_component.WidthCm : float = 750.0` — width of the platform along Forward (cm, 50-10000). Match the mesh size.
- `checkpoint_component.DepthCm : float = 750.0` — width of the platform along Left (cm, 50-10000).
- `checkpoint_component.ThicknessCm : float = 250.0` — thickness of the platform (cm, 10-2000).
- `checkpoint_component.ApproachCm : float = 300.0` — players moving upward from within this distance (cm, 50-1000) right below the platform are passed onto the top face.
- `checkpoint_factory_component.Prefab : concrete_subtype(entity) = entity` — the prefab used as the look (put in a mesh with collision). Left at the default entity, the checkpoint has no look.

`checkpoint_energy_refill_component` has no settings (what gets filled depends on where it is placed; see "Requirements, caveats and limits" below).

The `WidthCm`, `DepthCm` and `ThicknessCm` of checkpoints created by `checkpoint_factory_component` are the size of the area the spawner reserved (`spawn_area.GetSize()`). Size, level selection and placement are decided by the `spawner_component` settings.

## Events
- `checkpoint_reached_event` (scene_event, SendScoped: SendDown from the zone root; the whole world when there is no zone): `Checkpoint : checkpoint_component`, `Agent : agent`. Sent by `checkpoint_component` when someone steps onto the top face (whether it is the first time does not matter). Receivers: `checkpoint_presence_component`, components counting arrivals, etc. Not consumed.
- `checkpoint_left_event` (scene_event, SendScoped): `Checkpoint : checkpoint_component`, `Agent : agent`. Sent when someone leaves the top face, leaves the game, or the checkpoint is removed from the world. Not consumed.
- listenable (cannot be Signaled from outside)
  - `checkpoint_component.ReachedEvent : listenable(agent)` / `LeftEvent : listenable(agent)` — fire with the agent who stepped onto / left that checkpoint (same timing as the scene_event).
  - `checkpoint_presence_component.ReachedEvent : listenable(checkpoint_reached_event)` / `LeftEvent : listenable(checkpoint_left_event)` — the notification of any checkpoint in the zone, passed through as is.
  - `checkpoint_energy_refill_component.RefilledEvent : listenable(tuple(agent, energy_component))` — fires with (the agent who stepped on, the energy_component filled) when energy is filled (energy that was already full does not fire).
- Received: `checkpoint_presence_component` receives `checkpoint_reached_event` / `checkpoint_left_event`. `checkpoint_energy_refill_component` receives `checkpoint_reached_event`.

## Tags
- `on_checkpoint_tag` (derived from `player_state_tag`): attached to the agent by `checkpoint_component` while they stand on it. Removed when they leave, leave the game, or it stops (`OnEndSimulation`) (attached and removed through `player_tag_holder`).
- Other Systems check with `Agent.HasPlayerTag[on_checkpoint_tag]`. When you also need which checkpoint, use `checkpoint_presence_component.FindStandingCheckpoint`.

## Public API
```verse
checkpoint_reached_event<public> := class(scene_event):
    Checkpoint<public>:checkpoint_component
    Agent<public>:agent

checkpoint_left_event<public> := class(scene_event):
    Checkpoint<public>:checkpoint_component
    Agent<public>:agent

on_checkpoint_tag<public> := class(player_state_tag):

checkpoint_component<public> := class<final_super>(component):
    ReachedEvent<public><final>:listenable(agent)
    LeftEvent<public><final>:listenable(agent)
    WidthCm<public>:float
    DepthCm<public>:float
    ThicknessCm<public>:float
    ApproachCm<public>:float
    IsStanding<public>(Agent:agent)<decides><reads>:void        # up to one frame late
    GetStandingAgents<public>()<reads>:[]agent

# PresenceKit
checkpoint_presence_component<public> := class<final_super>(component):
    ReachedEvent<public><final>:listenable(checkpoint_reached_event)
    LeftEvent<public><final>:listenable(checkpoint_left_event)
    IsOnAnyCheckpoint<public>(Agent:agent)<decides><reads>:void
    FindStandingCheckpoint<public>(Agent:agent)<decides><reads>:checkpoint_component   # with overlaps, the last reached among those still stood on
    FindLastReached<public>(Agent:agent)<decides><reads>:checkpoint_component          # remembered after leaving / after it disappears
    ForgetLastReached<public>():void                                                   # forgets for everyone

# EnergyKit
checkpoint_energy_refill_component<public> := class<final_super>(component):
    RefilledEvent<public><final>:listenable(tuple(agent, energy_component))
    TryRefillFor<public>(Agent:agent):logic                     # fills as if stepped on. true when something was filled

# SpawnKit
checkpoint_factory_component<public> := class<final_super>(spawn_factory_component):
    Prefab<public>:concrete_subtype(entity)
    CreateSpawned<override>(Area:spawn_area):entity             # returns Prefab with checkpoint_component attached (size = Area.GetSize())
```

## Requirements, caveats and limits
- `checkpoint_component` needs one `player_manager_component` in the zone (`game_scope_component`; the world when there is none). The first one found is remembered; it is looked up every second until found.
- Every frame, every player in the zone is checked. Verse cannot change collision per player, so players moving upward from right below are moved onto the top face to look like they passed through the mesh.
- The checkpoints of one zone are watched together in one place (the internal `checkpoint_tracker`). At simulation start, a checkpoint registers with the tracker used by a checkpoint that started earlier in the same zone, and all of them are checked together in the `TickEvents.PrePhysics` of one of them (the one that started first). Player positions are read once per player per frame and compared with every checkpoint (previously each checkpoint read everyone's position, i.e. checkpoints x players queries. The comparison itself is still checkpoints x players). When the driving checkpoint disappears, one of the remaining ones takes over. With nested zones, only checkpoints whose nearest zone is the same are grouped.
- A player counts as standing when they are above the platform's area (with a small margin at the edges), within a certain height above the top face, and on the ground (`IsOnGround`).
- Match `WidthCm`, `DepthCm` and `ThicknessCm` to the mesh size (otherwise the look and the standable area disagree). The platform's rotation is ignored.
- What `checkpoint_energy_refill_component` fills: if this entity or a descendant has an `energy_component`, only that one (if the same entity has abilities (`ability_component` subclasses), only when someone granted one of them steps on). Otherwise, the `energy_component` attached to the agent who stepped on and every `energy_component` of their items (`FindEnergy`). Placed under a player's slot (inside a loadout, etc.), only when the owner steps on. Do not place it on an entity whose descendants include unrelated `energy_component`s (e.g. the zone root), or one of those gets filled. The reached notification travels down from the zone root, so do not place it outside the zone or inside an inventory.
- `checkpoint_presence_component` only remembers notifications; it never searches itself. Players already standing before it was placed (before simulation start) are not counted. Checkpoints spawned at runtime are counted. When standing on overlapping checkpoints at the same time, all of them are remembered per agent (leaving one of them still counts as standing on the rest; `FindStandingCheckpoint` returns the last reached among those still stood on).
- `checkpoint_factory_component` needs one `grid_component` (the spawner's requirement) and one `player_manager_component` (the requirement of `checkpoint_component`) in the zone. When spawning per level (`LevelIntervalCells` greater than 0), there is only one per level, and a level once used is not spawned again, even after it disappears, until `spawner_component.ForgetUsedLevels`.

## Verifying
- Test: `checkpoint_system_test_component` in `_Test/CheckpointSystemTest/`. Placement:
  - one entity with `player_manager_component` (in the same zone as the test entity when using a zone)
  - attach the test component to an entity near a flat floor (the player stays standing on the floor without moving)

  After checking `checkpoint_factory_component` and `spawner_component`'s level selection and the size of the created checkpoint, it waits for the first player to stand on the floor (up to 10 s) and creates a checkpoint with no look at their feet. It checks the reached notification and `IsStanding`, the left notification when the platform is moved sideways, the reached notification when it is moved back, the left notification when the platform disappears, the aggregation of `checkpoint_presence_component` (standing or not, last reached, and that leaving the later of two overlapping checkpoints still counts as standing on the earlier one), that when two checkpoints are watched together and the one that started first disappears the remaining one keeps checking, and `checkpoint_energy_refill_component` (energy on the same entity, no fill for agents not granted the ability, the energy of the agent who stepped on, `RefilledEvent`). Passing through from below is not checked automatically; a person checks it following the `[HUMAN]` steps in the log. Finishes in a few seconds. The result is `[TEST] CheckpointSystem` in the output log.
- No sample (`_Samples/`).

## Migration notes (2026-11-08)
| Old | New |
|---|---|
| `hover_ability_component.RefillOnCheckpoint` (HoverSystem) | place EnergyKit's `checkpoint_energy_refill_component` on the hover's entity (see the HoverSystem README) |
| each `checkpoint_component` checks everyone every frame | checked together in one place per zone (public API, notifications and tags are the same; placement does not change either) |
| field order `Agent`, `Checkpoint` of `checkpoint_reached_event` / `checkpoint_left_event` | `Checkpoint`, `Agent` (matching the Library-wide rule of putting the sender first. No change needed if you construct them with named fields) |
