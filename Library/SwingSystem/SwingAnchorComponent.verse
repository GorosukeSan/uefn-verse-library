using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

# Role: marker attached to the entity of a point grabbed by a swing. When the grabbed object breaks, calling Break cuts every swing holding that point
# Placement: at runtime, swing_runner (driven by swing_ability_component) attaches it to the entity of the grabbed point (not placed in the editor). swing_target_component.Shatter calls it
swing_anchor_component<public> := class<final_super>(component):

    # true once Break has been called (read-only from outside)
    var<private> Broken<public>:logic = false

    BrokenEventInternal<private><final>:event() = event(){}

    # Fires when Break is called (Await / Subscribe it; it cannot be Signaled from outside)
    BrokenEvent<public><final>:listenable(tuple()) = MakeProxyListenable(BrokenEventInternal)

    # Cut every swing holding this point (sets Broken to true and sends BrokenEvent). Does nothing from the second call on (BrokenEvent fires only once)
    Break<public>():void =
        if (Broken?):
            return
        set Broken = true
        BrokenEventInternal.Signal()
