using { /Verse.org/SceneGraph }

# 直下の子の entity に付いた ComponentType を、子の並び順で最初の 1 つ返す。直下だけを見る（孫は見ない）。無ければ失敗する
(InEntity:entity).FindChildComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<decides><reads>:t =
    first:
        Child : InEntity.GetEntities()
        Component := Child.GetComponent[ComponentType]
    do:
        Component

# 直下の子の entity に付いた ComponentType を、子の並び順で全部返す。直下だけを見る（孫は見ない）。無ければ空
(InEntity:entity).GetChildComponents<public>(ComponentType:castable_subtype(t) where t:subtype(component))<reads>:[]t =
    for:
        Child : InEntity.GetEntities()
        Component := Child.GetComponent[ComponentType]
    do:
        Component
