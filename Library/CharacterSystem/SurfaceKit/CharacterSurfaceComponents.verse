using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { /Verse.org/SpatialMath }
using { SceneGraphSystem }
using { CharacterSystem }
using { CharacterSystem.TooltipKit }

# How a custom character touches a surface (character_surface_component)
character_surface_contact<public> := enum:
    # Started touching (the body's box and the surface's box overlap, including the TouchMarginCm margin)
    Touched
    # Stopped touching (no longer overlapping, the surface was deactivated, or it left the search range)
    Untouched
    # Stepped on (grounded, with the feet on the top face of the surface)
    SteppedOn
    # Stepped off
    SteppedOff

# The surface's box (a world-axis-aligned cuboid, cm). A rotated surface becomes the cuboid enclosing its rotated box
character_surface_box<public> := struct<computes>:
    # Corner on the low side (world position, cm)
    MinCm<public>:vector3 = vector3{}
    # Corner on the high side (world position, cm)
    MaxCm<public>:vector3 = vector3{}

# Notification of touching / stepping on a surface. Direction: from the surface entity to the root (SendUp)
# Sender: character_touch_component (the same notification also goes to the Surface's ContactEvent). Receivers: the surface entity and ancestor components (map root, gimmicks). Not consumed
character_surface_contact_event<public> := class(scene_event):
    # The surface touched (attached to the entity that sent the notification)
    Surface<public>:character_surface_component
    # The body of the custom character that touched it
    Motor<public>:character_motor_component
    # The body's owner. false for a body without an owner
    Agent<public>:?agent
    # How it was touched
    Contact<public>:character_surface_contact

# Marker tag for surfaces a custom character can touch. character_surface_component attaches it to the entity at start and removes it when stopped (character_touch_component finds surfaces by this tag)
character_surface_tag<public> := class(tag):

