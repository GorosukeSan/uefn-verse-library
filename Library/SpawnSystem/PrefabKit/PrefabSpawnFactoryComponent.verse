using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { GridSystem }
using { SceneGraphSystem }
using { SpawnSystem }
using { SpawnSystem.TooltipKit }

# 役割：spawner が出すものを Prefab にする（大きさ・置き方は spawner の FootprintX/Y/Z・FitToArea・MeshSizeCm）
# 置き方：エディターで、spawner_component と同じ entity に付ける
# 同じ entity：spawner_component
prefab_spawn_factory_component<public> := class<final_super>(spawn_factory_component):

    # 出す prefab。既定の entity のままなら、何も無い entity を出す
    @editable:
        ToolTip := SpawnerPrefabToolTip
        Categories := array{SpawnerCategory, SpawnerPrefabCategory}
    Prefab<public>:concrete_subtype(entity) = entity

    CreateSpawned<override>(Area:spawn_area):entity =
        Prefab{}
