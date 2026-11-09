using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { SceneGraphSystem }
using { PlayerSystem.TooltipKit }

# Role: when the owner's character enters State (in air, crouching, sprinting, in water, etc.), sends the activation signal (activated_event) to Targets; when it leaves, the deactivation signal (deactivated_event) ("glow only while airborne", "show the HUD only while crouching", etc.)
#   Looks at the state every frame and sends only when it changes. If already in State at start, sends the activation signal right away
# Placement: in the editor, place it inside a loadout prefab (loadout_component's Prefab) (does nothing without an owner; reported in the output log)
# From outside: IsActive (whether currently in State)
player_state_trigger_component<public> := class<final_super>(component):

    # The state to watch. Default InAir
    @editable:
        ToolTip := PlayerStateToolTip
        Categories := array{PlayerMotionCategory}
    State<public>:player_motion_state = player_motion_state.InAir
    # Entities that receive the signals (reaches the entity and its descendants). If empty, sent to the child entities of this entity (not to its own entity)
    @editable:
        ToolTip := PlayerStateTargetsToolTip
        Categories := array{PlayerMotionCategory}
    Targets<public>:[]entity = array{}

    Watchers<private>:player_motion_watcher_set = player_motion_watcher_set{}
    var<private> Inside:logic = false
    var<private> Owner:?player = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (OwningPlayer := Entity.FindOwningPlayer[]):
            set Owner = option{OwningPlayer}
            Watchers.Start(Entity, OnMotion, TickEvents.PrePhysics)
            set Subscription = option{TickEvents.PrePhysics.Subscribe(OnTick)}
        else:
            Print("[player_state_trigger_component] No owner (place it somewhere with an owner, such as inside a loadout prefab)")

    var<private> Subscription:?cancelable = false

    OnEndSimulation<override>():void =
        Subscription.CancelIfSet()
        set Subscription = false
        Watchers.Stop()
        if (Inside?):
            Send(false)
        (super:)OnEndSimulation()

    # Succeeds if the owner is currently in State
    IsActive<public>()<decides><transacts>:void =
        Inside?

    OnMotion<private>(Agent:agent, Happened:player_motion):void = {}

    OnTick<private>(DeltaTime:float):void =
        if (Player := Owner?):
            Now := logic{Watchers.IsInState[Player, State]}
            if (Now <> Inside):
                Send(Now)

    Send<private>(Active:logic):void =
        set Inside = Active
        Receivers := if (Targets.Length > 0) then Targets else Entity.GetEntities()
        for (Receiver : Receivers):
            if (Active?):
                if (Player := Owner?):
                    Receiver.SendActivatedBy(Player)
                else:
                    Receiver.SendActivated()
            else:
                Receiver.SendDeactivated()
