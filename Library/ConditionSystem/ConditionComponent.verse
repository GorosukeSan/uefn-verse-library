using { /Verse.org/SceneGraph }
using { SceneGraphSystem }

# 条件を満たしているかが変わったかもしれない、という知らせ
# 方向：条件の entity から根へ（SendUp）
# 送り手：condition_component の派生（NotifyChanged）。受け手：祖先の game_node_component（遷移を調べ直す）、condition_all / condition_any（受け取って消費し、自分の知らせを送り直す）
condition_changed_event<public> := class(scene_event):
    # 送った条件
    Condition<public>:condition_component

# 役割：条件の基底。満たしているかを答え、変わったら上へ知らせる。派生は IsSatisfied だけを書き、変わったかもしれないときに NotifyChanged を呼ぶ
# 置き方：直接は置かない（派生を置く）
# 親：game_transition_component か condition_all / condition_any の entity の直下（ほかに ability_grant_condition_component の entity の直下など）
# 知らせ：condition_changed_event を上へ送り、ChangedEvent に今の結果を届ける
condition_component<public> := class<abstract><final_super>(component):

    # 派生が実装する。今満たしていれば成功し、満たしていなければ失敗する。<transacts> で何度も呼ばれるので、派生の実装は状態を変えない（副作用を持たない）こと
    IsSatisfied<public>()<decides><transacts>:void

    ChangedEventInternal<private><final>:event(logic) = event(logic){}

    # 満たしているかが変わったかもしれないときに、今の結果（満たしていれば true）で届く（Await / Subscribe する。外から Signal はできない）
    ChangedEvent<public><final>:listenable(logic) = MakeProxyListenable(ChangedEventInternal)

    # 派生が、満たしているかが変わったかもしれないときに呼ぶ。上へ condition_changed_event を送り、ChangedEvent に今の結果を届ける
    NotifyChanged<protected>():void =
        Entity.SendUp(condition_changed_event{Condition := Self})
        ChangedEventInternal.Signal(if (IsSatisfied[]) then true else false)

# InEntity の直下の子の条件（condition_component）を、すべて満たしていれば成功する。条件の子が無ければ成功する。孫は見ない
(InEntity:entity).AreChildConditionsSatisfied<public>()<decides><transacts>:void =
    Unsatisfied := for:
        Condition : InEntity.GetChildComponents(condition_component)
        not Condition.IsSatisfied[]
    do:
        Condition
    Unsatisfied.Length = 0

# InEntity の直下の子の条件（condition_component）のどれか 1 つでも満たしていれば成功する。条件の子が無ければ失敗する。孫は見ない
(InEntity:entity).IsAnyChildConditionSatisfied<public>()<decides><transacts>:void =
    Satisfied := for:
        Condition : InEntity.GetChildComponents(condition_component)
        Condition.IsSatisfied[]
    do:
        Condition
    Satisfied.Length > 0
