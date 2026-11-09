using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { PlayerSystem }
using { SceneGraphSystem }

# 役割：区画（game_scope_component）の見本。開始の次のフレームに、自分がどの区画に属するか（FindScopeEntity）と、FindScopedComponent[player_manager_component] が何を見つけるか（区画の中か、世界全体か、見つからないか）を Print する。OtherEntity を入れると、その entity から探した結果が自分と同じ player_manager_component かどうかも出す
# 置き方：エディターで entity に付ける。試す形：
#   - 区画 A（game_scope_component の entity）の下に player_manager_component の entity と、この component の entity
#   - 区画 B（別の game_scope_component）の下にも player_manager_component の entity を置き、その下の entity を OtherEntity に入れる → 「別の player_manager_component」と出る
#   - 区画の外に置くと「区画なし → 世界全体から探す」と出る
# 試し方：セッションを始めて出力ログの [scope_sample] を見る。RepeatSeconds を 0 より大きくすると、その間隔で繰り返し出す（実行時に entity を動かしたときの確認に）
scope_sample_component<public> := class<final_super>(component):

    # 比べる相手の entity（空なら比べない）
    @editable
    OtherEntity<public>:?entity = false

    # 0 より大きいと、この秒数ごとに繰り返し Print する。0 なら開始時の 1 回だけ
    @editable
    RepeatSeconds<public>:float = 0.0

    OnSimulate<override>()<suspends>:void =
        TickEvents.PrePhysics.Await()
        loop:
            Report()
            if (RepeatSeconds <= 0.0):
                break
            Sleep(RepeatSeconds)

    # 今の区画と、見つかる player_manager_component を Print する
    Report<public>():void =
        Print("[scope_sample] --- 区画の確認 ---", ?Duration := 8.0)
        if (Scope := Entity.FindScopeEntity[]):
            Depth := CountDepth(Scope)
            Print("[scope_sample] 区画あり: 一番近い祖先の game_scope_component は {Depth} 段上の entity（0 なら自分）", ?Duration := 8.0)
        else:
            Print("[scope_sample] 区画なし: 世界全体（simulation entity の配下）から探します", ?Duration := 8.0)

        if (Manager := Entity.FindScopedComponent[player_manager_component]):
            Where := if (Manager.Entity.FindScopeEntity[]) then "区画の中" else "区画の外（世界）"
            Print("[scope_sample] FindScopedComponent[player_manager_component]: 見つかりました（{Where}。参加者 {Manager.GetPlayerCount()} 人）", ?Duration := 8.0)
            if (Other := OtherEntity?):
                if (OtherManager := Other.FindScopedComponent[player_manager_component]):
                    Same := if (OtherManager = Manager) then "同じ player_manager_component" else "別の player_manager_component（区画が違う）"
                    Print("[scope_sample] OtherEntity から探すと: {Same}", ?Duration := 8.0)
                else:
                    Print("[scope_sample] OtherEntity から探すと: 見つかりません", ?Duration := 8.0)
        else:
            Print("[scope_sample] FindScopedComponent[player_manager_component]: 見つかりません（区画の中、または世界に player_manager_component を置いてください）", ?Duration := 8.0)

    # Entity から Ancestor まで親を何段たどるか（Ancestor が祖先でなければたどれた段数）
    CountDepth<private>(Ancestor:entity)<transacts>:int =
        var Depth:int = 0
        var Current:entity = Entity
        loop:
            if (Current = Ancestor):
                break
            if (Parent := Current.GetParent[]):
                set Current = Parent
                set Depth += 1
            else:
                break
        Depth
