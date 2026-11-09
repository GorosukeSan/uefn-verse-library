using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { GridSystem }
using { SceneGraphSystem }
using { SpawnSystem }
using { CheckpointSystem }
using { CheckpointSystem.TooltipKit }

# 役割：spawner が出すものを、チェックポイント（Prefab に checkpoint_component を付けたもの）にする。checkpoint の大きさ（WidthCm・DepthCm・ThicknessCm）は借りた範囲の大きさ
# 置き方：エディターで、spawner_component と同じ entity に付ける。spawner は、大きさを FootprintX/Y/Z（例 3 × 3 × 1）、高さを段ごと（LevelIntervalCells、例 50）、見た目を範囲いっぱい（FitToArea）にすると、段ごとに 1 つの足場になる
# 同じ entity：spawner_component。プレイヤーの位置を基準にするなら players_origin_component
# 前提：区画に grid_component と player_manager_component が 1 つずつ（checkpoint_component の前提）
checkpoint_factory_component<public> := class<final_super>(spawn_factory_component):

    # チェックポイントの見た目にする prefab（当たり判定のあるメッシュを入れる）。既定の entity のままだと見た目の無いチェックポイントになる
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
