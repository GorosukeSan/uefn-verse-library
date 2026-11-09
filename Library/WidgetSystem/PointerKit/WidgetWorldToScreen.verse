using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /Verse.org/Input }

# Find where a world position lands on the screen, as a screen ratio (top-left 0,0 to bottom-right 1,1) (v43.00). World -> screen math is gathered in this file (MarkerKit's markers use it too)
#   There is no API for the screen size, so the camera's "eye position, forward, right, up and extent to the screen edge (tan of half the field of view)" are packed into a widget_screen_projection and used to project. Two ways to build one
#   - (Player:player).GetScreenProjection: that person's current camera (any camera, including custom cameras and Orbit). Takes 4 DeprojectViewportToWorld rays and
#     derives the camera's forward, right and up directions and the extent to the screen edge (field of view) from how the rays relate. Field of view and aspect ratio are not hard-coded
#     Assumes the screen center is straight ahead of the camera (an ordinary perspective camera). With a camera without perspective (Orthographic) the rays are parallel, nothing can be derived, and it fails
#     ⚠ It runs on the server, so the result lags the camera by up to 0.1 s plus network latency (drifts while turning fast)
#   - MakeScreenProjectionInView / MakeScreenProjectionAlong: built from a camera position, direction and horizontal field of view decided in code (no Player needed). Aspect ratio defaults to 16:9
#     For a camera you placed yourself (results stage, overview camera, etc.) these do not lag even right after switching or moving it
#   When projecting many points in one frame, build the widget_screen_projection once and reuse it (GetScreenProjection takes 4 rays)
#   The result is a vector2 (/UnrealEngine.com/Temporary/SpatialMath; X horizontal, Y vertical, same as CardKit's widget_screen_rect.LocalOf). Off screen gives values outside 0-1 (ClampScreenRatio pulls them inside)
#   This file uses both SpatialMath modules, so vector3 and transform are written with (/Verse.org/SpatialMath:) (vector2 exists only in Temporary)
#   ⚠ Unverified (UEFN v43.00): whether the Origin of DeprojectViewportToWorld is the same camera eye position for all 4 rays. Whether perspective_camera_component.FieldOfView is the horizontal field of view

# The camera's eye position, directions and extent to the screen edge (used for world -> screen ratio math). Built with GetScreenProjection, MakeScreenProjectionInView or MakeScreenProjectionAlong
widget_screen_projection<public> := struct<computes>:
    # Camera eye position (world)
    Origin<public>:(/Verse.org/SpatialMath:)vector3 = (/Verse.org/SpatialMath:)vector3{}
    # Camera forward, screen right and screen up directions (world, unit length)
    Forward<public>:(/Verse.org/SpatialMath:)vector3 = (/Verse.org/SpatialMath:)vector3{Forward := 1.0}
    Right<public>:(/Verse.org/SpatialMath:)vector3 = (/Verse.org/SpatialMath:)vector3{Left := -1.0}
    Up<public>:(/Verse.org/SpatialMath:)vector3 = (/Verse.org/SpatialMath:)vector3{Up := 1.0}
    # Extent to the right and top screen edges (tan of half the horizontal / vertical field of view)
    TanH<public>:float = 1.0
    TanV<public>:float = 0.5625

# Screen ratio where world position WorldPosition lands with Projection's camera. Fails if behind or exactly beside the camera
(Projection:widget_screen_projection).ProjectToScreenRatio<public>(WorldPosition:(/Verse.org/SpatialMath:)vector3)<decides><reads>:(/UnrealEngine.com/Temporary/SpatialMath:)vector2 =
    WorldToScreenFromBasis[Projection.Origin, Projection.Forward, Projection.Right, Projection.Up, Projection.TanH, Projection.TanV, WorldPosition]

# Screen ratio where a point in direction Direction from Projection's camera eye lands (the direction of a Virtual Pointer ray, etc.). Fails for a direction behind or exactly beside
(Projection:widget_screen_projection).ProjectDirectionToScreenRatio<public>(Direction:(/Verse.org/SpatialMath:)vector3)<decides><reads>:(/UnrealEngine.com/Temporary/SpatialMath:)vector2 =
    WorldToScreenFromBasis[Projection.Origin, Projection.Forward, Projection.Right, Projection.Up, Projection.TanH, Projection.TanV, Projection.Origin + Direction]

# Width in viewport coordinates used for the derivation (spacing of the 4 rays). The math holds even when pointing off screen
WorldToScreenCalibrationSpan<internal>:float = 1000.0

