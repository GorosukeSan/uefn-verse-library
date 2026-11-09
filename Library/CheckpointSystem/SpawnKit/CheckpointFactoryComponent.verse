using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { GridSystem }
using { SceneGraphSystem }
using { SpawnSystem }
using { CheckpointSystem }
using { CheckpointSystem.TooltipKit }

# Role: makes what the spawner spawns a checkpoint (Prefab with checkpoint_component attached). The checkpoint's size (WidthCm, DepthCm, ThicknessCm) is the size of the reserved area
# Placement: attach to the same entity as spawner_component in the editor. With the spawner's size set by FootprintX/Y/Z (e.g. 3 x 3 x 1), height per level (LevelIntervalCells, e.g. 50) and look filling the area (FitToArea), you get one platform per level
# Same entity: spawner_component. players_origin_component to base positions on the players
# Requirements: one grid_component and one player_manager_component in the zone (the requirements of checkpoint_component)
checkpoint_factory_component<public> := class<final_super>(spawn_factory_component):

    # The prefab used as the checkpoint's look (put in a mesh with collision). Left at the default entity, the checkpoint has no look
    @editable:
        ToolTip := CheckpointPrefabToolTip
        Categories := array{CheckpointCategory}
    Prefab<public>:concrete_subtype(entity) = entity

    CreateSpawned<override>(Area:spawn_area):entity =
        Spawned := Prefab{}
        Size := Area.GetSize()
        Checkpoint := checkpoint_component:
            Entity := Spawned
            WidthCm := Size.Forward
            DepthCm := Size.Left
            ThicknessCm := Size.Up
        Spawned.AddComponents(array{Checkpoint})
        Spawned