# Role: a surface (box) that a custom character (CharacterSystem) can "touch" or "step on". The box is derived from the entity's position, rotation and scale
#   A custom character moves with its own capsule, so mesh overlap notifications (EntityEnteredEvent) never arrive. This component holds the box, and character_touch_component on the character compares the box with the body every frame
#   Box size: SizeCm if all its components are above 0 (the entity's scale is ignored). Otherwise the entity's scale (Scale) x MeshSizeCm (100 for a 100 cm cube mesh). With PivotAtBottom, the entity's position is the center of the box's bottom face; off, the center of the box
# Placement: in the editor, attach to the entity of a platform, wall or gimmick (the same entity as the collidable mesh). Touch-only objects (a goal crystal, etc.) may use a mesh without collision
# When: from start until stopped. Not touchable during SetActive(false) (vanishing platforms, etc.)
# Notifications: ContactEvent (started touching, stopped touching, stepped on, stepped off) and character_surface_contact_event (SendUp). Sent by character_touch_component
# Tags: attaches character_surface_tag to this entity
# From outside: GetBox / SetActive / IsActive
# Requirements / notes: moving surfaces (MoverSystem) are also compared at their position every frame. ⚠ Unverified: whether GetGlobalTransform of an entity driven by keyframed_movement_component returns the moved position every frame
character_surface_component<public> := class<final_super>(component):

    # Box size (cm. Forward / back, left / right, up / down). Used if all components are above 0 (the entity's scale is ignored). Default 0 (entity scale x MeshSizeCm)
    @editable:
        ToolTip := SurfaceSizeToolTip
        Categories := array{CharacterSurfaceCategory}
    SizeCm<public>:vector3 = vector3{}
    # Edge length of the mesh at scale 1 (cm). Multiplied by the entity's scale when SizeCm is not used. Default 100
    @editable_number(float):
        ToolTip := SurfaceMeshSizeToolTip
        Categories := array{CharacterSurfaceCategory}
        MinValue := option{1.0}
        MaxValue := option{100000.0}
    MeshSizeCm<public>:float = 100.0
    # When on, the entity's position is the center of the box's bottom face (a mesh with its origin at the bottom). When off, the center of the box. Default on
    @editable:
        ToolTip := SurfacePivotAtBottomToolTip
        Categories := array{CharacterSurfaceCategory}
    PivotAtBottom<public>:logic = true

    ContactEventInternal<private><final>:event(tuple(character_motor_component, character_surface_contact)) = event(tuple(character_motor_component, character_surface_contact)){}

    # Arrives as (that body, contact kind) when a custom character starts touching, stops touching, steps on or steps off (Await / Subscribe. Cannot be Signaled from outside)
    ContactEvent<public><final>:listenable(tuple(character_motor_component, character_surface_contact)) = MakeProxyListenable(ContactEventInternal)

    var<private> Active:logic = true
    var<private> TagKey:?tag_key = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set TagKey = option{Entity.AddTag(character_surface_tag{})}

    OnEndSimulation<override>():void =
        if (Key := TagKey?, Entity.RemoveTag[Key]) {}
        set TagKey = false
        (super:)OnEndSimulation()

    # The current box (world position, cm). Computed from the entity's position every call
    GetBox<public>()<transacts>:character_surface_box =
        Transform := Entity.GetGlobalTransform()
        Size := GetLocalSizeCm(Transform.Scale)
        Half := Size / 2.0
        Rotation := Transform.Rotation
        AxisForward := Rotation.GetForwardAxis()
        AxisLeft := Rotation.GetLeftAxis()
        AxisUp := Rotation.GetUpAxis()
        Center := if (PivotAtBottom?) then Transform.Translation + AxisUp * Half.Up else Transform.Translation
        Extent := vector3:
            Forward := Abs(AxisForward.Forward) * Half.Forward + Abs(AxisLeft.Forward) * Half.Left + Abs(AxisUp.Forward) * Half.Up
            Left := Abs(AxisForward.Left) * Half.Forward + Abs(AxisLeft.Left) * Half.Left + Abs(AxisUp.Left) * Half.Up
            Up := Abs(AxisForward.Up) * Half.Forward + Abs(AxisLeft.Up) * Half.Left + Abs(AxisUp.Up) * Half.Up
        character_surface_box{MinCm := Center - Extent, MaxCm := Center + Extent}

    # Toggles whether it can be touched (while false, touching bodies receive "stopped touching" and nothing can step on it). Collision and visuals are unchanged
    SetActive<public>(Value:logic):void =
        set Active = Value

    # Succeeds if touchable (not SetActive(false))
    IsActive<public>()<decides><transacts>:void =
        Active?

    # Called from character_touch_component: reports the contact on ContactEvent and character_surface_contact_event (SendUp)
    NotifyContact<internal>(Motor:character_motor_component, Contact:character_surface_contact):void =
        ContactEventInternal.Signal((Motor, Contact))
        Owner:?agent = if (Player := Motor.FindOwner[]) then option{Player} else false
        Entity.SendUp(character_surface_contact_event{Surface := Self, Motor := Motor, Agent := Owner, Contact := Contact})

    GetLocalSizeCm<private>(Scale:vector3)<transacts>:vector3 =
        if (SizeCm.Forward > 0.0, SizeCm.Left > 0.0, SizeCm.Up > 0.0):
            SizeCm
        else:
            vector3{Forward := Abs(Scale.Forward) * MeshSizeCm, Left := Abs(Scale.Left) * MeshSizeCm, Up := Abs(Scale.Up) * MeshSizeCm}

