using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { CharacterSystem }
using { CharacterSystem.TooltipKit }

# Base of the tags attached to the owner (agent) while modifiers (buffs / ability grants) are stacked on the body. The subclass tells what is changed
#   Attached by the BuffKit components (character_buff_component / character_move_grant_component). Two or more tags of the same type may be attached (stacking)
character_modified_tag<public> := class<abstract>(player_state_tag):
# A modifier with a speed multiplier other than 1 is stacked
character_speed_modified_tag<public> := class(character_modified_tag):
# A modifier with a jump multiplier other than 1 is stacked
character_jump_modified_tag<public> := class(character_modified_tag):
# A modifier with a gravity multiplier other than 1 is stacked
character_gravity_modified_tag<public> := class(character_modified_tag):
# The air jump count is increased
character_air_jumps_added_tag<public> := class(character_modified_tag):
# Dash is granted (allowed even when dash's RequiresGrant is on)
character_dash_granted_tag<public> := class(character_modified_tag):
# The side-input style (walk's SideStyle) is set by a modifier
character_side_style_modified_tag<public> := class(character_modified_tag):
# Clinging to walls / ceilings is granted (allowed even when ClingKit's character_cling_component has RequiresGrant on)
character_cling_granted_tag<public> := class(character_modified_tag):

