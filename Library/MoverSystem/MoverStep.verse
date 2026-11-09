using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { SceneGraphSystem }

# VelocityCmPerSecond（センチメートル毎秒）で DeltaTime 秒ぶん entity を動かす。動く先にほかの物があれば動かずに、当たった面で反射した速度を返す
(InEntity:entity).MoveStep<internal>(VelocityCmPerSecond:vector3, DeltaTime:float)<transacts>:?vector3 =
    Current := InEntity.GetGlobalTransform()
    Displacement := VelocityCmPerSecond * DeltaTime
    if (Normal := InEntity.FindBlockingNormal[Displacement]):
        option{VelocityCmPerSecond - Normal * (2.0 * DotProduct(VelocityCmPerSecond, Normal))}
    else:
        InEntity.SetGlobalTransform(Current.WithTranslation(Current.Translation + Displacement))
        false

# Position から Target へ SpeedCmPerSecond で向かう速度（センチメートル毎秒）と、この DeltaTime 秒で着くか
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

# 水平の向き Direction のヨー（ラジアン。前 = 0、左へ回ると正）。水平の長さがほぼ 0 なら失敗する
FindTravelYaw<internal>(Direction:vector3)<decides><reads>:float =
    Direction.LengthForwardLeft() > 0.01
    ArcTan(Direction.Left, Direction.Forward)

# entity の前（Forward 軸）の水平の向きのヨー（ラジアン。前 = 0、左へ回ると正）
(InEntity:entity).GetYawRadians<internal>()<transacts>:float =
    Axis := InEntity.GetGlobalTransform().Rotation.GetForwardAxis()
    ArcTan(Axis.Left, Axis.Forward)

# 上の軸まわりに、前を左へ LeftTurnRadians（ラジアン）回す回転。MakeRotationRadians の回る向きは、回したときの前の軸で確かめてから使う
MakeYawRotation<internal>(LeftTurnRadians:float)<reads>:rotation =
    Up := vector3{Up := 1.0}
    Probe := MakeRotationRadians(Up, PiFloat / 2.0).GetForwardAxis()
    Sign := if (Probe.Left >= 0.0) then 1.0 else -1.0
    MakeRotationRadians(Up, LeftTurnRadians * Sign)

# 角度（ラジアン）を -π より大きく π 以下にする
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

# entity を、水平の向き Direction へヨーだけ向ける（位置・大きさはそのまま。傾きは無くなる）。水平の長さがほぼ 0 なら何もしない
(InEntity:entity).FaceToward<internal>(Direction:vector3)<transacts>:void =
    if (Yaw := FindTravelYaw[Direction]):
        Current := InEntity.GetGlobalTransform()
        InEntity.SetGlobalTransform(transform{Translation := Current.Translation, Rotation := MakeYawRotation(Yaw), Scale := Current.Scale})

# From から Points を順に結ぶ折れ線で、Position に一番近い区間から先の点（その区間の終わりの点から）。区間 0 は From → Points[0]
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

# Point から線分 A–B までの距離（センチメートル）
DistanceToSegment<internal>(Point:vector3, A:vector3, B:vector3)<reads>:float =
    AB := B - A
    LengthSquared := DotProduct(AB, AB)
    Ratio := if (LengthSquared > 0.0001) then Max(0.0, Min(1.0, DotProduct(Point - A, AB) / LengthSquared)) else 0.0
    Distance(Point, A + AB * Ratio)
