using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { GridSystem }
using { SceneGraphSystem }

# Direction: SendDown from the spawner's entity (the spawner itself and its descendants; spawned items are children of the spawner, so they receive it too)
# Sender: spawner_component (Spawner). After one item is spawned and placed (same timing as SpawnedEvent)
# Receivers: components that add a look to the spawned item, etc. Not consumed
spawned_event<public> := class(scene_event):
    # The spawner that spawned it
    Spawner<public>:spawner_component
    # The spawned entity (a child of the spawner)
    Spawned<public>:entity
    # Where it was spawned (the reserved area)
    Area<public>:spawn_area

# Direction: SendDown from the spawner's entity (the spawner itself and its descendants)
# Sender: spawner_component (Spawner). When a spawned item leaves the world (shrank away, ClearAll, stop; same timing as DespawnedEvent)
# Receivers: components that count, etc. Not consumed
despawned_event<public> := class(scene_event):
    # The spawner that spawned it
    Spawner<public>:spawner_component
    # The entity that left the world
    Spawned<public>:entity

# Role: the place of one item spawned by a spawner. Inner is the usable range (cells); Reservation is the reservation including the gap around Inner (GapCells)
# Creation: created by spawner_component (not from outside)
spawn_area<public> := class:

    # The grid the reservation was made on
    Grid<public>:grid_component
    # The usable range (cells)
    Inner<public>:grid_box
    # The reservation including the gap around Inner. Released when the spawned item leaves the world
    Reservation<public>:grid_reservation

    # World position (centimeters) of the start corner of the usable range (Inner)
    GetMinPosition<public>()<transacts>:vector3 =
        Grid.CellToPosition(Inner.Start)

    # World position (centimeters) of the end corner of the usable range (Inner)
    GetMaxPosition<public>()<transacts>:vector3 =
        Grid.CellToPosition(Inner.GetEnd())

    # World position (centimeters) of the center of the usable range (Inner)
    GetCenter<public>()<transacts>:vector3 =
        (GetMinPosition() + GetMaxPosition()) / 2.0

    # Length of the usable range (Inner) along each axis (centimeters)
    GetSize<public>()<transacts>:vector3 =
        GetMaxPosition() - GetMinPosition()

    # A transform placed at the center of the range, stretched to fill it (no rotation). MeshSizeCm is the edge length of the mesh at scale 1 (centimeters; 100 for the engine cube). 0 or less gives scale 1
    MakeFitTransform<public>(MeshSizeCm:float)<transacts>:transform =
        Scale := if (MeshSizeCm > 0.0) then GetSize() / MeshSizeCm else vector3{Forward := 1.0, Left := 1.0, Up := 1.0}
        transform:
            Translation := GetCenter()
            Rotation := IdentityRotation()
            Scale := Scale

# Role: marker attached to an entity spawned by a spawner. The spawner counts only children carrying this (items that started disappearing via Leave are not counted). Releases the reservation and notifies the spawner when leaving the world
# Placement: attached at runtime by spawner_component (not placed in the editor)
spawned_component<public> := class<final_super>(component):

    # The spawner that spawned it
    Spawner<public>:spawner_component
    # Where it was spawned
    Area<public>:spawn_area

    # True once it started disappearing via Leave (read-only from outside)
    var<private> Leaving<public>:logic = false

    # Shrinks over Seconds seconds, then removes the entity (the reservation is released when it is gone). Returns right away without waiting. Does nothing the second time and later
    Leave<public>(Seconds:float):void =
        if (not Leaving?):
            set Leaving = true
            spawn{ShrinkAndRemove(Seconds)}

    # Succeeds if it started disappearing via Leave
    IsLeaving<public>()<decides><reads>:void =
        Leaving?

    ShrinkAndRemove<private>(Seconds:float)<suspends>:void =
        Entity.ShrinkOut(Seconds, TickEvents.PrePhysics)
        Entity.RemoveFromParent()

    OnEndSimulation<override>():void =
        Area.Reservation.Release()
        Spawner.NotifyDespawned(Entity)
        (super:)OnEndSimulation()

AppearMinScale<internal>:float = 0.01

# Changes the scale from near 0 to the current scale over Seconds seconds (position and rotation stay as they are every frame. Tick is the owning component's TickEvents.PrePhysics)
# Note: calls SetGlobalTransform every frame, so do not use it on an entity moved by keyframed_movement_component (set AppearSeconds to 0)
(InEntity:entity).GrowIn<public>(Seconds:float, Tick:listenable(float))<suspends>:void =
    Final := InEntity.GetGlobalTransform().Scale
    InEntity.ScaleTo(Final * AppearMinScale)
    InEntity.AnimateScale(Final * AppearMinScale, Final, Seconds, Tick)

# Changes the scale from the current scale to near 0 over Seconds seconds (Tick is the owning component's TickEvents.PrePhysics)
(InEntity:entity).ShrinkOut<public>(Seconds:float, Tick:listenable(float))<suspends>:void =
    Start := InEntity.GetGlobalTransform().Scale
    InEntity.AnimateScale(Start, Start * AppearMinScale, Seconds, Tick)

# Elapsed time is the sum of Tick's DeltaTime (not counted in frames)
(InEntity:entity).AnimateScale<internal>(From:vector3, To:vector3, Seconds:float, Tick:listenable(float))<suspends>:void =
    var Elapsed:float = 0.0
    loop:
        set Elapsed += Tick.Await()
        Ratio := if (Seconds > 0.0) then Min(Elapsed / Seconds, 1.0) else 1.0
        Eased := 1.0 - (1.0 - Ratio) * (1.0 - Ratio)
        InEntity.ScaleTo(From + (To - From) * Eased)
        if (Ratio >= 1.0):
            break

(InEntity:entity).ScaleTo<internal>(Scale:vector3):void =
    Current := InEntity.GetGlobalTransform()
    InEntity.SetGlobalTransform(transform{Translation := Current.Translation, Rotation := Current.Rotation, Scale := Scale})
