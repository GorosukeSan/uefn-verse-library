using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { SceneGraphSystem }
using { PlayerSystem.TooltipKit }

# Role: each time a momentary character motion (Motion: jump, landing, crouch, sprint, eliminated, damaged, etc.) happens, sends the activation signal (activated_event) to Targets and sends player_motion_event upward
#   The reaction (notification, giving items, attachments, enabling, etc.) is handled by activation-awaiting parts placed on the Targets entities (combine without writing code)
#   During CooldownSeconds, the same player's next motion is ignored (prevents duplicates of motions that repeat in quick succession)
# Placement: attach to an entity in the editor. Placed inside a loadout prefab (loadout_component's Prefab), it watches only the owner. Placed somewhere without an owner, it watches everyone in the scope
# Notifies: player_motion_event upward, MotionEvent with (the player, the motion)
# Requirements: when there is no owner, one player_manager_component in the scope (or world)
player_motion_trigger_component<public> := class<final_super>(component):

    # The motion to watch. Default Jumped
    @editable:
        ToolTip := PlayerMotionToolTip
        Categories := array{PlayerMotionCategory}
    Motion<public>:player_motion = player_motion.Jumped
    # Entities that receive the activation signal (reaches the entity and its descendants). If empty, sent to this entity and its descendants
    @editable:
        ToolTip := PlayerMotionTargetsToolTip
        Categories := array{PlayerMotionCategory}
    Targets<public>:[]entity = array{}
    # Time (seconds) during which the same player's next motion is ignored. 0 ignores nothing. Default 0
    @editable_number(float):
        ToolTip := PlayerMotionCooldownToolTip
        Categories := array{PlayerMotionCategory}
        MinValue := option{0.0}
        MaxValue := option{60.0}
    CooldownSeconds<public>:float = 0.0

    MotionEventInternal<private><final>:event(tuple(agent, player_motion)) = event(tuple(agent, player_motion)){}

    # Delivered with (the player, the motion) each time Motion happens (Await / Subscribe to it; it cannot be Signaled from outside)
    MotionEvent<public><final>:listenable(tuple(agent, player_motion)) = MakeProxyListenable(MotionEventInternal)

    Watchers<private>:player_motion_watcher_set = player_motion_watcher_set{}
    var<private> LastSeconds:[agent]float = map{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Watchers.Start(Entity, OnMotion, TickEvents.PrePhysics)

    OnEndSimulation<override>():void =
        Watchers.Stop()
        (super:)OnEndSimulation()

    OnMotion<private>(Agent:agent, Happened:player_motion):void =
        if (Happened <> Motion):
            return
        Now := GetSimulationElapsedTime()
        if (CooldownSeconds > 0.0, Previous := LastSeconds[Agent], Now - Previous < CooldownSeconds):
            return
        if (set LastSeconds[Agent] = Now) {}
        Entity.SendUp(player_motion_event{Trigger := Self, Agent := Agent, Motion := Happened})
        MotionEventInternal.Signal((Agent, Happened))
        Receivers := if (Targets.Length > 0) then Targets else array{Entity}
        for (Receiver : Receivers):
            Receiver.SendActivatedBy(Agent)
