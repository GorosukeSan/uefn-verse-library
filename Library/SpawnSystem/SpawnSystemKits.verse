# Make the Kits of SpawnSystem public so they can be used from outside the library (your code).
# Modules created from folders are internal by default, so they cannot be used with `using` from outside unless declared.
OriginKit<public> := module {}
# Parts that spawn prefabs (prefab_spawn_factory_component as the spawner's factory, spawn_prefab_component that spawns any number at chosen places on activation or from functions, and spawn_point_component for the places)
PrefabKit<public> := module {}
# Descriptions shown in the editor (message)
TooltipKit<public> := module {}
