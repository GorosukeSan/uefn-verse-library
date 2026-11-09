using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { PlayerSystem }
using { SceneGraphSystem }

# Role: a part used by grant components. Remembers the players it granted and calls Grant / Revoke on every ability of the Owner entity (never touches grants made by other granters)
ability_grant_set<internal> := class<unique>:

    var<private> Granted:[]agent = array{}

    GrantTo<internal>(Owner:entity, Agent:agent):void =
        if (Granted.Find[Agent]):
            return
        set Granted += array{Agent}
        for (Ability : Owner.GetAbilities()):
            Ability.Grant(Agent)

    RevokeFrom<internal>(Owner:entity, Agent:agent):void =
        if (Index := Granted.Find[Agent], Rest := Granted.RemoveElement[Index]):
            set Granted = Rest
            for (Ability : Owner.GetAbilities()):
                Ability.Revoke(Agent)

    RevokeAll<internal>(Owner:entity):void =
        for (Agent : Granted):
            RevokeFrom(Owner, Agent)

    IsGrantedBy<internal>(Agent:agent)<decides><transacts>:void =
        Granted.Find[Agent]

# Role: a part used by grant components. While running, grants to every player in Owner's scope (including late joiners) and revokes from players who leave and when stopped. If Owner is an entity with an owner (under a slot, inside a character, etc.), grants only to the owner
ability_player_feed<internal> := class<unique>:

    Set<internal>:ability_grant_set = ability_grant_set{}

    var<private> Owner:?entity = false
    var<private> Subscriptions:[]cancelable = array{}

    IsRunning<internal>()<decides><transacts>:void =
        Owner?

    Start<internal>(InOwner:entity):void =
        if (Owner?):
            return
        set Owner = option{InOwner}
        # On an entity with an owner (inside a character, etc.), grant only to that player
        if (OwningPlayer := InOwner.FindOwningPlayer[]):
            Set.GrantTo(InOwner, OwningPlayer)
        else if (Manager := InOwner.FindScopedComponent[player_manager_component]):
            set Subscriptions = array:
                Manager.PlayerAddedEvent.Subscribe(OnAdded)
                Manager.PlayerRemovedEvent.Subscribe(OnRemoved)
            for (Slot : Manager.GetSlots()):
                Set.GrantTo(InOwner, Slot.Player)

    Stop<internal>():void =
        if (Current := Owner?):
            for (Subscription : Subscriptions):
                Subscription.Cancel()
            set Subscriptions = array{}
            Set.RevokeAll(Current)
            set Owner = false

    OnAdded<private>(Player:player):void =
        if (Current := Owner?):
            Set.GrantTo(Current, Player)

    OnRemoved<private>(Player:player):void =
        if (Current := Owner?):
            Set.RevokeFrom(Current, Player)
