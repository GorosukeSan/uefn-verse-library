using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { ActivationSystem }
using { SceneGraphSystem }
using { PickupSystem }
using { PickupSystem.TooltipKit }

# Kind of stage signal
pickup_stage_signal<public> := enum:
    # Sends the activate signal (activated_event) (reveal hidden platforms, start a mechanism, etc.)
    Activate
    # Sends the deactivate signal (deactivated_event) (stop a hazard, stop a mechanism, etc.)
    Deactivate

# Where to look for the targets of a stage signal
pickup_stage_scope<public> := enum:
    # Inside the topmost ancestor (the level's top-level entity) of the picked-up object (the orb; this entity when outside an effect). In a game whose maps are top-level entities, inside that map
    SourceRoot
    # Inside the picked-up object's scope (ancestor game_scope_component). The world if there is no scope
    SourceScope
    # The whole world
    World

# Marker tag for entities that receive stage signals. pickup_stage_target_component adds it to its own entity at start and removes it when stopped
pickup_stage_target_tag<public> := class(tag):

# Role: marker for an entity that receives stage signals (pickup_stage_signal_component). When a signal with the same Group is received, sends the activate / deactivate signal to this entity and its descendants
#   The parts on the receiving entity (ActivationSystem's enable_on_activation_component, the game's hidden platforms, mechanisms, etc.) react to the activate / deactivate signals
#   Revert signals (when an effect ends) are counted: if the same signal came from two effects, the opposite signal is sent when both have ended
# Placement: attach in the editor to the entity the signal should drive (hidden platform, hazard, etc.). Enter a name in Group (the same name as the Group on the effect side)
# Tags: pickup_stage_target_tag on this entity (the sender finds targets by this tag)
# From outside: Hold / Release / Pulse (called by pickup_stage_signal_component; also usable from code), IsHeld
pickup_stage_target_component<public> := class<final_super>(component):

    # Name of the signal group. Receives if it matches the Group of the sender (pickup_stage_signal_component). Empty receives nothing. Default empty
    @editable:
        ToolTip := StageTargetGroupToolTip
        Categories := array{PickupStageCategory}
    Group<public>:string = ""

    var<private> TagKey:?tag_key = false
    var<private> ActivateHolds:int = 0
    var<private> DeactivateHolds:int = 0

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set TagKey = option{Entity.AddTag(pickup_stage_target_tag{})}

    OnEndSimulation<override>():void =
        if (Key := TagKey?, Entity.RemoveTag[Key]) {}
        set TagKey = false
        set ActivateHolds = 0
        set DeactivateHolds = 0
        (super:)OnEndSimulation()

    # "Hold" Signal: the first hold sends the Signal to this entity and its descendants (an activate signal raised by Activator, if given). Release with Release
    Hold<public>(Signal:pickup_stage_signal, Activator:?agent):void =
        if (Signal = pickup_stage_signal.Activate):
            set ActivateHolds += 1
            if (ActivateHolds = 1):
                Send(Signal, Activator)
        else:
            set DeactivateHolds += 1
            if (DeactivateHolds = 1):
                Send(Signal, Activator)

    # Release one Hold of Signal. When nobody holds it any more, sends the opposite signal (or re-sends the other signal if someone holds that one)
    Release<public>(Signal:pickup_stage_signal):void =
        if (Signal = pickup_stage_signal.Activate):
            if (ActivateHolds > 0):
                set ActivateHolds -= 1
                if (ActivateHolds = 0):
                    Send(if (DeactivateHolds > 0) then pickup_stage_signal.Deactivate else Opposite(Signal), false)
        else:
            if (DeactivateHolds > 0):
                set DeactivateHolds -= 1
                if (DeactivateHolds = 0):
                    Send(if (ActivateHolds > 0) then pickup_stage_signal.Activate else Opposite(Signal), false)

    # Sends the Signal once without counting (a signal that is not reverted)
    Pulse<public>(Signal:pickup_stage_signal, Activator:?agent):void =
        Send(Signal, Activator)

    # Succeeds if someone holds Signal
    IsHeld<public>(Signal:pickup_stage_signal)<decides><transacts>:void =
        if (Signal = pickup_stage_signal.Activate) then ActivateHolds > 0 else DeactivateHolds > 0

    Send<private>(Signal:pickup_stage_signal, Activator:?agent):void =
        if (Signal = pickup_stage_signal.Activate):
            if (Agent := Activator?):
                Entity.SendActivatedBy(Agent)
            else:
                Entity.SendActivated()
        else:
            Entity.SendDeactivated()

    Opposite<private>(Signal:pickup_stage_signal)<transacts>:pickup_stage_signal =
        if (Signal = pickup_stage_signal.Activate) then pickup_stage_signal.Deactivate else pickup_stage_signal.Activate

