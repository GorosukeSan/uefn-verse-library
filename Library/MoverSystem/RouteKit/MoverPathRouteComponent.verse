using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { SceneGraphSystem }
using { MoverSystem }
using { MoverSystem.TooltipKit }

# How fixed points are traversed
mover_path_mode<public> := enum:
    # After the last point, return to the first and keep going
    Loop
    # After the last point, go back in reverse order and keep going back and forth
    PingPong
    # Stop at the last point (the mover raises FinishedEvent)
    Once

# Direction: SendDown from the route entity (the mover entity) (itself and descendants)
# Sender: mover_path_route_component (Route). When the points to traverse are decided (when the first target is chosen after moving starts / after SetPoints)
# Receivers: looks that show the route (point markers, lines). Not consumed
mover_path_changed_event<public> := class(scene_event):
    # The mover_path_route_component that sent it
    Route<public>:mover_path_route_component
    # The points to traverse (world positions, centimeters), in Index order
    Points<public>:[]vector3

# Role: a route that traverses fixed points in the Mode order. The points are Points (world positions set from code) when present, otherwise the positions of the mover_waypoint_component direct children (ascending Order; the child order is not used). With IncludeStart, the position where moving started becomes the first point (number 0). Point positions are read once, when the first target is chosen after moving starts (they do not change even when the child markers move with the mover), and sent to its own entity as mover_path_changed_event (for looks)
# Placement: attach in the editor to the entity to move (the same entity as mover_component). When created at runtime, fill Points and attach
# Same entity: mover_component
# Children: when Points is empty, entities (without a look) carrying mover_waypoint_component, as direct children. The order is decided by each marker's Order
# From outside: SetPoints replaces the points (used from the next target on. After the route finished, Restart mover_component to move again)
mover_path_route_component<public> := class<final_super>(mover_route_component):

    # How the points are traversed (Loop / PingPong / Once). Default Loop
    @editable:
        ToolTip := MoverPathModeToolTip
        Categories := array{MoverCategory, MoverPathCategory}
    Mode<public>:mover_path_mode = mover_path_mode.Loop

    # When on, the start position becomes the first point (number 0). When off, only the marker points are visited. Default on
    @editable:
        ToolTip := MoverPathIncludeStartToolTip
        Categories := array{MoverCategory, MoverPathCategory}
    IncludeStart<public>:logic = true

    # Points set from code (world positions, centimeters). When empty, the mover_waypoint_component children are used
    Points<public>:[]vector3 = array{}

    var Override<private>:?[]vector3 = false
    var Resolved<private>:[]vector3 = array{}
    var IsResolved<private>:logic = false
    var Current<private>:int = -1
    var Forward<private>:logic = true

    # Replace the points (world positions, centimeters). The current target is kept; from the next target on, traversal restarts from the first of the new points (the start position with IncludeStart)
    SetPoints<public>(NewPoints:[]vector3):void =
        set Override = option{NewPoints}
        set IsResolved = false

    # Start over from the first point (called by mover_component's Restart). The points are re-read when the next target is chosen (points set with SetPoints stay in use)
    Reset<override>():void =
        set IsResolved = false

    # The points to traverse (world positions, centimeters, in number order). Empty before moving starts
    GetResolvedPoints<public>()<reads>:[]vector3 =
        Resolved

    # The mover_waypoint_component direct children in ascending Order (the order among equal Orders is unspecified)
    GetWaypoints<public>()<transacts>:[]mover_waypoint_component =
        var Sorted:[]mover_waypoint_component = array{}
        for (Waypoint : Entity.GetChildComponents(mover_waypoint_component)):
            set Sorted = InsertByOrder(Sorted, Waypoint)
        Sorted

    NextTarget<override>(Home:vector3, Position:vector3):?mover_target =
        if (not IsResolved?):
            Resolve(Home)
        MaybeNext := NextIndex()
        if (Next := MaybeNext?, Point := Resolved[Next]):
            set Current = Next
            option{mover_target{Position := Point, Index := Next}}
        else:
            false

    Resolve<private>(Home:vector3):void =
        Base := if (Code := Override?) then Code else if (Points.Length > 0) then Points else ReadWaypoints()
        set Resolved = if (IncludeStart?) then array{Home} + Base else Base
        set Current = if (IncludeStart?) then 0 else -1
        set Forward = true
        set IsResolved = true
        Entity.SendDown(mover_path_changed_event{Route := Self, Points := Resolved})

    ReadWaypoints<private>()<transacts>:[]vector3 =
        for (Waypoint : GetWaypoints()):
            Waypoint.Entity.GetGlobalTranslation()

    NextIndex<private>():?int =
        Count := Resolved.Length
        if (Count <= 0):
            false
        else if (Count = 1):
            if (Current < 0) then option{0} else false
        else if (Mode = mover_path_mode.Loop):
            option{Mod[Current + 1, Count] or 0}
        else if (Mode = mover_path_mode.Once):
            if (Current + 1 < Count) then option{Current + 1} else false
        else if (Forward?):
            if (Current + 1 < Count):
                option{Current + 1}
            else:
                set Forward = false
                option{Current - 1}
        else:
            if (Current - 1 >= 0):
                option{Current - 1}
            else:
                set Forward = true
                option{Current + 1}

# Role: marker for a point traversed by mover_path_route_component. Visited in ascending Order
# Placement: attach in the editor to an entity without a look
# Parent: the entity carrying mover_path_route_component (place as a direct child; the child order does not matter)
mover_waypoint_component<public> := class<final_super>(component):

    # Traversal order. Visited in ascending order (the child order is not used; the order among equal numbers is unspecified). Default 0
    @editable_number(int):
        ToolTip := MoverWaypointOrderToolTip
        Categories := array{MoverCategory, MoverPathCategory}
    Order<public>:int = 0

InsertByOrder<internal>(Sorted:[]mover_waypoint_component, Item:mover_waypoint_component)<reads>:[]mover_waypoint_component =
    Index := FindInsertIndex[Sorted, Item.Order] or Sorted.Length
    Before := for (I -> Current : Sorted, I < Index):
        Current
    After := for (I -> Current : Sorted, I >= Index):
        Current
    Before + array{Item} + After

FindInsertIndex<internal>(Sorted:[]mover_waypoint_component, Order:int)<decides><reads>:int =
    first (I -> Current : Sorted, Current.Order > Order):
        I