# Player's current camera (derived from 4 DeprojectViewportToWorld rays). Fails if the camera directions cannot be derived
(Player:player).GetScreenProjection<public>()<decides><reads>:widget_screen_projection =
    Span := WorldToScreenCalibrationSpan
    TopLeft := Player.DeprojectViewportToWorld((/Verse.org/SpatialMath:)vector3{})
    TopRight := Player.DeprojectViewportToWorld((/Verse.org/SpatialMath:)vector3{Left := Span})
    BottomLeft := Player.DeprojectViewportToWorld((/Verse.org/SpatialMath:)vector3{Up := -Span})
    BottomRight := Player.DeprojectViewportToWorld((/Verse.org/SpatialMath:)vector3{Left := Span, Up := -Span})
    A := TopLeft.Direction
    B := TopRight.Direction
    C := BottomLeft.Direction
    D := BottomRight.Direction
    # Rays of the same row (points side by side) lie on a plane that contains the screen-right direction. The intersection of the top row's plane and the bottom row's plane is right (same for columns: their intersection is up)
    RightAxis := WorldToScreenUnit[CrossProduct(CrossProduct(A, B), CrossProduct(C, D))]
    UpAxis := WorldToScreenUnit[CrossProduct(CrossProduct(A, C), CrossProduct(B, D))]
    # Match the sign of the directions to the difference of rays moved right / up on the screen
    Right := if (DotProduct(RightAxis, B - A) < 0.0) then RightAxis * -1.0 else RightAxis
    Up := if (DotProduct(UpAxis, A - C) < 0.0) then UpAxis * -1.0 else UpAxis
    # What remains of the top-left ray after removing the right and up components is forward
    Forward := WorldToScreenUnit[A - Right * DotProduct(A, Right) - Up * DotProduct(A, Up)]
    Depth := DotProduct(A, Forward)
    Depth > 0.0001
    # The slope of the top-left corner ray is the extent to the screen edge (tan of half the horizontal / vertical field of view)
    TanH := -DotProduct(A, Right) / Depth
    TanV := DotProduct(A, Up) / Depth
    TanH > 0.0001
    TanV > 0.0001
    widget_screen_projection{Origin := TopLeft.Origin, Forward := Forward, Right := Right, Up := Up, TanH := TanH, TanV := TanV}

# Camera at position / rotation View (horizontal field of view FieldOfViewDegrees degrees, screen width / height AspectRatio; below 0.1 becomes 0.1). Uses View's forward, left and up as they are (including roll)
MakeScreenProjectionInView<public>(View:(/Verse.org/SpatialMath:)transform, FieldOfViewDegrees:float, ?AspectRatio:float = 16.0 / 9.0)<reads>:widget_screen_projection =
    TanH := Tan(Clamp(FieldOfViewDegrees, 1.0, 179.0) * PiFloat / 360.0)
    widget_screen_projection:
        Origin := View.Translation
        Forward := View.Rotation.GetForwardAxis()
        Right := View.Rotation.GetLeftAxis() * -1.0
        Up := View.Rotation.GetUpAxis()
        TanH := TanH
        TanV := TanH / Max(AspectRatio, 0.1)

# Camera at position Origin looking along Forward (no roll. Horizontal field of view FieldOfViewDegrees degrees, screen width / height AspectRatio)
#   Use when only a direction is known (a fort_character's view direction, etc.). Fails when looking straight up or down, because the right direction is undefined
MakeScreenProjectionAlong<public>(Origin:(/Verse.org/SpatialMath:)vector3, Forward:(/Verse.org/SpatialMath:)vector3, FieldOfViewDegrees:float, ?AspectRatio:float = 16.0 / 9.0)<decides><reads>:widget_screen_projection =
    AspectRatio > 0.0001
    Front := WorldToScreenUnit[Forward]
    # The right of the horizontal forward (Forward, Left) is (Left, -Forward)
    Right := WorldToScreenUnit[(/Verse.org/SpatialMath:)vector3{Forward := Front.Left, Left := -Front.Forward}]
    WorldUp := (/Verse.org/SpatialMath:)vector3{Up := 1.0}
    Up := WorldToScreenUnit[WorldUp - Front * DotProduct(WorldUp, Front)]
    TanH := Tan(Clamp(FieldOfViewDegrees, 1.0, 179.0) * PiFloat / 360.0)
    widget_screen_projection{Origin := Origin, Forward := Front, Right := Right, Up := Up, TanH := TanH, TanV := TanH / AspectRatio}

