using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SpawnSystem.TooltipKit }

# Role: marks a place where spawn_prefab_component spawns. Items are spawned at this entity's position and rotation (scale is not used)
# Placement: attach to an entity in the editor
# Parent: directly under the entity of a spawn_prefab_component (grandchildren are not looked at)
spawn_point_component<public> := class<final_super>(component):

    # Order used when spawn_prefab_component's PointOrder is InOrder (smaller first). The order among equal values is undefined. Default 0
    @editable_number(int):
        ToolTip := SpawnPointOrderToolTip
        Categories := array{SpawnPrefabCategory}
        MinValue := option{0}
        MaxValue := option{1000}
    Order<public>:int = 0
