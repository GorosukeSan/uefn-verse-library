using { /Verse.org/SceneGraph }
using { /Verse.org/SpatialMath }

# Role: the path a mover takes to one target. mover_component moves from the current position through the Via points in order to the target, at a constant speed (SpeedCmPerSecond). Returned by curved routes (mover_spline_route_component in RouteKit)
mover_leg<public> := struct<computes>:
    # Intermediate points on the way to the target (world positions, centimeters; the target itself is not included). Empty means straight to the target
    Via<public>:[]vector3 = array{}
    # true aligns the entity's facing (yaw; the entity's front = Forward axis) to the direction of travel. Tilt (pitch / roll) is unchanged
    FaceTravelDirection<public>:logic = false

# Role: base class (route) that decides the targets of mover_component one at a time. Subclasses implement NextTarget (plus Reset when they keep traversal state, and GetLeg when the path is not straight)
# Placement: never placed directly (place a RouteKit subclass). At most one subclass per entity
# Same entity: mover_component
mover_route_component<public> := class<abstract><final_super>(component):

    # Returns the next target. Called by mover_component when it starts moving and whenever it reaches a target (also after giving up on a hit). Home is the position where the mover started moving, Position is the current position (both world positions, centimeters). Returns false when there are no more targets (end of a one-shot route); the mover then stops and raises FinishedEvent
    NextTarget<public>(Home:vector3, Position:vector3):?mover_target

    # Reset the traversal state (so that the next NextTarget returns the first target). Called by mover_component on Restart. Default does nothing (stateless route)
    Reset<public>():void = {}

    # The path to the Target returned by NextTarget (intermediate points, whether to face the direction of travel). Called once by mover_component right after NextTarget. From is the current position (world position, centimeters). Default is straight (no intermediate points, facing unchanged)
    GetLeg<public>(From:vector3, Target:mover_target):mover_leg = mover_leg{}
