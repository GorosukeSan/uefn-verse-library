using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Fortnite.com/Input }
using { /UnrealEngine.com/Itemization }
using { AbilitySystem }
using { ItemSystem }
using { InputSystem }
using { EnergySystem }
using { EnergySystem.TooltipKit }

# Direction: from the energy_restore_ability_component's entity upward (SendUp)
# Receivers: ancestors (for an item, up to the owning player). E.g. to show "nothing to restore" on the HUD. Not consumed
energy_restore_failed_event<public> := class(scene_event):
    # The ability that sent it
    Ability<public>:energy_restore_ability_component
    # The player who tried to use it
    Agent<public>:agent

# Role: an ability that restores energy. When a granted player presses RestoreAction (fire by default), restores RestoreAmount to that player's energy (FindRestoreTarget).
#   On a restore, if this entity is an item (has item_component) and ConsumeItemOnUse is on, consumes one item (the last one disappears and the ability is revoked). If there is nothing to restore, consumes nothing and sends energy_restore_failed_event upward
# How it is granted is chosen by a component on the same entity:
#   - as an item (while equipped; using it consumes one) → place it on the item's entity together with item_component, item_holder_component and ability_grant_item_component. Add basic_stackable_component to hold several
#   - to everyone from the start (unlimited uses) → ability_grant_players_component. Set CooldownSeconds to prevent spamming
#   - while a condition holds → ability_grant_condition_component (conditions as children)
#   - from code → Grant / Revoke
# Notifies: RestoredEvent on a restore; FailedEvent and energy_restore_failed_event when there is nothing to restore
energy_restore_ability_component<public> := class<final_super>(ability_component):

    # Amount restored per use. Restores the most depleted item in the inventory (or the player's energy if none) (default 100.0)
    @editable_number(float):
        ToolTip := EnergyRestoreAmountToolTip
        Categories := array{EnergyCategory, EnergyRestoreCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    RestoreAmount<public>:float = 100.0
    # Seconds after a restore before the next use. 0.0 means usable at once (default 0.0)
    @editable_number(float):
        ToolTip := EnergyRestoreCooldownToolTip
        Categories := array{EnergyCategory, EnergyRestoreCategory}
        MinValue := option{0.0}
        MaxValue := option{600.0}
    CooldownSeconds<public>:float = 0.0
    # true consumes one item per restore when placed on an item. Unused when not an item (default true)
    @editable:
        ToolTip := EnergyRestoreConsumeItemToolTip
        Categories := array{EnergyCategory, EnergyRestoreCategory}
    ConsumeItemOnUse<public>:logic = true
    # The input that restores when pressed (default WeaponPrimary = the attack button)
    @editable:
        ToolTip := EnergyRestoreActionToolTip
        Categories := array{EnergyCategory, EnergyInputCategory}
    RestoreAction<public>:input_action(logic) = Character.WeaponPrimary
    # The key mapping added while granted. Pick one that contains RestoreAction (default RangedWeaponMapping)
    @editable:
        ToolTip := EnergyRestoreMappingToolTip
        Categories := array{EnergyCategory, EnergyInputCategory}
    RestoreMapping<public>:input_mapping = Character.RangedWeaponMapping
    # true removes RestoreMapping when revoked. Set true only for a mapping dedicated to this ability (default false)
    @editable:
        ToolTip := EnergyRemoveMappingToolTip
        Categories := array{EnergyCategory, EnergyInputCategory}
    RemoveMappingOnRevoke<public>:logic = false

    RestoredEventInternal<private><final>:event(tuple(agent, energy_component)) = event(tuple(agent, energy_component)){}
    FailedEventInternal<private><final>:event(agent) = event(agent){}

    # Fires on a restore with (the user, the restored energy_component) (Await / Subscribe; cannot be signaled from outside)
    RestoredEvent<public><final>:listenable(tuple(agent, energy_component)) = MakeProxyListenable(RestoredEventInternal)

    # Fires with the user when it was used but there was nothing to restore (FindRestoreTarget)
    FailedEvent<public><final>:listenable(agent) = MakeProxyListenable(FailedEventInternal)

    RunFor<override>(Agent:agent)<suspends>:void =
        MaybeInput := Agent.AwaitPlayerInput()
        if (PlayerInput := MaybeInput?):
            race:
                PlayerInput.HoldInputMapping(RestoreMapping, RemoveMappingOnRevoke)
                loop:
                    PlayerInput.AwaitPressed(RestoreAction)
                    Restored := TryRestoreFor(Agent)
                    if (Restored?, CooldownSeconds > 0.0):
                        Sleep(CooldownSeconds)
        else if (not player[Agent]):
            Print("[energy_restore_ability_component] granted to a non-player agent. No input is available, so it does nothing")

    # Restores RestoreAmount to Agent's energy (same as pressing the button; call it to let a player use it without input). true if it restored.
    # On a restore, consumes one item if this is an item (ConsumeItemOnUse). If there is nothing to restore, consumes nothing, notifies and returns false
    # Cannot be <decides> because the notification (SendUp, Signal) and consuming the item cannot be rolled back. To only check whether a restore is possible, use FindRestoreTarget[]
    TryRestoreFor<public>(Agent:agent):logic =
        if (Target := FindRestoreTarget[Agent]):
            Target.Restore(RestoreAmount)
            RestoredEventInternal.Signal((Agent, Target))
            if (ConsumeItemOnUse?, Entity.GetComponent[item_component]):
                Entity.ConsumeOne()
            true
        else:
            Entity.SendUp(energy_restore_failed_event{Ability := Self, Agent := Agent})
            FailedEventInternal.Signal(Agent)
            false

    # Finds the restore target for Agent. In order: the energy_component among Agent's inventory items (items other than this entity) that is not full and has the lowest ratio → the energy_component on Agent itself (if not full)
    # Fails if none exists or all are full
    FindRestoreTarget<public>(Agent:agent)<decides><transacts>:energy_component =
        var Best:?energy_component = false
        for (Item : Agent.GetAgentItems(), Item <> Entity, Energy := Item.FindEnergy[], not Energy.IsFull[]):
            if (Current := Best?):
                if (Energy.GetRatio() < Current.GetRatio()):
                    set Best = option{Energy}
            else:
                set Best = option{Energy}
        if (Found := Best?):
            Found
        else:
            Own := Agent.GetComponent[energy_component]
            not Own.IsFull[]
            Own
