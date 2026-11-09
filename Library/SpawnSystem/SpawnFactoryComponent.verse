using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

# Role: base class that decides "what to spawn" for spawner_component. Subclasses write only CreateSpawned (create the entity).
#   The cells one item uses, how it is placed (stretched to fill the area or not) and how the height is chosen are decided by spawner_component's settings (FootprintX/Y/Z, FitToArea, LevelIntervalCells)
# Placement: never placed directly (place a subclass such as PrefabKit's prefab_spawn_factory_component or CheckpointSystem's checkpoint_factory_component). At most one subclass per entity
# Same entity: spawner_component
spawn_factory_component<public> := class<abstract><final_super>(component):

    # Creates the entity to spawn (not yet in the world). Area is the reserved area. The spawner then makes it its child, attaches spawned_component and places it with its own settings
    CreateSpawned<public>(Area:spawn_area):entity
