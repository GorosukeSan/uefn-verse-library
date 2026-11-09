using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Assets }
using { /Fortnite.com/Input }
using { CharacterSystem }
using { CharacterSystem.BodyKit }
using { CharacterSystem.CameraExperimentalKit }
using { CharacterSystem.MoveKit }
using { PlayerSystem }
using { ActivationSystem }
using { SceneGraphSystem }
using { VolumeSystem }

# Role: custom character (CharacterSystem) sample. A side-scrolling 2D game with only movement, jumping and a goal
#   With StartOnBegin, for every player who joins (when off, only for the player who sent an activate signal that knows who triggered it, such as a button), creates a custom character (character_motor_component, walk, jump, owner_stasis, camera) under that player's slot. Created at this component's position (the start)
#   Movement is left / right (world forward / back; AxisLock = Left) and jumping (double jump; a short press jumps lower). The look is the Fortnite character (not hidden; it follows the body). The camera is an orthographic side view
#   Every time a Fortnite round starts, everyone is returned to the start. Entering the goal (a box of GoalSizeCm at GoalOffsetCm from this entity) Prints and returns the player to the start
# Placement: attach in the editor to an empty entity above a floor (a mesh with collision). Arrange floors and platforms in the forward direction, and make a landable place beyond GoalOffsetCm. Place one player_manager_component in the scope (or the world)
# Try it: move left / right (the move input) and jump. Reaching the goal shows "Goal!" and returns you to the start
# Requirements / notes: the move input Character.Move and the camera (CameraExperimentalKit) are @experimental. An island with this sample cannot be published (VerseShare distributes it only to projects marked "includes experimental")
# ⚠ Unverified: the camera facing (YawDegrees). If it is not a side view, flip the sign of CameraYawDegrees
platformer_2d_sample_component<public> := class<final_super>(component):

    # Left / right input (a directional input). Default is Fortnite's move (@experimental)
    @editable
    MoveAction<public>:input_action(vector3) = Character.Move
    # Goal position (offset from this entity, cm). Default 3000 forward
    @editable
    GoalOffsetCm<public>:vector3 = vector3{Forward := 3000.0}
    # Size of the goal box (cm). Default 300
    @editable
    GoalSizeCm<public>:float = 300.0
    # Horizontal camera facing (degrees). Flip the sign if it is not a side view. Default -90
    @editable
    CameraYawDegrees<public>:float = -90.0
    # When on, creates a custom character for everyone from the start. When off, only for the player who sent an activate signal that knows who triggered it (button, volume entrance, ...). Default on
    @editable
    StartOnBegin<public>:logic = true
    # When on, deletes the player's custom character at the goal (control returns to the Fortnite character). When off, returns them to the start. Default off
    @editable
    ExitOnGoal<public>:logic = false

    var<private> Characters:[agent]entity = map{}
    var<private> Subscriptions:[]cancelable = array{}
    var<private> Goal:?entity = false
    Rounds<private>:round_watcher = round_watcher{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        MakeGoal()
        # Every time a Fortnite round starts, return everyone to the start
        Rounds.Start(Entity, OnRoundStarted, OnRoundEnded)
        if (Manager := Entity.FindScopedComponent[player_manager_component]):
            set Subscriptions += array{Manager.PlayerRemovedEvent.Subscribe(OnPlayerRemoved)}
            if (StartOnBegin?):
                set Subscriptions += array{Manager.PlayerAddedEvent.Subscribe(OnPlayerAdded)}
                for (Slot : Manager.GetSlots()):
                    Spawn(Slot)
        else:
            Print("[platformer_2d_sample_component] player_manager_component not found")

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        Rounds.Stop()
        for (Agent -> Pawn : Characters):
            Pawn.RemoveFromParent()
        set Characters = map{}
        if (Current := Goal?):
            Current.RemoveFromParent()
        set Goal = false
        (super:)OnEndSimulation()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent], Agent := SceneEvent.FindActivatingAgent[], Player := player[Agent]):
            OnPlayerAdded(Player)
        else if (deactivated_event[SceneEvent], not StartOnBegin?):
            for (Agent -> Pawn : Characters):
                OnPlayerRemoved(Agent)
        false

    OnPlayerAdded<private>(Player:player):void =
        if (Manager := Entity.FindScopedComponent[player_manager_component], Slot := Manager.FindSlot[Player]):
            Spawn(Slot)

    OnPlayerRemoved<private>(Agent:agent):void =
        if (Pawn := Characters[Agent]):
            Pawn.RemoveFromParent()
            set Characters = Characters.RemoveKey(Agent)

    # Create one player's custom character under that player's slot (under the slot, so the owner is that player)
    Spawn<private>(Slot:player_slot_component):void =
        if (Characters[Slot.Player]):
            return
        Pawn := entity{}
        Pawn.SetGlobalTransform(MakeTranslationTransform(GetStart()))
        Camera := character_camera_component:
            Entity := Pawn
            Projection := character_camera_projection.Orthographic
            OffsetCm := vector3{Left := 2000.0, Up := 150.0}
            YawDegrees := CameraYawDegrees
            PitchDegrees := 0.0
            OrthographicWidthCm := 2500.0
        Parts:[]component = array:
            character_motor_component{Entity := Pawn, AxisLock := character_axis_lock.Left, SpawnAtOwner := false, ResetOnRoundStart := false}
            character_walk_component{Entity := Pawn, MoveAction := option{MoveAction}, Space := character_walk_space.SideView, MaxSpeedCmPerSecond := 700.0}
            character_jump_component{Entity := Pawn, AirJumps := 1, JumpSpeedCmPerSecond := 1000.0}
            character_owner_stasis_component{Entity := Pawn}
            Camera
        Pawn.AddComponents(Parts)
        Slot.Entity.AddEntities(array{Pawn})
        if (set Characters[Slot.Player] = Pawn) {}

    # Create the goal box (player_volume_component; OnGoal on entry)
    MakeGoal<private>():void =
        GoalEntity := entity{}
        GoalEntity.SetGlobalTransform(MakeTranslationTransform(GetStart() + GoalOffsetCm))
        Volume := player_volume_component{Entity := GoalEntity, WidthCm := GoalSizeCm, DepthCm := GoalSizeCm * 4.0, HeightCm := GoalSizeCm, PollIntervalSeconds := 0.1}
        GoalEntity.AddComponents(array{Volume})
        Entity.AddEntities(array{GoalEntity})
        set Goal = option{GoalEntity}
        set Subscriptions += array{Volume.PlayerEnteredEvent.Subscribe(OnGoal)}

    OnGoal<private>(Agent:agent):void =
        if (ExitOnGoal?):
            Print("[platformer_2d_sample_component] Goal!", ?Duration := 3.0)
            OnPlayerRemoved(Agent)
            return
        Print("[platformer_2d_sample_component] Goal! Returning to the start", ?Duration := 3.0)
        if (Pawn := Characters[Agent], Motor := Pawn.GetComponent[character_motor_component]):
            Motor.SetVelocity(vector3{})
            Motor.TeleportTo(GetStart())

    OnRoundStarted<private>()<suspends>:void =
        for (Agent -> Pawn : Characters, Motor := Pawn.GetComponent[character_motor_component]):
            Motor.SetVelocity(vector3{})
            Motor.TeleportTo(GetStart())

    OnRoundEnded<private>():void = {}

    GetStart<private>()<transacts>:vector3 =
        Entity.GetGlobalTransform().Translation
