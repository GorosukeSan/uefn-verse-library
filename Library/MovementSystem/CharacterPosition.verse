using { /Verse.org/SceneGraph }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { SceneGraphSystem }

# キャラクターの位置と速度を、Verse の座標（Forward・Left・Up）とセンチメートルで扱う。

# キャラクターの entity の世界での位置（センチメートル。entity の原点で、足元ではない）。entity が取れなければ失敗する
(FortCharacter:fort_character).FindGlobalTranslation<public>()<decides><transacts>:vector3 =
    FortCharacter.GetEntity[].GetGlobalTranslation()

# キャラクターの速度（センチメートル毎秒）。fort_character.GetLinearVelocity はメートル毎秒なので 100 倍する
(FortCharacter:fort_character).GetVelocityCmPerSecond<public>()<reads>:vector3 =
    FortCharacter.GetLinearVelocity() * 100.0

# キャラクターの速度を決める（センチメートル毎秒）。fort_character.SetLinearVelocity はメートル毎秒なので 100 で割って渡す
(FortCharacter:fort_character).SetVelocityCmPerSecond<public>(VelocityCmPerSecond:vector3):void =
    FortCharacter.SetLinearVelocity(VelocityCmPerSecond / 100.0)
