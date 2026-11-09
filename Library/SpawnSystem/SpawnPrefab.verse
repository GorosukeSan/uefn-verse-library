using { /Verse.org/SceneGraph }
using { /Verse.org/SpatialMath }

# Prefab を 1 つ作って Parent の子にし、世界での位置・向き・大きさを Transform にして返す（関数版。数を数えたり、まとめて消したりはしない）
# 出したものを数える・まとめて消す・起動の合図で出し入れするなら、PrefabKit の spawn_prefab_component を使う
(Parent:entity).SpawnPrefab<public>(Prefab:concrete_subtype(entity), Transform:transform):entity =
    # 引数のままでは Prefab{} と書けない（V3545）ので、いったん変数に受ける
    PrefabType:concrete_subtype(entity) = Prefab
    Spawned := PrefabType{}
    Parent.AddEntities(array{Spawned})
    Spawned.SetGlobalTransform(Transform)
    Spawned