# Role: decides every frame whether the custom character touches / steps on surfaces (character_surface_component) and reports it
#   After the body (character_motor_component on the same entity) moves (PostMoveEvent), compares the body's box (a box with its bottom at the feet, diameter RadiusCm x 2, height HeightCm, plus the TouchMarginCm margin) with the boxes of nearby surfaces
#   The surface stood on: if the entity the body stands on by the ground sweep (the body's GetGroundEntity) carries an active surface, that surface (counts as stood on even if the box size / origin settings are off. Also counted as touching)
#     Otherwise decided by boxes: grounded, the feet within StandToleranceCm of the surface's top face, and the feet over the surface (may overhang sideways up to RadiusCm). If several match, the one nearest the feet (the higher one on a tie)
#   Candidate surfaces are refreshed every RefreshSeconds (descendants of SearchRoot, or the world by character_surface_tag if none, keeping only boxes within SearchRadiusCm of the feet. The world is not searched every frame)
# Placement: in the editor, attach to the same entity as character_motor_component
# Same entity: character_motor_component (required). character_ride_component for riding moving surfaces works without this component
# When: from start until stopped. When stopping, reports "stopped touching" and "stepped off" to the surfaces being touched
# Notifications: ContactEvent (surface touched, contact kind). The same notification also reaches the surface's ContactEvent and character_surface_contact_event (SendUp). Order: stepped off -> stopped touching -> started touching -> stepped on
# From outside: SetSearchRoot (narrow the search, e.g. the root of the map being played), GetTouchingSurfaces, IsTouching, FindStandingSurface
# Requirements / notes: compares world-axis-aligned boxes (a rotated surface becomes its enclosing box). Moving so fast that a surface is passed within one frame does not touch it (make thin surfaces thicker)
character_touch_component<public> := class<final_super>(component):

    # Margin added to the body's box (cm). The body stops 2 cm short of surfaces, so make it larger than that. Default 8
    @editable_number(float):
        ToolTip := TouchMarginToolTip
        Categories := array{CharacterSurfaceCategory}
        MinValue := option{0.0}
        MaxValue := option{500.0}
    TouchMarginCm<public>:float = 8.0
    # "Standing on" when the feet are within this distance (cm) of the surface's top face. Default 15
    @editable_number(float):
        ToolTip := TouchStandToleranceToolTip
        Categories := array{CharacterSurfaceCategory}
        MinValue := option{1.0}
        MaxValue := option{200.0}
    StandToleranceCm<public>:float = 15.0
    # Only surfaces within this distance (cm) of the feet are candidates. Default 3000
    @editable_number(float):
        ToolTip := TouchSearchRadiusToolTip
        Categories := array{CharacterSurfaceCategory}
        MinValue := option{100.0}
        MaxValue := option{100000.0}
    SearchRadiusCm<public>:float = 3000.0
    # Interval for refreshing the candidate surfaces (seconds). Default 0.5
    @editable_number(float):
        ToolTip := TouchRefreshToolTip
        Categories := array{CharacterSurfaceCategory}
        MinValue := option{0.05}
        MaxValue := option{10.0}
    RefreshSeconds<public>:float = 0.5

    ContactEventInternal<private><final>:event(tuple(character_surface_component, character_surface_contact)) = event(tuple(character_surface_component, character_surface_contact)){}

    # Arrives as (that surface, contact kind) when starting to touch, stopping, stepping on or stepping off a surface (Await / Subscribe. Cannot be Signaled from outside)
    ContactEvent<public><final>:listenable(tuple(character_surface_component, character_surface_contact)) = MakeProxyListenable(ContactEventInternal)

    var<private> Motor:?character_motor_component = false
    var<private> Subscription:?cancelable = false
    var<private> SearchRoot:?entity = false
    var<private> Candidates:[]character_surface_component = array{}
    var<private> Touching:[]character_surface_component = array{}
    var<private> Standing:?character_surface_component = false
    var<private> NextRefreshSeconds:float = 0.0

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := Entity.FindCharacterMotorAbove[]):
            set Motor = option{Found}
            set Subscription = option{Found.PostMoveEvent.Subscribe(OnPostMove)}
        else:
            Print("[character_touch_component] character_motor_component not found (place it on the same entity)")

    OnEndSimulation<override>():void =
        Subscription.CancelIfSet()
        set Subscription = false
        if (Found := Motor?):
            Update(Found, array{}, false)
        set Candidates = array{}
        set Motor = false
        (super:)OnEndSimulation()

    # Narrows the surface search to descendants of Root (false means the whole world). Re-searches on the next frame
    SetSearchRoot<public>(Root:?entity):void =
        set SearchRoot = Root
        set NextRefreshSeconds = 0.0

    # Surfaces currently touched (unordered)
    GetTouchingSurfaces<public>()<transacts>:[]character_surface_component =
        Touching

    # Succeeds if Surface is currently touched (up to one frame late)
    IsTouching<public>(Surface:character_surface_component)<decides><transacts>:void =
        Touching.Find[Surface]

    # The surface currently stood on. Fails if none (up to one frame late)
    FindStandingSurface<public>()<decides><transacts>:character_surface_component =
        Standing?

    OnPostMove<private>(DeltaTime:float):void =
        if (Found := Motor?):
            Now := GetSimulationElapsedTime()
            if (Now >= NextRefreshSeconds):
                set NextRefreshSeconds = Now + RefreshSeconds
                RefreshCandidates(Found)
            Feet := Found.Entity.GetGlobalTranslation()
            Reach := Found.RadiusCm + TouchMarginCm
            BodyMin := Feet - vector3{Forward := Reach, Left := Reach, Up := TouchMarginCm}
            BodyMax := Feet + vector3{Forward := Reach, Left := Reach, Up := Found.HeightCm + TouchMarginCm}
            Grounded := if (Found.IsGrounded[]) then true else false
            # If the entity stood on carries a surface, that is the surface stood on (not decided by boxes)
            GroundSurface:?character_surface_component = if (Ground := Found.GetGroundEntity[], OnGround := Ground.GetComponent[character_surface_component], OnGround.IsActive[]) then option{OnGround} else false
            var NowTouching:[]character_surface_component = array{}
            var NowStanding:?character_surface_component = GroundSurface
            var BestDistance:float = Inf
            var BestTop:float = -Inf
            if (OnGround := GroundSurface?):
                set NowTouching += array{OnGround}
            for (Surface : Candidates, Surface.IsActive[], not IsSame[Surface, GroundSurface]):
                Box := Surface.GetBox()
                if (Overlaps[BodyMin, BodyMax, Box]):
                    set NowTouching += array{Surface}
                    if (not GroundSurface?, Grounded?, Abs(Feet.Up - Box.MaxCm.Up) <= StandToleranceCm):
                        Away := HorizontalDistance(Feet, Box)
                        if (Away <= Found.RadiusCm, (Away < BestDistance or (Away = BestDistance and Box.MaxCm.Up > BestTop))):
                            set NowStanding = option{Surface}
                            set BestDistance = Away
                            set BestTop = Box.MaxCm.Up
            Update(Found, NowTouching, NowStanding)

    # Compares with the previous frame and reports the differences
    Update<private>(Found:character_motor_component, NowTouching:[]character_surface_component, NowStanding:?character_surface_component):void =
        Before := Touching
        WasStanding := Standing
        set Touching = NowTouching
        set Standing = NowStanding
        if (Old := WasStanding?, not IsSame[Old, NowStanding]):
            Notify(Found, Old, character_surface_contact.SteppedOff)
        for (Old : Before, not NowTouching.Find[Old]):
            Notify(Found, Old, character_surface_contact.Untouched)
        for (New : NowTouching, not Before.Find[New]):
            Notify(Found, New, character_surface_contact.Touched)
        if (New := NowStanding?, not IsSame[New, WasStanding]):
            Notify(Found, New, character_surface_contact.SteppedOn)

    Notify<private>(Found:character_motor_component, Surface:character_surface_component, Contact:character_surface_contact):void =
        ContactEventInternal.Signal((Surface, Contact))
        Surface.NotifyContact(Found, Contact)

    RefreshCandidates<private>(Found:character_motor_component):void =
        Feet := Found.Entity.GetGlobalTranslation()
        MaybeRoot:?entity = if (Root := SearchRoot?) then option{Root} else if (World := Entity.GetSimulationEntity[]) then option{World} else false
        if (Root := MaybeRoot?):
            set Candidates = for (Tagged : Root.FindDescendantEntitiesWithTag(character_surface_tag), Surface := Tagged.GetComponent[character_surface_component], DistanceToBox(Feet, Surface.GetBox()) <= SearchRadiusCm):
                Surface
        else:
            set Candidates = array{}

