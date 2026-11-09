using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Playspaces }
using { /Fortnite.com/UI }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { WidgetSystem.TooltipKit }

# Role: while activated, hides part of the standard Fortnite HUD (the checked elements) per person for everyone in the area. When it stops, restores only the people it hid (does not touch the island-wide settings)
# Placement: in the editor, attach to an entity
# When: with ActiveOnBegin, from the start. Hides on an activation signal and restores on a deactivation signal. Also hides for late joiners
# From outside: Activate / Deactivate / IsActive
# Requirements: one player_manager_component in the area (or world)
hud_hide_component<public> := class<final_super>(component):

    # When on, hides from the start of the game. Default off
    @editable:
        ToolTip := HudHideActiveOnBeginToolTip
        Categories := array{HudHideCategory}
    ActiveOnBegin<public>:logic = false
    # When on, hides the whole standard HUD (creative_hud_identifier_all, player_hud_identifier_all. The individual settings below are ignored). Default off
    @editable:
        ToolTip := HudHideAllToolTip
        Categories := array{HudHideCategory}
    HideAll<public>:logic = false
    # Minimap
    @editable:
        ToolTip := HudHideElementToolTip
        Categories := array{HudHideCategory}
    HideMinimap<public>:logic = true
    # Build menu and materials
    @editable:
        ToolTip := HudHideElementToolTip
        Categories := array{HudHideCategory}
    HideBuild<public>:logic = true
    # Team info, player count, eliminations
    @editable:
        ToolTip := HudHideElementToolTip
        Categories := array{HudHideCategory}
    HideTeamInfo<public>:logic = true
    # Round and storm info
    @editable:
        ToolTip := HudHideElementToolTip
        Categories := array{HudHideCategory}
    HideRoundInfo<public>:logic = true
    # Experience
    @editable:
        ToolTip := HudHideElementToolTip
        Categories := array{HudHideCategory}
    HideExperience<public>:logic = true
    # Health and shields
    @editable:
        ToolTip := HudHideElementToolTip
        Categories := array{HudHideCategory}
    HideHealth<public>:logic = false
    # Inventory bar
    @editable:
        ToolTip := HudHideElementToolTip
        Categories := array{HudHideCategory}
    HideInventory<public>:logic = false
    # Interaction prompts
    @editable:
        ToolTip := HudHideElementToolTip
        Categories := array{HudHideCategory}
    HideInteractionPrompts<public>:logic = false

    var<private> Active:logic = false
    var<private> Hidden:[]player = array{}
    var<private> AddedSubscription:?cancelable = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (ActiveOnBegin?):
            Activate()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Activate()
        else if (deactivated_event[SceneEvent]):
            Deactivate()
        false

    OnEndSimulation<override>():void =
        Deactivate()
        (super:)OnEndSimulation()

    # Start hiding (everyone present now and anyone who joins later). Does nothing if already hiding
    Activate<public>():void =
        if (Active?):
            return
        set Active = true
        if (OwningPlayer := Entity.FindOwningPlayer[]):
            # On an entity that has an owner (inside a character, etc.), hide only for the owner
            HideFor(OwningPlayer)
        else if (Manager := Entity.FindScopedComponent[player_manager_component]):
            set AddedSubscription = option{Manager.PlayerAddedEvent.Subscribe(HideFor)}
            for (Slot : Manager.GetSlots()):
                HideFor(Slot.Player)

    # Restore the people this component hid. Does nothing if not hiding
    Deactivate<public>():void =
        if (not Active?):
            return
        set Active = false
        AddedSubscription.CancelIfSet()
        set AddedSubscription = false
        if (Playspace := Entity.GetPlayspaceForEntity[]):
            Controller := Playspace.GetHUDController()
            for (Player : Hidden, Player.IsActive[]):
                Controller.ResetElementsForPlayer(Player, GetElements())
        set Hidden = array{}

    # Succeeds while hiding
    IsActive<public>()<decides><transacts>:void =
        Active?

    HideFor<private>(Player:player):void =
        if (Playspace := Entity.GetPlayspaceForEntity[]):
            Playspace.GetHUDController().HideElementsForPlayer(Player, GetElements())
            set Hidden += array{Player}

    GetElements<private>()<transacts>:[]hud_element_identifier =
        var Elements:[]hud_element_identifier = array{}
        if (HideAll?):
            # Everything (health, inventory, materials, minimap, rounds, interaction prompts, etc.). The individual ones are listed too (in case some element survives "all" alone)
            return array{creative_hud_identifier_all{}, player_hud_identifier_all{}, creative_hud_identifier_minimap{}, creative_hud_identifier_build_menu{}, creative_hud_identifier_crafting_resources{},
                creative_hud_identifier_team_info{}, creative_hud_identifier_player_count{}, creative_hud_identifier_elimination_counter{}, creative_hud_identifier_round_info{}, creative_hud_identifier_round_timer{},
                creative_hud_identifier_storm_timer{}, creative_hud_identifier_storm_notifications{}, creative_hud_identifier_experience_level{}, creative_hud_identifier_experience_ui{}, creative_hud_identifier_experience_supercharged{},
                creative_hud_identifier_health{}, creative_hud_identifier_health_numbers{}, creative_hud_identifier_shields{}, creative_hud_identifier_shield_numbers{}, creative_hud_identifier_player_inventory{},
                creative_hud_identifier_equipped_item{}, creative_hud_identifier_interaction_prompts{}, creative_hud_identifier_pickup_stream{}, creative_hud_identifier_map_prompts{}, creative_hud_identifier_hud_info{}}
        if (HideMinimap?):
            set Elements += array{creative_hud_identifier_minimap{}}
        if (HideBuild?):
            set Elements += array{creative_hud_identifier_build_menu{}, creative_hud_identifier_crafting_resources{}}
        if (HideTeamInfo?):
            set Elements += array{creative_hud_identifier_team_info{}, creative_hud_identifier_player_count{}, creative_hud_identifier_elimination_counter{}}
        if (HideRoundInfo?):
            set Elements += array{creative_hud_identifier_round_info{}, creative_hud_identifier_round_timer{}, creative_hud_identifier_storm_timer{}, creative_hud_identifier_storm_notifications{}}
        if (HideExperience?):
            set Elements += array{creative_hud_identifier_experience_level{}, creative_hud_identifier_experience_ui{}, creative_hud_identifier_experience_supercharged{}}
        if (HideHealth?):
            set Elements += array{creative_hud_identifier_health{}, creative_hud_identifier_health_numbers{}, creative_hud_identifier_shields{}, creative_hud_identifier_shield_numbers{}}
        if (HideInventory?):
            set Elements += array{creative_hud_identifier_player_inventory{}, creative_hud_identifier_equipped_item{}}
        if (HideInteractionPrompts?):
            set Elements += array{creative_hud_identifier_interaction_prompts{}}
        Elements
