using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Input }
using { /Verse.org/Assets }
using { PlayerSystem }
using { SceneGraphSystem }

# The body of the custom character that Agent is currently driving (looks under that player's slot via the player_manager_component in InEntity's scope). Fails if there is none
# Used when searching from outside the body, e.g. an ability's RunFor (Entity.FindCharacterMotorFor[Agent])
(InEntity:entity).FindCharacterMotorFor<public>(Agent:agent)<decides><transacts>:character_motor_component =
    Manager := InEntity.FindScopedComponent[player_manager_component]
    Slot := Manager.FindSlot[player[Agent]]
    Found := for (Motor : Slot.Entity.FindDescendantComponents(character_motor_component), Owner := Motor.FindOwner[], Owner = Agent):
        Motor
    Found[0]

# The character_motor_component on InEntity or one of its ancestors. Fails unless we are inside a custom character
(InEntity:entity).FindCharacterMotorAbove<public>()<decides><transacts>:character_motor_component =
    var Current:entity = InEntity
    var Found:?character_motor_component = false
    loop:
        if (Motor := Current.GetComponent[character_motor_component]):
            set Found = option{Motor}
            break
        if (Parent := Current.GetParent[]):
            set Current = Parent
        else:
            break
    Found?

# Role: remembers the current state of a button input (input_action(logic)). Remembers the press moment in seconds, so it can be used for input buffering (accepting an input pressed slightly early)
character_button_tracker<internal> := class<internal>:
    var<private> Down:logic = false
    var<private> PressedAt:float = -1000.0
    var<private> LastPressedAt:float = -1000.0
    var<private> ReleasedAt:float = -1000.0

    # Succeeds while held down
    IsDown<internal>()<decides><transacts>:void =
        Down?

    # Succeeds if pressed within WithinSeconds seconds and not consumed yet; marks it consumed
    ConsumePress<internal>(WithinSeconds:float)<decides><transacts>:void =
        GetSimulationElapsedTime() - PressedAt <= WithinSeconds
        set LastPressedAt = PressedAt
        set PressedAt = -1000.0

    # Puts back a press consumed by ConsumePress, keeping its press time (keeps an input that could not jump as a buffered input)
    Rebuffer<internal>():void =
        set PressedAt = LastPressedAt

    # Seconds since the last release
    GetSecondsSinceRelease<internal>()<transacts>:float =
        GetSimulationElapsedTime() - ReleasedAt

    Listen<internal>(PlayerInput:player_input, Action:input_action(logic)):[]cancelable =
        Events := PlayerInput.GetInputEvents(Action)
        array:
            Events.BeginDetectEvent.Subscribe(OnBegin)
            Events.EndDetectEvent.Subscribe(OnEnd)

    OnBegin<private>(Payload:tuple(player, logic)):void =
        set Down = true
        set PressedAt = GetSimulationElapsedTime()

    OnEnd<private>(Payload:tuple(player, float)):void =
        set Down = false
        set ReleasedAt = GetSimulationElapsedTime()

# Role: remembers the current value of a direction input (input_action(vector3)) (0 once released)
character_axis_tracker<internal> := class<internal>:
    var<private> Value:vector3 = vector3{}

    # Current value
    GetValue<internal>()<transacts>:vector3 =
        Value

    Listen<internal>(PlayerInput:player_input, Action:input_action(vector3)):[]cancelable =
        Events := PlayerInput.GetInputEvents(Action)
        # When another key is added or the direction changes while still held, the value only arrives on TriggerActivationEvent (every frame while the action holds).
        #   With Begin / Ongoing alone, the first direction stuck until every key was released (UEFN v43.00)
        array:
            Events.BeginDetectEvent.Subscribe(OnBegin)
            Events.DetectionOngoingEvent.Subscribe(OnOngoing)
            Events.TriggerActivationEvent.Subscribe(OnTriggered)
            Events.EndDetectEvent.Subscribe(OnEnd)

    OnBegin<private>(Payload:tuple(player, vector3)):void =
        set Value = Payload(1)

    OnOngoing<private>(Payload:tuple(player, vector3, float)):void =
        set Value = Payload(1)

    OnTriggered<private>(Payload:tuple(player, vector3)):void =
        set Value = Payload(1)

    OnEnd<private>(Payload:tuple(player, float)):void =
        set Value = vector3{}