# Screen ratio (top-left 0,0 to bottom-right 1,1) where world position WorldPosition lands with Player's current camera. Fails if behind or exactly beside the camera, or if the camera directions cannot be derived
#   When projecting many points, call GetScreenProjection once and reuse it
(Player:player).ProjectToScreenRatio<public>(WorldPosition:(/Verse.org/SpatialMath:)vector3)<decides><reads>:(/UnrealEngine.com/Temporary/SpatialMath:)vector2 =
    Player.GetScreenProjection[].ProjectToScreenRatio[WorldPosition]

# Convert Player's viewport coordinate ViewportPosition (the Virtual Pointer's PointerSelect value) to a screen ratio. Derived from the current camera's rays, so field of view and aspect ratio are not hard-coded
#   (PointerToScreenRatio assumes the Fortnite character's view direction and field of view. Use this one for a camera you placed yourself)
(Player:player).ViewportToScreenRatio<public>(ViewportPosition:(/Verse.org/SpatialMath:)vector3)<decides><reads>:(/UnrealEngine.com/Temporary/SpatialMath:)vector2 =
    Projection := Player.GetScreenProjection[]
    Ray := Player.DeprojectViewportToWorld(ViewportPosition)
    Projection.ProjectDirectionToScreenRatio[Ray.Direction]

# Screen ratio where WorldPosition lands with a camera at position / rotation View (horizontal field of view FieldOfViewDegrees degrees, screen width / height AspectRatio). Fails if behind or exactly beside the camera
ProjectToScreenRatioInView<public>(View:(/Verse.org/SpatialMath:)transform, FieldOfViewDegrees:float, WorldPosition:(/Verse.org/SpatialMath:)vector3, ?AspectRatio:float = 16.0 / 9.0)<decides><reads>:(/UnrealEngine.com/Temporary/SpatialMath:)vector2 =
    AspectRatio > 0.0001
    MakeScreenProjectionInView(View, FieldOfViewDegrees, ?AspectRatio := AspectRatio).ProjectToScreenRatio[WorldPosition]

# Screen ratio where WorldPosition lands with a camera at position Origin looking along Forward (no roll). Fails when looking straight up or down, or if behind or exactly beside the camera
ProjectToScreenRatioAlong<public>(Origin:(/Verse.org/SpatialMath:)vector3, Forward:(/Verse.org/SpatialMath:)vector3, FieldOfViewDegrees:float, WorldPosition:(/Verse.org/SpatialMath:)vector3, ?AspectRatio:float = 16.0 / 9.0)<decides><reads>:(/UnrealEngine.com/Temporary/SpatialMath:)vector2 =
    MakeScreenProjectionAlong[Origin, Forward, FieldOfViewDegrees, ?AspectRatio := AspectRatio].ProjectToScreenRatio[WorldPosition]

# Pull screen ratio Ratio inside the screen (at least Margin from the edge). Margin is 0.0-0.5
ClampScreenRatio<public>(Ratio:(/UnrealEngine.com/Temporary/SpatialMath:)vector2, ?Margin:float = 0.0)<transacts>:(/UnrealEngine.com/Temporary/SpatialMath:)vector2 =
    Edge := Clamp(Margin, 0.0, 0.5)
    (/UnrealEngine.com/Temporary/SpatialMath:)vector2{X := Clamp(Ratio.X, Edge, 1.0 - Edge), Y := Clamp(Ratio.Y, Edge, 1.0 - Edge)}

# Screen ratio of WorldPosition from the camera eye Origin, forward Forward, right Right, up Up (all unit length) and the extent to the screen edge TanH / TanV
WorldToScreenFromBasis<internal>(Origin:(/Verse.org/SpatialMath:)vector3, Forward:(/Verse.org/SpatialMath:)vector3, Right:(/Verse.org/SpatialMath:)vector3, Up:(/Verse.org/SpatialMath:)vector3, TanH:float, TanV:float, WorldPosition:(/Verse.org/SpatialMath:)vector3)<decides><reads>:(/UnrealEngine.com/Temporary/SpatialMath:)vector2 =
    TanH > 0.0001
    TanV > 0.0001
    Offset := WorldPosition - Origin
    Depth := DotProduct(Offset, Forward)
    Depth > 0.01
    X := DotProduct(Offset, Right) / Depth / TanH
    Y := DotProduct(Offset, Up) / Depth / TanV
    (/UnrealEngine.com/Temporary/SpatialMath:)vector2{X := 0.5 + 0.5 * X, Y := 0.5 - 0.5 * Y}

# Make V unit length. Fails if the length is nearly 0
WorldToScreenUnit<internal>(V:(/Verse.org/SpatialMath:)vector3)<decides><reads>:(/Verse.org/SpatialMath:)vector3 =
    Length := V.Length()
    Length > 0.000001
    V * (1.0 / Length)
