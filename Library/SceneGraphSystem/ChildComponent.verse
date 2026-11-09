using { /Verse.org/SceneGraph }

# Returns the first ComponentType attached to a direct child entity of InEntity, in child order. Only looks at direct children (not grandchildren). Fails if there is none
(InEntity:entity).FindChildComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<decides><reads>:t =
    first:
        Child : InEntity.GetEntities()
        Component := Child.GetComponent[ComponentType]
    do:
        Component

# Returns every ComponentType attached to the direct child entities of InEntity, in child order. Only looks at direct children (not grandchildren). Empty if there is none
(InEntity:entity).GetChildComponents<public>(ComponentType:castable_subtype(t) where t:subtype(component))<reads>:[]t =
    for:
        Child : InEntity.GetEntities()
        Component := Child.GetComponent[ComponentType]
    do:
        Component
