using { /Verse.org/SceneGraph }
using { /Verse.org/SpatialMath }

# Creates one Prefab, makes it a child of Parent, sets its world position / rotation / scale to Transform and returns it (function version; does not count or remove in bulk)
# To count what was spawned, remove it in bulk or spawn / despawn on activation signals, use spawn_prefab_component in PrefabKit
(Parent:entity).SpawnPrefab<public>(Prefab:concrete_subtype(entity), Transform:transform):entity =
    # Prefab{} cannot be written on the argument directly (V3545), so take it into a variable first
    PrefabType:concrete_subtype(entity) = Prefab
    Spawned := PrefabType{}
    Parent.AddEntities(array{Spawned})
    Spawned.SetGlobalTransform(Transform)
    Spawned
