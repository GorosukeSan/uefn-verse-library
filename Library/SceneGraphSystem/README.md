# SceneGraphSystem

A System of small Scene Graph (entity / component) helpers shared by the other Systems: find a "one per world" component from inside a scope (`game_scope_component`), find and remember it, wait until it is found, notify the whole scope, find components on direct children or the nearest ancestor, position math, grouping cancelables, removing one entry from a map, and so on.

## Setup (placement)

| component | Where to place | What it does |
|---|---|---|
| `game_scope_component` | The entity that is the root of a scope (one game or room) | Marks the scope. "One per world" mechanisms used under this entity (`player_manager_component`, `mode_select_component`, etc.) are looked up only inside the scope. Without it, the whole world is searched |

Everything else is functions and a class (`cancelable_group`), not components.

Example: two copies of the same game side by side
```
World
├ Room A (game_scope_component)
│ ├ player_manager_component
│ └ game flow ...
└ Room B (game_scope_component)
  ├ player_manager_component
  └ game flow ...
```
When a part inside Room A looks up `FindScopedComponent[player_manager_component]`, it finds Room A's. An event a part inside Room A sends with `SendScoped` does not reach Room B.

## Settings (@editable)
- There are no settings.

## Events
- This System has no scene_event or listenable of its own. It provides the functions that send to the scope or the world (`SendScoped` / `SendGlobal`).

## Finding and remembering one component in the scope
To "find the scope's `player_manager_component` and remember it once found", keep the storage (`var<private> X:?type = false`) in your own component and fill it with `ResolveScopedComponent`.
```verse
var<private> Manager:?player_manager_component = false

OnBeginSimulation<override>():void =
    (super:)OnBeginSimulation()
    # Keep it if remembered; otherwise look in the scope (or the world if there is none)
    set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)

IsSatisfied<override>()<decides><transacts>:void =
    # Do not look up inside a <decides> check (a failure also rolls back what was remembered)
    Manager?.GetPlayerCount() >= 2

# Subscribe / register only on the first find
if (not Manager?, Found := Entity.ResolveScopedComponent(Manager, player_manager_component)?):
    set Manager = option{Found}
    Found.PlayerRemovedEvent.Subscribe(OnPlayerRemoved)

# Wait until found (looks every second)
OnSimulate<override>()<suspends>:void =
    Found := Entity.AwaitScopedComponent(player_manager_component)
```
When stopping (`OnEndSimulation`), forget it with `set Manager = false`.

This is not a container class with a type parameter (such as `scoped_lookup(t)`) because using one in a field of a module that sorts before SceneGraphSystem by name (ConditionSystem, PlayerSystem, etc.) gives V3502 "Can't access a function from a preceding type" in the type check (functions do not have this problem). Keep this in mind when adding a class with a type parameter to another System.

