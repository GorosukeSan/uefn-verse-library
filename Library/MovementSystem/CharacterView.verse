using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }

# カメラ（視点）の世界での位置（Forward・Left・Up、センチメートル）。Epic の GetViewLocation（UE の XYZ）を Verse の座標に変えて返す（Forward = X、Left = -Y、Up = Z）
(FortCharacter:fort_character).GetViewOrigin<public>()<transacts>:vector3 =
    Location := FortCharacter.GetViewLocationXYZ()
    FromXYZ(Location)

# 視点の向き（世界の座標の、長さ 1 の vector3。Forward・Left・Up）。Epic の GetViewRotation（UE の XYZ）の前向きを Verse の座標に変えて返す（Forward = X、Left = -Y、Up = Z）
(FortCharacter:fort_character).GetViewDirection<public>()<transacts>:vector3 =
    Forward := FortCharacter.GetViewForwardXYZ()
    FromXYZ(Forward)

FromXYZ<internal>(XYZ:tuple(float, float, float))<computes>:vector3 =
    vector3{Forward := XYZ(0), Left := -XYZ(1), Up := XYZ(2)}
