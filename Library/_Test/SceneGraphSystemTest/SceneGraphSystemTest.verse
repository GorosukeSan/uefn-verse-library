using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SceneGraphSystem }
using { _Test }

# 役割：区画の探し方を確かめるための目印
scope_test_marker_component<public> := class<final_super>(component):

    # どの区画の目印か（テストで見分ける）
    @editable
    Label<public>:string = ""

# どこにも置かない component（見つからないときを確かめる）
scope_test_absent_component<public> := class<final_super>(component):

# 役割：SceneGraphSystem の動作確認。区画（game_scope_component）の中から探すこと、区画が無いときは世界から探すこと、直下の子だけを見ること、近い祖先から探すこと（FindNearestAncestorComponent）、探して覚えること（ResolveScopedComponent）を確かめる
# テストのレベル：
#   - entity A（game_scope_component）の下に scope_test_marker_component（Label = "A"）の entity と、ScopedChild に入れる entity
#   - entity B（game_scope_component）の下に scope_test_marker_component（Label = "B"）の entity
#   - このテストの component は、どの区画にも入らない場所に置く
# 結果：出力ログの [TEST] SceneGraphSystem
scene_graph_system_test_component<public> := class<final_super>(component):

    # 区画 A の中の entity（FindScopedComponent が A の目印を返すことを確かめる）
    @editable
    ScopedChild<public>:?entity = false

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "SceneGraphSystem"}
        TickEvents.PrePhysics.Await()
        if (Child := ScopedChild?):
            Results.Check("FindScopeEntity finds the nearest scope", if (Child.FindScopeEntity[]) then true else false)
            if (Marker := Child.FindScopedComponent[scope_test_marker_component]):
                Results.Check("FindScopedComponent stays inside scope A", if (Marker.Label = "A") then true else false)
            else:
                Results.Fail("FindScopedComponent stays inside scope A", "not found")
        else:
            Results.Fail("setup", "ScopedChild not set")
        Results.Check("outside any scope, FindScopedComponent falls back to the world", if (Entity.FindScopedComponent[scope_test_marker_component]) then true else false)
        Results.Check("FindScopeEntity fails outside any scope", if (Entity.FindScopeEntity[]) then false else true)
        Results.CheckInt("GetChildComponents sees direct children only", Entity.GetChildComponents(scope_test_marker_component).Length, 0)
        TestNearestAncestor(Results)
        TestResolveScoped(Results)
        if (Results.Finish[]) {}

    # Entity ─ Outer（目印 "outer"）─ Inner（目印 "inner"）─ Leaf を実行時に作り、近い順に探すことを確かめる
    TestNearestAncestor<private>(Results:test_log):void =
        Outer := entity{}
        Outer.AddComponents(array{scope_test_marker_component{Entity := Outer, Label := "outer"}})
        Inner := entity{}
        Inner.AddComponents(array{scope_test_marker_component{Entity := Inner, Label := "inner"}})
        Leaf := entity{}
        Inner.AddEntities(array{Leaf})
        Outer.AddEntities(array{Inner})
        Entity.AddEntities(array{Outer})
        if (Found := Leaf.FindNearestAncestorComponent[scope_test_marker_component]):
            Results.Check("FindNearestAncestorComponent returns the nearest ancestor", if (Found.Label = "inner") then true else false)
        else:
            Results.Fail("FindNearestAncestorComponent returns the nearest ancestor", "not found")
        if (Found := Inner.FindNearestAncestorComponent[scope_test_marker_component]):
            Results.Check("FindNearestAncestorComponent includes the entity itself", if (Found.Label = "inner") then true else false)
        else:
            Results.Fail("FindNearestAncestorComponent includes the entity itself", "not found")
        Results.Check("FindNearestAncestorComponent fails when no ancestor has it", if (Entity.FindNearestAncestorComponent[scope_test_marker_component]) then false else true)
        Outer.RemoveFromParent()

    # ResolveScopedComponent は、覚えていれば探さずにそれを返し、無ければ区画から探す
    TestResolveScoped<private>(Results:test_log):void =
        if (Child := ScopedChild?):
            var Known:?scope_test_marker_component = false
            set Known = Child.ResolveScopedComponent(Known, scope_test_marker_component)
            Results.Check("ResolveScopedComponent finds in scope A", if (Found := Known?, Found.Label = "A") then true else false)
            # 区画の外から呼んでも、覚えているもの（A）がそのまま返る
            Again := Entity.ResolveScopedComponent(Known, scope_test_marker_component)
            Results.Check("ResolveScopedComponent keeps the known one", if (Found := Again?, Found.Label = "A") then true else false)
        Nothing:?scope_test_absent_component = false
        Results.Check("ResolveScopedComponent returns false when not found", if (Entity.ResolveScopedComponent(Nothing, scope_test_absent_component)?) then false else true)
