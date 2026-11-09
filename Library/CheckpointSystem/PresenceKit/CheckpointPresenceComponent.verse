using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { CheckpointSystem }
using { SceneGraphSystem }

# 役割：区画の中のすべての checkpoint_component の「乗った・降りた」をまとめ、だれがどのチェックポイントに乗っているか・最後にどれに乗ったかに答える。checkpoint が区画全体へ送る checkpoint_reached_event / checkpoint_left_event を受けて覚えるだけで、自分では探さない（実行時に出たチェックポイントも数える）
# 置き方：エディターで、区画（game_scope_component の entity）の中のどこかの entity に付ける（区画が無ければ世界のどこか）。区画に 1 つ
# 知らせ：だれかが乗ったとき ReachedEvent、降りたとき LeftEvent（どちらも checkpoint の scene event そのもので届く）
# 前提：置く前に乗っていた人は数えない（シミュレーション開始から数える）。重なったチェックポイントに同時に乗っているときは、乗っているものを全部覚える（どれか 1 つから降りても、残りに乗っている扱いのまま）
checkpoint_presence_component<public> := class<final_super>(component):

    ReachedEventInternal<private><final>:event(checkpoint_reached_event) = event(checkpoint_reached_event){}

    # 区画のどれかのチェックポイントにだれかが乗ったときに、その知らせ（Agent と Checkpoint）で届く（Await / Subscribe する。外から Signal はできない）
    ReachedEvent<public><final>:listenable(checkpoint_reached_event) = MakeProxyListenable(ReachedEventInternal)

    LeftEventInternal<private><final>:event(checkpoint_left_event) = event(checkpoint_left_event){}

    # 区画のどれかのチェックポイントからだれかが降りた（退出した・チェックポイントが消えた）ときに、その知らせで届く（Await / Subscribe する。外から Signal はできない）
    LeftEvent<public><final>:listenable(checkpoint_left_event) = MakeProxyListenable(LeftEventInternal)

    # 人ごとに、今乗っているチェックポイント（乗った順。最後が一番新しい）
    var Standing<private>:[agent][]checkpoint_component = map{}
    var LastReached<private>:[agent]checkpoint_component = map{}

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Reached := checkpoint_reached_event[SceneEvent]):
            # 乗り直したものは最後へ動かす（同じものを 2 回数えない）
            Others := WithoutCheckpoint(GetStanding(Reached.Agent), Reached.Checkpoint)
            if (set Standing[Reached.Agent] = Others + array{Reached.Checkpoint}) {}
            if (set LastReached[Reached.Agent] = Reached.Checkpoint) {}
            ReachedEventInternal.Signal(Reached)
        else if (Left := checkpoint_left_event[SceneEvent]):
            Rest := WithoutCheckpoint(GetStanding(Left.Agent), Left.Checkpoint)
            if (Rest.Length > 0):
                if (set Standing[Left.Agent] = Rest) {}
            else:
                set Standing = Standing.RemoveKey(Left.Agent)
            LeftEventInternal.Signal(Left)
        false

    # Agent が区画のどれかのチェックポイントの上に立っていれば成功する
    IsOnAnyCheckpoint<public>(Agent:agent)<decides><reads>:void =
        FindStandingCheckpoint[Agent]

    # Agent が今立っているチェックポイント（重なっているときは、まだ乗っているもののうち最後に乗ったもの）。立っていなければ失敗する
    FindStandingCheckpoint<public>(Agent:agent)<decides><reads>:checkpoint_component =
        OnTop := for (Checkpoint : Standing[Agent], Checkpoint.IsStanding[Agent]):
            Checkpoint
        OnTop[OnTop.Length - 1]

    # Agent が最後に乗ったチェックポイント（降りたあとも、そのチェックポイントが消えたあとも覚えている。リスポーン地点などに使う）。一度も乗っていなければ失敗する
    FindLastReached<public>(Agent:agent)<decides><reads>:checkpoint_component =
        LastReached[Agent]

    # 覚えている「最後に乗ったチェックポイント」を全員分忘れる（ゲームのやり直しなど）
    ForgetLastReached<public>():void =
        set LastReached = map{}

    GetStanding<private>(Agent:agent)<transacts>:[]checkpoint_component =
        if (List := Standing[Agent]) then List else array{}

    WithoutCheckpoint<private>(List:[]checkpoint_component, Checkpoint:checkpoint_component)<transacts>:[]checkpoint_component =
        for (Other : List, Other <> Checkpoint):
            Other
