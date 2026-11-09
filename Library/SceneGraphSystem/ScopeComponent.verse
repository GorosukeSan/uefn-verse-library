using { /Verse.org/SceneGraph }

# 役割：区画（1 つのゲームや部屋）の根の目印。この entity の配下で使う「世界に 1 つ」の仕組み（player_manager・grid・mode_select など）は、区画の中だけで探される。同じ仕組みを 2 区画に置いても混ざらない
# 置き方：エディターで、区画の根にする entity に付ける。付けなければ、今までどおり世界全体から探す
# 前提・注意：区画は入れ子にできる（一番近い祖先の区画が使われる）
game_scope_component<public> := class<final_super>(component):

# InEntity 自身か、親をたどって一番近い、game_scope_component の付いた entity を返す。無ければ失敗する
(InEntity:entity).FindScopeEntity<public>()<decides><transacts>:entity =
    InEntity.FindNearestAncestorComponent[game_scope_component].Entity

# InEntity が属する区画（FindScopeEntity）の配下から ComponentType を探す。区画が無ければ世界全体（FindWorldComponent）から探す
# 区画の中に 1 つだけ置く前提で、複数あるとどれが返るかは決まらない。無いとき・InEntity がまだ世界に入っていないときは失敗する。毎フレーム呼ぶなら結果を覚えておく
(InEntity:entity).FindScopedComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<decides><transacts>:t =
    if (Scope := InEntity.FindScopeEntity[]):
        first (Component : Scope.FindDescendantComponents(ComponentType)):
            Component
    else:
        InEntity.FindWorldComponent[ComponentType]

# SceneEvent を、InEntity が属する区画（FindScopeEntity）の根から下へ送る。区画が無ければ世界全体へ送る（SendGlobal）。受け手のどれかが受け取ったなら true
(InEntity:entity).SendScoped<public>(SceneEvent:scene_event):logic =
    if (Scope := InEntity.FindScopeEntity[]):
        Scope.SendDown(SceneEvent)
    else:
        InEntity.SendGlobal(SceneEvent)
