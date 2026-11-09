using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { PlayerSystem }
using { SceneGraphSystem }

# 役割：付与の component が使う部品。自分が付与した人を覚え、Owner の entity の能力すべてへ Grant / Revoke する（ほかの付与元が付与した分には触らない）
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

# 役割：付与の component が使う部品。動いているあいだ、Owner の区画の全プレイヤー（途中参加も）に付与し、退出した人・止めたときに剥奪する。Owner が持ち主のいる entity（slot の下。キャラクターの中など）なら、持ち主にだけ付与する
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
        # 持ち主のいる entity（キャラクターの中など）なら、その人にだけ付与する
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
