using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Input }
using { AbilitySystem }
using { ItemSystem }
using { InputSystem }
using { MovementSystem }
using { SceneGraphSystem }
using { GravitySystem.TooltipKit }

# Role: an ability that places gravity points. When a granted player presses PlaceAction (fire by default), places a gravity point (gravity_well_component) where the reticle aims (in front of whatever is hit within PlaceDistanceCm, or PlaceDistanceCm ahead if nothing is hit) and removes it after DurationSeconds seconds.
#   Pressing again while placed removes it without waiting. Each player can place at most one (per instance of this ability). A placed point stays until its time runs out even if the ability is revoked (removed at the end of the simulation)
#   The point's look is created from WellPrefab (a prefab with a mesh etc.) and gravity_well_component (RadiusCm, StrengthCmPerSecondSquared) is added. With the default entity as WellPrefab, the point has no visual
# How it is granted is chosen by a component on the same entity:
#   - as an item (while equipped) → place it on the item's entity together with item_component, item_holder_component and ability_grant_item_component. Add exclusive_item_component to limit it to one per player
#   - to everyone from the start / while active → ability_grant_players_component (each player can place one)
#   - while a condition holds → ability_grant_condition_component (conditions as children)
#   - from code → Grant / Revoke
# Notifies: PlacedEvent on placing, RemovedEvent on removal
# Requirements: one player_manager_component in the scope (or the world), so the gravity knows whom to pull
gravity_point_ability_component<public> := class<final_super>(ability_component):

    # The prefab used as the look of a placed point. Each placement creates one and adds gravity (with the default entity, the point has no visual)
    @editable:
        ToolTip := GravityWellPrefabToolTip
        Categories := array{GravityCategory}
    WellPrefab<public>:concrete_subtype(entity) = entity
    # Time until a placed point disappears (seconds; default 30). Pressing again while placed removes it at once
    @editable_number(float):
        ToolTip := GravityDurationToolTip
        Categories := array{GravityCategory}
        MinValue := option{1.0}
        MaxValue := option{600.0}
    DurationSeconds<public>:float = 30.0
    # How many centimeters ahead of the reticle to place it (default 800). If something is in the way, it is placed in front of it
    @editable_number(float):
        ToolTip := GravityPlaceDistanceToolTip
        Categories := array{GravityCategory}
        MinValue := option{100.0}
        MaxValue := option{10000.0}
    PlaceDistanceCm<public>:float = 800.0
    # Radius the placed point's pull reaches (centimeters; default 1500). Strongest at the center, 0 at this distance
    @editable_number(float):
        ToolTip := GravityRadiusToolTip
        Categories := array{GravityCategory}
        MinValue := option{100.0}
        MaxValue := option{20000.0}
    RadiusCm<public>:float = 1500.0
    # Pull strength of the placed point at its center (centimeters per second squared; default 1200)
    @editable_number(float):
        ToolTip := GravityStrengthToolTip
        Categories := array{GravityCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    StrengthCmPerSecondSquared<public>:float = 1200.0
    # The input that places a point (or removes it while placed). Default WeaponPrimary (the attack button)
    @editable:
        ToolTip := GravityPlaceActionToolTip
        Categories := array{GravityCategory, GravityInputCategory}
    PlaceAction<public>:input_action(logic) = Character.WeaponPrimary
    # The key mapping enabled while granted. One that contains PlaceAction. Default RangedWeaponMapping
    @editable:
        ToolTip := GravityPlaceMappingToolTip
        Categories := array{GravityCategory, GravityInputCategory}
    PlaceMapping<public>:input_mapping = Character.RangedWeaponMapping
    # true removes PlaceMapping when revoked (only for a mapping dedicated to this ability; default false)
    @editable:
        ToolTip := GravityRemoveMappingToolTip
        Categories := array{GravityCategory, GravityInputCategory}
    RemoveMappingOnRevoke<public>:logic = false

    # Distance to keep in front of the hit surface (centimeters)
    SurfaceGapCm<private>:float = 150.0

    PlacedEventInternal<private><final>:event(tuple(agent, gravity_well_component)) = event(tuple(agent, gravity_well_component)){}
    RemovedEventInternal<private><final>:event(agent) = event(agent){}

    # Fires when someone places a point, with (the placer, the placed point) (Await / Subscribe; cannot be signaled from outside)
    PlacedEvent<public><final>:listenable(tuple(agent, gravity_well_component)) = MakeProxyListenable(PlacedEventInternal)

    # Fires with the placer when someone's point disappears (timed out, pressed again, end of the simulation)
    RemovedEvent<public><final>:listenable(agent) = MakeProxyListenable(RemovedEventInternal)

    var Wells<private>:[agent]gravity_well_component = map{}
    var PlaceCounts<private>:[agent]int = map{}

    # Returns the point Agent placed if it exists now. Fails if none
    FindWell<public>(Agent:agent)<decides><transacts>:gravity_well_component =
        Wells[Agent]

    RunFor<override>(Agent:agent)<suspends>:void =
        MaybeInput := Agent.AwaitPlayerInput()
        if (PlayerInput := MaybeInput?):
            race:
                PlayerInput.HoldInputMapping(PlaceMapping, RemoveMappingOnRevoke)
                loop:
                    PlayerInput.AwaitPressed(PlaceAction)
                    Toggle(Agent)

    # Places a point where the reticle aims if Agent has none, removes it if one exists (same as pressing the button; call it to let a player use it without input). Does nothing without a character
    Toggle<public>(Agent:agent):void =
        if (FindWell[Agent]):
            RemoveWell(Agent)
        else if (FortCharacter := Agent.GetFortCharacter[]):
            PlaceWell(Agent, FindPlacePosition(FortCharacter))

    # Removes Agent's point. Does nothing if none
    RemoveWell<public>(Agent:agent):void =
        if (Well := Wells[Agent]):
            set Wells = Wells.RemoveKey(Agent)
            Well.Entity.RemoveFromParent()
            RemovedEventInternal.Signal(Agent)

    OnEndSimulation<override>():void =
        for (Agent -> Well : Wells):
            RemoveWell(Agent)
        (super:)OnEndSimulation()

    PlaceWell<private>(Agent:agent, Position:vector3):void =
        if (SimulationEntity := Entity.GetSimulationEntity[]):
            Body := WellPrefab{}
            Well := gravity_well_component{Entity := Body, RadiusCm := RadiusCm, StrengthCmPerSecondSquared := StrengthCmPerSecondSquared}
            Body.AddComponents(array{Well})
            SimulationEntity.AddEntities(array{Body})
            Current := Body.GetGlobalTransform()
            Body.SetGlobalTransform(Current.WithTranslation(Position))
            Count := GetPlaceCount(Agent) + 1
            if (set PlaceCounts[Agent] = Count) {}
            if (set Wells[Agent] = Well) {}
            PlacedEventInternal.Signal((Agent, Well))
            spawn{ExpireLater(Agent, Count)}

    GetPlaceCount<private>(Agent:agent)<transacts>:int =
        if (Count := PlaceCounts[Agent]) then Count else 0

    ExpireLater<private>(Agent:agent, Count:int)<suspends>:void =
        Sleep(DurationSeconds)
        if (GetPlaceCount(Agent) = Count):
            RemoveWell(Agent)

    FindPlacePosition<private>(FortCharacter:fort_character)<transacts>:vector3 =
        Origin := FortCharacter.GetViewOrigin()
        Direction := FortCharacter.GetViewDirection()
        if (CharacterEntity := FortCharacter.GetEntity[], Hit := FindFirstHit[CharacterEntity, Origin, Direction * PlaceDistanceCm]):
            Origin + Direction * Max(Hit.SourceHitDistance - SurfaceGapCm, 0.0)
        else:
            Origin + Direction * PlaceDistanceCm

    FindFirstHit<private>(CharacterEntity:entity, Origin:vector3, Displacement:vector3)<decides><transacts>:sweep_hit =
        first:
            Hit : CharacterEntity.FindSweepHits(Displacement, MakeTranslationTransform(Origin), collision_point{})
            Hit.TargetComponent.Entity <> CharacterEntity
        do:
            Hit
