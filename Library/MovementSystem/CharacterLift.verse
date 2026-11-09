using { /Verse.org/SceneGraph }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { SceneGraphSystem }

# MovementSystem：fort_character を Verse の座標（/Verse.org/SpatialMath の vector3。Forward・Left・Up、センチメートル、世界の座標）で扱う小道具。
# 名前は v43.00 の digest（/Fortnite.com・/Verse.org・/UnrealEngine.com）にある fort_character のメンバーと重ならないことを確かめてある（Epic 側の GetViewLocation / GetViewRotation / TeleportTo は Temporary の座標を使う別物）

# キャラクターを今の位置から真上（世界の Up）へ HeightCm センチメートル動かす（向き・大きさはそのまま。当たり判定は見ずに、キャラクターの entity の位置を直接変える。負なら下へ）。キャラクターの entity が取れなければ何もしない
(FortCharacter:fort_character).LiftBy<public>(HeightCm:float)<transacts>:void =
    if (CharacterEntity := FortCharacter.GetEntity[]):
        Start := CharacterEntity.GetGlobalTransform()
        Lifted := Start.WithTranslation(Start.Translation + vector3{Up := HeightCm})
        CharacterEntity.SetGlobalTransform(Lifted)
