using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

# Helpers to find one component in the scope (or the world) and remember it. Collects the "find and remember if not remembered" and "keep looking until found" code that each part used to write itself.
# The remembered value lives in a field of the calling component (var<private> Manager:?player_manager_component = false).
# Usage:
#   - Where looking up is allowed (OnBeginSimulation, OnReceive, Activate, etc.): set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)
#   - Inside <decides> checks such as a condition's IsSatisfied, do not look up; just read Manager? (remembering inside <decides> is rolled back when the check fails)
#   - Things to do only on the first find (subscribe, register) go inside if (not Manager?, Found := Entity.ResolveScopedComponent(Manager, X)?) together with set Manager = option{Found}
#   - To wait until found: Entity.AwaitScopedComponent(player_manager_component)
#   - When stopping (OnEndSimulation), forget with set Manager = false
# Requirements / Notes: assumes one per scope (same as FindScopedComponent). Does not notice when the remembered component is destroyed
# Note: this is not a class with a type parameter (a container like scoped_lookup(t)) because using it from a module that sorts before this one by name (ConditionSystem, PlayerSystem, etc.) gives V3502 "Can't access a function from a preceding type" (functions do not have this problem)

# If Known has a value, returns it (no lookup). Otherwise looks for ComponentType in InEntity's scope (FindScopedComponent; the world if there is no scope) and returns it. False if not found
# Store the return value back into the caller's field to remember it (set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component))
(InEntity:entity).ResolveScopedComponent<public>(Known:?t, ComponentType:castable_subtype(t) where t:subtype(component))<transacts>:?t =
    if (Found := Known?):
        option{Found}
    else if (Found := InEntity.FindScopedComponent[ComponentType]):
        option{Found}
    else:
        false

# Looks every second until ComponentType is found in InEntity's scope (FindScopedComponent; the world if there is no scope) and returns it (returns right away if present)
# Avoids depending on placement order (when a part in the scope is created later or added later by a prefab). Remember the return value in a field
(InEntity:entity).AwaitScopedComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<suspends>:t =
    loop:
        if (Found := InEntity.FindScopedComponent[ComponentType]):
            return Found
        Sleep(1.0)
