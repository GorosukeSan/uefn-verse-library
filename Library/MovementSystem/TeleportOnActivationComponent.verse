using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { ActivationSystem }
using { SceneGraphSystem }
using { MovementSystem.TooltipKit }

# Role: when an activation signal that knows who triggered it arrives (activated_by_agent_event: button, choice menu, volume entrance, etc.), move that person's character to this entity's position (+ OffsetCm) (warp / go to the chosen place)
#   It moves the character entity's position (ignores collision). A signal that does not know who triggered it does nothing
# Placement: in the editor, attach to the destination entity. Put this entity in the Targets of a choice menu, an interact, etc.
# From outside: TeleportAgent(Agent) moves directly
# ⚠ Unverified: whether the movement state (falling, etc.) continues as is when the character entity's position is rewritten
teleport_on_activation_component<public> := class<final_super>(component):

    # Offset from this entity's position (cm; the character origin is the middle of the body, so about 100 up when on a floor). Default is 100 up
    @editable:
        ToolTip := TeleportOffsetToolTip
        Categories := array{TeleportCategory}
    OffsetCm<public>:vector3 = vector3{Up := 100.0}

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent], Agent := SceneEvent.FindActivatingAgent[]):
            TeleportAgent(Agent)
        false

    # Move the Agent's character to this entity's position (+ OffsetCm). Does nothing if there is no character
    TeleportAgent<public>(Agent:agent):void =
        if (Character := Agent.GetFortCharacter[], Body := Character.GetEntity[]):
            Target := Entity.GetGlobalTransform().Translation + OffsetCm
            Body.SetGlobalTransform(Body.GetGlobalTransform().WithTranslation(Target))
