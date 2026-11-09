using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { SceneGraphSystem }
using { PlayerSystem.TooltipKit }

# Role: condition satisfied while the owner's character is in State (in air, crouching, sprinting, in water, etc.)
#   Placed as a child of an ability_grant_condition_component it gives "an ability usable only while crouching"; as a child of a game_transition_component, "advance when airborne", and so on, without code
#   Looks at the state every frame and notifies only when it changes
# Placement: attach to an entity in the editor. Place it inside a loadout prefab (loadout_component's Prefab) (never satisfied without an owner)
# Parent: directly under the entity of an ability_grant_condition_component / game_transition_component / condition_all / condition_any
player_state_condition_component<public> := class<final_super>(condition_component):

    # The state that satisfies. Default Crouching
    @editable:
        ToolTip := PlayerStateToolTip
        Categories := array{PlayerMotionCategory}
    State<public>:player_motion_state = player_motion_state.Crouching

    Watchers<private>:player_motion_watcher_set = player_motion_watcher_set{}
    var<private> Satisfied:logic = false
    var<private> Owner:?player = false
    var<private> Subscription:?cancelable = false

    IsSatisfied<override>()<decides><transacts>:void =
        Satisfied?

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (OwningPlayer := Entity.FindOwningPlayer[]):
            set Owner = option{OwningPlayer}
            Watchers.Start(Entity, OnMotion, TickEvents.PrePhysics)
            set Subscription = option{TickEvents.PrePhysics.Subscribe(OnTick)}
        else:
            Print("[player_state_condition_component] No owner (place it somewhere with an owner, such as inside a loadout prefab)")

    OnEndSimulation<override>():void =
        Subscription.CancelIfSet()
        set Subscription = false
        Watchers.Stop()
        (super:)OnEndSimulation()

    OnMotion<private>(Agent:agent, Happened:player_motion):void = {}

    OnTick<private>(DeltaTime:float):void =
        if (Player := Owner?):
            Now := logic{Watchers.IsInState[Player, State]}
            if (Now <> Satisfied):
                set Satisfied = Now
                NotifyChanged()
