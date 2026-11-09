using { /UnrealEngine.com/Temporary/SpatialMath }
using { /Fortnite.com/Characters }

(FortCharacter:fort_character).GetViewLocationXYZ<internal>()<transacts>:tuple(float, float, float) =
    Location := FortCharacter.GetViewLocation()
    (Location.X, Location.Y, Location.Z)

(FortCharacter:fort_character).GetViewForwardXYZ<internal>()<transacts>:tuple(float, float, float) =
    Forward := FortCharacter.GetViewRotation().GetLocalForward()
    (Forward.X, Forward.Y, Forward.Z)
