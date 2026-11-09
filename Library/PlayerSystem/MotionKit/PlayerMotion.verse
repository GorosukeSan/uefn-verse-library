using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Game }

# A momentary motion of a character (notified by player_motion_trigger_component)
player_motion<public> := enum:
    # Jumped
    Jumped
    # Landed on the ground (from the air to the ground)
    Landed
    # Left the ground (jump, fall, launch)
    LeftGround
    # Started crouching
    CrouchStarted
    # Stopped crouching
    CrouchEnded
    # Started running (sprint)
    SprintStarted
    # Stopped running
    SprintEnded
    # Was eliminated
    Eliminated
    # Took damage
    Damaged

# A continuing state of a character (looked at by player_state_trigger_component / player_state_condition_component)
player_motion_state<public> := enum:
    # On the ground
    OnGround
    # In the air
    InAir
    # Falling
    Falling
    # Crouching
    Crouching
    # Running (sprint)
    Sprinting
    # Gliding with the glider
    Gliding
    # In water
    InWater
    # Flying (flight state)
    Flying
    # Down (downed but not out)
    Down

# Notification that a motion happened
# Direction: from the player_motion_trigger_component's entity to the root (SendUp)
# Sender: player_motion_trigger_component (Trigger). Receivers: ancestor components (parts inside the character, your components). Not consumed
player_motion_event<public> := class(scene_event):
    # The part that sent it
    Trigger<public>:player_motion_trigger_component
    # The player who moved
    Agent<public>:agent
    # The motion that happened
    Motion<public>:player_motion

# Role: runtime class that watches one character (used by the MotionKit / ConditionKit parts). Calling Update every frame resubscribes when the character changed (respawn), checks ground transitions and passes motions to Notify
player_motion_watcher<internal> := class<internal>:
    Agent<internal>:agent
    Notify<internal>:type{_(:agent, :player_motion):void}

    var<private> Character:?fort_character = false
    var<private> Subscriptions:[]cancelable = array{}
    var<private> Sprinting:logic = false
    var<private> WasOnGround:logic = true

    # Check for a changed character and ground transitions (call every frame from TickEvents)
    Update<internal>():void =
        if (C := Agent.GetFortCharacter[]):
            if (not IsWatching[C]):
                Watch(C)
            OnGround := logic{C.IsOnGround[]}
            if (WasOnGround? and not OnGround?):
                Notify(Agent, player_motion.LeftGround)
            else if (not WasOnGround? and OnGround?):
                Notify(Agent, player_motion.Landed)
            set WasOnGround = OnGround
        else if (Character?):
            Unwatch()

    IsWatching<private>(C:fort_character)<decides><transacts>:void =
        Known := Character?
        Known = C

    # Succeeds if Agent's current character is in State. Fails if there is no character
    IsInState<internal>(State:player_motion_state)<decides><transacts>:void =
        C := Agent.GetFortCharacter[]
        case (State):
            player_motion_state.OnGround => C.IsOnGround[]
            player_motion_state.InAir => C.IsInAir[]
            player_motion_state.Falling => C.IsFalling[]
            player_motion_state.Crouching => C.IsCrouching[]
            player_motion_state.Sprinting => Sprinting?
            player_motion_state.Gliding => C.IsGliding[]
            player_motion_state.InWater => C.IsInWater[]
            player_motion_state.Flying => C.IsFlying[]
            player_motion_state.Down => C.IsDownButNotOut[]

    Stop<internal>():void =
        Unwatch()

    Watch<private>(C:fort_character):void =
        Unwatch()
        set Character = option{C}
        set Sprinting = false
        set WasOnGround = logic{C.IsOnGround[]}
        set Subscriptions = array:
            C.JumpedEvent().Subscribe(OnJumped)
            C.CrouchedEvent().Subscribe(OnCrouched)
            C.SprintedEvent().Subscribe(OnSprinted)
            C.EliminatedEvent().Subscribe(OnEliminated)
            C.DamagedEvent().Subscribe(OnDamaged)

    Unwatch<private>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        set Character = false
        set Sprinting = false

    OnJumped<private>(C:fort_character):void =
        Notify(Agent, player_motion.Jumped)

    OnCrouched<private>(Changed:tuple(fort_character, logic)):void =
        Notify(Agent, if (Changed(1)?) then player_motion.CrouchStarted else player_motion.CrouchEnded)

    OnSprinted<private>(Changed:tuple(fort_character, logic)):void =
        set Sprinting = Changed(1)
        Notify(Agent, if (Changed(1)?) then player_motion.SprintStarted else player_motion.SprintEnded)

    OnEliminated<private>(Result:elimination_result):void =
        Notify(Agent, player_motion.Eliminated)

    OnDamaged<private>(Result:damage_result):void =
        Notify(Agent, player_motion.Damaged)