# Role: on the activate signal, sends the Signal to every pickup_stage_target_component with the same Group within Scope (found by the pickup_stage_target_tag tag). With RevertOnEnd, reverts on the deactivate signal (when the effect ends)
#   Placed inside an effect prefab (PickupSystem's pickup_effect_component), the scope is based on the picked-up object (the orb). Examples: "reveal that map's hidden platforms for 10 s", "stop that map's hazards for 5 s"
#   It may also be placed outside an effect (anywhere the activate signal is delivered). The scope is then based on this entity
# Placement: attach in the editor to the root or a child of the effect prefab (one entity per Group)
# When: on the activate signal and on the deactivate signal. Also reverts when stopped (with RevertOnEnd)
# From outside: Apply / Revert / GetTargetCount
# Requirements / notes: targets are searched once when the signal is sent (targets added later do not receive it). Other players on the same map see the same targets (the stage is shared)
pickup_stage_signal_component<public> := class<final_super>(component):

    # Group name of the targets (Group of pickup_stage_target_component). Empty sends nothing. Default empty
    @editable:
        ToolTip := StageSignalGroupToolTip
        Categories := array{PickupStageCategory}
    Group<public>:string = ""
    # Signal to send (Activate = activate / Deactivate = deactivate). Default Activate
    @editable:
        ToolTip := StageSignalSignalToolTip
        Categories := array{PickupStageCategory}
    Signal<public>:pickup_stage_signal = pickup_stage_signal.Activate
    # Where to look for targets (SourceRoot = inside the picked-up object's top-level entity / SourceScope = the picked-up object's scope / World = the world). Default SourceRoot
    @editable:
        ToolTip := StageSignalScopeToolTip
        Categories := array{PickupStageCategory}
    Scope<public>:pickup_stage_scope = pickup_stage_scope.SourceRoot
    # When on, reverts on the deactivate signal (when the effect ends). When off, leaves the signal as sent (resetting is up to the target's parts). Default on
    @editable:
        ToolTip := StageSignalRevertToolTip
        Categories := array{PickupStageCategory}
    RevertOnEnd<public>:logic = true

    var<private> Held:[]pickup_stage_target_component = array{}
    var<private> Applied:logic = false

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Apply(if (Agent := SceneEvent.FindActivatingAgent[]) then option{Agent} else false)
        else if (deactivated_event[SceneEvent]):
            Revert()
        false

    OnEndSimulation<override>():void =
        Revert()
        (super:)OnEndSimulation()

    # Sends the signal to the targets within the scope (with RevertOnEnd, holds it until Revert). Does nothing if already sent
    Apply<public>(Activator:?agent):void =
        if (Applied? or Group = ""):
            return
        set Applied = true
        Targets := FindTargets()
        if (Targets.Length = 0):
            Print("[pickup_stage_signal_component] No target (pickup_stage_target_component) with Group '{Group}' found within the scope")
        for (Target : Targets):
            if (RevertOnEnd?):
                Target.Hold(Signal, Activator)
            else:
                Target.Pulse(Signal, Activator)
        if (RevertOnEnd?):
            set Held = Targets

    # Reverts the sent signal (with RevertOnEnd; does nothing if not sent)
    Revert<public>():void =
        if (not Applied?):
            return
        set Applied = false
        for (Target : Held):
            Target.Release(Signal)
        set Held = array{}

    # Number of targets currently within the scope (searches again)
    GetTargetCount<public>()<transacts>:int =
        FindTargets().Length

    FindTargets<private>()<transacts>:[]pickup_stage_target_component =
        Base := if (Effect := Entity.FindPickupEffect[], Source := Effect.FindSource[]) then Source else Entity
        MaybeRoot:?entity = case (Scope):
            pickup_stage_scope.SourceRoot => option{Base.FindTopEntity()}
            pickup_stage_scope.SourceScope =>
                if (ScopeEntity := Base.FindScopeEntity[]) then option{ScopeEntity} else if (World := Base.GetSimulationEntity[]) then option{World} else false
            pickup_stage_scope.World =>
                if (World := Base.GetSimulationEntity[]) then option{World} else false
        if (Root := MaybeRoot?):
            for (Tagged : Root.FindDescendantEntitiesWithTag(pickup_stage_target_tag), Target := Tagged.GetComponent[pickup_stage_target_component], Target.Group = Group):
                Target
        else:
            array{}

# The topmost ancestor of InEntity (directly under the simulation entity; the level's top-level entity). InEntity itself if it is top-level
(InEntity:entity).FindTopEntity<public>()<transacts>:entity =
    var Current:entity = InEntity
    loop:
        if (Parent := Current.GetParent[], Parent.GetParent[]):
            set Current = Parent
        else:
            break
    Current