# Succeeds if Surface is the same as the content of Maybe
IsSame<internal>(Surface:character_surface_component, Maybe:?character_surface_component)<decides><transacts>:void =
    Other := Maybe?
    Other = Surface

# Succeeds if the body's box (Low..High) overlaps Box
Overlaps<internal>(Low:vector3, High:vector3, Box:character_surface_box)<decides><transacts>:void =
    Low.Forward <= Box.MaxCm.Forward
    High.Forward >= Box.MinCm.Forward
    Low.Left <= Box.MaxCm.Left
    High.Left >= Box.MinCm.Left
    Low.Up <= Box.MaxCm.Up
    High.Up >= Box.MinCm.Up

# Distance from Point to Box (cm. 0 if inside)
DistanceToBox<internal>(Point:vector3, Box:character_surface_box)<transacts>:float =
    DF := Max(Max(Box.MinCm.Forward - Point.Forward, 0.0), Point.Forward - Box.MaxCm.Forward)
    DL := Max(Max(Box.MinCm.Left - Point.Left, 0.0), Point.Left - Box.MaxCm.Left)
    DU := Max(Max(Box.MinCm.Up - Point.Up, 0.0), Point.Up - Box.MaxCm.Up)
    Sqrt(DF * DF + DL * DL + DU * DU)

