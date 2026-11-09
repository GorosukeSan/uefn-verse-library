using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Input }
using { /Fortnite.com/Playspaces }
using { ItemSystem }
using { MovementSystem }
using { SceneGraphSystem }

# Role: runs one agent's swing for the duration of Run (every setting is a field of Ability = swing_ability_component. Lengths in cm, speeds in cm/s, accelerations in cm/s^2). Pressing GrabAction attaches a rope to an object within MaxRangeCm beyond the reticle and grabs it; the pendulum swings until jump (ReleaseAction) is pressed
# Grabbing: sweeps a sphere of radius GrabRadiusCm in the reticle direction and grabs the hit point (reaches even slightly off-aim). Objects between the camera and the character, and the player's own items, are excluded. The found point is remembered: after the reticle leaves it, it can still be grabbed for GrabGraceSeconds (until the next point is found; the HUD stays green too). A grab press made while grabbing still counts if it came within GrabBufferSeconds before the release: the next object is grabbed right after releasing (no second press needed). For moving objects the remembered point is held as a position on that object. The grabbed point becomes an entity whose SetOrigin is the hit entity, so it follows that object when it moves
# Ground: grabbing on the ground only attaches the rope and waits (pressing ReelOutAction (aim) while waiting releases the rope without launching); jump lifts by GrabLiftHeightCm and launches with GroundLaunchMultiplier times the airborne momentum (1x when falling off the ground). While grabbing (waiting or swinging), going farther than MaxRangeCm releases (no boost added). Landing later than LandingGraceSeconds after launch returns to waiting (touching the ground before that keeps the swing going)
# Pendulum: computed here and applied every frame (Tick = the owner's TickEvents.PrePhysics; integrated with the delivered DeltaTime) with SetLinearVelocity. On launch adds GrabKickSpeedCmPerSecond in the direction of motion, SwingStartSpeedCmPerSecond over SwingEaseSeconds, and over AutoReelSeconds after launch reels the rope in, slowing down gradually, to AutoReelRatio (default 2/3) of its length at launch; every frame applies gravity SwingGravityCmPerSecondSquared, steering acceleration toward the look direction SwingSteerAccelerationCmPerSecondSquared and air drag SwingDrag. Only the outward speed along the rope is removed; the excess is pulled back at up to MaxRopeCorrectionSpeedCmPerSecond (the pull-back does not carry over to the next frame). Speed is capped at MaxSwingSpeedCmPerSecond. If hitting a wall or floor changes the actual velocity a lot, resyncs to the actual velocity (velocity is held in the engine unit, meters per second; settings are converted with ToEngineSpeed)
# Length: while swinging, pressing the grab input again reels in and ReelOutAction (aim) reels out (ReelSpeedCmPerSecond)
# Multi swing: up to MaxRopes ropes (plus swing_stats.ExtraRopes) can be attached. Pressing the grab input while swinging attaches a rope to the next point if there is room (the press also counts for reeling in). The pendulum pivot is the center of the attached rope points. When a point breaks, gets farther than MaxRangeCm or the grabbed object disappears (checked every frame), only that rope detaches (swing_rope_detached_event); when none is left, releases
# Following: ropes can also be attached to other agents (not only players: a participant's character or their items). With a rope on another agent, instead of waiting for a jump from the ground, once the distance to them reaches within 50 centimeters of FollowDistanceRatio (default 1/4) times the rope limit (MaxRangeCm), lifts by GrabLiftHeightCm and launches the pendulum from the point on them (follows them as they move; jumping to launch also works). Landing mid-swing and moving apart again launches the same way. A rope on another agent does not detach beyond the limit
# Pulling the rope: while on the ground, looking through the reticle at a player whose rope is attached to you (their swing_runner answers HasRopeOn; they are found through Registry) passes swing_reel_hint_event{Holder := that player} to Notify (shows the hint; Holder := false when no longer in view), and pressing the grab input calls their ReelToward instead of grabbing. The called side launches at once if waiting on the ground, pauses its pendulum, is pulled straight toward the puller at ReelPullSpeedCmPerSecond for ReelPullLengthCm (or until as close as possible), and its rope shortens by that much. It then returns to the pendulum on the shorter rope. Needs a swing_registry_component in the scope
# Pull: while a rope is attached to another agent, the strength pulling you back is scaled by PullerCorrectionRatio (a small correction on the pulling side). No force is applied to the other agent (the pulled side)
# Releasing: holding jump while swinging accelerates in the direction of motion at HoldAccelerationCmPerSecondSquared (speed capped at MaxHoldSpeedCmPerSecond); letting go of jump releases, keeping the momentum and adding ReleaseBoostCmPerSecond in the direction of motion. If the grabbed object breaks (swing_anchor_component.Break) or ForceRelease (swing_ability_component.Release) is called, the swing is cut there (no boost added)
# Strength: the swing_stats that Registry (swing_registry_component) combines for this agent is re-read only at start and when Registry reports a change in the modifier sources (ModifiersChangedEvent), and is applied to the grab range, speed limit, acceleration, release boost and reel speed (no polling). If grabbing is disallowed, no new grabs are made. On change, passes swing_stats_changed_event to Notify
# Check interval: leaving the ground, landing, a rope on another agent going taut, and what the reticle points at (grabbable, pullable) have no notification (event), so they are checked every CheckIntervalSeconds (0.1 s)
# Notifies: while idle, swing_target_changed_event when grabbability changes. Passes to Notify swing_grabbed_event (entity of the grabbed point) on every rope attached, swing_rope_detached_event when only one rope detaches, swing_released_event on release, and swing_state_changed_event when the state (idle / waiting on the ground / pendulum) changes. Sends down to the grabbed object (the hit entity) swing_attached_event on grab, swing_pulled_event on every launch and swing_detached_event on release
# Placement: created at runtime by swing_ability_component for each granted agent. Entities of grabbed points are created under the ability entity's simulation entity. Registers itself with Registry if present (SetRunner; so pullers can find it). The state is passed to Notify and the ability turns it into tags (swinging_tag subclasses)
swing_runner := class<unique><internal>:

    # Settings (grab, rope, release, boost, pendulum, input) and the sender of notifications
    Ability<internal>:swing_ability_component
    # Function that receives the notifications (swing_*_event). The owning component re-sends them from its own entity
    Notify<internal>:type{_(:agent, :scene_event):void}
    # Per-frame signal (the owning component's TickEvents.PrePhysics). Await returns the seconds since the previous frame
    Tick<internal>:listenable(float)
    # Scope registry (the owner looks it up once and passes it). false if none
    Registry<internal>:?swing_registry_component
    Agent<internal>:agent
    PlayerInput<internal>:player_input

    # Interval (seconds) for checking the ground, landing, distance to the other agent and the reticle. Character landing and camera direction have no notification (event), so they are checked at this interval
    CheckIntervalSeconds<private>:float = 0.1
    # Slack (centimeters) within which a rope on another agent counts as taut
    TautSlackCm<private>:float = 50.0
    # If the actual velocity differs from the last applied one by more than this (meters per second, the engine velocity unit), treat it as a collision and resync
    VelocitySyncThreshold<private>:float = 3.0

    var RopeLength<private>:float = 0.0
    var ReelingIn<private>:logic = false
    var ReelingOut<private>:logic = false
    var SwingVelocity<private>:vector3 = vector3{}
    var LastApplied<private>:vector3 = vector3{}
    var LastCorrection<private>:vector3 = vector3{}
    var LaunchScale<private>:float = 1.0
    var AutoReelLength<private>:float = 0.0
    var Boosting<private>:logic = false
    var State<private>:swing_state = swing_state.Idle
    var LastCanGrab<private>:?logic = false
    var LastGrab<private>:?swing_grab = false
    var LastGrabTime<private>:float = 0.0
    var PressCount<private>:int = 0
    var UsedPressCount<private>:int = 0
    var LastPressTime<private>:float = 0.0
    var Stats<private>:swing_stats = swing_stats{}
    var Ropes<private>:[]swing_rope = array{}
    var LastReelHolder<private>:?agent = false
    var PendingReel<private>:?agent = false
    var ReelLeft<private>:float = 0.0

    ReelRequestedEvent<private>:event() = event(){}

    GrabPressedEvent<private>:event() = event(){}

    ForceReleaseEvent<private>:event() = event(){}

    Run<internal>()<suspends>:void =
        PlayerInput.AddInputMapping(Ability.GrabMapping)
        PlayerInput.AddInputMapping(Ability.ReleaseMapping)
        PlayerInput.AddInputMapping(Ability.ReelOutMapping)
        GrabEvents := PlayerInput.GetInputEvents(Ability.GrabAction)
        UpdateStats()
        if (Current := Registry?):
            Current.SetRunner(Agent, Self)
        defer:
            if (Current := Registry?):
                Current.ForgetRunner(Agent, Self)
        race:
            TrackGrabPresses(GrabEvents)
            RunGrabLoop()
            WatchAim()
            WatchModifiers()

    # If grabbing (waiting on the ground or swinging), forces a release. No boost added
    ForceRelease<internal>():void =
        ForceReleaseEvent.Signal()

    TrackGrabPresses<private>(GrabEvents:input_events(logic))<suspends>:void =
        loop:
            GrabEvents.BeginDetectEvent.Await()
            set PressCount += 1
            set LastPressTime = GetSimulationElapsedTime()
            GrabPressedEvent.Signal()

    RunGrabLoop<private>()<suspends>:void =
        loop:
            if (not HasBufferedPress[]):
                GrabPressedEvent.Await()
            set UsedPressCount = PressCount
            if (FortCharacter := Agent.GetFortCharacter[]):
                if (Holder := FindReelableHolder[FortCharacter]):
                    Holder.ReelToward(Agent)
                else if (Grab := FindGrab[FortCharacter]):
                    set LastGrab = false
                    Attached := AttachRope(Grab)
                    if (Attached?):
                        Swing(FortCharacter)

    HasRopeOn<internal>(Target:agent)<decides><transacts>:void =
        first (Rope : Ropes, Held := Rope.TargetAgent?, Held = Target):
            Rope

    ReelToward<internal>(Puller:agent):void =
        if (HasRopeOn[Puller]):
            set PendingReel = option{Puller}
            ReelRequestedEvent.Signal()
            if (State = swing_state.Swinging, FortCharacter := Agent.GetFortCharacter[]):
                ApplyReel(FortCharacter)

    ApplyReel<private>(FortCharacter:fort_character):void =
        if (PendingReel?):
            set PendingReel = false
            set ReelLeft = Ability.ReelPullLengthCm

    StepReel<private>(FortCharacter:fort_character, Position:vector3, Pivot:vector3, DeltaTime:float):void =
        Offset := Pivot - Position
        Closest := Ability.MinRopeLengthCm
        if (Offset.Length() <= Closest):
            set ReelLeft = 0.0
            set RopeLength = Closest
        else:
            Step := Ability.ReelPullSpeedCmPerSecond * DeltaTime
            set ReelLeft -= Step
            set RopeLength = Max(Offset.Length() - Step, Closest)
            set SwingVelocity = Offset.MakeUnitVector() * ToEngineSpeed(Ability.ReelPullSpeedCmPerSecond)
            ApplyVelocity(FortCharacter, SwingVelocity, vector3{})

    FindReelableHolder<private>(FortCharacter:fort_character)<decides><transacts>:swing_runner =
        FortCharacter.IsOnGround[]
        Hit := FindGrabHit[FortCharacter]
        Holder := FindPullTarget(Hit.TargetComponent.Entity)?
        Runner := Registry?.FindRunner[Holder]
        Runner.HasRopeOn[Agent]
        Runner

    HasBufferedPress<private>()<decides><transacts>:void =
        PressCount > UsedPressCount
        GetSimulationElapsedTime() - LastPressTime <= Ability.GrabBufferSeconds

    FindGrab<private>(FortCharacter:fort_character)<decides><transacts>:swing_grab =
        Stats.CanGrab?
        if (Hit := FindGrabHit[FortCharacter]):
            Target := Hit.TargetComponent.Entity
            Grab := swing_grab{Target := Target, LocalPosition := Target.ToLocalPosition(Hit.ContactPosition), TargetAgent := FindPullTarget(Target)}
            set LastGrab = option{Grab}
            set LastGrabTime = GetSimulationElapsedTime()
            Grab
        else:
            Remembered := LastGrab?
            GetSimulationElapsedTime() - LastGrabTime <= Ability.GrabGraceSeconds
            Remembered.Target.GetSimulationEntity[]
            Remembered

    FindGrabHit<private>(FortCharacter:fort_character)<decides><transacts>:sweep_hit =
        CharacterEntity := FortCharacter.GetEntity[]
        Origin := FortCharacter.GetViewOrigin()
        CameraGap := Distance(Origin, CharacterEntity.GetGlobalTranslation())
        Displacement := FortCharacter.GetViewDirection() * GetMaxRangeCm()
        first:
            Hit : CharacterEntity.FindSweepHits(Displacement, MakeTranslationTransform(Origin), GetGrabVolume())
            Hit.SourceHitDistance > CameraGap
            Hit.TargetComponent.Entity <> CharacterEntity
            CanGrabEntity[Hit.TargetComponent.Entity]
        do:
            Hit

    CanGrabEntity<private>(Target:entity)<decides><transacts>:void =
        if (Owner := Target.FindOwnerAgent[]):
            Owner <> Agent
            Owner.GetFortCharacter[]

    FindPullTarget<private>(Target:entity)<transacts>:?agent =
        if (Found := FindCharacterAgent[Target]):
            option{Found}
        else if (Owner := Target.FindOwnerAgent[], Owner <> Agent, Owner.GetFortCharacter[]):
            option{Owner}
        else:
            false

    FindCharacterAgent<private>(Target:entity)<decides><transacts>:agent =
        Playspace := Ability.Entity.GetPlayspaceForEntity[]
        first:
            Participant : Playspace.GetParticipants()
            Participant <> Agent
            Participant.GetFortCharacter[].GetEntity[] = Target
        do:
            Participant

    GetGrabVolume<private>()<transacts>:collision_volume =
        if (Ability.GrabRadiusCm > 0.0):
            collision_sphere{Radius := Ability.GrabRadiusCm}
        else:
            collision_point{}

    CreateAnchor<private>(Grab:swing_grab):?entity =
        if (SimulationEntity := Ability.Entity.GetSimulationEntity[]):
            Anchor := entity{}
            Anchor.SetOrigin(entity_origin{Entity := Grab.Target})
            Anchor.SetLocalTransform(MakeTranslationTransform(Grab.LocalPosition))
            Anchor.AddComponents(array{swing_anchor_component{Entity := Anchor}})
            SimulationEntity.AddEntities(array{Anchor})
            option{Anchor}
        else:
            false

    AttachRope<private>(Grab:swing_grab):?swing_rope =
        NewAnchor := CreateAnchor(Grab)
        if (Anchor := NewAnchor?):
            Rope := swing_rope{Anchor := Anchor, Target := Grab.Target, TargetAgent := Grab.TargetAgent}
            set Ropes += array{Rope}
            Notify(Agent, swing_grabbed_event{Ability := Ability, Agent := Agent, Anchor := Anchor})
            Grab.Target.SendDown(swing_attached_event{Ability := Ability, Agent := Agent, Anchor := Anchor})
            option{Rope}
        else:
            false

    GetDistanceTo<private>(Anchor:entity)<transacts>:float =
        if (Position := Agent.GetFortCharacter[].FindGlobalTranslation[]):
            Distance(Position, Anchor.GetGlobalTranslation())
        else:
            0.0

    DetachRope<private>(Rope:swing_rope):void =
        set Ropes = for:
            Current : Ropes
            Current <> Rope
        do:
            Current
        Rope.Target.SendDown(swing_detached_event{Ability := Ability, Agent := Agent, Anchor := Rope.Anchor})
        Rope.Anchor.RemoveFromParent()

    DetachAll<private>():void =
        for (Rope : Ropes):
            DetachRope(Rope)

    Swing<private>(FortCharacter:fort_character)<suspends>:void =
        defer:
            DetachAll()
            Notify(Agent, swing_released_event{Ability := Ability, Agent := Agent})
            SetState(swing_state.Idle)
        ReleaseEvents := PlayerInput.GetInputEvents(Ability.ReleaseAction)
        race:
            WatchReel(Ability.GrabAction, true)
            WatchReel(Ability.ReelOutAction, false)
            KeepSwinging(FortCharacter, ReleaseEvents)
            WatchRopes(FortCharacter)
            WatchExtraGrabs(FortCharacter)
            ForceReleaseEvent.Await()

    WatchRopes<private>(FortCharacter:fort_character)<suspends>:void =
        loop:
            Tick.Await()
            for (Rope : Ropes):
                if (not IsRopeKept[FortCharacter, Rope]):
                    DetachRope(Rope)
                    Notify(Agent, swing_rope_detached_event{Ability := Ability, Agent := Agent, Anchor := Rope.Anchor})
            if (Ropes.Length = 0):
                return

    IsRopeKept<private>(FortCharacter:fort_character, Rope:swing_rope)<decides><transacts>:void =
        Rope.Target.GetSimulationEntity[]
        Marker := Rope.Anchor.GetComponent[swing_anchor_component]
        not Marker.Broken?
        Position := FortCharacter.FindGlobalTranslation[]
        Limit := if (Rope.TargetAgent?) then Inf else GetMaxRangeCm()
        Distance(Position, Rope.Anchor.GetGlobalTranslation()) <= Limit

    WatchExtraGrabs<private>(FortCharacter:fort_character)<suspends>:void =
        loop:
            GrabPressedEvent.Await()
            if (Ropes.Length < GetMaxRopes(), Grab := FindGrab[FortCharacter]):
                set UsedPressCount = PressCount
                set LastGrab = false
                Attached := AttachRope(Grab)
                if (Attached?):
                    FitRopeLength(FortCharacter)

    FitRopeLength<private>(FortCharacter:fort_character):void =
        if (Position := FortCharacter.FindGlobalTranslation[]):
            set RopeLength = Max(Distance(Position, GetPivot()), Ability.MinRopeLengthCm)

    GetMaxRopes<private>()<reads>:int =
        Max(Ability.MaxRopes + Stats.ExtraRopes, 1)

    GetPivot<private>()<transacts>:vector3 =
        var Sum:vector3 = vector3{}
        for (Rope : Ropes):
            set Sum = Sum + Rope.Anchor.GetGlobalTranslation()
        if (Ropes.Length > 0):
            Sum / (Ropes.Length * 1.0)
        else:
            Sum

    HasAgentRope<private>()<decides><reads>:void =
        Ropes.Length > 0
        for (Rope : Ropes):
            Rope.TargetAgent?

    KeepSwinging<private>(FortCharacter:fort_character, ReleaseEvents:input_events(logic))<suspends>:void =
        loop:
            Launch := AwaitLaunch(FortCharacter, ReleaseEvents)
            if (Scale := Launch?):
                Landed := Fly(FortCharacter, ReleaseEvents, Scale)
                if (not Landed?):
                    break
            else:
                break

    AwaitLaunch<private>(FortCharacter:fort_character, ReleaseEvents:input_events(logic))<suspends>:?float =
        if (FortCharacter.IsOnGround[]):
            SetState(swing_state.Anchored)
            WaitForLaunch(FortCharacter, ReleaseEvents)
        else:
            option{1.0}

    WaitForLaunch<private>(FortCharacter:fort_character, ReleaseEvents:input_events(logic))<suspends>:?float =
        race:
            block:
                ReleaseEvents.BeginDetectEvent.Await()
                option{Ability.GroundLaunchMultiplier}
            block:
                AwaitLeftGround(FortCharacter)
                option{1.0}
            block:
                AwaitAgentRopeTaut()
                option{1.0}
            block:
                ReelRequestedEvent.Await()
                option{1.0}
            block:
                PlayerInput.GetInputEvents(Ability.ReelOutAction).BeginDetectEvent.Await()
                false

    AwaitAgentRopeTaut<private>()<suspends>:void =
        loop:
            Sleep(CheckIntervalSeconds)
            if (IsAgentRopeTaut[]):
                return

    IsAgentRopeTaut<private>()<decides><transacts>:void =
        first:
            Rope : Ropes
            Rope.TargetAgent?
            GetDistanceTo(Rope.Anchor) >= GetMaxRangeCm() * Ability.FollowDistanceRatio - TautSlackCm
        do:
            Rope

    AwaitLeftGround<private>(FortCharacter:fort_character)<suspends>:void =
        loop:
            Sleep(CheckIntervalSeconds)
            if (FortCharacter.IsInAir[]):
                return

    AwaitLanded<private>(FortCharacter:fort_character)<suspends>:void =
        Sleep(Ability.LandingGraceSeconds)
        loop:
            Sleep(CheckIntervalSeconds)
            if (FortCharacter.IsOnGround[]):
                return

    Fly<private>(FortCharacter:fort_character, ReleaseEvents:input_events(logic), Scale:float)<suspends>:logic =
        if (FortCharacter.IsOnGround[]):
            FortCharacter.LiftBy(Ability.GrabLiftHeightCm)
        set LaunchScale = Scale
        set SwingVelocity = FortCharacter.GetLinearVelocity()
        if (Position := FortCharacter.FindGlobalTranslation[]):
            AnchorPosition := GetPivot()
            set RopeLength = Max(Distance(Position, AnchorPosition), Ability.MinRopeLengthCm)
            set AutoReelLength = RopeLength * (1.0 - Ability.AutoReelRatio)
            Outward := GetOutward(Position, AnchorPosition)
            Kick := GetMoveTangent(FortCharacter, Outward) * (ToEngineSpeed(Ability.GrabKickSpeedCmPerSecond) * Stats.AccelerationScale * Scale)
            set SwingVelocity = SwingVelocity + Kick
        ApplyVelocity(FortCharacter, SwingVelocity, vector3{})
        SetState(swing_state.Swinging)
        ApplyReel(FortCharacter)
        for (Rope : Ropes):
            Rope.Target.SendDown(swing_pulled_event{Ability := Ability, Agent := Agent, Anchor := Rope.Anchor})
        Landed := race:
            block:
                KeepRope(FortCharacter)
                false
            block:
                BoostUntilReleased(ReleaseEvents)
                false
            block:
                AwaitLanded(FortCharacter)
                true
        if (not Landed?):
            Release(FortCharacter)
        Landed

    BoostUntilReleased<private>(ReleaseEvents:input_events(logic))<suspends>:void =
        ReleaseEvents.BeginDetectEvent.Await()
        set Boosting = true
        defer:
            set Boosting = false
        ReleaseEvents.EndDetectEvent.Await()

    Release<private>(FortCharacter:fort_character):void =
        Speed := SwingVelocity.Length()
        if (Speed > 0.1):
            Boost := SwingVelocity * (ToEngineSpeed(Ability.ReleaseBoostCmPerSecond) * Stats.BoostScale / Speed)
            FortCharacter.SetLinearVelocity(SwingVelocity + Boost)

    SetState<private>(NewState:swing_state):void =
        set State = NewState
        set LastCanGrab = false
        Notify(Agent, swing_state_changed_event{Ability := Ability, Agent := Agent, State := NewState})

    KeepRope<private>(FortCharacter:fort_character)<suspends>:void =
        var Elapsed:float = 0.0
        loop:
            FrameSeconds := Tick.Await()
            DeltaTime := Max(FrameSeconds, 0.001)
            set Elapsed += DeltaTime
            UpdateRopeLength(DeltaTime, Elapsed)
            if (Elapsed > Ability.SwingEaseSeconds):
                SyncWithActualVelocity(FortCharacter)
            if (Position := FortCharacter.FindGlobalTranslation[], Ropes.Length > 0):
                if (ReelLeft > 0.0):
                    StepReel(FortCharacter, Position, GetPivot(), DeltaTime)
                else:
                    StepPendulum(FortCharacter, Position, GetPivot(), DeltaTime, Elapsed)

    SyncWithActualVelocity<private>(FortCharacter:fort_character):void =
        Actual := FortCharacter.GetLinearVelocity()
        if (Distance(Actual, LastApplied) > VelocitySyncThreshold):
            set SwingVelocity = Actual - LastCorrection

    UpdateRopeLength<private>(DeltaTime:float, Elapsed:float)<transacts>:void =
        Step := Ability.ReelSpeedCmPerSecond * Stats.ReelScale * DeltaTime
        if (ReelingIn?):
            ShortenRope(Step)
        if (ReelingOut?):
            set RopeLength = Min(RopeLength + Step, GetMaxRangeCm())
        Progress := GetAutoReelProgress(Elapsed) - GetAutoReelProgress(Elapsed - DeltaTime)
        if (Progress > 0.0):
            ShortenRope(AutoReelLength * Progress)

    GetAutoReelProgress<private>(Elapsed:float)<reads>:float =
        if (Ability.AutoReelSeconds > 0.0):
            Ratio := Min(Max(Elapsed / Ability.AutoReelSeconds, 0.0), 1.0)
            1.0 - (1.0 - Ratio) * (1.0 - Ratio)
        else:
            0.0

    ShortenRope<private>(Amount:float)<transacts>:void =
        set RopeLength = Max(RopeLength - Amount, Ability.MinRopeLengthCm)

    StepPendulum<private>(FortCharacter:fort_character, Position:vector3, AnchorPosition:vector3, DeltaTime:float, Elapsed:float):void =
        CurrentLength := Distance(Position, AnchorPosition)
        Outward := GetOutward(Position, AnchorPosition)
        Gravity := vector3{Up := -ToEngineSpeed(Ability.SwingGravityCmPerSecondSquared) * DeltaTime}
        Steer := GetViewTangent(FortCharacter, Outward) * (ToEngineSpeed(Ability.SwingSteerAccelerationCmPerSecondSquared) * Stats.AccelerationScale * DeltaTime)
        Push := GetMoveTangent(FortCharacter, Outward) * ((GetStartAcceleration(Elapsed) + GetHoldAcceleration()) * DeltaTime)
        DragScale := Max(1.0 - Ability.SwingDrag * DeltaTime, 0.0)
        var Velocity:vector3 = (SwingVelocity + Gravity + Steer + Push) * DragScale
        var Correction:vector3 = vector3{}
        if (CurrentLength >= RopeLength):
            OutwardSpeed := DotProduct(Velocity, Outward)
            if (OutwardSpeed > 0.0):
                set Velocity = Velocity - Outward * OutwardSpeed
            Stretch := (CurrentLength - RopeLength) / 100.0
            CorrectionSpeed := Min(Stretch * GetCorrectionRate(), ToEngineSpeed(Ability.MaxRopeCorrectionSpeedCmPerSecond))
            set Correction = Outward * -CorrectionSpeed
        Speed := Velocity.Length()
        SpeedLimit := GetSpeedLimit()
        if (Speed > SpeedLimit):
            set Velocity = Velocity * (SpeedLimit / Speed)
        set SwingVelocity = Velocity
        ApplyVelocity(FortCharacter, Velocity, Correction)

    GetCorrectionRate<private>()<reads>:float =
        if (HasAgentRope[]):
            Ability.RopeCorrectionRate * Ability.PullerCorrectionRatio
        else:
            Ability.RopeCorrectionRate

    ApplyVelocity<private>(FortCharacter:fort_character, Velocity:vector3, Correction:vector3):void =
        set LastApplied = Velocity + Correction
        set LastCorrection = Correction
        FortCharacter.SetLinearVelocity(LastApplied)

    GetStartAcceleration<private>(Elapsed:float)<reads>:float =
        if (Elapsed < Ability.SwingEaseSeconds):
            ToEngineSpeed(Ability.SwingStartSpeedCmPerSecond) * Stats.AccelerationScale * LaunchScale / Ability.SwingEaseSeconds
        else:
            0.0

    GetHoldAcceleration<private>()<reads>:float =
        if (Boosting?):
            ToEngineSpeed(Ability.HoldAccelerationCmPerSecondSquared) * Stats.AccelerationScale
        else:
            0.0

    GetSpeedLimit<private>()<reads>:float =
        if (Boosting?):
            ToEngineSpeed(Max(Ability.MaxSwingSpeedCmPerSecond, Ability.MaxHoldSpeedCmPerSecond)) * Stats.SpeedScale
        else:
            ToEngineSpeed(Ability.MaxSwingSpeedCmPerSecond) * Stats.SpeedScale

    GetOutward<private>(Position:vector3, AnchorPosition:vector3)<reads>:vector3 =
        Offset := Position - AnchorPosition
        if (Offset.Length() > 1.0):
            Offset.MakeUnitVector()
        else:
            vector3{Up := -1.0}

    GetMoveTangent<private>(FortCharacter:fort_character, Outward:vector3)<transacts>:vector3 =
        Tangent := SwingVelocity - Outward * DotProduct(SwingVelocity, Outward)
        if (Tangent.Length() > 0.5):
            Tangent.MakeUnitVector()
        else:
            GetViewTangent(FortCharacter, Outward)

    GetViewTangent<private>(FortCharacter:fort_character, Outward:vector3)<transacts>:vector3 =
        View := FortCharacter.GetViewDirection()
        Tangent := View - Outward * DotProduct(View, Outward)
        if (Tangent.Length() > 0.01):
            Tangent.MakeUnitVector()
        else:
            vector3{}

    WatchReel<private>(Action:input_action(logic), Inward:logic)<suspends>:void =
        Events := PlayerInput.GetInputEvents(Action)
        defer:
            SetReeling(Inward, false)
        loop:
            Events.BeginDetectEvent.Await()
            SetReeling(Inward, true)
            Events.EndDetectEvent.Await()
            SetReeling(Inward, false)

    SetReeling<private>(Inward:logic, Value:logic):void =
        if (Inward?):
            set ReelingIn = Value
        else:
            set ReelingOut = Value

    WatchAim<private>()<suspends>:void =
        loop:
            Sleep(CheckIntervalSeconds)
            if (State = swing_state.Idle):
                NotifyCanGrab(IsGrabbable())
            NotifyReelHint(FindReelHolder())

    NotifyCanGrab<private>(CanGrab:logic):void =
        Unchanged := logic{LastCanGrab? = CanGrab}
        if (not Unchanged?):
            set LastCanGrab = option{CanGrab}
            Notify(Agent, swing_target_changed_event{Ability := Ability, Agent := Agent, CanGrab := CanGrab})

    NotifyReelHint<private>(Holder:?agent):void =
        Same := logic{Holder? = LastReelHolder? or (not Holder?, not LastReelHolder?)}
        if (not Same?):
            set LastReelHolder = Holder
            Notify(Agent, swing_reel_hint_event{Ability := Ability, Agent := Agent, Holder := Holder})

    FindReelHolder<private>()<transacts>:?agent =
        if (State = swing_state.Idle, FortCharacter := Agent.GetFortCharacter[], Runner := FindReelableHolder[FortCharacter]):
            option{Runner.Agent}
        else:
            false

    IsGrabbable<private>()<transacts>:logic =
        if (FortCharacter := Agent.GetFortCharacter[], FindGrab[FortCharacter]):
            true
        else:
            false

    GetMaxRangeCm<private>()<reads>:float =
        Ability.MaxRangeCm * Stats.RangeScale

    # Converts a speed / acceleration setting (cm/s, cm/s^2) to the engine velocity unit (SetLinearVelocity's meters per second)
    ToEngineSpeed<private>(CmPerSecond:float)<computes>:float =
        CmPerSecond / 100.0

    # Rebuilds only when the registry reports a change in the modifier sources (without a registry no modifier applies)
    WatchModifiers<private>()<suspends>:void =
        if (Current := Registry?):
            loop:
                Current.ModifiersChangedEvent.Await()
                UpdateStats()
        else:
            Sleep(Inf)

    UpdateStats<private>():void =
        NewStats := ComputeStats()
        Unchanged := logic{Stats = NewStats}
        if (not Unchanged?):
            set Stats = NewStats
            Notify(Agent, swing_stats_changed_event{Ability := Ability, Agent := Agent, Stats := NewStats})

    ComputeStats<private>()<transacts>:swing_stats =
        if (Current := Registry?) then Current.GetStats(Agent) else swing_stats{}

swing_grab<internal> := struct:
    # Entity of the object to grab
    Target<public>:entity
    # Position of the grab point relative to Target (centimeters)
    LocalPosition<public>:vector3
    # If Target belongs to another agent (their character or item), that agent. Otherwise false
    TargetAgent<public>:?agent = false

swing_rope<internal> := class<unique>:
    # Entity of the rope point (with swing_anchor_component)
    Anchor<public>:entity
    # Entity of the object the rope is attached to
    Target<public>:entity
    # If the rope is attached to another agent, that agent. Otherwise false
    TargetAgent<public>:?agent
