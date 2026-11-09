using { /Verse.org/SceneGraph }

# Role: marks the root of a scope (one game or room). "One per world" mechanisms used under this entity (player_manager, grid, mode_select, etc.) are looked up only inside the scope. Placing the same mechanism in two scopes does not mix them
# Placement: attach in the editor to the entity that is the root of the scope. Without it, lookups search the whole world as before
# Requirements / Notes: scopes can be nested (the nearest ancestor scope is used)
game_scope_component<public> := class<final_super>(component):

# Returns InEntity itself or, walking up the parents, the nearest entity with a game_scope_component. Fails if there is none
(InEntity:entity).FindScopeEntity<public>()<decides><transacts>:entity =
    InEntity.FindNearestAncestorComponent[game_scope_component].Entity

# Looks for ComponentType under the scope InEntity belongs to (FindScopeEntity). Without a scope, searches the whole world (FindWorldComponent)
# Assumes one per scope; with several, which one is returned is undefined. Fails when there is none or when InEntity is not yet in the world. Remember the result if you call this every frame
(InEntity:entity).FindScopedComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<decides><transacts>:t =
    if (Scope := InEntity.FindScopeEntity[]):
        first (Component : Scope.FindDescendantComponents(ComponentType)):
            Component
    else:
        InEntity.FindWorldComponent[ComponentType]

# Sends SceneEvent downward from the root of the scope InEntity belongs to (FindScopeEntity). Without a scope, sends to the whole world (SendGlobal). True if any receiver accepted it
(InEntity:entity).SendScoped<public>(SceneEvent:scene_event):logic =
    if (Scope := InEntity.FindScopeEntity[]):
        Scope.SendDown(SceneEvent)
    else:
        InEntity.SendGlobal(SceneEvent)
