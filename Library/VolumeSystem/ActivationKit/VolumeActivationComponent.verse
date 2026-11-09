using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { VolumeSystem }
using { VolumeSystem.TooltipKit }

# Role: sends the activation signal (activated_event) to Targets when the first player enters the volume and the deactivation signal (deactivated_event) when the last one leaves (a gadget that "runs only while someone is there")
# Placement: attach in the editor to the same entity as player_volume_component, or to an ancestor entity
# Notifies: activated_event / deactivated_event to the Targets entities and their descendants. When Targets is empty, sends to this entity's child entities (never to its own entity or to entities carrying player_volume_component, because the deactivation signal would stop the volume)
# Requirements: counts the notifications that reach this entity from volumes on it or its descendants (summed when there are several)
volume_activation_component<public> := class<final_super>(component):

    # Entities that receive the activation signal when the first player enters and the deactivation signal when the last one leaves (the entity and its descendants receive it). When empty, sends to this entity's children
    @editable:
        ToolTip := VolumeActivationTargetsToolTip
        Categories := array{VolumeCategory}
    Targets<public>:[]entity = array{}

    var<private> Inside:[agent]int = map{}

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Entered := player_volume_entered_event[SceneEvent]):
            WasEmpty := IsEmpty()
            Count := if (Current := Inside[Entered.Agent]) then Current else 0
            if (set Inside[Entered.Agent] = Count + 1) {}
            if (WasEmpty?):
                Send(true, option{Entered.Agent})
        else if (Exited := player_volume_exited_event[SceneEvent]):
            if (Current := Inside[Exited.Agent], Current > 0):
                if (set Inside[Exited.Agent] = Current - 1) {}
                if (IsEmpty()?):
                    Send(false, false)
        false

    # Succeeds if someone is inside now
    IsOccupied<public>()<decides><transacts>:void =
        not IsEmpty()?

    IsEmpty<private>()<transacts>:logic =
        Occupied := for (Agent -> Count : Inside, Count > 0):
            Agent
        if (Occupied.Length = 0) then true else false

    Send<private>(Activate:logic, By:?agent):void =
        Receivers := if (Targets.Length > 0) then Targets else Entity.GetEntities()
        # Skip the volume's entity (the deactivation signal would stop the volume and it would never check again)
        for (Receiver : Receivers, not Receiver.GetComponent[player_volume_component]):
            if (Activate?):
                if (Agent := By?):
                    Receiver.SendActivatedBy(Agent)
                else:
                    Receiver.SendActivated()
            else:
                Receiver.SendDeactivated()
