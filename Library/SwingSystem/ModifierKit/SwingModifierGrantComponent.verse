using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { SwingSystem }
using { SwingSystem.TooltipKit }
using { SceneGraphSystem }

# Role: when a swing_modifier_request_event{Agent} reaches this entity, applies the modifier of the swing_modifier_component on the same entity to that agent for DurationSeconds (power-up items, objects that weaken you on touch, etc.). If the same agent receives it again, the timer restarts. DurationSeconds 0 means until deactivated. The deactivate signal (deactivated_event) removes it from everyone
# Placement: attach in the editor to the same entity as swing_modifier_component
# Parent: if you use the deactivate signal, somewhere it is delivered (for a game sequence, the node entity or a descendant)
# Requirements: something that sends swing_modifier_request_event to this entity (SendDown / SendUp) when the modifier should apply. To apply directly from code, call Request
swing_modifier_grant_component<public> := class<final_super>(component):

    # How long the modifier stays applied after a request (seconds; default 10). 0 means until deactivated
    @editable_number(float):
        ToolTip := SwingModifierDurationToolTip
        Categories := array{SwingCategory, SwingModifierCategory}
        MinValue := option{0.0}
        MaxValue := option{600.0}
    DurationSeconds<public>:float = 10.0

    # Agents the modifier is applied to and when to remove it (a GetSimulationElapsedTime value; Inf means no expiry)
    var<private> Expiries:[agent]float = map{}

    # Tells the expiry loop (OnSimulate) that an expiry changed (a request was received)
    ExpiriesChangedEvent<private>:event() = event(){}

    # Succeeds if this component is currently applying to Agent
    IsApplyingTo<public>(Agent:agent)<decides><transacts>:void =
        Expiries[Agent]

    # Same as receiving swing_modifier_request_event (applies to Agent for DurationSeconds; restarts the timer if already applied)
    Request<public>(Agent:agent):void =
        if (Modifier := Entity.GetComponent[swing_modifier_component]):
            Expiry := if (DurationSeconds > 0.0) then GetSimulationElapsedTime() + DurationSeconds else Inf
            if (not Expiries[Agent]):
                Modifier.ApplyTo(Agent)
            if (set Expiries[Agent] = Expiry) {}
            if (DurationSeconds > 0.0):
                ExpiriesChangedEvent.Signal()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Requested := swing_modifier_request_event[SceneEvent]):
            Request(Requested.Agent)
        else if (deactivated_event[SceneEvent]):
            RemoveAll()
        false

    OnEndSimulation<override>():void =
        RemoveAll()
        (super:)OnEndSimulation()

    # Removes on expiry. A single loop sleeps until the earliest expiry (a request arriving meanwhile wakes it to recompute). When stopped (before OnEndSimulation) this loop stops too, so no sleeping task is left behind
    OnSimulate<override>()<suspends>:void =
        loop:
            Now := GetSimulationElapsedTime()
            for (Agent -> Expiry : Expiries, Expiry <= Now):
                Remove(Agent)
            var Next:float = Inf
            for (Agent -> Expiry : Expiries, Expiry < Next):
                set Next = Expiry
            if (Next < Inf):
                race:
                    Sleep(Next - Now)
                    ExpiriesChangedEvent.Await()
            else:
                ExpiriesChangedEvent.Await()

    Remove<private>(Agent:agent):void =
        set Expiries = Expiries.RemoveKey(Agent)
        if (Modifier := Entity.GetComponent[swing_modifier_component]):
            Modifier.RemoveFrom(Agent)

    RemoveAll<private>():void =
        for (Agent -> Expiry : Expiries):
            Remove(Agent)
