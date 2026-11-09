using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SceneGraphSystem }
using { _Test }

# Role: marker for checking scope lookup
scope_test_marker_component<public> := class<final_super>(component):

    # Which scope this marker belongs to (the test tells them apart)
    @editable
    Label<public>:string = ""

# Component placed nowhere (checks the not-found case)
scope_test_absent_component<public> := class<final_super>(component):

# Role: verification of SceneGraphSystem. Checks finding inside a scope (game_scope_component), finding in the world when there is no scope, looking only at direct children, finding from the nearest ancestor (FindNearestAncestorComponent), and find-and-remember (ResolveScopedComponent)
# Test level:
#   - under entity A (game_scope_component): an entity with scope_test_marker_component (Label = "A") and the entity to put into ScopedChild
#   - under entity B (game_scope_component): an entity with scope_test_marker_component (Label = "B")
#   - place this test component where it belongs to no scope
# Result: [TEST] SceneGraphSystem in the output log
scene_graph_system_test_component<public> := class<final_super>(component):

    # Entity inside scope A (checks that FindScopedComponent returns A's marker)
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

    # Creates Entity - Outer (marker "outer") - Inner (marker "inner") - Leaf at runtime and checks that the nearest is found first
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

    # ResolveScopedComponent returns the remembered one without searching, otherwise finds it from the scope
    TestResolveScoped<private>(Results:test_log):void =
        if (Child := ScopedChild?):
            var Known:?scope_test_marker_component = false
            set Known = Child.ResolveScopedComponent(Known, scope_test_marker_component)
            Results.Check("ResolveScopedComponent finds in scope A", if (Found := Known?, Found.Label = "A") then true else false)
            # Even when called from outside the scope, the remembered one (A) is returned as is
            Again := Entity.ResolveScopedComponent(Known, scope_test_marker_component)
            Results.Check("ResolveScopedComponent keeps the known one", if (Found := Again?, Found.Label = "A") then true else false)
        Nothing:?scope_test_absent_component = false
        Results.Check("ResolveScopedComponent returns false when not found", if (Entity.ResolveScopedComponent(Nothing, scope_test_absent_component)?) then false else true)