# Role: from the activation signal (activated_event) to the deactivation signal (deactivated_event), stacks multipliers (speed, jump, gravity) onto the custom character's body. Always removes them when stopped
#   With OverrideSideStyle, sets walk's side-input style to SideStyle for that time (pick up to switch between turning, strafing and turning in place)
#   Stacking: however many are placed (however many times the effect is picked up), multipliers multiply. Removing one restores only its share (other components' shares remain). The side-input style is the last one stacked; when all are removed, walk's base value returns
#   Which body it affects: (1) the body on this entity or an ancestor (when placed inside a loadout body), (2) the owner's body (under the player's slot: a PickupSystem effect prefab or a loadout), (3) the body of the agent in an activation signal that says who triggered it (activated_by_agent_event)
# Placement: in the editor, attach to an entity. The root of a PickupSystem effect prefab (same entity as pickup_effect_component) or a child, inside a loadout, or wherever the activation signal arrives
# When: from the activation signal to the deactivation signal. From start with ActiveOnBegin
# Tags: while stacked, on the body's owner: character_speed_modified_tag / character_jump_modified_tag / character_gravity_modified_tag (only those whose multiplier is not 1) / character_side_style_modified_tag (with OverrideSideStyle)
# From outside: Apply / Remove / IsApplied
# Requirements / notes: only custom character bodies (character_motor_component). Speed applies to walk's MaxSpeedCmPerSecond (also when running), jump to jump's JumpSpeedCmPerSecond. Logs to the output log if no body is found
character_buff_component<public> := class<final_super>(component):

    # Multiplier on the walk / run speed cap. Default 1 (unchanged)
    @editable_number(float):
        ToolTip := BuffSpeedToolTip
        Categories := array{CharacterBuffCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    SpeedMultiplier<public>:float = 1.0
    # Multiplier on the upward speed at the moment of jumping (height changes roughly with the square). Default 1
    @editable_number(float):
        ToolTip := BuffJumpToolTip
        Categories := array{CharacterBuffCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    JumpMultiplier<public>:float = 1.0
    # Multiplier on gravity (0.5 for a floaty fall, 0 for no falling). Default 1
    @editable_number(float):
        ToolTip := BuffGravityToolTip
        Categories := array{CharacterBuffCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    GravityMultiplier<public>:float = 1.0
    # When on, sets walk's side-input style to SideStyle while stacked. Default off (unchanged)
    @editable:
        ToolTip := BuffOverrideSideStyleToolTip
        Categories := array{CharacterBuffCategory}
    OverrideSideStyle<public>:logic = false
    # With OverrideSideStyle, the side-input style while stacked (Turn / Strafe / TankTurn). Default Strafe
    @editable:
        ToolTip := BuffSideStyleToolTip
        Categories := array{CharacterBuffCategory}
    SideStyle<public>:character_side_style = character_side_style.Strafe
    # When on, stacks from start without waiting for the activation signal. Default off
    @editable:
        ToolTip := BuffActiveOnBeginToolTip
        Categories := array{CharacterBuffCategory}
    ActiveOnBegin<public>:logic = false

    Applier<private>:character_modifier_applier = character_modifier_applier{Label := "character_buff_component"}

    OnSimulate<override>()<suspends>:void =
        if (ActiveOnBegin?):
            # Wait until the body (components of the same prefab) is complete
            Sleep(0.0)
            Apply(false)

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Apply(if (Agent := SceneEvent.FindActivatingAgent[]) then option{Agent} else false)
        else if (deactivated_event[SceneEvent]):
            Remove()
        false

    OnEndSimulation<override>():void =
        Remove()
        (super:)OnEndSimulation()

    # Stacks the multipliers onto the body (does nothing if already stacked). Activator is a hint for finding the body (who triggered it. false if unknown)
    Apply<public>(Activator:?agent):void =
        var AddedTags:[]tag = array{}
        if (SpeedMultiplier <> 1.0):
            set AddedTags += array{character_speed_modified_tag{}}
        if (JumpMultiplier <> 1.0):
            set AddedTags += array{character_jump_modified_tag{}}
        if (GravityMultiplier <> 1.0):
            set AddedTags += array{character_gravity_modified_tag{}}
        if (OverrideSideStyle?):
            set AddedTags += array{character_side_style_modified_tag{}}
        Side:?character_side_style = if (OverrideSideStyle?) then option{SideStyle} else false
        Applier.Apply(Entity, Activator, character_modifier{SpeedMultiplier := SpeedMultiplier, JumpMultiplier := JumpMultiplier, GravityMultiplier := GravityMultiplier, SideStyle := Side}, AddedTags)

    # Removes the stacked multipliers (does nothing if not stacked)
    Remove<public>():void =
        Applier.Remove()

    # Succeeds if currently stacked
    IsApplied<public>()<decides><transacts>:void =
        Applier.IsApplied[]

# Role: from the activation signal to the deactivation signal, adds abilities to the custom character's body (more air jumps, dash permission, clinging to walls and ceilings). Always removes them when stopped
#   Air jumps: adds ExtraAirJumps to jump's AirJumps (picked up in the air, the extra jumps are usable right away). Stacking adds up
#   Dash: with GrantDash, a body whose dash has RequiresGrant on can dash (keep the dash component and its DashAction input on the body)
#   Cling: with GrantCling, a body carrying ClingKit's character_cling_component (RequiresGrant on) can cling to walls and ceilings (the slime ability. When removed, a clinging body lets go and falls)
#   Which body it affects: same as character_buff_component
# Placement: in the editor, attach to an entity. A PickupSystem effect prefab, inside a loadout, or wherever the activation signal arrives
# When: from the activation signal to the deactivation signal. From start with ActiveOnBegin
# Tags: while added, on the body's owner: character_air_jumps_added_tag (when ExtraAirJumps is not 0) / character_dash_granted_tag (with GrantDash) / character_cling_granted_tag (with GrantCling)
# From outside: Apply / Remove / IsApplied
character_move_grant_component<public> := class<final_super>(component):

    # Number added to the air jump count (1 for a double jump). Default 1
    @editable_number(int):
        ToolTip := MoveGrantAirJumpsToolTip
        Categories := array{CharacterBuffCategory}
        MinValue := option{0}
        MaxValue := option{10}
    ExtraAirJumps<public>:int = 1
    # When on, a body whose dash has RequiresGrant on can dash. Default off
    @editable:
        ToolTip := MoveGrantDashToolTip
        Categories := array{CharacterBuffCategory}
    GrantDash<public>:logic = false
    # When on, a body carrying ClingKit's character_cling_component (RequiresGrant on) can cling to walls and ceilings (the slime ability). Default off
    @editable:
        ToolTip := MoveGrantClingToolTip
        Categories := array{CharacterBuffCategory}
    GrantCling<public>:logic = false
    # When on, adds from start without waiting for the activation signal. Default off
    @editable:
        ToolTip := BuffActiveOnBeginToolTip
        Categories := array{CharacterBuffCategory}
    ActiveOnBegin<public>:logic = false

    Applier<private>:character_modifier_applier = character_modifier_applier{Label := "character_move_grant_component"}

    OnSimulate<override>()<suspends>:void =
        if (ActiveOnBegin?):
            Sleep(0.0)
            Apply(false)

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Apply(if (Agent := SceneEvent.FindActivatingAgent[]) then option{Agent} else false)
        else if (deactivated_event[SceneEvent]):
            Remove()
        false

    OnEndSimulation<override>():void =
        Remove()
        (super:)OnEndSimulation()

    # Adds the abilities to the body (does nothing if already added). Activator is a hint for finding the body
    Apply<public>(Activator:?agent):void =
        var AddedTags:[]tag = array{}
        if (ExtraAirJumps <> 0):
            set AddedTags += array{character_air_jumps_added_tag{}}
        if (GrantDash?):
            set AddedTags += array{character_dash_granted_tag{}}
        if (GrantCling?):
            set AddedTags += array{character_cling_granted_tag{}}
        Applier.Apply(Entity, Activator, character_modifier{ExtraAirJumps := ExtraAirJumps, GrantsDash := GrantDash, GrantsCling := GrantCling}, AddedTags)

    # Removes the added abilities (does nothing if not added)
    Remove<public>():void =
        Applier.Remove()

    # Succeeds if currently added
    IsApplied<public>()<decides><transacts>:void =
        Applier.IsApplied[]

# Role: helper shared by the BuffKit components for finding the body and stacking / removing a modifier (runtime only). Remembers the stacked modifier and the tags attached to the owner, and removes only its own share on Remove
character_modifier_applier<internal> := class<internal>:
    # Component name shown in the output log
    Label<internal>:string

    var<private> Handle:?cancelable = false
    var<private> Holders:[]player_tag_holder = array{}

    # Finds the body from Context (ancestor body -> owner's body -> Activator's body), stacks Modifier and attaches OwnerTags to the body's owner. Does nothing if already stacked
    Apply<internal>(Context:entity, Activator:?agent, Modifier:character_modifier, OwnerTags:[]tag):void =
        if (Handle?):
            return
        if (Motor := FindTargetMotor[Context, Activator]):
            set Handle = option{Motor.AddModifier(Modifier)}
            if (Owner := Motor.FindOwner[]):
                set Holders = for (Tag : OwnerTags):
                    Holder := player_tag_holder{}
                    Holder.Add(Owner, Tag)
                    Holder
        else:
            Print("[{Label}] no custom character body (character_motor_component) to affect (place it inside the body or where there is an owner, or drive it with an activation signal that says who triggered it)")

    # Removes the stacked modifier and the attached tags
    Remove<internal>():void =
        Handle.CancelIfSet()
        set Handle = false
        for (Holder : Holders):
            Holder.RemoveAll()
        set Holders = array{}

    IsApplied<internal>()<decides><transacts>:void =
        Handle?

    FindTargetMotor<private>(Context:entity, Activator:?agent)<decides><transacts>:character_motor_component =
        if (Above := Context.FindCharacterMotorAbove[]):
            Above
        else if (Owner := Context.FindOwningPlayer[], Motor := Context.FindCharacterMotorFor[Owner]):
            Motor
        else:
            Context.FindCharacterMotorFor[Activator?]
