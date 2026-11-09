using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

# 区画（または世界）で 1 つを探して覚える補助。部品ごとに書いていた「覚えていなければ探して覚える」「見つかるまで探す」をまとめたもの。
# 覚える場所は呼ぶ側の component のフィールド（var<private> Manager:?player_manager_component = false）。
# 使い方：
#   - 探してよいところ（OnBeginSimulation・OnReceive・Activate など）で set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)
#   - 条件の IsSatisfied など <decides> の判定の中では探さずに Manager? を読む（<decides> の中で覚えると、判定が失敗したときに巻き戻って覚えられないため）
#   - 初めて見つけたときだけすること（購読・登録）は if (not Manager?, Found := Entity.ResolveScopedComponent(Manager, X)?) の中で set Manager = option{Found} と一緒に書く
#   - 見つかるまで待つなら Entity.AwaitScopedComponent(player_manager_component)
#   - 止まるとき（OnEndSimulation）に set Manager = false で忘れる
# 前提・注意：区画の中に 1 つだけ置く前提（FindScopedComponent と同じ）。覚えた component が消されても気付かない
# 補足：型引数を持つクラス（scoped_lookup(t) のような入れ物）にしなかったのは、名前の順でそのモジュールより前のモジュール（ConditionSystem・PlayerSystem など）から使うと V3502「Can't access a function from a preceding type」になるため（関数なら起きない）

# Known に中身があればそれを返す（探さない）。無ければ InEntity の区画（FindScopedComponent。区画が無ければ世界）から ComponentType を探して返す。見つからなければ false
# 返り値を呼ぶ側のフィールドに入れ直して覚える（set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)）
(InEntity:entity).ResolveScopedComponent<public>(Known:?t, ComponentType:castable_subtype(t) where t:subtype(component))<transacts>:?t =
    if (Found := Known?):
        option{Found}
    else if (Found := InEntity.FindScopedComponent[ComponentType]):
        option{Found}
    else:
        false

# InEntity の区画（FindScopedComponent。区画が無ければ世界）に ComponentType が見つかるまで、1 秒ごとに探して返す（あればすぐ返す）
# 置き場所の順に頼らずに済む（区画の中の部品が後から作られる・プレハブで後から足されるとき）。返り値はフィールドに覚えておく
(InEntity:entity).AwaitScopedComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<suspends>:t =
    loop:
        if (Found := InEntity.FindScopedComponent[ComponentType]):
            return Found
        Sleep(1.0)
