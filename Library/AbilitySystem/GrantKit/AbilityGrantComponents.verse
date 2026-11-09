using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }
using { ActivationSystem }
using { ConditionSystem }
using { ItemSystem }
using { SceneGraphSystem }
using { AbilitySystem }
using { AbilitySystem.TooltipKit }

# Role: grants every ability on the same entity to every player in the scope (including late joiners). Revokes from players who leave. On an entity with an owner (inside a CharacterSystem character, etc.), grants only to the owner
# When: from the start of the simulation (as soon as a player joins) when GrantOnBegin is true. When false, from the activation signal (activated_event) until the deactivation signal (deactivated_event)
# Placement: attach in the editor to the same entity as the ability (an ability_component subclass)
# Requirements: one player_manager_component in the scope (or the world)
ability_grant_players_component<public> := class<final_super>(component):

    # true (default) grants to everyone from the start of the simulation. false grants from the activation signal until the deactivation signal
    @editable:
        ToolTip := AbilityGrantOnBeginToolTip
        Categories := array{AbilityGrantCategory}
    GrantOnBegin<public>:logic = true

    Feed<private>:ability_player_feed = ability_player_feed{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (GrantOnBegin?):
            Feed.Start(Entity)

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Feed.Start(Entity)
        else if (deactivated_event[SceneEvent]):
            Feed.Stop()
        false

    OnEndSimulation<override>():void =
        Feed.Stop()
        (super:)OnEndSimulation()

    # Succeeds while granting
    IsGranting<public>()<decides><transacts>:void =
        Feed.IsRunning[]

# Role: grants every ability on the same entity to the item's holder (decided by the item_holder_component on the same entity: while equipped / while held) and revokes when it is dropped
# Placement: attach in the editor to the item's entity (the same entity as item_component, item_holder_component and the ability)
ability_grant_item_component<public> := class<final_super>(component):

    Set<private>:ability_grant_set = ability_grant_set{}
    var Subscriptions<private>:[]cancelable = array{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Holder := Entity.GetComponent[item_holder_component]):
            set Subscriptions = array:
                Holder.HolderAddedEvent.Subscribe(OnHolderAdded)
                Holder.HolderRemovedEvent.Subscribe(OnHolderRemoved)
            if (Current := Holder.FindHolder[]):
                OnHolderAdded(Current)

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        Set.RevokeAll(Entity)
        (super:)OnEndSimulation()

    OnHolderAdded<private>(Agent:agent):void =
        Set.GrantTo(Entity, Agent)

    OnHolderRemoved<private>(Agent:agent):void =
        Set.RevokeFrom(Entity, Agent)

# Role: while the condition (a condition_component subclass directly under it) holds, grants every ability on the same entity to every player in the scope (including late joiners). Revokes when it no longer holds. On an entity with an owner, grants only to the owner (e.g. an ability inside a character "usable only while crouching")
# Placement: attach in the editor to the same entity as the ability
# Children: one entity with a condition_component subclass directly under it (combine several conditions with condition_all / condition_any)
# Requirements: one player_manager_component in the scope (or the world)
ability_grant_condition_component<public> := class<final_super>(component):

    Feed<private>:ability_player_feed = ability_player_feed{}
    var Subscription<private>:?cancelable = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Condition := Entity.FindChildComponent[condition_component]):
            set Subscription = option{Condition.ChangedEvent.Subscribe(OnConditionChanged)}
            OnConditionChanged(if (Condition.IsSatisfied[]) then true else false)

    OnEndSimulation<override>():void =
        Subscription.CancelIfSet()
        set Subscription = false
        Feed.Stop()
        (super:)OnEndSimulation()

    OnConditionChanged<private>(Satisfied:logic):void =
        if (Satisfied?):
            Feed.Start(Entity)
        else:
            Feed.Stop()

    # Succeeds while granting (while the condition holds)
    IsGranting<public>()<decides><transacts>:void =
        Feed.IsRunning[]
