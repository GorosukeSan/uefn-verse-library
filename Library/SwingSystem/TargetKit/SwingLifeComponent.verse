using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SwingSystem }
using { SwingSystem.TooltipKit }

# Role: lifetime target. LifeSeconds after the swing_target_component on the same entity is first grabbed, breaks it with Shatter (releasing does not extend it; the swing of whoever holds it is cut)
# Notifies: every 0.1 s sends the remaining ratio (1 -> 0) to its own entity as swing_life_changed_event, and during the last BlinkSeconds toggles Visible BlinkCount times to signal blinking (for switching the look)
# Placement: attach in the editor to the same entity as swing_target_component (the cube you want players to grab). May share an entity with a mover. Same when created at runtime (AddComponents swing_target_component{Entity := E} and swing_life_component{Entity := E, LifeSeconds := 5.0} together)
# Same entity: swing_target_component (required), a mesh with collision. To change the look, a component that receives swing_life_changed_event
swing_life_component<public> := class<final_super>(component):

    # Time from the first grab until it breaks (seconds; default 5). Includes the final blinking time
    @editable_number(float):
        ToolTip := SwingLifeSecondsToolTip
        Categories := array{SwingCategory, SwingLifeCategory}
        MinValue := option{0.5}
        MaxValue := option{120.0}
    LifeSeconds<public>:float = 5.0
    # Number of blinks just before it breaks (default 3)
    @editable_number(int):
        ToolTip := SwingLifeBlinkCountToolTip
        Categories := array{SwingCategory, SwingLifeCategory}
        MinValue := option{1}
        MaxValue := option{10}
    BlinkCount<public>:int = 3
    # Blinking time just before it breaks (seconds; default 0.9)
    @editable_number(float):
        ToolTip := SwingLifeBlinkSecondsToolTip
        Categories := array{SwingCategory, SwingLifeCategory}
        MinValue := option{0.1}
        MaxValue := option{10.0}
    BlinkSeconds<public>:float = 0.9

    # Interval between remaining-time notifications (seconds). Meant for look updates, so not every frame
    NotifyIntervalSeconds<private>:float = 0.1

    OnSimulate<override>()<suspends>:void =
        MaybeTarget := Entity.AwaitSwingTarget(TickEvents.PrePhysics)
        if (Target := MaybeTarget?):
            if (not Target.WasAttached[]):
                Target.AttachedEvent.Await()
            RunCountdown()
            Target.Shatter()

    RunCountdown<private>()<suspends>:void =
        Life := Max(LifeSeconds, 0.01)
        StartTime := GetSimulationElapsedTime()
        SteadySeconds := Max(Life - BlinkSeconds, 0.0)
        loop:
            Elapsed := GetSimulationElapsedTime() - StartTime
            if (Elapsed >= SteadySeconds):
                break
            Entity.SendDown(swing_life_changed_event{Life := Self, RemainingRatio := 1.0 - Elapsed / Life, Visible := true})
            Sleep(NotifyIntervalSeconds)
        Remaining := Min(BlinkSeconds, Life) / Life
        HalfSeconds := BlinkSeconds / (2.0 * (Max(BlinkCount, 1) * 1.0))
        var Count:int = 0
        loop:
            if (Count >= BlinkCount):
                break
            Entity.SendDown(swing_life_changed_event{Life := Self, RemainingRatio := Remaining, Visible := false})
            Sleep(HalfSeconds)
            Entity.SendDown(swing_life_changed_event{Life := Self, RemainingRatio := Remaining, Visible := true})
            Sleep(HalfSeconds)
            set Count += 1

# Remaining lifetime of a lifetime target (swing_life_component). Arrives every 0.1 s and during the final blinking
# Direction: swing_life_component SendDowns it to its own entity. Receivers: look components on the same entity / descendants. Not consumed
swing_life_changed_event<public> := class(scene_event):
    # Sender
    Life<public>:swing_life_component
    # Remaining ratio (1 -> 0)
    RemainingRatio<public>:float
    # false while blinking (hide the look)
    Visible<public>:logic
