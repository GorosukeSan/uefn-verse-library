# MoverSystem

A System that moves an entity through fixed points or random targets in order. It can also travel between points along a smooth curve at a constant speed (`mover_spline_route_component`). The central `mover_component` handles speed, wait time and the way of moving; how targets are chosen is selected by the route placed on the same entity (a `mover_route_component` subclass; RouteKit). The activate signal (ActivationSystem) starts it, the deactivate signal pauses it. `Restart` starts the route over from the beginning (even after it finished).

## Placement

| component | Where | What it does |
|---|---|---|
| `mover_component` | the entity to move (one per entity; may be created at runtime) | Moves through the targets decided by the route at `SpeedCmPerSecond`, in order. On arrival, waits `WaitSeconds` seconds, then moves on. Stops when the route ends |
| `mover_path_route_component` (RouteKit) | the same entity as `mover_component` | Traverses fixed points in `Mode` (Loop / PingPong / Once). The points are `Points` (code) or the `mover_waypoint_component` direct children |
| `mover_spline_route_component` (RouteKit) | the same entity as `mover_component` | Joins the points with a smooth curve (centripetal Catmull-Rom; always passes through the points) and travels along it at a constant speed. `Closed` for a loop, `Mode` (PingPong / Once) for an open path. The points are `Points` (code) or the `mover_waypoint_component` direct children |
| `mover_waypoint_component` (RouteKit) | an entity without a look, as a direct child of the `mover_path_route_component` / `mover_spline_route_component` entity | Marker for a point to traverse. Visited in ascending `Order` (the child order is not used) |
| `mover_random_route_component` (RouteKit) | the same entity as `mover_component` | Picks random points within `RadiusCm` of the start position as the targets, one after another (never ends) |
| `mover_box_route_component` (RouteKit) | the same entity as `mover_component` (created at runtime) | Picks random points inside the box `BoxMinCm`-`BoxMaxCm` as the targets, one after another (never ends) |

At most one route component per entity. Without a route, `mover_component` finishes immediately without moving (`FinishedEvent` fires).

Example: "a floor that cycles through 3 places"
```
Moving floor (mesh + mover_component + mover_path_route_component)
├ Point A (mover_waypoint_component, Order = 1)
├ Point B (mover_waypoint_component, Order = 2)
└ Point C (mover_waypoint_component, Order = 3)
```
The marker positions are read once, when the first target is chosen after moving starts. The points do not change even when the markers move with the floor.

Example: "a floor that smoothly goes around a loop through 4 places" (just replace `mover_path_route_component` with `mover_spline_route_component`)
```
Moving floor (mesh + mover_component + mover_spline_route_component (Closed = true, IncludeStart = false))
├ Point A (mover_waypoint_component, Order = 1; same as where the floor is placed)
├ Point B (mover_waypoint_component, Order = 2)
├ Point C (mover_waypoint_component, Order = 3)
└ Point D (mover_waypoint_component, Order = 4)
```
It keeps going around A -> B -> C -> D -> A along a curve. The arrival notification (`TargetReachedEvent`) fires per point, and `WaitSeconds` applies per point too.

