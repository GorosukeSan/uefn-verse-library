using { /Verse.org/SceneGraph }
using { /Verse.org/SpatialMath }

# 位置だけを持つ transform（回転なし、大きさ 1）
MakeTranslationTransform<public>(Translation:vector3)<computes>:transform =
    transform:
        Translation := Translation
        Rotation := IdentityRotation()
        Scale := vector3{Forward := 1.0, Left := 1.0, Up := 1.0}

# 回転と大きさはそのままで、位置だけ Translation に変えた transform
(Transform:transform).WithTranslation<public>(Translation:vector3)<computes>:transform =
    transform:
        Translation := Translation
        Rotation := Transform.Rotation
        Scale := Transform.Scale

# この entity の世界での位置（センチメートル）
(InEntity:entity).GetGlobalTranslation<public>()<transacts>:vector3 =
    InEntity.GetGlobalTransform().Translation

# 世界での位置を、この entity から見た位置（位置・回転・大きさを戻したもの）に変える。大きさが 0 の軸は 0 を返す
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
