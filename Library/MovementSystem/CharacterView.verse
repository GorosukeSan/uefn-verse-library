using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }

# World position of the camera (view) (Forward / Left / Up, centimeters). Converts Epic's GetViewLocation (UE XYZ) to Verse coordinates (Forward = X, Left = -Y, Up = Z)
(FortCharacter:fort_character).GetViewOrigin<public>()<transacts>:vector3 =
    Location := FortCharacter.GetViewLocationXYZ()
    FromXYZ(Location)

# View direction (unit-length vector3 in world coordinates, Forward / Left / Up). Converts the forward of Epic's GetViewRotation (UE XYZ) to Verse coordinates (Forward = X, Left = -Y, Up = Z)
(FortCharacter:fort_character).GetViewDirection<public>()<transacts>:vector3 =
    Forward := FortCharacter.GetViewForwardXYZ()
    FromXYZ(Forward)

FromXYZ<internal>(XYZ:tuple(float, float, float))<computes>:vector3 =
    vector3{Forward := XYZ(0), Left := -XYZ(1), Up := XYZ(2)}
