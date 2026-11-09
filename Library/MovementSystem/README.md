# MovementSystem

Helpers that handle `fort_character` in Verse coordinates (`vector3` from `/Verse.org/SpatialMath`: Forward / Left / Up, centimeters, world space). Only extension functions that read and write position, velocity and view; there are no components. Other Systems (Swing, Jetpack, Hover, Gravity, etc.) use this.

## Setup (placement)

There is no component to place. `using { MovementSystem }` and call the functions on a `fort_character`.

| component | Where to place | What it does |
|---|---|---|
| (none) | — | Call extension functions such as `FortCharacter.LiftBy(...)` from code |

Example: lift the player 2 meters, then launch them upward at 1000 cm/s
```
if (FortCharacter := Agent.GetFortCharacter[]):
    FortCharacter.LiftBy(200.0)
    FortCharacter.SetVelocityCmPerSecond(vector3{Up := 1000.0})
```

## Settings (@editable)
None.

## Events
None.

## Public API
```verse
# CharacterPosition: position and velocity (centimeters, centimeters per second)
(FortCharacter:fort_character).FindGlobalTranslation<public>()<decides><transacts>:vector3      # the entity origin (not the feet). Fails if the entity cannot be obtained
(FortCharacter:fort_character).GetVelocityCmPerSecond<public>()<reads>:vector3                  # GetLinearVelocity (meters per second) times 100
(FortCharacter:fort_character).SetVelocityCmPerSecond<public>(VelocityCmPerSecond:vector3):void # divides by 100 and passes to SetLinearVelocity

# CharacterLift: move straight up
(FortCharacter:fort_character).LiftBy<public>(HeightCm:float)<transacts>:void   # move HeightCm along world Up (negative moves down). Ignores collision

# CharacterView: view
(FortCharacter:fort_character).GetViewOrigin<public>()<transacts>:vector3      # world position of the camera
(FortCharacter:fort_character).GetViewDirection<public>()<transacts>:vector3   # view direction (unit length)
```

## Requirements, caveats and limits
- Velocity: Epic's `fort_character.GetLinearVelocity` / `SetLinearVelocity` are in meters per second. To work in centimeters per second, use `GetVelocityCmPerSecond` / `SetVelocityCmPerSecond`.
- `FindGlobalTranslation` is the position of the character entity's origin, not the feet.
- `LiftBy` ignores collision and changes the character entity's position directly (rotation and scale unchanged). It does nothing if the character's entity cannot be obtained.
- `GetViewOrigin` / `GetViewDirection` convert Epic's `GetViewLocation` / `GetViewRotation` (UE XYZ, the coordinates of `/UnrealEngine.com/Temporary/SpatialMath`) to Verse coordinates (Forward = X, Left = -Y, Up = Z). Only the internal `CharacterViewRaw.verse` uses the Temporary coordinates.
- The names were checked against the `fort_character` members in the v43.00 digest (/Fortnite.com, /Verse.org, /UnrealEngine.com) so they do not collide.
- No experimental APIs are used.

## Verifying
- Test: `movement_system_test_component` in `_Test/MovementSystemTest/`. Place one entity with `player_manager_component` and attach this test component to any entity. Leave 3 meters of free space above the player's head. With the first player to join, it checks that `FindGlobalTranslation` can be obtained, that `LiftBy(200.0)` moves exactly 200 cm straight up without drifting sideways, that `GetViewDirection` has length 1, and that `GetViewOrigin` is within 3 meters of the character (it ends up far away if the coordinate conversion is reversed). It finishes within a few frames once a player joins. Results are in the output log under `[TEST] MovementSystem`.
- There is no sample (`_Samples/`).

## Teleport (teleport_on_activation_component)
- Attach to the destination entity. When an activation signal that knows who triggered it arrives (`activated_by_agent_event`: the Targets of a choice menu, an interact, a volume entrance, etc.), it moves that person's character to this entity's position + `OffsetCm` (default 100 up). A signal that does not know who triggered it does nothing.
- From code: `TeleportAgent(Agent)`.
- ⚠ Unverified: whether the movement state, such as falling, continues as is when the character entity's position is rewritten.
