using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { CharacterSystem }
using { CharacterSystem.TooltipKit }

# Notification of something that happened to the custom character
# Direction: from the character_action_trigger_component entity to the root (SendUp)
# Sender: character_action_trigger_component (Trigger). Receivers: ancestor components. Not consumed
character_action_event<public> := class(scene_event):
    # The component that sent it
    Trigger<public>:character_action_trigger_component
    # What happened
    Action<public>:character_action

# Role: whenever Action (landed, jumped, dashed, started moving, hit a wall, ...) happens to the custom character, sends an activation signal (activated_event) to Targets and sends character_action_event upward
#   The reaction (sound, particles, notification, enabling, items) is handled by activation-awaiting components placed on the Targets entities (combine without writing code)
#   Ignores further occurrences during CooldownSeconds (avoids duplicates when it happens many times in a row)
# Placement: in the editor, attach to the custom character's entity (the same entity as character_motor_component) or a descendant
# Notifications: character_action_event upward, and TriggeredEvent
character_action_trigger_component<public> := class<final_super>(component):

    # What to watch for. Default Landed
    @editable:
        ToolTip := ActionTriggerActionToolTip
        Categories := array{CharacterEventCategory}
    Action<public>:character_action = character_action.Landed
    # Entities to send the activation signal to (reaches each entity and its descendants). If empty, sends to this entity and its descendants
    @editable:
        ToolTip := ActionTriggerTargetsToolTip
        Categories := array{CharacterEventCategory}
    Targets<public>:[]entity = array{}
    # Time to ignore further occurrences (seconds). 0 never ignores. Default 0
    @editable_number(float):
        ToolTip := ActionTriggerCooldownToolTip
        Categories := array{CharacterEventCategory}
        MinValue := option{0.0}
        MaxValue := option{60.0}
    CooldownSeconds<public>:float = 0.0

    TriggeredEventInternal<private><final>:event(character_action) = event(character_action){}

    # Arrives whenever Action happens (Await / Subscribe. Cannot be Signaled from outside)
    TriggeredEvent<public><final>:listenable(character_action) = MakeProxyListenable(TriggeredEventInternal)

    var<private> Subscription:?cancelable = false
    var<private> LastSeconds:float = -1000.0

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Motor := Entity.FindCharacterMotorAbove[]):
            set Subscription = option{Motor.ActionEvent.Subscribe(OnAction)}
        else:
            Print("[character_action_trigger_component] character_motor_component not found (place it on the custom character's entity or a descendant)")

    OnEndSimulation<override>():void =
        if (Current := Subscription?):
            Current.Cancel()
        set Subscription = false
        (super:)OnEndSimulation()

    OnAction<private>(Happened:character_action):void =
        if (Happened <> Action):
            return
        Now := GetSimulationElapsedTime()
        if (CooldownSeconds > 0.0 and Now - LastSeconds < CooldownSeconds):
            return
        set LastSeconds = Now
        Entity.SendUp(character_action_event{Trigger := Self, Action := Happened})
        TriggeredEventInternal.Signal(Happened)
        Receivers := if (Targets.Length > 0) then Targets else array{Entity}
        for (Receiver : Receivers):
            if (Motor := Entity.FindCharacterMotorAbove[], Owner := Motor.FindOwner[]):
                Receiver.SendActivatedBy(Owner)
            else:
                Receiver.SendActivated()
