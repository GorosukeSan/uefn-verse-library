using { /Verse.org/SceneGraph }
using { /Verse.org/SpatialMath }

# Reference points a spawn_origin_component returns on each refill (all world positions, centimeters)
spawn_origins<public> := struct:
    # Reference points around which bands are built to spawn. If empty, the spawner does nothing that round
    SpawnPoints<public>:[]vector3 = array{}
    # Reference points of the bands that decide whether to despawn. If empty, SpawnPoints is used
    DespawnPoints<public>:[]vector3 = array{}
    # Points near which (within the spawner's KeepNearCells) nothing is despawned
    KeepPoints<public>:[]vector3 = array{}

# Role: base class that decides "around whom (where)" the spawner spawns. Subclasses write only UpdateOrigins. The spawner builds a band (upper and lower limit) per point and merges nearby ones
# Placement: never placed directly (place a subclass such as OriginKit's players_origin_component). At most one subclass per entity. Without one, the spawner uses its own entity's position as the reference (one fixed point)
# Same entity: spawner_component
spawn_origin_component<public> := class<abstract><final_super>(component):

    # Implemented by the subclass. Returns the current reference points. Called once by the spawner on every refill (the subclass may update its own state here)
    UpdateOrigins<public>()<transacts>:spawn_origins
