using { /Verse.org/SceneGraph }

# Looks for ComponentType in the world (under the simulation entity); InEntity can be anywhere. Assumes one per world; with several, which one is returned is undefined
# Fails when InEntity is not yet in the world (not under the simulation entity) and when there is none. Searches the whole world, so remember the result if you call this every frame
(InEntity:entity).FindWorldComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<decides><transacts>:t =
    first (Component : InEntity.GetSimulationEntity[].FindDescendantComponents(ComponentType)):
        Component

# Sends SceneEvent downward from the simulation entity (to the whole world). True if any receiver accepted it (OnReceive returned true)
# When InEntity is not yet in the world, sends nothing and returns false without notice
(InEntity:entity).SendGlobal<public>(SceneEvent:scene_event):logic =
    if (SimulationEntity := InEntity.GetSimulationEntity[]):
        SimulationEntity.SendDown(SceneEvent)
    else:
        false
