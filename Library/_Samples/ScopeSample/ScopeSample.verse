using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { PlayerSystem }
using { SceneGraphSystem }

# Role: scope (game_scope_component) sample. On the frame after start, Prints which scope it belongs to (FindScopeEntity) and what FindScopedComponent[player_manager_component] finds (inside the scope, the whole world, or nothing). With OtherEntity set, also tells whether the search from that entity finds the same player_manager_component as its own
# Placement: attach to an entity in the editor. Setups to try:
#   - Under scope A (a game_scope_component entity), an entity with player_manager_component and the entity with this component
#   - Under scope B (another game_scope_component), another entity with player_manager_component; set an entity below it as OtherEntity -> prints "a different player_manager_component"
#   - Placed outside any scope -> prints "No scope: searching the whole world"
# Try it: start the session and look for [scope_sample] in the output log. With RepeatSeconds above 0, it repeats at that interval (to check after moving the entity at runtime)
scope_sample_component<public> := class<final_super>(component):

    # Entity to compare with (nothing is compared when empty)
    @editable
    OtherEntity<public>:?entity = false

    # When above 0, Prints repeatedly every this many seconds. 0 prints once at start
    @editable
    RepeatSeconds<public>:float = 0.0

    OnSimulate<override>()<suspends>:void =
        TickEvents.PrePhysics.Await()
        loop:
            Report()
            if (RepeatSeconds <= 0.0):
                break
            Sleep(RepeatSeconds)

    # Print the current scope and the player_manager_component found
    Report<public>():void =
        Print("[scope_sample] --- Scope check ---", ?Duration := 8.0)
        if (Scope := Entity.FindScopeEntity[]):
            Depth := CountDepth(Scope)
            Print("[scope_sample] Scope found: the nearest ancestor game_scope_component is the entity {Depth} level(s) up (0 means itself)", ?Duration := 8.0)
        else:
            Print("[scope_sample] No scope: searching the whole world (under the simulation entity)", ?Duration := 8.0)

        if (Manager := Entity.FindScopedComponent[player_manager_component]):
            Where := if (Manager.Entity.FindScopeEntity[]) then "inside a scope" else "outside any scope (world)"
            Print("[scope_sample] FindScopedComponent[player_manager_component]: found ({Where}. {Manager.GetPlayerCount()} player(s))", ?Duration := 8.0)
            if (Other := OtherEntity?):
                if (OtherManager := Other.FindScopedComponent[player_manager_component]):
                    Same := if (OtherManager = Manager) then "the same player_manager_component" else "a different player_manager_component (different scope)"
                    Print("[scope_sample] Searching from OtherEntity: {Same}", ?Duration := 8.0)
                else:
                    Print("[scope_sample] Searching from OtherEntity: not found", ?Duration := 8.0)
        else:
            Print("[scope_sample] FindScopedComponent[player_manager_component]: not found (place a player_manager_component inside the scope or in the world)", ?Duration := 8.0)

    # How many parent levels from Entity up to Ancestor (the levels walked when Ancestor is not an ancestor)
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
