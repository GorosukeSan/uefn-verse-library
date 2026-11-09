using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { GridSystem }
using { SceneGraphSystem }
using { SpawnSystem }
using { SpawnSystem.TooltipKit }

# Role: makes the spawner spawn Prefab (size and placement come from the spawner's FootprintX/Y/Z, FitToArea and MeshSizeCm)
# Placement: attach in the editor to the same entity as spawner_component
# Same entity: spawner_component
prefab_spawn_factory_component<public> := class<final_super>(spawn_factory_component):

    # The prefab to spawn. Left at the default entity, an empty entity is spawned
    @editable:
        ToolTip := SpawnerPrefabToolTip
        Categories := array{SpawnerCategory, SpawnerPrefabCategory}
    Prefab<public>:concrete_subtype(entity) = entity

    CreateSpawned<override>(Area:spawn_area):entity =
        Prefab{}
