using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { MovementSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { GravitySystem.TooltipKit }

# Role: a point with gravity. Every frame (TickEvents.PrePhysics), pulls players within RadiusCm of this entity toward the center with StrengthCmPerSecondSquared (maximum at the center, 0 at RadiusCm) (added to their velocity). Players whose movement is being controlled (body carries controlled_movement_tag; swinging, etc.) are not pulled (their movement takes priority)
# Placement: attach to an entity in the editor (gravity_point_ability_component may also create it at run time)
# Same entity: the visual mesh (with collision, it can also be grabbed by a swing)
# Requirements: one player_manager_component in the scope (or the world) (the players to pull). Looked up once at the start and remembered (retrying every second until found)
gravity_well_component<public> := class<final_super>(component):

    # Radius the pull reaches (centimeters; default 1500). Strongest at the center, 0 at this distance
    @editable_number(float):
        ToolTip := GravityRadiusToolTip
        Categories := array{GravityCategory}
        MinValue := option{100.0}
        MaxValue := option{20000.0}
    RadiusCm<public>:float = 1500.0
    # Pull strength at the center (centimeters per second squared; default 1200). The speed toward the center grows by this much every second
    @editable_number(float):
        ToolTip := GravityStrengthToolTip
        Categories := array{GravityCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    StrengthCmPerSecondSquared<public>:float = 1200.0

    OnSimulate<override>()<suspends>:void =
        # Retry every second until a player_manager_component is found (once found, remember it and never look again)
        Found := Entity.AwaitScopedComponent(player_manager_component)
        loop:
            DeltaTime := TickEvents.PrePhysics.Await()
            PullPlayers(Found, DeltaTime)

    PullPlayers<private>(Found:player_manager_component, DeltaTime:float):void =
        Center := Entity.GetGlobalTranslation()
        for (Slot : Found.GetSlots(), not Slot.Player.HasPlayerTag[controlled_movement_tag]):
            Pull(Slot.Player, Center, DeltaTime)

    Pull<private>(Agent:agent, Center:vector3, DeltaTime:float):void =
        if:
            FortCharacter := Agent.GetFortCharacter[]
            Position := FortCharacter.FindGlobalTranslation[]
            Offset := Center - Position
            Gap := Offset.Length()
            Gap > 1.0
            Gap < RadiusCm
        then:
            Falloff := 1.0 - Gap / RadiusCm
            # GetLinearVelocity / SetLinearVelocity are in meters per second, so convert from centimeters
            Push := Offset.MakeUnitVector() * (StrengthCmPerSecondSquared / 100.0 * Falloff * DeltaTime)
            FortCharacter.SetLinearVelocity(FortCharacter.GetLinearVelocity() + Push)
