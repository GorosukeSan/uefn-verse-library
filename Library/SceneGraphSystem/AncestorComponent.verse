using { /Verse.org/SceneGraph }

# InEntity 自身か、親をたどって一番近い祖先の entity に付いた ComponentType を返す（近い順に 1 つずつ見る）。無ければ失敗する
# エンジンの FindAncestorComponents は並び順が決まっていないので、「一番近いもの」が要るときはこちらを使う
(InEntity:entity).FindNearestAncestorComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<decides><transacts>:t =
    if (Component := InEntity.GetComponent[ComponentType]):
        Component
    else:
        InEntity.GetParent[].FindNearestAncestorComponent[ComponentType]
