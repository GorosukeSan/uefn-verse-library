using { /Verse.org/SceneGraph }

# 世界（simulation entity の配下）にある ComponentType を探す（InEntity はどこでもよい）。世界に 1 つだけ置く前提で、複数あるとどれが返るかは決まらない
# InEntity がまだ世界に入っていない（simulation entity の下にない）ときと、無いときは失敗する。世界全体を探すので、毎フレーム呼ぶなら結果を覚えておく
(InEntity:entity).FindWorldComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<decides><transacts>:t =
    first (Component : InEntity.GetSimulationEntity[].FindDescendantComponents(ComponentType)):
        Component

# SceneEvent を simulation entity から下へ（世界全体へ）送る。受け手のどれかが受け取った（OnReceive が true を返した）なら true
# InEntity がまだ世界に入っていないときは何も送らず、知らせもなく false を返す
(InEntity:entity).SendGlobal<public>(SceneEvent:scene_event):logic =
    if (SimulationEntity := InEntity.GetSimulationEntity[]):
        SimulationEntity.SendDown(SceneEvent)
    else:
        false
