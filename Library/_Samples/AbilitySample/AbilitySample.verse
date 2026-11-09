using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Verse.org/Input/UI }
using { AbilitySystem }
using { AbilitySystem.GrantKit }
using { ActivationSystem }
using { GravitySystem }
using { HoverSystem }
using { InputSystem }
using { JetpackSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { SwingSystem }

# Role: AbilitySystem sample. Places no abilities itself; at start it Prints a list of the abilities (ability_component subclasses) and grant components on the same entity, and Prints each ability's GrantedEvent / RevokedEvent. While running, each player can press ToggleAction (default E / RB) to toggle their own grant of every ability on this entity (Revoke when granted, Grant otherwise)
# Placement: attach in the editor to an entity with at least one ability component (swing_ability_component, jetpack_ability_component, hover_ability_component, gravity_point_ability_component, ...). A grant component (ability_grant_players_component etc.) is optional. Place one player_manager_component in the scope (or the world)
# Try it: when the session starts, the output log shows "Abilities: n" and "Grant: ...". Pressing ToggleAction alternates "Grant" / "Revoke" together with the abilities' GrantedEvent / RevokedEvent Prints. With an ability_grant_players_component (GrantOnBegin) placed alongside, the ability is granted from the start, so the first press is a Revoke (grant count 1 -> 0)
# When: with StartOnBegin true, from the start of the simulation. With false, from the activate signal (activated_event) to the deactivate signal (deactivated_event)
# Requirements / notes: Revoke only decrements the grant count by 1, so when granted by several sources it does not stop after one press (see ability_component). ToggleMapping is removed on stop (RemoveMappingOnStop). If you choose a character-control Mapping as ToggleMapping, turn RemoveMappingOnStop off (removing it makes the player unable to move)
ability_sample_component<public> := class<final_super>(component):

    # When on, starts from the start of the simulation. When off, waits for the activate signal
    @editable
    StartOnBegin<public>:logic = true

    # Input that toggles the grant (choose one contained in ToggleMapping)
    @editable
    ToggleAction<public>:input_action(logic) = NextTab

    # Key mapping added to each player while running
    @editable
    ToggleMapping<public>:input_mapping = MenuNavigationMapping

    # When on, ToggleMapping is removed on stop. Turn off when a character-control Mapping is chosen
    @editable
    RemoveMappingOnStop<public>:logic = true

    Views<private>:player_view_set = player_view_set{}
    var<private> Subscriptions:[]cancelable = array{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Describe()
        for (Ability : Entity.GetAbilities()):
            set Subscriptions += array:
                Ability.GrantedEvent.Subscribe(OnGranted)
                Ability.RevokedEvent.Subscribe(OnRevoked)
        if (StartOnBegin?):
            Activate()

    OnReceive<override>(SceneEvent:scene_event):logic =
        Views.HandleActivation(SceneEvent, Entity, CreateView)
        false

    OnEndSimulation<override>():void =
        Views.Deactivate()
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        (super:)OnEndSimulation()

    # Accept the toggle input from everyone (late joiners too). Does nothing when already accepting
    Activate<public>():void =
        Views.Activate(Entity, CreateView)

    # Stop accepting
    Deactivate<public>():void =
        Views.Deactivate()

    # Succeeds while running
    IsActive<public>()<decides><transacts>:void =
        Views.IsActive[]

    # Toggle the grant of every ability on this entity for Agent (called from the view)
    Toggle<internal>(Agent:agent):void =
        Abilities := Entity.GetAbilities()
        if (Abilities.Length = 0):
            Print("[ability_sample] This entity has no ability (ability_component subclass)", ?Duration := 4.0)
            return
        for (Ability : Abilities):
            Label := DescribeAbility(Ability)
            if (Ability.IsGranted[Agent]):
                Print("[ability_sample] Revoke: {Label}", ?Duration := 4.0)
                Ability.Revoke(Agent)
            else:
                Print("[ability_sample] Grant: {Label}", ?Duration := 4.0)
                Ability.Grant(Agent)

    # Print the abilities and grant components on the same entity
    Describe<private>():void =
        Abilities := Entity.GetAbilities()
        Print("[ability_sample] Abilities: {Abilities.Length}", ?Duration := 8.0)
        for (Ability : Abilities):
            Print("[ability_sample]   - {DescribeAbility(Ability)}", ?Duration := 8.0)
        var GrantCount:int = 0
        if (Grant := Entity.GetComponent[ability_grant_players_component]):
            set GrantCount += 1
            OnBegin := if (Grant.GrantOnBegin?) then "on" else "off"
            Print("[ability_sample] Grant: ability_grant_players_component (to everyone. GrantOnBegin is {OnBegin})", ?Duration := 8.0)
        if (Entity.GetComponent[ability_grant_item_component]):
            set GrantCount += 1
            Print("[ability_sample] Grant: ability_grant_item_component (to the item holder)", ?Duration := 8.0)
        if (Entity.GetComponent[ability_grant_condition_component]):
            set GrantCount += 1
            Print("[ability_sample] Grant: ability_grant_condition_component (while the child conditions are satisfied)", ?Duration := 8.0)
        if (GrantCount = 0):
            Print("[ability_sample] Grant: none (press ToggleAction to Grant / Revoke from code)", ?Duration := 8.0)

    # Human-readable name of the ability kind (Library abilities by name, others as "other")
    DescribeAbility<private>(Ability:ability_component)<transacts>:string =
        if (swing_ability_component[Ability]):
            "swing_ability_component (swing)"
        else if (jetpack_ability_component[Ability]):
            "jetpack_ability_component (jetpack)"
        else if (hover_ability_component[Ability]):
            "hover_ability_component (hover)"
        else if (gravity_point_ability_component[Ability]):
            "gravity_point_ability_component (gravity point)"
        else:
            "ability_component subclass (other)"

    OnGranted<private>(Agent:agent):void =
        Print("[ability_sample] GrantedEvent: granted ({GrantedCount()} player(s) granted)", ?Duration := 4.0)

    OnRevoked<private>(Agent:agent):void =
        Print("[ability_sample] RevokedEvent: revoked ({GrantedCount()} player(s) granted)", ?Duration := 4.0)

    # Number of players granted any ability (the count of the first ability, not the sum over abilities)
    GrantedCount<private>()<transacts>:int =
        if (First := Entity.GetAbilities()[0]) then First.GetGrantedAgents().Length else 0

    CreateView<private>(ViewEntity:entity, Slot:player_slot_component):component =
        ability_sample_view_component{Entity := ViewEntity, Source := Self, Player := Slot.Player}

# Role: one player's toggle input. Adds ToggleMapping and calls Source.Toggle every time ToggleAction is pressed
# Placement: created at runtime by ability_sample_component (never placed in the editor)
ability_sample_view_component<public> := class<final_super>(component):

    Source<public>:ability_sample_component
    Player<public>:player

    OnSimulate<override>()<suspends>:void =
        if (PlayerInput := Player.FindPlayerInput[]):
            Print("[ability_sample] Press the key that toggles the grant (default E / RB)", ?Duration := 6.0)
            race:
                PlayerInput.HoldInputMapping(Source.ToggleMapping, Source.RemoveMappingOnStop)
                loop:
                    PlayerInput.AwaitPressed(Source.ToggleAction)
                    Source.Toggle(Player)
        else:
            Print("[ability_sample] Cannot get this player's input (player_input)")
