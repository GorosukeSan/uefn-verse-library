using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SceneGraphSystem }

# 「だれのものか」を entity の木から決める。
# プレイヤーの slot（player_slot_component の entity）の下に置かれた entity は、その人のもの（持ち主がいる）。
# CharacterSystem のキャラクター・player_view_set の view などは slot の下に作られるので、その中の部品は持ち主だけに効く（能力の付与・widget・付ける物・アイテムを配る部品などが、これを見て相手を持ち主に絞る）。

# InEntity か、その祖先の slot のプレイヤー（持ち主）。slot の下に無ければ失敗する
(InEntity:entity).FindOwningPlayer<public>()<decides><transacts>:player =
    InEntity.FindOwningSlot[].Player

# InEntity か、その祖先で最初に見つかった player_slot_component。無ければ失敗する
(InEntity:entity).FindOwningSlot<public>()<decides><transacts>:player_slot_component =
    InEntity.FindNearestAncestorComponent[player_slot_component]
