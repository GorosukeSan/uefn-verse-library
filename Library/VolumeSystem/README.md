# VolumeSystem

A System that detects players entering and leaving a box- or cylinder-shaped volume and notifies about it. `player_volume_component` only notifies; what happens inside (conditions, activation, screens) is decided by other components placed on the same entity or an ancestor. Players inside get the `in_volume_tag`.

## Placement

| component | Where to place | What it does |
|---|---|---|
| `player_volume_component` | the entity that anchors the volume (the center of the bottom face is this entity's position; no mesh is needed if you do not want a visual) | while active, checks entries and exits every `PollIntervalSeconds` seconds and sends `player_volume_entered_event` / `player_volume_exited_event` upward only when something changed |
| `player_in_volume_condition_component` (ConditionKit) | directly under the entity of a `game_transition_component` or `condition_all` / `condition_any`. Place the volume under it or pick it with `Volume` | satisfied when at least `MinPlayers` players are inside (several volumes are summed) |
| `volume_activation_component` (ActivationKit) | the same entity as `player_volume_component`, or an ancestor | sends an activation signal to `Targets` (the child entities when empty) when the first player enters, and a deactivation signal when the last one leaves |
| `widget_show_in_volume_component` (WidgetKit) | the same entity as `player_volume_component`, or an ancestor. A `player_widget_component` subclass (`Audience = Chosen`) on the same entity | shows every widget on the same entity to the player while inside, and hides them when they leave |

Example: "go to the next node when someone enters the goal" and "a gadget that runs only while someone is there"
```
Node (game_node_component)
└ Next (game_transition_component)
  └ At least 1 player in the goal (player_in_volume_condition_component)
    └ Goal (player_volume_component)

Room (player_volume_component + volume_activation_component)
└ Gadget (a component driven by the activation signal)
```

## Settings (@editable)
- `player_volume_component.Shape : player_volume_shape = player_volume_shape.Box` — shape of the volume. `Box` is a width x depth x height box, `Cylinder` is an upright cylinder whose diameter is the width.
- `player_volume_component.WidthCm : float = 100.0` — width of the volume (forward/back, cm, at least 1). Multiplied by the entity's Scale. The diameter for a cylinder.
- `player_volume_component.DepthCm : float = 100.0` — depth of the volume (left/right, cm, at least 1). Multiplied by Scale. Unused for a cylinder.
- `player_volume_component.HeightCm : float = 100.0` — height of the volume (cm, at least 1). The bottom face is at the entity's position. Multiplied by Scale.
- `player_volume_component.HeightMarginCm : float = 100.0` — extra margin added above and below the volume (cm, 0–2000). A character's position is the middle of its body, so use about 300 for a thin floor-like volume.
- `player_volume_component.PollIntervalSeconds : float = 0.25` — interval between checks (seconds, 0.05–10). Shorter notices sooner but costs more.
- `player_volume_component.ActiveOnBegin : logic = true` — when on, checks from the start of the simulation. When off, from the activation signal.
- `player_in_volume_condition_component.MinPlayers : int = 1` — satisfied when at least this many players are inside (1–100).
- `player_in_volume_condition_component.Volume : ?entity = false` — the volume to watch (an entity with `player_volume_component`). When empty, counts the notifications that reach this entity from volumes on it or its descendants.
- `volume_activation_component.Targets : []entity = array{}` — the entities to signal (the entity and its descendants receive it). When empty, sends to this entity's child entities. In either case, entities carrying `player_volume_component` are skipped.

## Events
- `player_volume_entered_event` (scene_event, SendUp): `Volume : player_volume_component`, `Agent : agent`. From the volume's entity to the root. Receivers are components on the same entity and ancestors (Kits, your components). Not consumed. Receivers tell volumes apart with `Volume` (for only the volume on your own entity, `Entered.Volume.Entity = Entity`).
- `player_volume_exited_event` (scene_event, SendUp): same fields, direction and receivers as entered. Sent when a player leaves, their character disappears, they leave the game, or the volume stops.
- listenable (cannot be signaled from outside)
  - `player_volume_component.PlayerEnteredEvent : listenable(agent)` — fires with the player each time someone enters.
  - `player_volume_component.PlayerExitedEvent : listenable(agent)` — fires with the player each time someone leaves (also for everyone inside when the volume stops).
- Sent: `volume_activation_component` sends `SendActivatedBy(that player)` (`activated_by_agent_event`) when the first player enters and `deactivated_event` when the last one leaves.
- Received: `player_volume_component` takes `activated_event` (start checking) / `deactivated_event` (stop). The three Kits take the entered / exited notifications.

## Tags
- `in_volume_tag` (a `player_state_tag` subclass): `player_volume_component` attaches it to the player (agent) while inside. Removed when they leave or the volume stops. It does not say which volume (it goes through `player_tag_holder`, so tags attached by other volumes stay).
- Other Systems check with `Agent.HasPlayerTag[in_volume_tag]`. When you need to know which volume, use `player_volume_component.IsInside[Agent]`.

## Public API
```verse
player_volume_shape<public> := enum:
    Box
    Cylinder

player_volume_entered_event<public> := class(scene_event):
    Volume<public>:player_volume_component
    Agent<public>:agent

player_volume_exited_event<public> := class(scene_event):
    Volume<public>:player_volume_component
    Agent<public>:agent

player_volume_component<public> := class<final_super>(component):
    Shape<public>:player_volume_shape
    WidthCm<public>:float
    DepthCm<public>:float
    HeightCm<public>:float
    HeightMarginCm<public>:float
    PollIntervalSeconds<public>:float
    ActiveOnBegin<public>:logic
    PlayerEnteredEvent<public><final>:listenable(agent)
    PlayerExitedEvent<public><final>:listenable(agent)
    Activate<public>():void                                 # does nothing if already checking
    Deactivate<public>():void                               # sends "exited" for everyone inside and empties
    IsActive<public>()<decides><transacts>:void
    GetAgentsInside<public>()<transacts>:[]agent            # order is unspecified
    GetInsideCount<public>()<transacts>:int
    IsInside<public>(Agent:agent)<decides><transacts>:void
    AwaitLeft<public>(Agent:agent)<suspends>:void           # returns at once if not inside now
    Contains<public>(Position:vector3)<decides><transacts>:void   # succeeds if the world position (cm) is inside the current volume

in_volume_tag<public> := class(player_state_tag):

# ConditionKit
player_in_volume_condition_component<public> := class<final_super>(condition_component):
    MinPlayers<public>:int
    Volume<public>:?entity

# ActivationKit
volume_activation_component<public> := class<final_super>(component):
    Targets<public>:[]entity
    IsOccupied<public>()<decides><transacts>:void           # succeeds if someone is inside now

# WidgetKit
widget_show_in_volume_component<public> := class<final_super>(component):
```

## Requirements, caveats and limits
- One `player_manager_component` (PlayerSystem) is needed in the scope (or the world); it is remembered once found.
- How entries are detected: (1) entities overlapping this entity's mesh are queried with `FindOverlapHits`, and the player is taken from the `possessable_component`'s Agent. (2) Players not found that way have their character position compared with the volume (the code records that the position check is confirmed in UEFN). Either hit means inside.
- ⚠ Unverified (`PlayerVolumeComponent.verse`): whether a player's character entity appears in the overlap results and an agent can be read from `possessable_component`. Even if not, the position check finds them.
- The volume is multiplied by the entity's Scale, but rotation is ignored.
- `volume_activation_component` counts the notifications that reach this entity from volumes on it or its descendants (summed when there are several). It does not send the deactivation signal to the volume's entity because the volume would stop and no longer check.
- When `widget_show_in_volume_component` shows a `Mode = Menu` widget and the player closes it with the close button, it is not shown again while they stay in the volume (re-entering shows it again).
- `widget_show_in_volume_component` uses WidgetSystem.

## Verifying
- Test: `volume_system_test_component` in `_Test/VolumeSystemTest/`. Place one entity with `player_manager_component` and one with this component, and start with 1 player (standing on the ground). It builds a volume (600 x 600 x 600 cm) at the player's position and checks `Contains`, "entered" (`PlayerEnteredEvent`, `IsInside`, `GetInsideCount`, `in_volume_tag`), that `player_in_volume_condition_component` is satisfied and that `volume_activation_component` sends the activation signal to its children. It then moves the volume far away and checks "exited" (`PlayerExitedEvent`, the tag is removed, the condition is no longer satisfied, the deactivation signal, the volume keeps running) and `Deactivate`. It finishes in a few seconds. Results go to the output log as `[TEST] VolumeSystem`.
- There is no sample (`_Samples/`).
