using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SpawnSystem.TooltipKit }

# 役割：spawn_prefab_component が出す場所の目印。この entity の位置と向きに出す（大きさは使わない）
# 置き方：エディターで entity に付ける
# 親：spawn_prefab_component の entity の直下（孫は見ない）
spawn_point_component<public> := class<final_super>(component):

    # spawn_prefab_component の PointOrder が InOrder のときに使う順番（小さいほど先）。同じ値どうしの順は決まらない。既定 0
    @editable_number(int):
        ToolTip := SpawnPointOrderToolTip
        Categories := array{SpawnPrefabCategory}
        MinValue := option{0}
        MaxValue := option{1000}
    Order<public>:int = 0
