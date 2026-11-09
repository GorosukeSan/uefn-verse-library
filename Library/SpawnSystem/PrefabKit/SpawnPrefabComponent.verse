using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Random }
using { ActivationSystem }
using { SceneGraphSystem }
using { SpawnSystem }
using { SpawnSystem.TooltipKit }

# The order in which spawn_prefab_component uses its direct-child spawn_point_components
spawn_point_order<public> := enum:
    # Use them one by one by ascending Order, back to the first after the last
    InOrder
    # Pick one at random each time
    Random

# Role: spawns Prefab as children of this entity, counts the spawned items and removes them in bulk. Spawns SpawnOnActivate items on the activation signal and removes everything on the deactivation signal (when DespawnOnDeactivate)
# Where: the position and rotation of a direct-child spawn_point_component if there is one (in PointOrder order), otherwise this entity's position and rotation. From there, offset at random inside a box of ScatterHalfSizeCm (along the rotation's axes; 0 means no offset). Scale is 1. TrySpawnAt spawns at any place
# Count: when MaxCount is greater than 0, nothing more is spawned once the spawned count reaches it
# Placement: attach to an entity in the editor
# Parent: wherever the activation signal reaches (in a game flow, the node's entity or a descendant). Anywhere if the activation signal is not used (call Spawn / TrySpawnAt from code)
# Children: spawn point markers (spawn_point_component). Spawned items (with prefab_spawned_component attached) also become children of this entity
# Notifies: SpawnedEvent on spawn, DespawnedEvent when a spawned item leaves the world (Despawn, DespawnAll, the deactivation signal, removed by other code)
# From outside: Spawn / TrySpawnAt / Despawn / DespawnAll, GetSpawned / GetSpawnedCount / GetSpawnPoints / IsFull
spawn_prefab_component<public> := class<final_super>(component):

    # The prefab to spawn. Left at the default entity, only an empty entity is spawned
    @editable:
        ToolTip := SpawnPrefabToolTip
        Categories := array{SpawnPrefabCategory}
    Prefab<public>:concrete_subtype(entity) = entity

    # Number spawned each time the activation signal (activated_event) arrives. 0 spawns nothing on the signal (call Spawn / TrySpawnAt from code). Default 1
    @editable_number(int):
        ToolTip := SpawnPrefabOnActivateToolTip
        Categories := array{SpawnPrefabCategory}
        MinValue := option{0}
        MaxValue := option{100}
    SpawnOnActivate<public>:int = 1

    # Maximum number that can exist at once. Once reached, nothing more is spawned. 0 means no limit (default)
    @editable_number(int):
        ToolTip := SpawnPrefabMaxCountToolTip
        Categories := array{SpawnPrefabCategory}
        MinValue := option{0}
        MaxValue := option{1000}
    MaxCount<public>:int = 0

    # The order in which the direct-child spawn_point_components are used. Default InOrder (one by one by ascending Order)
    @editable:
        ToolTip := SpawnPrefabPointOrderToolTip
        Categories := array{SpawnPrefabCategory}
    PointOrder<public>:spawn_point_order = spawn_point_order.InOrder

    # From the spawn place (a point or this entity), offset at random inside a box of +/- this length (centimeters) forward, left and up (along the point's rotation axes). An axis set to 0 is not offset. Default 0
    @editable:
        ToolTip := SpawnPrefabScatterToolTip
        Categories := array{SpawnPrefabCategory}
    ScatterHalfSizeCm<public>:vector3 = vector3{}

    # When on, every spawned item is removed on the deactivation signal (deactivated_event) (default). When off, the deactivation signal removes nothing (removed by DespawnAll or at the end of the simulation)
    @editable:
        ToolTip := SpawnPrefabDespawnOnDeactivateToolTip
        Categories := array{SpawnPrefabCategory}
    DespawnOnDeactivate<public>:logic = true

    SpawnedEventInternal<private><final>:event(entity) = event(entity){}

    # Delivered with the spawned entity after one item is spawned and placed (Await / Subscribe to it; it cannot be Signaled from outside)
    SpawnedEvent<public><final>:listenable(entity) = MakeProxyListenable(SpawnedEventInternal)

    DespawnedEventInternal<private><final>:event(entity) = event(entity){}

    # Delivered with the entity when a spawned item leaves the world (Despawn, DespawnAll, the deactivation signal, removed by other code. Await / Subscribe to it; it cannot be Signaled from outside)
    DespawnedEvent<public><final>:listenable(entity) = MakeProxyListenable(DespawnedEventInternal)

    # Index of the next point to use when PointOrder is InOrder
    var<private> NextPoint:int = 0

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Spawn(SpawnOnActivate)
        else if (deactivated_event[SceneEvent]):
            if (DespawnOnDeactivate?):
                DespawnAll()
        false

    OnEndSimulation<override>():void =
        DespawnAll()
        (super:)OnEndSimulation()

    # Spawns Count items at the chosen places (a direct-child spawn_point_component or this entity's position, offset by ScatterHalfSizeCm) and returns them. Stops when MaxCount is reached (returns fewer than Count)
    Spawn<public>(Count:int):[]entity =
        var Result:[]entity = array{}
        var Left:int = Count
        loop:
            if (Left <= 0):
                break
            set Left -= 1
            MaybeSpawned := TrySpawnAt(NextTransform())
            if (Spawned := MaybeSpawned?):
                set Result += array{Spawned}
            else:
                break
        Result

    # Spawns one item with its world position / rotation / scale set to Transform and returns it. False without spawning when MaxCount is reached (not <decides> because spawning changes the world)
    TrySpawnAt<public>(Transform:transform):?entity =
        if (IsFull[]):
            return false
        Spawned := Prefab{}
        Spawned.AddComponents(array{prefab_spawned_component{Entity := Spawned, Source := Self}})
        Entity.AddEntities(array{Spawned})
        Spawned.SetGlobalTransform(Transform)
        SpawnedEventInternal.Signal(Spawned)
        option{Spawned}

    # If Spawned was spawned by this component, removes it right away (DespawnedEvent is delivered). Does nothing for anything else
    Despawn<public>(Spawned:entity):void =
        if (Marker := Spawned.GetComponent[prefab_spawned_component], Marker.Source = Self):
            Marker.Remove()

    # Removes every spawned item right away (DespawnedEvent is delivered one by one)
    DespawnAll<public>():void =
        for (Marker : GetMarkers()):
            Marker.Remove()

    # Items currently spawned (excluding those being removed). Looks only at the direct children of this entity. Order is undefined
    GetSpawned<public>()<reads>:[]entity =
        for (Marker : GetMarkers()):
            Marker.Entity

    # Number of items currently spawned (the count of GetSpawned)
    GetSpawnedCount<public>()<reads>:int =
        GetMarkers().Length

    # Succeeds if MaxCount is greater than 0 and the spawned count has reached it
    IsFull<public>()<decides><reads>:void =
        MaxCount > 0
        GetSpawnedCount() >= MaxCount

    # Returns the direct-child spawn_point_components by ascending Order (the order among equal Orders is undefined)
    GetSpawnPoints<public>()<transacts>:[]spawn_point_component =
        var Sorted:[]spawn_point_component = array{}
        for (Point : Entity.GetChildComponents(spawn_point_component)):
            set Sorted = InsertSpawnPointByOrder(Sorted, Point)
        Sorted

    # Called by prefab_spawned_component when it leaves the world
    NotifyDespawned<internal>(Spawned:entity):void =
        DespawnedEventInternal.Signal(Spawned)

    GetMarkers<private>()<reads>:[]prefab_spawned_component =
        for (Marker : Entity.GetChildComponents(prefab_spawned_component), Marker.Source = Self, not Marker.IsLeaving[]):
            Marker

    # The next spawn place. The point chosen by PointOrder if there are points, otherwise this entity. Offset from there inside a box of ScatterHalfSizeCm (along the rotation's axes). Scale is 1
    NextTransform<private>()<transacts>:transform =
        Points := GetSpawnPoints()
        Base := if (Point := Points[NextPointIndex(Points.Length)]) then Point.Entity.GetGlobalTransform() else Entity.GetGlobalTransform()
        Offset := vector3:
            Forward := RandomWithin(ScatterHalfSizeCm.Forward)
            Left := RandomWithin(ScatterHalfSizeCm.Left)
            Up := RandomWithin(ScatterHalfSizeCm.Up)
        transform:
            Translation := Base.Translation + Offset * Base.Rotation
            Rotation := Base.Rotation
            Scale := vector3{Forward := 1.0, Left := 1.0, Up := 1.0}

    # Index of the point to use (-1 if there are no points). InOrder advances one at a time
    NextPointIndex<private>(Count:int)<transacts>:int =
        if (Count <= 0):
            -1
        else if (PointOrder = spawn_point_order.Random):
            GetRandomInt(0, Count - 1)
        else:
            Index := Mod[NextPoint, Count] or 0
            set NextPoint = Index + 1
            Index

    RandomWithin<private>(Half:float)<transacts>:float =
        if (Half > 0.0) then GetRandomFloat(-Half, Half) else 0.0

