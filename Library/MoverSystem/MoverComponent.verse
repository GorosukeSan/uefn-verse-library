using { /Verse.org/SceneGraph }
using { /Verse.org/SceneGraph/KeyframedMovement }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { ActivationSystem }
using { SceneGraphSystem }
using { MoverSystem.TooltipKit }

# How the mover moves
mover_motion<public> := enum:
    # The engine (keyframed_movement_component) moves straight to the target at a constant speed (recommended). The server does not send the position every frame, so it is smooth on every screen. Does not collide with other objects; passes through them
    Keyframe
    # Moved a little every frame in Verse; when something is in the way, bounces off the surface it hit (BounceSeconds). Use only when bouncing is needed
    Physics

# Role: moves the entity, at SpeedCmPerSecond (centimeters per second), through the targets decided by the route (a mover_route_component subclass) on the same entity, in order. On reaching a target, waits WaitSeconds seconds, then moves on. Stops when the route ends (no more targets)
# Motion: with Motion = Keyframe, plays one leg at a time through keyframed_movement_component (attached when the entity has none). With Physics, moves every frame (TickEvents.PrePhysics); on a hit, travels in the bounced direction for BounceSeconds seconds and then heads back to the same target (0 gives up that target and moves on)
# When: with StartOnBegin, moves from the start. The activate signal (activated_event) starts / resumes it, the deactivate signal (deactivated_event) pauses it (stops in place; the next activation continues from there). Restart starts the route over from the beginning (even after it finished)
# Placement: attach in the editor to the entity to move (may also be created at runtime). One per entity
# Same entity: a route (exactly one of mover_path_route_component / mover_random_route_component / mover_box_route_component from RouteKit). With Physics, a mesh with collision. With Keyframe, keyframed_movement_component (attached at runtime when missing; no other component may keyframe-move the same entity)
# Notifies: mover_target_changed_event and TargetChangedEvent when a target is chosen, mover_target_reached_event and TargetReachedEvent on arrival, mover_finished_event and FinishedEvent when finished (scene events are SendDown from its own entity; with AlsoSendUp, also SendUp from the parent)
# One way: with mover_path_route_component Mode = Once, stops at the last point and FinishedEvent fires (to move once from the current position to another target, call SetPoints then Restart(?ReturnToStart := false))
# Curves: when the route's GetLeg returns intermediate points (mover_leg.Via), the mover passes through them in order to the target at a constant speed (mover_spline_route_component). With Keyframe, the points up to one target are combined into one SetKeyframes. With mover_leg.FaceTravelDirection, yaw is aligned to the direction of travel
# From outside: Play / Pause / Restart / SetSpeed, IsMoving / IsFinished / FindTarget / FindStartPosition
# Requirements / notes: the start position is the position one frame after the simulation begins (a spawner may re-place it on the same frame). Keyframe legs are built as deltas seen from the parent entity (should reach the world target even when the parent is rotated. ⚠ Unverified:)
mover_component<public> := class<final_super>(component):

    # How to move (Keyframe = the engine moves it smoothly and it passes through other objects. Physics = moved in Verse and bounces on hits). Default Keyframe
    @editable:
        ToolTip := MoverMotionToolTip
        Categories := array{MoverCategory, MoverMoveCategory}
    Motion<public>:mover_motion = mover_motion.Keyframe
    # Speed (centimeters per second. 1-10000). Default 300
    @editable_number(float):
        ToolTip := MoverSpeedToolTip
        Categories := array{MoverCategory, MoverMoveCategory}
        MinValue := option{1.0}
        MaxValue := option{10000.0}
    SpeedCmPerSecond<public>:float = 300.0
    # When on, moves from the start of the game. When off, starts on the activate signal (activated_event) or Play. Default on
    @editable:
        ToolTip := MoverStartOnBeginToolTip
        Categories := array{MoverCategory, MoverMoveCategory}
    StartOnBegin<public>:logic = true
    # Seconds to stay at each target before heading to the next. Default 0 (no stop)
    @editable_number(float):
        ToolTip := MoverWaitSecondsToolTip
        Categories := array{MoverCategory, MoverMoveCategory}
        MinValue := option{0.0}
        MaxValue := option{60.0}
    WaitSeconds<public>:float = 0.0
    # With Physics, seconds to travel in the bounced direction after a hit. Then heads back to the same target. 0 gives up that target and moves on. Default 0.3
    @editable_number(float):
        ToolTip := MoverBounceSecondsToolTip
        Categories := array{MoverCategory, MoverMoveCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    BounceSeconds<public>:float = 0.3
    # When on, the notifications (mover_target_changed_event / mover_target_reached_event / mover_finished_event) are also sent from the parent up to the ancestors (SendUp), in addition to the descendants (SendDown) (for game flow nodes / ancestor parts that react to arrival). Its own entity receives only the one SendDown. Default off
    @editable:
        ToolTip := MoverAlsoSendUpToolTip
        Categories := array{MoverCategory, MoverMoveCategory}
    AlsoSendUp<public>:logic = false

    TargetChangedEventInternal<private><final>:event(mover_target) = event(mover_target){}

    # Fires with the target when the next target is chosen and the mover starts heading for it (Await / Subscribe; cannot be Signaled from outside)
    TargetChangedEvent<public><final>:listenable(mover_target) = MakeProxyListenable(TargetChangedEventInternal)

    TargetReachedEventInternal<private><final>:event(mover_target) = event(mover_target){}

    # Fires with the target on arrival (before the WaitSeconds wait. Await / Subscribe; cannot be Signaled from outside)
    TargetReachedEvent<public><final>:listenable(mover_target) = MakeProxyListenable(TargetReachedEventInternal)

    FinishedEventInternal<private><final>:event() = event(){}

    # Fires when the route ends and the mover stops (never for Loop / PingPong / random routes. After a Restart it fires again when the route ends again. Await / Subscribe; cannot be Signaled from outside)
    FinishedEvent<public><final>:listenable(tuple()) = MakeProxyListenable(FinishedEventInternal)

    var Playing<private>:logic = false
    var Finished<private>:logic = false
    var SpeedOverride<private>:?float = false
    var Target<private>:?mover_target = false
    var Keyframed<private>:?keyframed_movement_component = false
    var SegmentActive<private>:logic = false
    # Position one frame after the simulation began (where Restart returns to). false until read
    var StartPosition<private>:?vector3 = false
    # Rotation one frame after the simulation began (where Restart returns to)
    var StartRotation<private>:rotation = IdentityRotation()
    # Whether the next restart returns to the start position (argument of Restart)
    var ReturnOnRestart<private>:logic = true

    PlayEvent<private>:event() = event(){}
    ReplanEvent<private>:event() = event(){}
    RestartEvent<private>:event() = event(){}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (StartOnBegin?):
            set Playing = true

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Play()
        else if (deactivated_event[SceneEvent]):
            Pause()
        false

    OnSimulate<override>()<suspends>:void =
        # A spawner or the like may re-place the entity on the same frame, so wait one frame before reading the start position
        TickEvents.PrePhysics.Await()
        StartTransform := Entity.GetGlobalTransform()
        Start := StartTransform.Translation
        set StartPosition = option{Start}
        set StartRotation = StartTransform.Rotation
        var Home:vector3 = Start
        loop:
            # Run the route to the end. On a Restart midway, stop there and start over
            Restarted := race:
                block:
                    RunRoute(Home)
                    false
                block:
                    RestartEvent.Await()
                    true
            if (not Restarted?):
                Finish()
                RestartEvent.Await()
            set Home = PrepareRestart(Start)

    # Move through the route's targets in order. Returns when there are no more targets (end of the route / no route component)
    RunRoute<private>(Home:vector3)<suspends>:void =
        if (Route := Entity.GetComponent[mover_route_component]):
            if (Motion = mover_motion.Keyframe, not Keyframed?):
                Found := FindOrAddKeyframed()
                set Keyframed = option{Found}
            loop:
                AwaitPlaying()
                MaybeNext := Route.NextTarget(Home, Entity.GetGlobalTranslation())
                if (Next := MaybeNext?):
                    set Target = option{Next}
                    Leg := Route.GetLeg(Entity.GetGlobalTranslation(), Next)
                    TargetChangedEventInternal.Signal(Next)
                    Send(mover_target_changed_event{Mover := Self, Target := Next})
                    Reached := MoveTo(Next.Position, Leg)
                    if (Reached?):
                        TargetReachedEventInternal.Signal(Next)
                        Send(mover_target_reached_event{Mover := Self, Target := Next})
                        WaitFor(WaitSeconds)
                else:
                    break
        else:
            Print("[mover_component] No route component (mover_route_component subclass) on the same entity. Finishing without moving")

    Finish<private>():void =
        set Target = false
        set Finished = true
        FinishedEventInternal.Signal()
        Send(mover_finished_event{Mover := Self})

    # Prepare a restart. Stops the leg playback, returns to the start position and rotation when ReturnOnRestart, and resets the route. Returns the Home (start position) of the next run
    # ⚠ Unverified: whether SetGlobalTransform after keyframed_movement_component.Stop lands at that position on every screen (whether Stop re-sends the position where it stopped and overwrites it)
    PrepareRestart<private>(Start:vector3):vector3 =
        if (K := Keyframed?):
            K.Stop()
        set SegmentActive = false
        set Target = false
        set Finished = false
        if (ReturnOnRestart?):
            Entity.SetGlobalTransform(transform{Translation := Start, Rotation := StartRotation, Scale := Entity.GetGlobalTransform().Scale})
        if (Route := Entity.GetComponent[mover_route_component]):
            Route.Reset()
        if (ReturnOnRestart?) then Start else Entity.GetGlobalTranslation()

    # Send to itself and its descendants. With AlsoSendUp, also from the parent to the ancestors (from the parent, so its own entity does not receive it twice)
    Send<private>(SceneEvent:scene_event):void =
        Entity.SendDown(SceneEvent)
        if (AlsoSendUp?, Parent := Entity.GetParent[]):
            Parent.SendUp(SceneEvent)

    # Start moving (the start when StartOnBegin is false, or resume after Pause). Continues from where it stopped. Does nothing when the route has finished
    Play<public>():void =
        if (not Playing?):
            set Playing = true
            if (K := Keyframed?, SegmentActive?):
                K.Play()
            PlayEvent.Signal()

    # Pause in place (Play continues from there). Does nothing when already stopped
    Pause<public>():void =
        if (Playing?):
            set Playing = false
            if (K := Keyframed?, SegmentActive?):
                K.Pause()

    # Start the route over from the beginning (while moving, while paused or after finishing. Starts moving when paused). With ReturnToStart = true (default), first teleports back to the position (FindStartPosition) and rotation at simulation start. With false, moves from the current position, and the route's Home (the first point of IncludeStart / the random center) becomes the current position too. Called before moving starts (the first frame), it is the same as Play
    Restart<public>(?ReturnToStart:logic = true):void =
        set ReturnOnRestart = ReturnToStart
        set Playing = true
        PlayEvent.Signal()
        RestartEvent.Signal()

    # Change the speed (centimeters per second; below 1 becomes 1). Takes effect immediately, even on the leg in progress
    SetSpeed<public>(CmPerSecond:float):void =
        set SpeedOverride = option{Max(CmPerSecond, 1.0)}
        ReplanEvent.Signal()

    # Current speed (centimeters per second). SpeedCmPerSecond unless changed with SetSpeed
    GetSpeedCmPerSecond<public>()<reads>:float =
        if (Speed := SpeedOverride?) then Speed else Max(SpeedCmPerSecond, 1.0)

    # Succeeds while moving (Played and the route has not finished). Also succeeds during the WaitSeconds wait
    IsMoving<public>()<decides><reads>:void =
        Playing?
        not Finished?

    # Succeeds when the route has ended and the mover stopped
    IsFinished<public>()<decides><reads>:void =
        Finished?

    # Position one frame after the simulation began (world position, centimeters; where Restart returns to). Fails until read
    FindStartPosition<public>()<decides><reads>:vector3 =
        StartPosition?

    # The target currently headed for (or reached and waiting at). Fails before moving starts and after finishing
    FindTarget<public>()<decides><reads>:mover_target =
        Target?

    AwaitPlaying<private>()<suspends>:void =
        loop:
            if (Playing?):
                break
            PlayEvent.Await()

    WaitFor<private>(Seconds:float)<suspends>:void =
        var Left:float = Seconds
        loop:
            if (Left <= 0.0):
                break
            AwaitPlaying()
            set Left -= TickEvents.PrePhysics.Await()

    # Move to Destination through the Leg.Via points in order. true on arrival (false when Physics hit something and gave up that target)
    MoveTo<private>(Destination:vector3, Leg:mover_leg)<suspends>:logic =
        Path := Leg.Via + array{Destination}
        if (K := Keyframed?):
            MoveByKeyframes(K, Path, Leg.FaceTravelDirection)
        else:
            MoveAlongBySteps(Path, Leg.FaceTravelDirection)

    # Play the legs through the Path points as one combined SetKeyframes. On SetSpeed (ReplanEvent), rebuild from the current leg onward at the new speed
    MoveByKeyframes<private>(K:keyframed_movement_component, Path:[]vector3, Face:logic)<suspends>:logic =
        var Remaining:[]vector3 = Path
        loop:
            From := Entity.GetGlobalTranslation()
            Keyframes := MakeKeyframes(From, Remaining, Face)
            if (Keyframes.Length = 0):
                break
            K.SetKeyframes(Keyframes, oneshot_keyframed_movement_playback_mode{})
            set SegmentActive = true
            if (Playing?):
                K.Play()
            Done := race:
                block:
                    K.FinishedEvent.Await()
                    true
                block:
                    ReplanEvent.Await()
                    false
            set SegmentActive = false
            if (Done?):
                break
            set Remaining = DropPassedPoints(From, Remaining, Entity.GetGlobalTranslation())
        true

    # Physics: pass through the Path points one by one with MoveBySteps. false when it gave up midway
    MoveAlongBySteps<private>(Path:[]vector3, Face:logic)<suspends>:logic =
        var Index:int = 0
        var Reached:logic = true
        loop:
            if (not Reached?):
                break
            if (Point := Path[Index]):
                set Reached = MoveBySteps(Point, Face)
                set Index += 1
            else:
                break
        Reached

    MoveBySteps<private>(Destination:vector3, Face:logic)<suspends>:logic =
        var DetourLeft:float = 0.0
        var Detour:vector3 = vector3{}
        var Done:logic = false
        var Reached:logic = false
        loop:
            if (Done?):
                break
            AwaitPlaying()
            DeltaTime := TickEvents.PrePhysics.Await()
            if (Playing?):
                if (DetourLeft > 0.0):
                    set DetourLeft -= DeltaTime
                    if (Reflected := Entity.MoveStep(Detour, DeltaTime)?):
                        set Detour = Reflected
                else:
                    Step := StepTowardPoint(Entity.GetGlobalTranslation(), Destination, GetSpeedCmPerSecond(), DeltaTime)
                    if (Reflected := Entity.MoveStep(Step(0), DeltaTime)?):
                        if (BounceSeconds > 0.0):
                            set Detour = Reflected
                            set DetourLeft = BounceSeconds
                        else:
                            set Done = true
                    else:
                        if (Face?):
                            Entity.FaceToward(Step(0))
                        if (Step(1)?):
                            set Reached = true
                            set Done = true
        Reached

    # Keyframes for the legs from From through Points in order (legs under 1 cm are skipped). Each leg lasts the seconds needed at GetSpeedCmPerSecond. With Face, adds a rotation that aligns yaw to the leg direction
    # ⚠ Unverified: whether the keyframe Translation (additive) is added as seen from the parent without being rotated by the same keyframe's rotation (if it is rotated, the path drifts with Face)
    MakeKeyframes<private>(From:vector3, Points:[]vector3, Face:logic)<transacts>:[]keyframed_movement_delta =
        Speed := GetSpeedCmPerSecond()
        var Previous:vector3 = From
        var Yaw:float = Entity.GetYawRadians()
        var Keyframes:[]keyframed_movement_delta = array{}
        for (Point : Points):
            SegmentCm := Distance(Previous, Point)
            if (SegmentCm >= 1.0):
                var Turn:rotation = IdentityRotation()
                if (Face?, NewYaw := FindTravelYaw[Point - Previous]):
                    set Turn = MakeYawRotation(WrapRadians(NewYaw - Yaw))
                    set Yaw = NewYaw
                set Keyframes = Keyframes + array{MakeDelta(Previous, Point, SegmentCm / Speed, Turn)}
                set Previous = Point
        Keyframes

    MakeDelta<private>(From:vector3, To:vector3, Seconds:float, Turn:rotation)<transacts>:keyframed_movement_delta =
        keyframed_movement_delta:
            Transform := transform:
                Translation := ToParentSpace(From, To)
                Rotation := Turn
                Scale := vector3{}
            Duration := Max(Seconds, 0.01)
            Easing := linear_easing_function{}

    ToParentSpace<private>(From:vector3, To:vector3)<transacts>:vector3 =
        if (Parent := Entity.GetParent[]):
            Parent.ToLocalPosition(To) - Parent.ToLocalPosition(From)
        else:
            To - From

    FindOrAddKeyframed<private>():keyframed_movement_component =
        if (Found := Entity.GetComponent[keyframed_movement_component]):
            Found
        else:
            Added := keyframed_movement_component{Entity := Entity}
            Entity.AddComponents(array{Added})
            Added