# Horizontal distance from Point to Box (cm. 0 if directly above or below)
HorizontalDistance<internal>(Point:vector3, Box:character_surface_box)<transacts>:float =
    DF := Max(Max(Box.MinCm.Forward - Point.Forward, 0.0), Point.Forward - Box.MaxCm.Forward)
    DL := Max(Max(Box.MinCm.Left - Point.Left, 0.0), Point.Left - Box.MaxCm.Left)
    Sqrt(DF * DF + DL * DL)

# Role: carries a custom character standing on a moving floor along with it. The object ridden is the entity the body (character_motor_component) hit with its ground sweep (GetGroundEntity. The moving floor's mesh entity, or a child moving with its parent)
#   Twice per frame, compares the floor's remembered position / yaw with the current ones and carries the body by the difference (the body's CarryBy: vertical as is, horizontal stops short on hitting anything other than the floor. Velocity unchanged)
#     1st: before the body moves (PreMoveEvent). The body first moves as much as the floor, then by its own velocity (no sweeping while penetrating a floor that rose)
#     2nd: after physics (TickEvents.PostPhysics). On frames where the floor (MoverSystem keyframes, floors moved from Verse every frame) moved after the body, the body is realigned onto the floor at the end of the frame
#   With FollowYaw, when the floor turns in yaw, the body's position is rotated around the floor's position (the entity's origin) by the same amount (the body's facing is unchanged)
#   The floor's velocity (amount carried / seconds) is written to the body's GetGroundVelocity and to GetRideVelocity
#   Leaving: stops riding when leaving upward (jump, launch), falling off the edge, or after GraceSeconds. With InheritVelocity, adds the floor's velocity (excluding downward speed) to the body's velocity (the body's InheritVelocity. walk does not brake this part in the air)
#     If grounding drops for a moment (not rising, and the same floor is still within 50 cm below the feet), keeps carrying as if riding for GraceSeconds
#   Landing from the air: with InheritVelocity, removes from the body's horizontal velocity the part along the floor's direction of motion, up to the floor's speed (no sliding on the floor when jumping and landing back on the same floor. Nothing to remove when landing on a stopped floor)
# Placement: in the editor, attach to the same entity as character_motor_component (character_touch_component and the floor's character_surface_component are not needed. Add them only when touch / step-on notifications are wanted)
# When: from start until stopped. On the first frame of a new floor, only the position at that moment is remembered (earlier motion is not carried)
# From outside: FindRidingEntity (the object currently ridden), GetRideVelocity (its velocity). Also readable through the body's GetGroundVelocity / GetInheritedVelocity
# Requirements / notes: only the body's position is carried (the facing is unchanged. Pitch / roll of the floor are not followed). A frame where the floor jumped a long way (above MaxCarryCm) is not carried (so a warp / reset does not drag the body along)
#   If carried into a ceiling above, the body is not pushed back (it penetrates the ceiling). Not carried along the axis locked by the body's AxisLock
# ⚠ Unverified: whether GetGlobalTransform of a floor driven by keyframed_movement_component returns the moved position every frame on the server. Whether the carried body and the floor stay aligned visually on clients (the body arrives at the server position, the floor plays back on the client)
character_ride_component<public> := class<final_super>(component):

    # Do not follow a floor that moved more than this (cm) in one frame. Default 300
    @editable_number(float):
        ToolTip := RideMaxCarryToolTip
        Categories := array{CharacterSurfaceCategory}
        MinValue := option{1.0}
        MaxValue := option{10000.0}
    MaxCarryCm<public>:float = 300.0
    # When on, when the floor ridden turns in yaw, the body's position is also rotated around the floor's position (the entity's origin) by the same amount (the body's facing is unchanged). When off, only the floor's positional motion is added. Default on
    @editable:
        ToolTip := RideFollowYawToolTip
        Categories := array{CharacterSurfaceCategory}
    FollowYaw<public>:logic = true
    # If grounding drops for a moment while the same floor is still right below the feet, keeps carrying as if riding for up to this many seconds (not used when leaving upward). 0 disables. Default 0.1
    @editable_number(float):
        ToolTip := RideGraceToolTip
        Categories := array{CharacterSurfaceCategory}
        MinValue := option{0.0}
        MaxValue := option{2.0}
    GraceSeconds<public>:float = 0.1
    # When on, adds the floor's velocity (excluding downward speed) to the body when leaving a moving floor (jump, falling off the edge), and removes the inherited part when landing from the air. When off, nothing is added (the floor's motion vanishes the moment you leave). Default on
    @editable:
        ToolTip := RideInheritVelocityToolTip
        Categories := array{CharacterSurfaceCategory}
    InheritVelocity<public>:logic = true

    # Distance to probe down from the feet for the same floor when grounding drops for a moment (cm)
    GraceProbeCm<private>:float = 50.0

    var<private> Motor:?character_motor_component = false
    var<private> Subscriptions:[]cancelable = array{}
    # The object ridden, and its position / yaw (radians) when last carried (remembered)
    var<private> Riding:?entity = false
    var<private> LastPosition:vector3 = vector3{}
    var<private> LastYaw:float = 0.0
    var<private> GraceLeft:float = 0.0
    # Total carried since the previous PreMoveEvent (cm. For the floor's velocity) and the derived floor velocity (cm/s)
    var<private> CarriedSinceSample:vector3 = vector3{}
    var<private> RideVelocity:vector3 = vector3{}
    # Just landed from the air (on the next PreMoveEvent, once the floor's velocity is known, the inherited part is removed)
    var<private> JustLanded:logic = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := Entity.FindCharacterMotorAbove[]):
            set Motor = option{Found}
            set Subscriptions = array{Found.PreMoveEvent.Subscribe(OnPreMove), Found.PostMoveEvent.Subscribe(OnPostMove), TickEvents.PostPhysics.Subscribe(OnPostPhysics)}
        else:
            Print("[character_ride_component] character_motor_component not found (place it on the same entity)")

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        if (Found := Motor?, Riding?):
            Found.SetGroundVelocity(vector3{})
        set Riding = false
        set RideVelocity = vector3{}
        (super:)OnEndSimulation()

    # The object currently ridden (the entity the body stands on. Also during the GraceSeconds of a momentary drop). Fails if not riding
    FindRidingEntity<public>()<decides><transacts>:entity =
        Riding?

    # Velocity of the object currently ridden (cm/s, world space. For a rotating floor, the speed at the feet). 0 if not riding
    GetRideVelocity<public>()<transacts>:vector3 =
        RideVelocity

    # Before the body moves: carries by the floor's motion and derives the floor's velocity. If just landed from the air, removes the inherited velocity
    OnPreMove<private>(DeltaTime:float):void =
        if (Found := Motor?, Platform := Riding?):
            Sync(Found, Platform)
            set RideVelocity = if (DeltaTime > 0.0) then CarriedSinceSample / DeltaTime else vector3{}
            set CarriedSinceSample = vector3{}
            Found.SetGroundVelocity(RideVelocity)
            if (JustLanded?):
                set JustLanded = false
                if (InheritVelocity?):
                    CancelLandingVelocity(Found)

    # After physics: carries by the floor's motion that happened after the body moved (realigns onto the floor at the end of the frame)
    OnPostPhysics<private>(DeltaTime:float):void =
        if (Found := Motor?, Platform := Riding?):
            Sync(Found, Platform)

    # After the body moves: switches floors if the entity stood on changed; stops riding when leaving the ground (after waiting up to GraceSeconds for a momentary drop)
    OnPostMove<private>(DeltaTime:float):void =
        if (Found := Motor?):
            if (Ground := Found.GetGroundEntity[]):
                if (Platform := Riding?, Platform = Ground):
                    set GraceLeft = GraceSeconds
                else:
                    FromAir := if (Riding?) then false else true
                    Begin(Ground, FromAir)
            else if (Platform := Riding?):
                # Leaving upward (jump, launch): stop at once. Otherwise wait up to GraceSeconds while the same floor is right below the feet
                Rising := if (Found.GetVelocity().Up > 1.0) then true else false
                if (not Rising?, GraceLeft > 0.0, Below := Found.FindGroundEntityBelow[GraceProbeCm], Below = Platform):
                    set GraceLeft -= DeltaTime
                else:
                    Leave(Found)

    # Starts riding Ground (only remembers the current position / yaw. Carrying starts next time). FromAir means landing from the air
    Begin<private>(Ground:entity, FromAir:logic):void =
        set Riding = option{Ground}
        Remember(Ground.GetGlobalTransform())
        set CarriedSinceSample = vector3{}
        set GraceLeft = GraceSeconds
        set JustLanded = FromAir

    # Stops riding. With InheritVelocity, adds the floor's velocity (excluding downward speed) to the body's velocity
    Leave<private>(Found:character_motor_component):void =
        if (InheritVelocity?):
            Found.InheritVelocity(vector3{Forward := RideVelocity.Forward, Left := RideVelocity.Left, Up := Max(RideVelocity.Up, 0.0)})
        else:
            Found.SetGroundVelocity(vector3{})
        set Riding = false
        set RideVelocity = vector3{}
        set CarriedSinceSample = vector3{}
        set JustLanded = false

    # Has the body carried by how much the floor moved since the remembered position / yaw (with FollowYaw, also the rotation, applied at the body's position). Not carried above MaxCarryCm. Re-remembers the current position / yaw
    Sync<private>(Found:character_motor_component, Platform:entity):void =
        Transform := Platform.GetGlobalTransform()
        Position := Transform.Translation
        Body := Found.Entity.GetGlobalTransform().Translation
        Turn := if (FollowYaw?) then YawRadiansOf(Transform) - LastYaw else 0.0
        Delta := Position + TurnAroundUp(Body - LastPosition, Turn) - Body
        Moved := Delta.Length()
        if (Moved > 0.01, Moved <= MaxCarryCm):
            Found.CarryBy(Delta, Platform)
            set CarriedSinceSample = CarriedSinceSample + Delta
        Remember(Transform)

    Remember<private>(Transform:transform):void =
        set LastPosition = Transform.Translation
        set LastYaw = YawRadiansOf(Transform)

    # Landing from the air: removes from the body's horizontal velocity the part along the floor's direction of motion, up to the floor's speed (the part inherited from the floor. Nothing if opposed or stopped)
    CancelLandingVelocity<private>(Found:character_motor_component):void =
        Platform := vector3{Forward := RideVelocity.Forward, Left := RideVelocity.Left}
        PlatformCm := Platform.Length()
        if (PlatformCm > 1.0):
            Direction := Platform / PlatformCm
            Velocity := Found.GetVelocity()
            Along := Clamp(DotProduct(Velocity, Direction), 0.0, PlatformCm)
            if (Along > 0.0):
                Found.SetVelocity(Velocity - Direction * Along)

# Yaw of the horizontal direction of Transform's forward (Forward axis) (radians. Forward = 0, positive turning left)
YawRadiansOf<internal>(Transform:transform)<reads>:float =
    Axis := Transform.Rotation.GetForwardAxis()
    ArcTan(Axis.Left, Axis.Forward)

# Rotates Offset around the up axis by LeftTurnRadians (radians), forward turning toward left (the up component is unchanged)
TurnAroundUp<internal>(Offset:vector3, LeftTurnRadians:float)<reads>:vector3 =
    C := Cos(LeftTurnRadians)
    S := Sin(LeftTurnRadians)
    vector3{Forward := Offset.Forward * C - Offset.Left * S, Left := Offset.Forward * S + Offset.Left * C, Up := Offset.Up}
