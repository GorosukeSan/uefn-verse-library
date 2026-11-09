using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Random }
using { MoverSystem }
using { MoverSystem.TooltipKit }

# Role: a route (never ends) whose targets are random points within RadiusCm of the position where moving started (Home). Targets are chosen at least MinStepCm away from the current position (kept as is when several tries fail) and never more than MaxDescentCm below Home
# Placement: attach in the editor to the entity to move (the same entity as mover_component)
# Same entity: mover_component (Motion = Physics to bounce on hits)
mover_random_route_component<public> := class<final_super>(mover_route_component):

    # Radius (centimeters) around the start position within which targets are chosen. Default 1500
    @editable_number(float):
        ToolTip := MoverRandomRadiusToolTip
        Categories := array{MoverCategory, MoverRandomCategory}
        MinValue := option{100.0}
        MaxValue := option{50000.0}
    RadiusCm<public>:float = 1500.0
    # The next target is at least this far from the current position (centimeters). Default 400
    @editable_number(float):
        ToolTip := MoverRandomMinStepToolTip
        Categories := array{MoverCategory, MoverRandomCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    MinStepCm<public>:float = 400.0
    # How far below the start position it may go (centimeters). Targets lower than this are lifted to this height. 0 never goes below. Default 300
    @editable_number(float):
        ToolTip := MoverRandomMaxDescentToolTip
        Categories := array{MoverCategory, MoverRandomCategory}
        MinValue := option{0.0}
        MaxValue := option{50000.0}
    MaxDescentCm<public>:float = 300.0

    MaxAttempts<private>:int = 8

    var Picked<private>:int = 0

    # Reset the pick count (mover_target.Index) to 0 (called by mover_component's Restart)
    Reset<override>():void =
        set Picked = 0

    NextTarget<override>(Home:vector3, Position:vector3):?mover_target =
        var Candidate:vector3 = MakeRandomPoint(Home)
        var Attempt:int = 1
        loop:
            if (Attempt >= MaxAttempts or Distance(Candidate, Position) >= MinStepCm):
                break
            set Candidate = MakeRandomPoint(Home)
            set Attempt += 1
        Index := Picked
        set Picked += 1
        option{mover_target{Position := KeepAboveFloor(Home, Candidate), Index := Index}}

    KeepAboveFloor<private>(Home:vector3, Point:vector3)<reads>:vector3 =
        LowestUp := Home.Up - MaxDescentCm
        if (Point.Up < LowestUp):
            vector3{Forward := Point.Forward, Left := Point.Left, Up := LowestUp}
        else:
            Point

    MakeRandomPoint<private>(Home:vector3)<transacts>:vector3 =
        Home + MakeRandomDirection() * GetRandomFloat(0.0, RadiusCm)

MakeRandomDirection<internal>()<transacts>:vector3 =
    Up := GetRandomFloat(-1.0, 1.0)
    Angle := GetRandomFloat(0.0, 2.0 * PiFloat)
    Flat := Sqrt(Max(1.0 - Up * Up, 0.0))
    vector3:
        Forward := Flat * Cos(Angle)
        Left := Flat * Sin(Angle)
        Up := Up
