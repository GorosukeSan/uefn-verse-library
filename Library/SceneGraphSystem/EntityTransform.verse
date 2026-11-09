using { /Verse.org/SceneGraph }
using { /Verse.org/SpatialMath }

# A transform with only a position (no rotation, scale 1)
MakeTranslationTransform<public>(Translation:vector3)<computes>:transform =
    transform:
        Translation := Translation
        Rotation := IdentityRotation()
        Scale := vector3{Forward := 1.0, Left := 1.0, Up := 1.0}

# The transform with rotation and scale unchanged and only the position replaced by Translation
(Transform:transform).WithTranslation<public>(Translation:vector3)<computes>:transform =
    transform:
        Translation := Translation
        Rotation := Transform.Rotation
        Scale := Transform.Scale

# This entity's position in the world (centimeters)
(InEntity:entity).GetGlobalTranslation<public>()<transacts>:vector3 =
    InEntity.GetGlobalTransform().Translation

# Converts a world position into a position seen from this entity (position, rotation and scale undone). Axes whose scale is 0 return 0
(InEntity:entity).ToLocalPosition<public>(WorldPosition:vector3)<transacts>:vector3 =
    Global := InEntity.GetGlobalTransform()
    Rotated := (WorldPosition - Global.Translation) * Global.Rotation.Invert()
    vector3:
        Forward := DivideOrZero(Rotated.Forward, Global.Scale.Forward)
        Left := DivideOrZero(Rotated.Left, Global.Scale.Left)
        Up := DivideOrZero(Rotated.Up, Global.Scale.Up)

DivideOrZero<internal>(Value:float, Divisor:float)<computes>:float =
    if (Abs(Divisor) > 0.000001):
        Value / Divisor
    else:
        0.0
