using { /Verse.org/SceneGraph }
using { /Verse.org/SpatialMath }
using { /Verse.org/Random }
using { MoverSystem }

# Role: a route (never ends) whose targets are random points inside the box BoxMinCm-BoxMaxCm (world positions, centimeters). Uses the inside shrunk by MarginCm (pass half of your own size to stay inside). Targets are chosen at least MinStepCm away from the current position (kept as is when several tries fail)
# Placement: created at runtime (e.g. a spawner that borrowed a grid volume puts the borrowed volume in BoxMinCm / BoxMaxCm and attaches it)
# Same entity: mover_component (Motion = Physics to bounce on hits)
mover_box_route_component<public> := class<final_super>(mover_route_component):

    # Corner of the box on the small side (world position, centimeters)
    BoxMinCm<public>:vector3 = vector3{}
    # Corner of the box on the large side (world position, centimeters)
    BoxMaxCm<public>:vector3 = vector3{}
    # Inset from each face (centimeters). When larger than the axis length, only the middle of that axis is used
    MarginCm<public>:float = 0.0
    # The next target is at least this far from the current position (centimeters)
    MinStepCm<public>:float = 100.0

    MaxAttempts<private>:int = 8

    var Picked<private>:int = 0

    # Reset the pick count (mover_target.Index) to 0 (called by mover_component's Restart)
    Reset<override>():void =
        set Picked = 0

    NextTarget<override>(Home:vector3, Position:vector3):?mover_target =
        var Candidate:vector3 = MakeRandomPoint()
        var Attempt:int = 1
        loop:
            if (Attempt >= MaxAttempts or Distance(Candidate, Position) >= MinStepCm):
                break
            set Candidate = MakeRandomPoint()
            set Attempt += 1
        Index := Picked
        set Picked += 1
        option{mover_target{Position := Candidate, Index := Index}}

    MakeRandomPoint<private>()<transacts>:vector3 =
        vector3:
            Forward := PickBetween(BoxMinCm.Forward, BoxMaxCm.Forward)
            Left := PickBetween(BoxMinCm.Left, BoxMaxCm.Left)
            Up := PickBetween(BoxMinCm.Up, BoxMaxCm.Up)

    PickBetween<private>(Low:float, High:float)<transacts>:float =
        Inner := Low + MarginCm
        Outer := High - MarginCm
        if (Inner < Outer):
            GetRandomFloat(Inner, Outer)
        else:
            (Low + High) / 2.0