# Role: marker attached to an entity spawned by spawn_prefab_component. spawn_prefab_component counts only direct children carrying this (items being removed are not counted). Notifies the spawning component when leaving the world
# Placement: attached at runtime by spawn_prefab_component (not placed in the editor)
prefab_spawned_component<public> := class<final_super>(component):

    # The spawn_prefab_component that spawned it
    Source<public>:spawn_prefab_component

    var<private> Leaving:logic = false

    # Succeeds if removal has started
    IsLeaving<public>()<decides><reads>:void =
        Leaving?

    # Marks removal as started, then removes from the world (so a recount in the same frame does not include it)
    Remove<internal>():void =
        if (not Leaving?):
            set Leaving = true
            Entity.RemoveFromParent()

    OnEndSimulation<override>():void =
        Source.NotifyDespawned(Entity)
        (super:)OnEndSimulation()

InsertSpawnPointByOrder<internal>(Sorted:[]spawn_point_component, Item:spawn_point_component)<reads>:[]spawn_point_component =
    Index := FindSpawnPointInsertIndex[Sorted, Item.Order] or Sorted.Length
    Before := for (I -> Current : Sorted, I < Index):
        Current
    After := for (I -> Current : Sorted, I >= Index):
        Current
    Before + array{Item} + After

FindSpawnPointInsertIndex<internal>(Sorted:[]spawn_point_component, Order:int)<decides><reads>:int =
    first (I -> Current : Sorted, Current.Order > Order):
        I
