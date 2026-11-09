using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { CharacterSystem }
using { CharacterSystem.TooltipKit }

# Role: a condition satisfied while the custom character is in State (grounded, airborne, rising, falling, moving, still)
#   As a child of ability_grant_condition_component it makes "an ability usable only in the air"; combined with an enable component, "glows only while moving", and so on, without code
#   Checks the state every frame (after the body has moved) and notifies only when it changes
# Placement: in the editor, attach to a descendant of the custom character's entity (the same entity as character_motor_component)
# Parent: directly under the entity of ability_grant_condition_component / game_transition_component / condition_all / condition_any
character_motor_condition_component<public> := class<final_super>(condition_component):

    # State to satisfy. Default Airborne
    @editable:
        ToolTip := MotorConditionStateToolTip
        Categories := array{CharacterEventCategory}
    State<public>:character_motor_state = character_motor_state.Airborne

    var<private> Satisfied:logic = false
    var<private> Motor:?character_motor_component = false
    var<private> Subscription:?cancelable = false

    IsSatisfied<override>()<decides><transacts>:void =
        Satisfied?

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := Entity.FindCharacterMotorAbove[]):
            set Motor = option{Found}
            set Subscription = option{Found.PostMoveEvent.Subscribe(OnPostMove)}
        else:
            Print("[character_motor_condition_component] character_motor_component not found (place it on a descendant of the custom character's entity)")

    OnEndSimulation<override>():void =
        if (Current := Subscription?):
            Current.Cancel()
        set Subscription = false
        (super:)OnEndSimulation()

    OnPostMove<private>(DeltaTime:float):void =
        if (Found := Motor?):
            Now := logic{Found.IsInState[State]}
            if (Now <> Satisfied):
                set Satisfied = Now
                NotifyChanged()
