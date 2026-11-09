using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

# Role: when the simulation starts, sends the activation signal (activated_event) once to this entity and its descendants. Starts parts that wait for activation (countdowns, input, screens, etc.) from the beginning without the game flow (GameSequenceSystem)
# Placement: attach in the editor to the entity of the part to activate (or an ancestor)
# Notifies: sends activated_event downward on the frame after start (waits one frame so that every component in the same tree has finished OnBeginSimulation first)
# Requirements / notes: does not send the deactivation signal (to stop, call SendDeactivated or each part's Stop / Deactivate)
activate_on_begin_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        TickEvents.PrePhysics.Await()
        Entity.SendActivated()
