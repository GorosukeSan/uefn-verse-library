using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { CharacterSystem }
using { CharacterSystem.MoveKit }
using { CharacterSystem.TooltipKit }

# Role: cling to and crawl on walls and ceilings (the slime ability). With RequiresGrant, only while a modifier granting cling is on the body (character_modifier's GrantsCling. GrantCling of BuffKit's character_move_grant_component)
#   Attaching:
#     Wall: in the air or on the ground (AttachFromGround. After pushing for GroundAttachDelaySeconds), when walk's input direction points at a wall (non-walkable surface) within 60 degrees and a wall is within a short distance (about 10 cm) in that direction
#     Ceiling: on the frame the body hits a ceiling (downward-facing surface) in the air (the body's HitWall), when a ceiling is within a short distance straight up
#     At the moment of attaching, only the velocity along the surface is kept (cut to the crawl speed) and the body is pulled to SkinCm from the surface. No attaching during ReattachCooldownSeconds (after jumping, releasing or hopping onto a ledge)
#   While clinging (every frame):
#     PreMoveEvent: sets gravity to 0 (the body's ScaleGravityThisFrame(0)) and derives a velocity along the surface from the input (walk leaves the velocity alone = the body's IsMoveOverridden)
#       Wall: maps walk's input direction (GetInputDirection. With Space = View, relative to the view) onto the wall. Toward the wall = up, away from the wall = down, along the wall = sideways (left / right as seen facing the wall)
#         With TankTurn, walk's raw input (GetMoveInput): forward = up, back = down, left / right = left / right as seen facing the wall (the body does not turn). In SideView (side-scroller), pushing into the wall goes up, away goes down
#         Without input, slides down at WallSlideSpeedCmPerSecond (0 stops). On a tilted (overhanging) wall, up means up along the surface
#       Ceiling: crawls horizontally (along the surface) in walk's input direction. Stops without input
#       Speed is ClimbSpeedCmPerSecond / CeilingSpeedCmPerSecond x the speed multiplier of the modifiers stacked on the body. Approached with ClimbAccelerationCmPerSecondSquared
#     PostMoveEvent: sticks to the surface (probes a little toward the surface, pulls to SkinCm from it and refreshes the normal. Follows gently curved walls)
#       Inner corners (concave): if another clingable surface lies in the direction moved on the wall, switches to it (wall -> adjacent wall, climbing a wall onto the ceiling). Never ceiling -> wall (the same input would switch back and forth. Heading into a wall on a ceiling just stops)
#       Outer corners (convex): with FollowOuterCorners, crawling sideways on a wall past where the surface ends wraps around the corner onto the adjacent wall (off: see "no surface" below)
#       Top ledge: climbing a wall (moving more up than sideways) and the surface ends (or the ledge corner = a walkable surface is touched): a small hop onto the ledge (LedgeHopUp / LedgeHopForward. Releases)
#       No surface: releases after ContactGraceSeconds (bottom edge of a wall, edge of a ceiling, a window. Falls)
#   Releasing: jump (jump checks this cling first. On a wall, jumps away from the wall x WallJumpAwaySpeedCmPerSecond with upward WallJumpUpSpeedCmPerSecond; on a ceiling, drops at CeilingDropSpeedCmPerSecond),
#     no surface (above), grant removed (effect ended), the body's LockInput, holding input away from the wall for AwayDetachSeconds, landing on the ground on a wall with no climb input, touching the ground on a ceiling, Release
#   Interplay with other components: walk leaves the velocity alone and on a wall does not turn the body even with TankTurn. jump jumps off the cling first, and air jumps are restored while clinging. dash does not dash while clinging and ends a dash in progress on attaching.
#     face (BodyKit's character_face_movement_component) faces the wall on a wall and uses its usual rule on a ceiling (airborne, so Turn faces the input direction). The body does not probe for ground while rising. Not carried by moving walls / floors (ride)
# Placement: in the editor, attach to the same entity as character_motor_component (walk is required too. With jump, you can jump off)
# Notifications: ClingStart (attached) / ClingEnd (released) on the body's ActionEvent. When jumping off a wall, jump also reports Jumped
# From outside: IsClinging / GetClingSurface / GetClingNormal (the body has the same), IsAllowed, Release
# Requirements / notes: while clinging, velocity added by other components (knockback, launch) is overwritten by the crawl velocity on the next frame (Release first to knock the body away)
# ⚠ Unverified: the sweep hits when wrapping around corners, hopping onto ledges and switching to the ceiling (UEFN 43.00 in the editor)
character_cling_component<public> := class<final_super>(component):

    # When on, clings only while a modifier granting cling (GrantsCling) is on the body (a pickup ability). When off, always. Default on
    @editable:
        ToolTip := ClingRequiresGrantToolTip
        Categories := array{CharacterClingCategory}
    RequiresGrant<public>:logic = true
    # Whether to cling to walls. Default on
    @editable:
        ToolTip := ClingWallToolTip
        Categories := array{CharacterClingCategory}
    WallCling<public>:logic = true
    # Whether to cling to ceilings. Default on
    @editable:
        ToolTip := ClingCeilingToolTip
        Categories := array{CharacterClingCategory}
    CeilingCling<public>:logic = true
    # Whether pushing into a wall while standing on the ground attaches (off: in the air only). Default on
    @editable:
        ToolTip := ClingAttachFromGroundToolTip
        Categories := array{CharacterClingCategory}
    AttachFromGround<public>:logic = true
    # Time to keep pushing into a wall before attaching from the ground (seconds). 0 attaches at once. Default 0.15
    @editable_number(float):
        ToolTip := ClingGroundAttachDelayToolTip
        Categories := array{CharacterClingCategory}
        MinValue := option{0.0}
        MaxValue := option{5.0}
    GroundAttachDelaySeconds<public>:float = 0.15
    # Crawl speed on walls (cm/s). Default 400
    @editable_number(float):
        ToolTip := ClingClimbSpeedToolTip
        Categories := array{CharacterClingCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    ClimbSpeedCmPerSecond<public>:float = 400.0
    # Crawl speed on ceilings (cm/s). Default 350
    @editable_number(float):
        ToolTip := ClingCeilingSpeedToolTip
        Categories := array{CharacterClingCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    CeilingSpeedCmPerSecond<public>:float = 350.0
    # Acceleration toward the crawl speed (cm/s^2). 0 reaches it at once. Default 4000
    @editable_number(float):
        ToolTip := ClingAccelerationToolTip
        Categories := array{CharacterClingCategory}
        MinValue := option{0.0}
        MaxValue := option{100000.0}
    ClimbAccelerationCmPerSecondSquared<public>:float = 4000.0
    # Slide-down speed on a wall without input (cm/s). 0 stops. Default 50
    @editable_number(float):
        ToolTip := ClingWallSlideToolTip
        Categories := array{CharacterClingCategory}
        MinValue := option{0.0}
        MaxValue := option{5000.0}
    WallSlideSpeedCmPerSecond<public>:float = 50.0
    # Speed away from the wall when jumping off a wall (cm/s). Default 600
    @editable_number(float):
        ToolTip := ClingWallJumpAwayToolTip
        Categories := array{CharacterClingCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    WallJumpAwaySpeedCmPerSecond<public>:float = 600.0
    # Upward speed when jumping off a wall (cm/s. The modifiers' jump multiplier also applies). Default 850
    @editable_number(float):
        ToolTip := ClingWallJumpUpToolTip
        Categories := array{CharacterClingCategory}
        MinValue := option{0.0}
        MaxValue := option{20000.0}
    WallJumpUpSpeedCmPerSecond<public>:float = 850.0
    # Downward speed when pressing jump on a ceiling to let go (cm/s). 0 falls by gravity alone. Default 0
    @editable_number(float):
        ToolTip := ClingCeilingDropToolTip
        Categories := array{CharacterClingCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    CeilingDropSpeedCmPerSecond<public>:float = 0.0
    # Upward speed of the small hop on reaching the top ledge of a wall (cm/s). Default 500
    @editable_number(float):
        ToolTip := ClingLedgeHopUpToolTip
        Categories := array{CharacterClingCategory}
        MinValue := option{0.0}
        MaxValue := option{5000.0}
    LedgeHopUpSpeedCmPerSecond<public>:float = 500.0
    # Speed toward the top of the ledge of the small hop on reaching the top ledge of a wall (cm/s). Default 300
    @editable_number(float):
        ToolTip := ClingLedgeHopForwardToolTip
        Categories := array{CharacterClingCategory}
        MinValue := option{0.0}
        MaxValue := option{5000.0}
    LedgeHopForwardSpeedCmPerSecond<public>:float = 300.0
    # Time from losing the surface to releasing (seconds). Default 0.15
    @editable_number(float):
        ToolTip := ClingContactGraceToolTip
        Categories := array{CharacterClingCategory}
        MinValue := option{0.0}
        MaxValue := option{5.0}
    ContactGraceSeconds<public>:float = 0.15
    # Time holding input away from the wall before releasing (seconds). 0 never releases by input. Default 0.4
    @editable_number(float):
        ToolTip := ClingAwayDetachToolTip
        Categories := array{CharacterClingCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    AwayDetachSeconds<public>:float = 0.4
    # Time after jumping, releasing or hopping onto a ledge before attaching again (seconds). Default 0.25
    @editable_number(float):
        ToolTip := ClingReattachCooldownToolTip
        Categories := array{CharacterClingCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    ReattachCooldownSeconds<public>:float = 0.25
    # When on, wraps around outer (convex) corners onto the adjacent wall. When off, releases at the corner. Default on
    @editable:
        ToolTip := ClingFollowOuterCornersToolTip
        Categories := array{CharacterClingCategory}
    FollowOuterCorners<public>:logic = true

    # Probe distance for a surface to attach to (cm. Added to SkinCm, the distance kept from surfaces)
    AttachReachCm<private>:float = 8.0
    # Probe distance for sticking to the surface while clinging (cm. Added to SkinCm)
    ContactProbeCm<private>:float = 12.0
    # Probe distance for inner corners (cm. Added to SkinCm)
    CornerProbeCm<private>:float = 8.0
    # Input direction shorter than this does not count as pushing into a wall
    PushInputThreshold<private>:float = 0.3
    # Pushing into the wall when the dot product of input direction and wall normal is below minus this (-0.5 = heading in within 60 degrees)
    PushDot<private>:float = 0.5
    # Holding away from the wall when the wall's up input is below minus this (-0.7)
    AwayDot<private>:float = 0.7
    # Magnitude treated as no input
    NoInput<private>:float = 0.05
    # A surface whose normal's vertical component is at most this is a ceiling (non-walkable surfaces above it are walls)
    CeilingNormalUp<private>:float = -0.7
    # Normals whose dot product is at least this are the same surface (not an inner corner)
    SameSurfaceDot<private>:float = 0.98
    # Interval (seconds) between retries when walk is not found
    WalkSearchIntervalSeconds<private>:float = 1.0

    var<private> Motor:?character_motor_component = false
    var<private> Subscriptions:[]cancelable = array{}
    # Kind of surface clung to (false when not clinging) and its normal (outward unit vector)
    var<private> Surface:?character_cling_surface = false
    var<private> Normal:vector3 = vector3{}
    # Crawl velocity applied this frame (used in PostMove as the direction to probe for inner / outer corners) and the wall's up input (-1..1)
    var<private> Desired:vector3 = vector3{}
    var<private> ClimbInput:float = 0.0
    var<private> LostSeconds:float = 0.0
    var<private> AwaySeconds:float = 0.0
    var<private> PushSeconds:float = 0.0
    var<private> CooldownLeftSeconds:float = 0.0
    # The body hit a wall / ceiling (HitWall) during this frame's move
    var<private> HitThisFrame:logic = false
    var<private> CachedWalk:?character_walk_component = false
    var<private> NextWalkSearchAt:float = -1000.0

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := Entity.FindCharacterMotorAbove[]):
            set Motor = option{Found}
            set Subscriptions += array{Found.PreMoveEvent.Subscribe(OnPreMove), Found.PostMoveEvent.Subscribe(OnPostMove), Found.ActionEvent.Subscribe(OnAction)}
        else:
            Print("[character_cling_component] character_motor_component not found (place it on the same entity or an ancestor)")

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        if (Found := Motor?):
            Detach(Found, false)
        (super:)OnEndSimulation()

    # Succeeds while clinging to a wall or ceiling
    IsClinging<public>()<decides><transacts>:void =
        Surface?

    # Kind of surface clung to (Wall / Ceiling). Fails when not clinging
    GetClingSurface<public>()<decides><transacts>:character_cling_surface =
        Surface?

    # Normal of the surface clung to (outward unit vector). When not clinging, the last surface clung to (vector3{} if never)
    GetClingNormal<public>()<transacts>:vector3 =
        Normal

    # Succeeds if clinging is possible now (RequiresGrant is off, or a modifier granting cling is on the body)
    IsAllowed<public>()<decides><transacts>:void =
        Found := Motor?
        IsAllowedFor[Found]

    # Releases from code (does nothing if not clinging). No re-attaching during ReattachCooldownSeconds. Velocity unchanged (gravity returns and the body falls)
    Release<public>():void =
        if (Found := Motor?):
            Detach(Found, true)

    IsAllowedFor<private>(Found:character_motor_component)<decides><transacts>:void =
        not RequiresGrant? or Found.CanCling[]

    OnAction<private>(Action:character_action):void =
        if (Action = character_action.HitWall):
            set HitThisFrame = true

    # Before the move: if clinging, decides whether to release; if not releasing, sets gravity to 0 and derives the velocity along the surface
    OnPreMove<private>(DeltaTime:float):void =
        set HitThisFrame = false
        if (CooldownLeftSeconds > 0.0):
            set CooldownLeftSeconds -= DeltaTime
        if (Found := Motor?, Current := Surface?):
            if (Found.TakeClingRelease()?):
                # jump jumped (wall) or dropped (ceiling). jump set the velocity
                Detach(Found, true)
            else if (not IsAllowedFor[Found] or Found.IsInputLocked[]):
                # Grant removed (effect ended) or input locked: velocity unchanged, gravity returns and the body falls
                Detach(Found, false)
            else:
                case (Current):
                    character_cling_surface.Wall => SteerWall(Found, DeltaTime)
                    character_cling_surface.Ceiling => SteerCeiling(Found, DeltaTime)

    # After the move: if clinging, sticks to the surface (decides corners, ledges, no surface). If not, decides whether to attach
    OnPostMove<private>(DeltaTime:float):void =
        if (Found := Motor?):
            if (Current := Surface?):
                if (Found.TakeClingRelease()?):
                    Detach(Found, true)
                else:
                    FollowSurface(Found, Current, DeltaTime)
            else:
                TryAttach(Found, DeltaTime)
        set HitThisFrame = false

    # Wall: velocity from the input mapped onto the wall. Releases on landing with no climb input, or when holding input away from the wall
    SteerWall<private>(Found:character_motor_component, DeltaTime:float):void =
        Axes := WallAxes(Normal)
        UpAxis := Axes(1)
        LeftAxis := Axes(2)
        Amounts := WallInput(Found, Axes(0), LeftAxis)
        Climb := Amounts(0)
        Side := Amounts(1)
        set ClimbInput = Climb
        # Standing on the ground at the foot of the wall: release without climb input (so you can walk along the wall)
        if (Found.IsGrounded[], Climb <= NoInput):
            Detach(Found, false)
            return
        # Holding input away from the wall releases (a short push just crawls down)
        if (AwayDetachSeconds > 0.0 and Climb < -AwayDot):
            set AwaySeconds += DeltaTime
            if (AwaySeconds >= AwayDetachSeconds):
                Detach(Found, true)
                return
        else:
            set AwaySeconds = 0.0
        Speed := ClimbSpeedCmPerSecond * Found.GetSpeedMultiplier()
        Input := UpAxis * Climb + LeftAxis * Side
        InputCm := Input.Length()
        Target := if (InputCm > NoInput) then Input * (Speed / Max(InputCm, 1.0)) else UpAxis * (-WallSlideSpeedCmPerSecond)
        SteerToward(Found, Target, DeltaTime)
        Publish(Found)

    # Ceiling: velocity from walk's input direction along the ceiling (stops without input). Releases on touching the ground
    SteerCeiling<private>(Found:character_motor_component, DeltaTime:float):void =
        set ClimbInput = 0.0
        set AwaySeconds = 0.0
        if (Found.IsGrounded[]):
            Detach(Found, false)
            return
        Dir := if (Walk := FindWalk(Found)?) then Walk.GetInputDirection() else vector3{}
        DirCm := Dir.Length()
        Flat := Dir - Normal * DotProduct(Dir, Normal)
        FlatCm := Flat.Length()
        Speed := CeilingSpeedCmPerSecond * Found.GetSpeedMultiplier()
        Target := if (DirCm > NoInput and FlatCm > 0.001) then Flat * (Speed * Min(DirCm, 1.0) / FlatCm) else vector3{}
        SteerToward(Found, Target, DeltaTime)
        Publish(Found)

    # Approaches Target from the current velocity along the surface at ClimbAccelerationCmPerSecondSquared, sets it as the body's velocity and zeroes this frame's gravity (velocity toward / away from the surface is removed)
    SteerToward<private>(Found:character_motor_component, Target:vector3, DeltaTime:float):void =
        Velocity := Found.GetVelocity()
        Along := Velocity - Normal * DotProduct(Velocity, Normal)
        Next := if (ClimbAccelerationCmPerSecondSquared <= 0.0) then Target else ClingStepToward(Along, Target, ClimbAccelerationCmPerSecondSquared * DeltaTime)
        set Desired = Next
        Found.SetVelocity(Next)
        Found.ScaleGravityThisFrame(0.0)

    # Input on a wall (up, side). Up = the part toward the wall (negative is down), side = left as seen facing the wall
    #   TankTurn: walk's raw input (forward = up, left = left). Otherwise: walk's input direction (world horizontal) split into the toward-wall direction Into and the along-wall left LeftAxis
    WallInput<private>(Found:character_motor_component, Into:vector3, LeftAxis:vector3)<transacts>:tuple(float, float) =
        if (Walk := FindWalk(Found)?):
            if (SideInputTurnsBody(Walk.GetSideStyle())?):
                Local := Walk.GetMoveInput()
                return (Local.Forward, Local.Left)
            Dir := Walk.GetInputDirection()
            return (DotProduct(Dir, Into), DotProduct(Dir, LeftAxis))
        (0.0, 0.0)

    # Gives the body the current cling state and the velocity jump uses
    Publish<private>(Found:character_motor_component):void =
        if (Current := Surface?):
            Found.SetClingState(option{Current}, Normal, ClingJumpVelocity(Found, Current))

    # Velocity jump uses: on a wall, away from the wall x WallJumpAwaySpeedCmPerSecond + up x WallJumpUpSpeedCmPerSecond (x the modifiers' jump multiplier) + the current sideways velocity along the wall. On a ceiling, the current velocity along the ceiling + down x CeilingDropSpeedCmPerSecond
    ClingJumpVelocity<private>(Found:character_motor_component, Current:character_cling_surface)<transacts>:vector3 =
        Velocity := Found.GetVelocity()
        case (Current):
            character_cling_surface.Wall =>
                Axes := WallAxes(Normal)
                Axes(0) * (-WallJumpAwaySpeedCmPerSecond) + vector3{Up := WallJumpUpSpeedCmPerSecond * Found.GetJumpMultiplier()} + Axes(2) * DotProduct(Velocity, Axes(2))
            character_cling_surface.Ceiling =>
                Velocity - Normal * DotProduct(Velocity, Normal) + vector3{Up := -CeilingDropSpeedCmPerSecond}

    # After the move while clinging: checks inner corner -> stick to surface -> top ledge -> outer corner -> no surface, in that order
    FollowSurface<private>(Found:character_motor_component, Current:character_cling_surface, DeltaTime:float):void =
        Feet := Found.Entity.GetGlobalTransform().Translation
        Skin := Found.GetSkinCm()
        # Inner corner: if another clingable surface lies in the direction we tried to move, switch to it (wall -> adjacent wall, climbing a wall onto the ceiling)
        #   Never ceiling -> wall (after moving from wall to ceiling the same input still points at the wall, so it would switch back and forth. Heading into a wall on a ceiling stops at the wall)
        DesiredCm := Desired.Length()
        if (DesiredCm > 1.0, Current = character_cling_surface.Wall):
            MoveDir := Desired / DesiredCm
            if (Hit := Found.ProbeSurfaceFrom[Feet, MoveDir * (Skin + CornerProbeCm)], Kind := Classify[Found, Hit.ContactNormal], DotProduct(Hit.ContactNormal, Normal) < SameSurfaceDot, DotProduct(MoveDir, Hit.ContactNormal) < -0.3):
                Found.SnapToHit(Hit, MoveDir)
                SwitchTo(Found, Kind, Hit.ContactNormal)
                return
        # Stick to the surface: probe toward the surface; if it is the same kind, pull to SkinCm from it and refresh the normal (follows gently curved surfaces)
        Climbing := IsClimbingUp()
        Toward := Normal * (-1.0)
        if (Hit := Found.ProbeSurfaceFrom[Feet, Toward * (Skin + ContactProbeCm)]):
            HitNormal := Hit.ContactNormal
            if (Kind := Classify[Found, HitNormal], Kind = Current):
                Found.SnapToHit(Hit, Toward)
                SwitchTo(Found, Kind, HitNormal)
                return
            if (Current = character_cling_surface.Wall, Climbing?, Found.IsWalkableNormal[HitNormal]):
                # Climbing and touched the top ledge corner (a surface at a walkable angle)
                LedgeHop(Found)
                return
            # Touching a non-clingable surface or a surface of another kind (a floor corner, etc.): counts as contact (no pull, normal unchanged)
            set LostSeconds = 0.0
            return
        # No surface: if climbing (moving more up than sideways), we reached the top ledge
        if (Current = character_cling_surface.Wall, Climbing?):
            LedgeHop(Found)
            return
        Wrapped := if (Current = character_cling_surface.Wall, FollowOuterCorners?) then TryWrapOuterCorner(Found) else false
        if (Wrapped?):
            return
        set LostSeconds += DeltaTime
        if (LostSeconds > ContactGraceSeconds):
            # Bottom edge of a wall, edge of a ceiling, a window: release and fall
            Detach(Found, false)

    # true if climbing the wall (the up component along the surface of this frame's crawl velocity is faster than 1 cm/s and at least the sideways component)
    IsClimbingUp<private>()<transacts>:logic =
        Axes := WallAxes(Normal)
        UpSpeed := DotProduct(Desired, Axes(1))
        SideSpeed := DotProduct(Desired, Axes(2))
        if (ClimbInput > NoInput, UpSpeed > 1.0, UpSpeed >= Abs(SideSpeed)) then true else false

    # Outer corner: when crawling sideways on a wall and the surface ends, moves around to the side the wall was on, probes opposite to the direction of travel and switches to the adjacent wall if there is one (true). Does nothing (false) if the space around the corner is blocked or there is no adjacent wall
    TryWrapOuterCorner<private>(Found:character_motor_component):logic =
        Axes := WallAxes(Normal)
        Into := Axes(0)
        LeftAxis := Axes(2)
        SideSpeed := DotProduct(Desired, LeftAxis)
        if (SideSpeed > -1.0 and SideSpeed < 1.0):
            return false
        # Direction of sideways travel
        Ahead := if (SideSpeed > 0.0) then LeftAxis else LeftAxis * (-1.0)
        Feet := Found.Entity.GetGlobalTransform().Translation
        Skin := Found.GetSkinCm()
        Reach := Found.RadiusCm + Skin * 2.0
        # Can we move to the side the wall was on (beyond the corner)?
        if (not Found.IsSweepClear[Feet, Into * Reach]):
            return false
        Corner := Feet + Into * Reach
        Back := Ahead * (-1.0)
        if (Hit := Found.ProbeSurfaceFrom[Corner, Back * (Reach + Skin + ContactProbeCm)], Kind := Classify[Found, Hit.ContactNormal], Kind = character_cling_surface.Wall, DotProduct(Hit.ContactNormal, Ahead) > 0.5):
            Found.MoveBodyBy(Into * Reach)
            Found.SnapToHit(Hit, Back)
            SwitchTo(Found, Kind, Hit.ContactNormal)
            return true
        false

    # Reached the top ledge: a small hop onto the ledge and release (toward the wall x LedgeHopForwardSpeedCmPerSecond + up x LedgeHopUpSpeedCmPerSecond)
    LedgeHop<private>(Found:character_motor_component):void =
        Into := WallAxes(Normal)(0)
        Found.SetVelocity(Into * LedgeHopForwardSpeedCmPerSecond + vector3{Up := LedgeHopUpSpeedCmPerSecond})
        Detach(Found, true)

    # Sets the surface clung to to Kind / NewNormal (same surface: only refreshes the normal). A surface was found, so the no-surface time resets to 0
    SwitchTo<private>(Found:character_motor_component, Kind:character_cling_surface, NewNormal:vector3):void =
        set Normal = NewNormal
        set Surface = option{Kind}
        set LostSeconds = 0.0
        Publish(Found)

    # When not clinging: decides whether to attach, ceiling first (hit this frame with a ceiling straight above), then wall (a wall in the input direction)
    TryAttach<private>(Found:character_motor_component, DeltaTime:float):void =
        if (CooldownLeftSeconds > 0.0 or not IsAllowedFor[Found] or Found.IsInputLocked[]):
            set PushSeconds = 0.0
            return
        Feet := Found.Entity.GetGlobalTransform().Translation
        Skin := Found.GetSkinCm()
        UpDir := vector3{Up := 1.0}
        if (CeilingCling?, HitThisFrame?, not Found.IsGrounded[], Hit := Found.ProbeSurfaceFrom[Feet, UpDir * (Skin + AttachReachCm)], Kind := Classify[Found, Hit.ContactNormal], Kind = character_cling_surface.Ceiling):
            Attach(Found, Hit, UpDir, Kind)
            return
        if (WallCling?, Walk := FindWalk(Found)?):
            Dir := Walk.GetInputDirection()
            DirCm := Dir.Length()
            if (DirCm > PushInputThreshold):
                Ahead := Dir / DirCm
                if (Hit := Found.ProbeSurfaceFrom[Feet, Ahead * (Skin + AttachReachCm)], Kind := Classify[Found, Hit.ContactNormal], Kind = character_cling_surface.Wall, DotProduct(Ahead, Hit.ContactNormal) < -PushDot):
                    if (Found.IsGrounded[]):
                        if (not AttachFromGround?):
                            set PushSeconds = 0.0
                            return
                        # From the ground, only after pushing into the wall for GroundAttachDelaySeconds (do not start climbing after merely grazing a wall)
                        set PushSeconds += DeltaTime
                        if (PushSeconds < GroundAttachDelaySeconds):
                            return
                    Attach(Found, Hit, Ahead, Kind)
                    return
        set PushSeconds = 0.0

    # Attaches to the surface of Hit found by probing along Direction: pulls to SkinCm from the surface, keeps only the velocity along it cut to the crawl speed, and reports ClingStart
    Attach<private>(Found:character_motor_component, Hit:sweep_hit, Direction:vector3, Kind:character_cling_surface):void =
        Found.SnapToHit(Hit, Direction)
        set Normal = Hit.ContactNormal
        set Surface = option{Kind}
        set LostSeconds = 0.0
        set AwaySeconds = 0.0
        set PushSeconds = 0.0
        set ClimbInput = 0.0
        BaseSpeed := case (Kind):
            character_cling_surface.Wall => ClimbSpeedCmPerSecond
            character_cling_surface.Ceiling => CeilingSpeedCmPerSecond
        Speed := BaseSpeed * Found.GetSpeedMultiplier()
        Velocity := Found.GetVelocity()
        Along := Velocity - Normal * DotProduct(Velocity, Normal)
        AlongCm := Along.Length()
        Kept := if (AlongCm > Speed and AlongCm > 0.001) then Along * (Speed / AlongCm) else Along
        Found.SetVelocity(Kept)
        set Desired = Kept
        Publish(Found)
        Found.ReportAction(character_action.ClingStart)

    # Releases (does nothing if not clinging). With Cooldown, no re-attaching during ReattachCooldownSeconds. Velocity unchanged. Reports ClingEnd
    Detach<private>(Found:character_motor_component, Cooldown:logic):void =
        if (not Surface?):
            return
        set Surface = false
        set LostSeconds = 0.0
        set AwaySeconds = 0.0
        set PushSeconds = 0.0
        set ClimbInput = 0.0
        set Desired = vector3{}
        set CooldownLeftSeconds = if (Cooldown?) then ReattachCooldownSeconds else 0.0
        Found.SetClingState(false, Normal, vector3{})
        Found.ReportAction(character_action.ClingEnd)

    # If Normal is a clingable surface, its kind (fails for walkable surfaces and disabled kinds). Ceiling if the normal's vertical component is at most CeilingNormalUp, other non-walkable surfaces are walls
    Classify<private>(Found:character_motor_component, SurfaceNormal:vector3)<decides><transacts>:character_cling_surface =
        not Found.IsWalkableNormal[SurfaceNormal]
        Kind := if (SurfaceNormal.Up <= CeilingNormalUp) then character_cling_surface.Ceiling else character_cling_surface.Wall
        IsEnabled[Kind]
        Kind

    # Succeeds if clinging to Kind is enabled (WallCling / CeilingCling)
    IsEnabled<private>(Kind:character_cling_surface)<decides><transacts>:void =
        case (Kind):
            character_cling_surface.Wall => WallCling?
            character_cling_surface.Ceiling => CeilingCling?

    # The body's walk (FindCharacterWalk). Remembered once found; while missing, retried every WalkSearchIntervalSeconds
    FindWalk<private>(Found:character_motor_component)<transacts>:?character_walk_component =
        if (Cached := CachedWalk?, Cached.IsInScene[]):
            return option{Cached}
        set CachedWalk = false
        Now := GetSimulationElapsedTime()
        if (Now < NextWalkSearchAt):
            return false
        set NextWalkSearchAt = Now + WalkSearchIntervalSeconds
        if (Walk := Found.FindCharacterWalk[]):
            set CachedWalk = option{Walk}
        CachedWalk

# From the wall normal WallNormal: unit vectors (horizontal direction into the wall, up along the surface, left as seen facing the wall (horizontal))
#   Left follows the same rule as walk's walking direction (left = CrossProduct(up, forward)). If the normal is nearly straight up or down, forward is taken as the into-wall direction
WallAxes<internal>(WallNormal:vector3)<transacts>:tuple(vector3, vector3, vector3) =
    Flat := vector3{Forward := WallNormal.Forward, Left := WallNormal.Left}
    FlatCm := Flat.Length()
    Into := if (FlatCm > 0.001) then Flat * (-1.0 / FlatCm) else vector3{Forward := 1.0}
    UpRaw := vector3{Up := 1.0} - WallNormal * WallNormal.Up
    UpCm := UpRaw.Length()
    UpAxis := if (UpCm > 0.001) then UpRaw / UpCm else vector3{Up := 1.0}
    (Into, UpAxis, CrossProduct(vector3{Up := 1.0}, Into))

# Vector moved from Current toward Target by at most MaxStep in length
ClingStepToward<internal>(Current:vector3, Target:vector3, MaxStep:float)<transacts>:vector3 =
    Gap := Target - Current
    GapCm := Gap.Length()
    if (GapCm <= MaxStep or GapCm <= 0.0001) then Target else Current + Gap * (MaxStep / GapCm)
