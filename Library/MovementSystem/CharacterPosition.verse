using { /Verse.org/SceneGraph }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { SceneGraphSystem }

# Handle the character's position and velocity in Verse coordinates (Forward / Left / Up) and centimeters.

# World position of the character's entity (centimeters; the entity origin, not the feet). Fails if the entity cannot be obtained
(FortCharacter:fort_character).FindGlobalTranslation<public>()<decides><transacts>:vector3 =
    FortCharacter.GetEntity[].GetGlobalTranslation()

# Character velocity (centimeters per second). fort_character.GetLinearVelocity is in meters per second, so multiply by 100
(FortCharacter:fort_character).GetVelocityCmPerSecond<public>()<reads>:vector3 =
    FortCharacter.GetLinearVelocity() * 100.0

# Set the character velocity (centimeters per second). fort_character.SetLinearVelocity takes meters per second, so divide by 100
(FortCharacter:fort_character).SetVelocityCmPerSecond<public>(VelocityCmPerSecond:vector3):void =
    FortCharacter.SetLinearVelocity(VelocityCmPerSecond / 100.0)
