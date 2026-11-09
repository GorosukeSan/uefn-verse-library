using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Input }
using { AbilitySystem }
using { EnergySystem }
using { ItemSystem }
using { InputSystem }
using { MovementSystem }
using { PlayerSystem }
using { HoverSystem.TooltipKit }

# Tag attached to a hovering person (agent). hover_ability_component attaches and removes it (other Systems check with Agent.HasPlayerTag[hovering_tag])
hovering_tag<public> := class(player_state_tag):

# Direction: up from the hover_ability_component's entity (SendUp). Sent when hovering starts and stops
# Receivers: ancestors (for an item, up to the owning player). Effects and HUD. Not consumed
hover_changed_event<public> := class(scene_event):
    # The ability that sent it
    Ability<public>:hover_ability_component
    # The person who started / stopped hovering
    Agent<public>:agent
    # true = started hovering, false = stopped
    Active<public>:logic

# Role: the hover ability. While a granted person holds HoverAction (default Jump) in the air, their fall speed is capped at MaxFallSpeedCmPerSecond so they float.
#   If there is energy (FindEnergyFor: an energy_component on this entity or a child, otherwise one attached to the player), it uses EnergyPerSecond per second while hovering, and hovering is impossible at 0 (the item is not lost).
#   This ability does not restore energy (to refill at checkpoints use CheckpointSystem's EnergyKit; to restore by using something use EnergySystem's RestoreKit). A person whose movement is being controlled (controlled_movement_tag attached, e.g. while swinging) does not hover
# How it is granted is chosen by the component placed on the same entity:
#   - To everyone from the start / while activated -> ability_grant_players_component (energy placed on this entity is shared by everyone; attach it to the player to have one per person)
#   - As an item (while equipped) -> place on the item's entity together with item_component, item_holder_component and ability_grant_item_component (energy on the item's entity)
#   - While a condition holds -> ability_grant_condition_component (conditions as children)
#   - From code -> Grant / Revoke
# Notifications: HoverChangedEvent and hover_changed_event when hovering starts and stops
# Tags: while hovering, hovering_tag is attached to the person (agent)
hover_ability_component<public> := class<final_super>(ability_component):

    # Fall speed cap while hovering (centimeters per second; default 100). 0 holds the current height
    @editable_number(float):
        ToolTip := HoverMaxFallSpeedToolTip
        Categories := array{HoverCategory}
        MinValue := option{0.0}
        MaxValue := option{3000.0}
    MaxFallSpeedCmPerSecond<public>:float = 100.0
    # Energy used per second while hovering (default 20). Nothing is consumed if there is no energy
    @editable_number(float):
        ToolTip := HoverEnergyPerSecondToolTip
        Categories := array{HoverCategory}
        MinValue := option{0.0}
        MaxValue := option{1000.0}
    EnergyPerSecond<public>:float = 20.0
    # Input held in the air to hover. Default is Jump
    @editable:
        ToolTip := HoverActionToolTip
        Categories := array{HoverCategory, HoverInputCategory}
    HoverAction<public>:input_action(logic) = Character.Jump
    # Key mapping enabled while granted. Must contain HoverAction. Default is TraversalMapping
    @editable:
        ToolTip := HoverMappingToolTip
        Categories := array{HoverCategory, HoverInputCategory}
    HoverMapping<public>:input_mapping = Character.TraversalMapping
    # true removes HoverMapping on revoke (only for a mapping dedicated to this ability; default false)
    @editable:
        ToolTip := HoverRemoveMappingToolTip
        Categories := array{HoverCategory, HoverInputCategory}
    RemoveMappingOnRevoke<public>:logic = false

    HoverChangedEventInternal<private><final>:event(tuple(agent, logic)) = event(tuple(agent, logic)){}

    # Delivered as (the person, true = started / false = stopped) when someone starts or stops hovering (Await / Subscribe; cannot be Signaled from outside)
    HoverChangedEvent<public><final>:listenable(tuple(agent, logic)) = MakeProxyListenable(HoverChangedEventInternal)

    var HoveringTags<private>:player_tag_holder = player_tag_holder{}

    # Succeeds if Agent is hovering now (fall speed being capped)
    IsHovering<public>(Agent:agent)<decides><transacts>:void =
        HoveringTags.Has[Agent]

    RunFor<override>(Agent:agent)<suspends>:void =
        MaybeInput := Agent.AwaitPlayerInput()
        if (PlayerInput := MaybeInput?):
            defer:
                SetHovering(Agent, false)
            race:
                PlayerInput.HoldInputMapping(HoverMapping, RemoveMappingOnRevoke)
                loop:
                    PlayerInput.AwaitPressed(HoverAction)
                    race:
                        PlayerInput.AwaitReleased(HoverAction)
                        HoverWhileHeld(Agent)
                    SetHovering(Agent, false)
        else if (not player[Agent]):
            Print("[hover_ability_component] Granted to an agent that is not a player. Input cannot be read, so it does nothing")

    HoverWhileHeld<private>(Agent:agent)<suspends>:void =
        loop:
            DeltaTime := TickEvents.PrePhysics.Await()
            if (FortCharacter := Agent.GetFortCharacter[], CanHover[Agent, FortCharacter]):
                SetHovering(Agent, true)
                Velocity := FortCharacter.GetVelocityCmPerSecond()
                if (Velocity.Up < -MaxFallSpeedCmPerSecond):
                    FortCharacter.SetVelocityCmPerSecond(vector3{Forward := Velocity.Forward, Left := Velocity.Left, Up := -MaxFallSpeedCmPerSecond})
                if (Energy := Entity.FindEnergyFor[Agent]):
                    Energy.Consume(EnergyPerSecond * DeltaTime)
            else:
                SetHovering(Agent, false)

    CanHover<private>(Agent:agent, FortCharacter:fort_character)<decides><transacts>:void =
        FortCharacter.IsInAir[]
        not Agent.HasPlayerTag[controlled_movement_tag]
        if (Energy := Entity.FindEnergyFor[Agent]):
            not Energy.IsEmpty[]

    SetHovering<private>(Agent:agent, Value:logic):void =
        Was := logic{HoveringTags.Has[Agent]}
        if (Was <> Value):
            HoveringTags.Set(Agent, Value, hovering_tag{})
            HoverChangedEventInternal.Signal((Agent, Value))
            Entity.SendUp(hover_changed_event{Ability := Self, Agent := Agent, Active := Value})