## Public API
```verse
# ScopeComponent
game_scope_component<public> := class<final_super>(component):
(InEntity:entity).FindScopeEntity<public>()<decides><transacts>:entity        # Itself or the nearest ancestor scope. Fails if none
(InEntity:entity).FindScopedComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<decides><transacts>:t   # Under the scope. The world if there is no scope
(InEntity:entity).SendScoped<public>(SceneEvent:scene_event):logic           # Down from the scope root. SendGlobal if there is no scope

# ScopedLookup
(InEntity:entity).ResolveScopedComponent<public>(Known:?t, ComponentType:castable_subtype(t) where t:subtype(component))<transacts>:?t   # Known if present, otherwise FindScopedComponent. False if not found
(InEntity:entity).AwaitScopedComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<suspends>:t                 # FindScopedComponent every second until found

# AncestorComponent
(InEntity:entity).FindNearestAncestorComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<decides><transacts>:t   # Itself or the nearest ancestor. Fails if none

# WorldComponent
(InEntity:entity).FindWorldComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<decides><transacts>:t    # Under the simulation entity
(InEntity:entity).SendGlobal<public>(SceneEvent:scene_event):logic           # Down from the simulation entity. False if not yet in the world

# ChildComponent
(InEntity:entity).FindChildComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<decides><reads>:t   # Direct children only. The first one
(InEntity:entity).GetChildComponents<public>(ComponentType:castable_subtype(t) where t:subtype(component))<reads>:[]t          # Direct children only. Empty if none

# EntityTransform
MakeTranslationTransform<public>(Translation:vector3)<computes>:transform     # No rotation, scale 1
(Transform:transform).WithTranslation<public>(Translation:vector3)<computes>:transform   # Rotation and scale unchanged
(InEntity:entity).GetGlobalTranslation<public>()<transacts>:vector3           # Position in the world (cm)
(InEntity:entity).ToLocalPosition<public>(WorldPosition:vector3)<transacts>:vector3   # Axes whose scale is 0 give 0

# Cancelable
cancelable_group<public> := class(cancelable):
    Cancelables<public>:[]cancelable = array{}
    Add<public>(Cancelable:cancelable)<transacts>:void     # If already Canceled, the added one is Canceled on the spot
    Cancel<override>()<transacts>:void                     # Does nothing the second time and later
(Subscription:?cancelable).CancelIfSet<public>()<transacts>:void   # Cancels the content if there is one

# MapHelpers
(Map:[k]v).RemoveKey<public>(Key:k where k:subtype(comparable), v:type)<transacts>:[k]v   # Returns the map without Key
```

## Requirements, caveats and limits
- Scopes can be nested (the nearest ancestor scope is used).
- `FindScopedComponent` searches only under the scope when there is one. If the component is not in the scope, it fails even when one is placed in the world (the whole world is searched only when there is no scope).
- `FindScopedComponent` / `FindWorldComponent` assume one instance; with several, which one is returned is undefined. They fail when there is none or when `InEntity` is not yet in the world. They search the scope or the whole world, so remember the result if you call them every frame.
- `SendScoped` / `SendGlobal` return true if any receiver accepted the event (`OnReceive` returned true). `SendGlobal` sends nothing and returns false without notice when `InEntity` is not yet in the world.
- `ResolveScopedComponent` holds no state (the caller's field remembers). It does not notice when the remembered component is destroyed. `AwaitScopedComponent` searches the scope (or the world) every second until found.
- `FindNearestAncestorComponent` walks from itself up through the parents one by one and returns the first match. The engine's `FindAncestorComponents` has no defined order, so use this when you need "the nearest one". `FindScopeEntity` (and PlayerSystem's `FindOwningSlot` / `FindAncestorGroup`) use it.
- `FindChildComponent` / `GetChildComponents` only look at direct children (not grandchildren). They return in child order, but by library convention the order carries no meaning.
- `RemoveKey` returns a new map with the rest repacked, because Verse maps have no operation to remove one entry.
- No experimental API is used.

## Verifying
- Test: `scene_graph_system_test_component` in `_Test/SceneGraphSystemTest/`. Under entity A (`game_scope_component`), place an entity with `scope_test_marker_component` (`Label = "A"`) and the entity to set in the test's `ScopedChild`. Under entity B (`game_scope_component`), place an entity with `scope_test_marker_component` (`Label = "B"`). Place the test component somewhere outside every scope. It checks `FindScopeEntity` (found inside a scope, fails outside), `FindScopedComponent` (inside scope A finds A's marker; outside a scope finds from the world), `GetChildComponents` (direct children only), `FindNearestAncestorComponent` (the nearest in a nest built at runtime, including itself, fails if none) and `ResolveScopedComponent` (finds in scope A, returns the remembered one as is, false if none). It finishes on the frame after start. Results are in the output log under `[TEST] SceneGraphSystem`.
- Sample: `scope_sample_component` in `_Samples/ScopeSample/`. Place it inside and outside a scope; it Prints its own scope (`FindScopeEntity`) and whether `FindScopedComponent[player_manager_component]` resolves to the scope's, the world's or none. If you set `OtherEntity`, it also prints whether the lookup from that entity gives the same `player_manager_component`. Set `RepeatSeconds` above 0 to print repeatedly. Look for `[scope_sample]` in the output log.
