using { /Verse.org/SceneGraph }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { SceneGraphSystem }

# MovementSystem: helpers that handle fort_character in Verse coordinates (vector3 from /Verse.org/SpatialMath: Forward / Left / Up, centimeters, world space).
# The names were checked against the fort_character members in the v43.00 digest (/Fortnite.com, /Verse.org, /UnrealEngine.com) so they do not collide (Epic's GetViewLocation / GetViewRotation / TeleportTo are different things that use the Temporary coordinates)

# Move the character straight up (world Up) by HeightCm centimeters from its current position (rotation and scale unchanged; ignores collision and changes the character entity's position directly; negative moves down). Does nothing if the character's entity cannot be obtained
(FortCharacter:fort_character).LiftBy<public>(HeightCm:float)<transacts>:void =
    if (CharacterEntity := FortCharacter.GetEntity[]):
        Start := CharacterEntity.GetGlobalTransform()
        Lifted := Start.WithTranslation(Start.Translation + vector3{Up := HeightCm})
        CharacterEntity.SetGlobalTransform(Lifted)
