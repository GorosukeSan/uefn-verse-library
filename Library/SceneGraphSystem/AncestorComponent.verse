using { /Verse.org/SceneGraph }

# Returns the ComponentType attached to InEntity itself or, walking up the parents, to the nearest ancestor entity (checked one by one, nearest first). Fails if there is none
# The engine's FindAncestorComponents has no defined order, so use this when you need "the nearest one"
(InEntity:entity).FindNearestAncestorComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<decides><transacts>:t =
    if (Component := InEntity.GetComponent[ComponentType]):
        Component
    else:
        InEntity.GetParent[].FindNearestAncestorComponent[ComponentType]
