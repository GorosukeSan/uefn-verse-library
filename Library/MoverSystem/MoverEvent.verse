using { /Verse.org/SceneGraph }
using { /Verse.org/SpatialMath }

# Role: one target of a mover. Position is a world position (centimeters). Index is the point number for mover_path_route_component (0-based in the arranged order; the same point keeps the same number when going back and forth), or the pick count (0-based) for random routes
mover_target<public> := struct<computes>:
    # World position of the target (centimeters)
    Position<public>:vector3 = vector3{}
    # Point number for a fixed-point route, pick count for a random route (both 0-based)
    Index<public>:int = 0

# Direction: SendDown from the mover entity (itself and descendants)
# Sender: mover_component (Mover). When the next target is chosen and the mover starts heading for it
# Receivers: looks such as target markers. Not consumed
mover_target_changed_event<public> := class(scene_event):
    # The mover_component that sent it
    Mover<public>:mover_component
    # The chosen target
    Target<public>:mover_target

# Direction: SendDown from the mover entity (itself and descendants)
# Sender: mover_component (Mover). On arrival at a target (same timing as TargetReachedEvent)
# Receivers: arrival effects and the like. Not consumed
mover_target_reached_event<public> := class(scene_event):
    # The mover_component that sent it
    Mover<public>:mover_component
    # The reached target
    Target<public>:mover_target

# Direction: SendDown from the mover entity (itself and descendants)
# Sender: mover_component (Mover). When the mover stops at the end of the route (reached the last point of mover_path_mode.Once / no route component) (same timing as FinishedEvent)
# Receivers: stop effects and the like. Not consumed
mover_finished_event<public> := class(scene_event):
    # The mover_component that stopped
    Mover<public>:mover_component