### Curved routes (mover_spline_route_component)
- Each segment between points is divided into `SubdivisionsPerSegment` (default 8) straight lines; the subdivided points and a "length table" (curve length from the first point) are built once, when the first target is chosen after moving starts. The mover travels the subdivided lines at the same speed, so the speed along the curve is constant (neither faster nor slower at sharp turns). Read the curve length with `GetLengthCm` and a position along the curve with `SampleAtDistance`.
- With 2 points it is a straight line (not subdivided). 3 or more points give a curve.
- With `Closed = true`, the last point is also joined to the first with a curve, and the direction changes smoothly at the seam too (`Mode` is ignored). With `Closed = false`, `Mode` applies: `PingPong` goes back along the same curve in reverse, `Once` stops at the last point, and `Loop` returns straight from the last point to the first.
- With `FaceTravelDirection = true`, the entity's facing (yaw; front = Forward axis) is aligned to the direction of travel (default off). At a `PingPong` turnaround, it makes a half turn during the first short leg of the way back. `Restart()` resets the facing along with the position.
- A custom character (CharacterSystem) is carried by a platform with collision when its body carries `character_ride_component` from SurfaceKit (the motion of the entity the body stands on, found by the grounding sweep, is added to the body twice: before the body moves and after physics. When the platform turns with `FaceTravelDirection`, the body's position is rotated around the platform too (`character_ride_component.FollowYaw`, default on). The body's facing is unchanged. Jumping off inherits the platform's velocity (`InheritVelocity`, default on)). The platform does not need `character_surface_component` (only when you need the mounted / dismounted notifications: `character_touch_component` on the body and `character_surface_component` on the platform).
- Why a route (RouteKit) rather than a separate part beside mover_component: splitting the curve into "targets (points)" and "intermediate points on the way there (`mover_leg.Via`)" lets `mover_component`'s own speed, waits, `Play` / `Pause` / `Restart`, `SetSpeed`, arrival / finish notifications and Keyframe / Physics be reused as they are (game parts that look up `mover_component` keep working too). The route base class gained `GetLeg`, which returns a non-straight path (straight by default), and `mover_component` plays the intermediate points up to one point as one combined `SetKeyframes` (not rebuilt per subdivided point, so it does not stop midway).

## Common tasks
| To do this | Write this |
|---|---|
| One way and stop (A -> B, done) | `mover_path_route_component.Mode = Once`. Stops at the last point, and `FinishedEvent` / `mover_finished_event` fire |
| Know when it arrived | Per point: `TargetReachedEvent` / `mover_target_reached_event` (before the `WaitSeconds` wait). End of the route: `FinishedEvent` / `mover_finished_event` |
| Receive the arrival in a node (ancestor) | `AlsoSendUp = true` (the notifications are also sent from the parent upward) |
| Move again from the beginning | `Restart()` (returns to the position and facing at simulation start first. Starts moving even while paused or after finishing) |
| Move once from the current place to another target | Put `SetPoints(array{Target})` into a `Mode = Once` route and call `Restart(?ReturnToStart := false)` |
| Pass through other objects | `Motion = Keyframe` (default). `Physics` only when bouncing is needed |
| Go around a curved loop / back and forth along an S curve | `mover_spline_route_component` (loop: `Closed = true`; back and forth: `Closed = false` with `Mode = PingPong`) |
| Face the direction of travel | `mover_spline_route_component.FaceTravelDirection = true` |
| Carry a custom character standing on it | `character_ride_component` (CharacterSystem / SurfaceKit) on the body. The platform is a mesh with collision |

Rotation in place (a `mover_rotate_component` idea), carrying Fortnite characters, and progress (0-1) are not available for now (see "Not available for now" below).

## Settings (@editable)
- `mover_component.Motion : mover_motion = mover_motion.Keyframe` — how to move. `Keyframe` lets the engine (`keyframed_movement_component`) move straight to the target at a constant speed (smooth on every screen; passes through other objects; recommended). `Physics` moves it in Verse every frame and bounces when it hits another object.
- `mover_component.SpeedCmPerSecond : float = 300.0` — speed (centimeters per second; 1-10000).
- `mover_component.StartOnBegin : logic = true` — when on, moves from the start of the game. When off, starts on the activate signal or `Play`.
- `mover_component.WaitSeconds : float = 0.0` — seconds to stay at each target before heading to the next (0-60).
- `mover_component.BounceSeconds : float = 0.3` — with Physics, seconds to travel in the bounced direction after a hit (0-10). Then heads back to the same target. 0 gives up that target and moves on.
- `mover_component.AlsoSendUp : logic = false` — when on, the notifications (`mover_target_changed_event` / `mover_target_reached_event` / `mover_finished_event`) are also sent from the parent to the ancestors (SendUp), in addition to the descendants. Its own entity receives them only once.
- `mover_path_route_component.Mode : mover_path_mode = mover_path_mode.Loop` — how the points are traversed. `Loop` returns to the first after the last, `PingPong` goes back and forth, `Once` stops at the last point.
- `mover_path_route_component.IncludeStart : logic = true` — when on, the start position becomes the first point (number 0). When off, only the marker points are visited.
- `mover_spline_route_component.Closed : logic = false` — when on, the last point is also joined to the first with a curve and it keeps going around the loop (`Mode` is ignored). 3 or more points (2 give a straight back-and-forth).
- `mover_spline_route_component.Mode : mover_path_mode = mover_path_mode.PingPong` — traversal when not `Closed`. `PingPong` goes back and forth along the same curve, `Once` stops at the last point, `Loop` returns straight from the last point to the first.
- `mover_spline_route_component.IncludeStart : logic = true` — when on, the start position becomes the first point (number 0). When off, only the marker points are visited (when the placed position differs from the first marker, it first heads straight there).
- `mover_spline_route_component.SubdivisionsPerSegment : int = 8` — number of straight lines each curve between points is divided into (1-64). 1 with 2 points.
- `mover_spline_route_component.FaceTravelDirection : logic = false` — when on, the entity's facing (yaw; front = Forward axis) is aligned to the direction of travel. Tilt is unchanged.
- `mover_waypoint_component.Order : int = 0` — traversal order, ascending. The order among equal numbers is unspecified.
- `mover_random_route_component.RadiusCm : float = 1500.0` — radius around the start position within which targets are chosen (centimeters; 100-50000).
- `mover_random_route_component.MinStepCm : float = 400.0` — the next target is at least this far from the current position (centimeters).
- `mover_random_route_component.MaxDescentCm : float = 300.0` — how far below the start position it may go (centimeters). Targets lower than this are lifted to this height. 0 never goes below.

Values set from code (not shown in the editor): `mover_path_route_component.Points : []vector3` and `mover_spline_route_component.Points : []vector3` (when empty, the child markers are used); `mover_box_route_component`'s `BoxMinCm` / `BoxMaxCm : vector3`, `MarginCm : float = 0.0` (inset from each face), `MinStepCm : float = 100.0`.

## Events
- `mover_target_changed_event` (scene_event, SendDown from the mover entity; with `AlsoSendUp`, also SendUp from the parent. Same for the next two): `Mover : mover_component`, `Target : mover_target`. When `mover_component` chooses the next target and starts heading for it. Not consumed.
- `mover_target_reached_event` (scene_event, SendDown): `Mover : mover_component`, `Target : mover_target`. On arrival at a target (before the `WaitSeconds` wait). Not consumed.
- `mover_finished_event` (scene_event, SendDown): `Mover : mover_component`. When the route ends and the mover stops (reached the last point of `Once` / no route component). Not consumed.
- `mover_path_changed_event` (RouteKit; scene_event, SendDown from the route entity): `Route : mover_path_route_component`, `Points : []vector3`. When `mover_path_route_component` decides the points to traverse (when the first target is chosen after moving starts / after `SetPoints`). For point markers and line looks. Not consumed.
- `mover_spline_changed_event` (RouteKit; scene_event, SendDown from the route entity): `Route : mover_spline_route_component`, `Points : []vector3` (the points the curve passes through), `CurvePoints : []vector3` (the subdivided points of the curve; point i is `CurvePoints[i x subdivisions]`; with `Closed` the last equals the first). When the curve is built (when the first target is chosen after moving starts / at the first target after `SetPoints` or `Restart`). For curve line looks. Not consumed.
- `mover_component.TargetChangedEvent : listenable(mover_target)` — when the next target is chosen and the mover starts heading for it.
- `mover_component.TargetReachedEvent : listenable(mover_target)` — on arrival at a target (before the `WaitSeconds` wait).
- `mover_component.FinishedEvent : listenable(tuple())` — when the route ends and the mover stops. Never fires for Loop / PingPong / random routes. After a `Restart`, fires again when the route ends again.
- Received: `mover_component` handles `activated_event` (start / resume) and `deactivated_event` (pause in place; the next activation continues from there).

## Public API
```verse
mover_motion<public> := enum:
    Keyframe
    Physics

mover_component<public> := class<final_super>(component):
    Motion<public>:mover_motion
    SpeedCmPerSecond<public>:float
    StartOnBegin<public>:logic
    WaitSeconds<public>:float
    BounceSeconds<public>:float
    AlsoSendUp<public>:logic
    TargetChangedEvent<public><final>:listenable(mover_target)
    TargetReachedEvent<public><final>:listenable(mover_target)
    FinishedEvent<public><final>:listenable(tuple())
    Play<public>():void                                 # Start moving / continue from where it stopped
    Pause<public>():void                                # Pause in place
    Restart<public>(?ReturnToStart:logic = true):void   # Start the route over (while moving, paused or finished). true returns to the start position and facing first, false moves from the current position
    SetSpeed<public>(CmPerSecond:float):void            # Below 1 becomes 1. Takes effect immediately, even mid-leg
    GetSpeedCmPerSecond<public>()<reads>:float          # SpeedCmPerSecond unless changed with SetSpeed
    IsMoving<public>()<decides><reads>:void             # Played and not finished. Also succeeds during the wait
    IsFinished<public>()<decides><reads>:void
    FindTarget<public>()<decides><reads>:mover_target   # Fails before moving starts and after finishing
    FindStartPosition<public>()<decides><reads>:vector3 # Position one frame after simulation start (where Restart returns to). Fails before it is read

mover_target<public> := struct<computes>:
    Position<public>:vector3                            # World position (cm)
    Index<public>:int                                   # Point number for fixed points, pick count for random (0-based)

mover_target_changed_event<public> := class(scene_event):
    Mover<public>:mover_component
    Target<public>:mover_target

mover_target_reached_event<public> := class(scene_event):
    Mover<public>:mover_component
    Target<public>:mover_target

mover_finished_event<public> := class(scene_event):
    Mover<public>:mover_component

# The path to one target (returned by curved routes)
mover_leg<public> := struct<computes>:
    Via<public>:[]vector3                               # Intermediate points on the way to the target (world positions; the target excluded). Empty means straight
    FaceTravelDirection<public>:logic                   # Align yaw to the direction of travel

# Route base class. Subclasses implement NextTarget (plus Reset when they keep traversal state, and GetLeg when the path is not straight)
mover_route_component<public> := class<abstract><final_super>(component):
    NextTarget<public>(Home:vector3, Position:vector3):?mover_target   # false when there are no more targets (the mover stops)
    Reset<public>():void                                               # Reset the traversal state (called by the mover's Restart). Default does nothing
    GetLeg<public>(From:vector3, Target:mover_target):mover_leg        # Called by the mover right after NextTarget. Default is straight (mover_leg{})

# RouteKit
mover_path_changed_event<public> := class(scene_event):
    Route<public>:mover_path_route_component
    Points<public>:[]vector3

mover_path_mode<public> := enum:
    Loop
    PingPong
    Once

mover_path_route_component<public> := class<final_super>(mover_route_component):
    Mode<public>:mover_path_mode
    IncludeStart<public>:logic
    Points<public>:[]vector3
    SetPoints<public>(NewPoints:[]vector3):void         # From the next target on, restart from the first of the new points
    GetResolvedPoints<public>()<reads>:[]vector3        # Empty before moving starts
    GetWaypoints<public>()<transacts>:[]mover_waypoint_component   # The direct child markers in ascending Order

mover_spline_changed_event<public> := class(scene_event):
    Route<public>:mover_spline_route_component
    Points<public>:[]vector3
    CurvePoints<public>:[]vector3

mover_spline_route_component<public> := class<final_super>(mover_route_component):
    Closed<public>:logic
    Mode<public>:mover_path_mode
    IncludeStart<public>:logic
    SubdivisionsPerSegment<public>:int
    FaceTravelDirection<public>:logic
    Points<public>:[]vector3
    SetPoints<public>(NewPoints:[]vector3):void         # From the next target on, restart from the first of the new points (the curve is rebuilt)
    GetResolvedPoints<public>()<reads>:[]vector3        # The points the curve passes through. Empty before moving starts
    GetCurvePoints<public>()<reads>:[]vector3           # The subdivided curve points. Empty before moving starts
    GetLengthCm<public>()<reads>:float                  # Curve length (one lap with Closed). 0 before moving starts
    FindDistanceAtPoint<public>(Index:int)<decides><reads>:float   # Curve length from the first point to point Index (with Closed, Index = number of points gives one lap)
    SampleAtDistance<public>(DistanceCm:float)<transacts>:vector3  # Position DistanceCm along the curve (wraps with Closed, otherwise clamped at both ends)
    GetWaypoints<public>()<transacts>:[]mover_waypoint_component

mover_waypoint_component<public> := class<final_super>(component):
    Order<public>:int

mover_random_route_component<public> := class<final_super>(mover_route_component):
    RadiusCm<public>:float
    MinStepCm<public>:float
    MaxDescentCm<public>:float

mover_box_route_component<public> := class<final_super>(mover_route_component):
    BoxMinCm<public>:vector3
    BoxMaxCm<public>:vector3
    MarginCm<public>:float
    MinStepCm<public>:float
```

## Requirements, caveats and limits
- The start position is the position one frame after the simulation begins (a spawner or the like may re-place the entity on the same frame).
- With Keyframe, `keyframed_movement_component` is attached at runtime when the entity has none. Do not keyframe-move the same entity from another component.
- Keyframe legs are built as deltas seen from the parent entity. It should reach the world target even when the parent is rotated, but this is not confirmed in UEFN (see "⚠ confirm in UEFN" in the requirements / notes of `MoverComponent.verse`).
- Without a route component (a `mover_route_component` subclass) on the same entity, it finishes immediately without moving (`FinishedEvent` / `mover_finished_event` fire) and the output log shows `[mover_component] No route component ... on the same entity`.
- Physics needs a mesh with collision (the way ahead is checked with `FindSweepHits`).
- Random routes use the point as is when, after several tries, no point at least `MinStepCm` away is found.
- To move an entity spawned by SpawnSystem with Keyframe, set the spawner's `AppearSeconds` to 0 (the scale change calls `SetGlobalTransform` every frame).
- With Keyframe, `Restart` stops the leg being played with `keyframed_movement_component.Stop`, then returns to the start position with `SetGlobalTransform`. How the position is handled after the stop (whether the engine re-sends the stopped position to everyone) is not confirmed in UEFN (`PrepareRestart` in `MoverComponent.verse`; ⚠ Unverified).
- `Restart(?ReturnToStart := false)` also makes the route's Home (the first point of `IncludeStart` / the random center) the current position. The next `Restart()` (default) always returns to the position at simulation start.
- Curved routes: with Keyframe, the intermediate points up to one point are played as one `SetKeyframes` (one keyframe per subdivided segment). The next leg is rebuilt on every arrival at a point, so even with `WaitSeconds = 0` it may stop at a point for about one frame (⚠ Unverified: visible in the `worst speed error` printed by `mover_spline_test_component` in `_Test`).
- `FaceTravelDirection` of curved routes: with Keyframe, a yaw rotation is added to each leg's keyframe. This assumes the keyframe's position delta (additive) is added as seen from the parent without being rotated by that rotation (⚠ Unverified: visible in `still arrives at the goal` of `mover_spline_test_component`). The yaw turning direction is decided by probing the forward axis rotated with `MakeRotationRadians`. With Physics, only yaw is turned toward the direction of travel every frame (tilt is removed).
- Physics curves arrive at each subdivided point before moving on, so they are slightly slower by a fraction of a frame per point (Keyframe is exactly constant).
- The curve depends only on the point positions (point facing / tangents are not used). Being centripetal (the square root of the point spacing is the parameter step), it rarely forms cusps or small loops even with unevenly spaced points. The ends of an open path are built by adding points mirrored across the end points on the outside.
- No experimental API is used.

## Not available for now
- Rotation in place (a `mover_rotate_component` idea; facing the direction of travel is possible with `mover_spline_route_component.FaceTravelDirection`), carrying riders (`CarryRiders`; a custom character (CharacterSystem) is carried when its body has `character_ride_component` from SurfaceKit; Fortnite characters are still not carried), ignoring only players in Physics (`IgnorePlayers`), progress (`GetProgress`), path-following routes (`path_follower_component` of a PathKit). Requested by the genre implementations (L-17 of `GAP_SUMMARY.md`) but not added as of 2026-11-08.

## Verifying
- Test: `mover_system_test_component` in `_Test/MoverSystemTest/`. Just attach it to an entity in the air with nothing within 10 meters (the test creates the moving entity as its own child; no player needed). Checks route traversal (Loop / PingPong / Once) and `IncludeStart`, the `Order` ordering, Keyframe arrival time and position, `Pause` / `Play`, `SetSpeed`, the finish notification, Physics arrival, route `Reset`, `Restart` (back to the start position and again / from the current position to replaced points), and `AlsoSendUp` (received on the parent entity). Takes about 6 s. Results go to the output log as `[TEST] MoverSystem`.
- Test (curves): `mover_spline_test_component` in `_Test/MoverSystemTest/MoverSplineTest.verse`. Same placement as above (just attach it to an entity in the air with nothing within 10 meters). Numerically checks the curve length (a 2-point line is exact; an 8-point loop on a circle is within 1% of the circumference), that the points are passed through, that points taken at equal lengths from the length table are evenly spaced, the loop seam (the last -> first segment is a curve too, the curvature at the seam matches the middle, one lap returns to the same position), the PingPong index order and that the intermediate points on the way back are the reverse of the way out, and that an open-path Loop returns straight. Moving (Keyframe), checks that one lap takes length / speed, that the speed every 0.2 s is constant and stays on the circle, the turnaround time and intermediate positions of PingPong, that `FaceTravelDirection` faces the direction of travel without drifting, and that `Restart` returns to the initial facing. About 7 s. Results go to the output log as `[TEST] MoverSpline` (the `worst speed error` line also shows the largest speed deviation and the largest deviation from the circle).
- There is no MoverSystem sample in `_Samples/`. The platform map of the author's game uses `mover_spline_route_component` for a loop and an S curve.

## Migration notes (2026-11-08)
- Added (curves): `mover_spline_route_component` and `mover_spline_changed_event` in RouteKit, `mover_leg` and `mover_route_component.GetLeg` in MoverSystem (straight by default, so existing routes and your own subclasses keep working).
- `Restart()` (`ReturnToStart` true) now resets the facing along with the position to what it was at simulation start (previously the facing was kept). No difference for routes that do not change the facing.
- Added: `Restart`, `AlsoSendUp`, `FindStartPosition`, `mover_route_component.Reset`.
- The type of `mover_target_changed_event.Mover`, `mover_target_reached_event.Mover` and `mover_finished_event.Mover` changed from `component` to `mover_component` (aligned with the Library-wide rule "senders keep their concrete type"). If the receiver cast with `mover_component[Event.Mover]`, drop the cast and use `Event.Mover` directly (the cast still works if kept). Code that stored it in a `component` variable keeps working.
- `mover_path_changed_event` moved from the top level of MoverSystem to RouteKit, and the type of `Route` changed from `component` to `mover_path_route_component`. Code that received it with only `using { MoverSystem }` adds `using { MoverSystem.RouteKit }`.
- If you wrote your own `mover_route_component` subclass that keeps traversal state (the current number, ...), reset that state in `Reset<override>()` so that `Restart` takes effect (without it, a restart continues from the next target).
