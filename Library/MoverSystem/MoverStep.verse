using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { SceneGraphSystem }

# Move the entity by VelocityCmPerSecond (centimeters per second) for DeltaTime seconds. When something is in the way, does not move and returns the velocity reflected off the surface it hit
(InEntity:entity).MoveStep<internal>(VelocityCmPerSecond:vector3, DeltaTime:float)<transacts>:?vector3 =
    Current := InEntity.GetGlobalTransform()
    Displacement := VelocityCmPerSecond * DeltaTime
    if (Normal := InEntity.FindBlockingNormal[Displacement]):
        option{VelocityCmPerSecond - Normal * (2.0 * DotProduct(VelocityCmPerSecond, Normal))}
    else:
        InEntity.SetGlobalTransform(Current.WithTranslation(Current.Translation + Displacement))
        false

# The velocity (centimeters per second) from Position toward Target at SpeedCmPerSecond, and whether it arrives within this DeltaTime seconds
StepTowardPoint<internal>(Position:vector3, Target:vector3, SpeedCmPerSecond:float, DeltaTime:float)<reads>:tuple(vector3, logic) =
    Offset := Target - Position
    StepLength := SpeedCmPerSecond * DeltaTime
    if (Offset.Length() <= StepLength):
        (Offset * (1.0 / Max(DeltaTime, 0.001)), true)
    else:
        (Offset.MakeUnitVector() * SpeedCmPerSecond, false)

(InEntity:entity).FindBlockingNormal<internal>(Displacement:vector3)<decides><transacts>:vector3 =
    Displacement.Length() > 0.01
    first:
        Hit : InEntity.FindSweepHits(Displacement)
        Hit.TargetComponent.Entity <> InEntity
        DotProduct(Displacement, Hit.ContactNormal) < 0.0
    do:
        Hit.ContactNormal

# Yaw (radians; forward = 0, positive turning left) of the horizontal direction Direction. Fails when the horizontal length is about 0
FindTravelYaw<internal>(Direction:vector3)<decides><reads>:float =
    Direction.LengthForwardLeft() > 0.01
    ArcTan(Direction.Left, Direction.Forward)

# Yaw (radians; forward = 0, positive turning left) of the horizontal direction of the entity's front (Forward axis)
(InEntity:entity).GetYawRadians<internal>()<transacts>:float =
    Axis := InEntity.GetGlobalTransform().Rotation.GetForwardAxis()
    ArcTan(Axis.Left, Axis.Forward)

# Rotation about the up axis that turns the front to the left by LeftTurnRadians (radians). The turning direction of MakeRotationRadians is probed with the rotated forward axis before use
MakeYawRotation<internal>(LeftTurnRadians:float)<reads>:rotation =
    Up := vector3{Up := 1.0}
    Probe := MakeRotationRadians(Up, PiFloat / 2.0).GetForwardAxis()
    Sign := if (Probe.Left >= 0.0) then 1.0 else -1.0
    MakeRotationRadians(Up, LeftTurnRadians * Sign)

# Wrap an angle (radians) into (-pi, pi]
WrapRadians<internal>(Angle:float)<transacts>:float =
    var Result:float = Angle
    loop:
        if (Result <= PiFloat):
            break
        set Result -= 2.0 * PiFloat
    loop:
        if (Result > -PiFloat):
            break
        set Result += 2.0 * PiFloat
    Result

# Turn the entity (yaw only) toward the horizontal direction Direction (position and scale unchanged; tilt is removed). Does nothing when the horizontal length is about 0
(InEntity:entity).FaceToward<internal>(Direction:vector3)<transacts>:void =
    if (Yaw := FindTravelYaw[Direction]):
        Current := InEntity.GetGlobalTransform()
        InEntity.SetGlobalTransform(transform{Translation := Current.Translation, Rotation := MakeYawRotation(Yaw), Scale := Current.Scale})

# On the polyline from From through Points in order, the points from the segment nearest to Position onward (from that segment's end point). Segment 0 is From -> Points[0]
DropPassedPoints<internal>(From:vector3, Points:[]vector3, Position:vector3)<transacts>:[]vector3 =
    var Best:int = 0
    var BestDistance:float = -1.0
    var Previous:vector3 = From
    for (Index -> Point : Points):
        Gap := DistanceToSegment(Position, Previous, Point)
        if (BestDistance < 0.0 or Gap < BestDistance):
            set Best = Index
            set BestDistance = Gap
        set Previous = Point
    for (Index -> Point : Points, Index >= Best):
        Point

# Distance (centimeters) from Point to the segment A-B
DistanceToSegment<internal>(Point:vector3, A:vector3, B:vector3)<reads>:float =
    AB := B - A
    LengthSquared := DotProduct(AB, AB)
    Ratio := if (LengthSquared > 0.0001) then Max(0.0, Min(1.0, DotProduct(Point - A, AB) / LengthSquared)) else 0.0
    Distance(Point, A + AB * Ratio)
