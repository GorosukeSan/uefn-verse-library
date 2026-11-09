using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { SceneGraphSystem }
using { SwingSystem }
using { SwingSystem.TooltipKit }

# Role: lift target. When a swing is launched from the swing_target_component on the same entity (it does not move while the player waits on the ground), it moves straight by TravelCm at SpeedCmPerSecond and, on arrival, breaks with Shatter (the swing of whoever holds it is cut)
# Notifies: sends swing_lift_changed_event{Active := true} to its own entity when it starts moving (for switching the look)
# Placement: attach in the editor to the same entity as swing_target_component (the cube you want players to grab). Do not put it on the same entity as a mover (they fight over the position). Same when created at runtime (AddComponents together with swing_target_component)
# Same entity: swing_target_component (required), a mesh with collision. To change the look, a component that receives swing_lift_changed_event
# Requirements / notes: the position is moved every frame (TickEvents.PrePhysics) with SetGlobalTransform. Elapsed time is the sum of DeltaTime
swing_lift_component<public> := class<final_super>(component):

    # Direction and distance to move when launched (centimeters; default straight up 4000)
    @editable:
        ToolTip := SwingLiftTravelToolTip
        Categories := array{SwingCategory, SwingLiftCategory}
    TravelCm<public>:vector3 = vector3{Up := 4000.0}
    # Speed after launch (centimeters per second; default 800)
    @editable_number(float):
        ToolTip := SwingLiftSpeedToolTip
        Categories := array{SwingCategory, SwingLiftCategory}
        MinValue := option{50.0}
        MaxValue := option{6000.0}
    SpeedCmPerSecond<public>:float = 800.0

    OnSimulate<override>()<suspends>:void =
        MaybeTarget := Entity.AwaitSwingTarget(TickEvents.PrePhysics)
        if (Target := MaybeTarget?):
            if (not Target.WasPulled[]):
                Target.PulledEvent.Await()
            Entity.SendDown(swing_lift_changed_event{Lift := Self, Active := true})
            Travel()
            Target.Shatter()

    Travel<private>()<suspends>:void =
        Start := Entity.GetGlobalTransform()
        Duration := Max(TravelCm.Length() / Max(SpeedCmPerSecond, 1.0), 0.01)
        var Elapsed:float = 0.0
        loop:
            DeltaTime := TickEvents.PrePhysics.Await()
            set Elapsed += DeltaTime
            Ratio := Min(Elapsed / Duration, 1.0)
            Entity.SetGlobalTransform(Start.WithTranslation(Start.Translation + TravelCm * Ratio))
            if (Ratio >= 1.0):
                break

# The lift target (swing_lift_component) started moving (Active := true)
# Direction: swing_lift_component SendDowns it to its own entity. Receivers: look components on the same entity / descendants. Not consumed
swing_lift_changed_event<public> := class(scene_event):
    # Sender
    Lift<public>:swing_lift_component
    # true when it started moving
    Active<public>:logic
