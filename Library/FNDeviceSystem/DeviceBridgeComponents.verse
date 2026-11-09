using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Devices }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { FNDeviceSystem.TooltipKit }

# FNDeviceSystem: the System that gathers everything relying on Fortnite creative devices (creative_device).
# Connects Scene Graph parts (activation / deactivation signals, who caused them) with things only devices can do (ending the game, class and team, score, cinematics, audio, ...).
# Devices placed in the level are chosen through @editable. No other System depends on devices (to use a device, place a part of this System).

# Role: on the activation signal, fires the trigger device in Trigger. On the deactivation signal, fires StopTrigger
#   When the signal tells who caused it (activated_by_agent_event), calls Trigger(Agent) with that agent (so device settings that act on the "instigator" work as is)
#   A trigger device can be wired to almost any device action in the editor, so this is the universal outlet for driving devices from the Scene Graph
# Placement: attach to an entity in the editor (wherever the signal arrives: the Targets of an interact, a volume, a menu, ...)
# From outside: Fire / FireFor (fire from code)
# Requirements: devices are chosen one at a time (an array of devices cannot be written through MCP). To use several devices, place one of this part on each child entity
device_trigger_component<public> := class<final_super>(component):

    # The trigger device fired on the activation signal
    @editable:
        ToolTip := DeviceTriggersToolTip
        Categories := array{FNDeviceCategory}
    Trigger<public>:?trigger_device = false
    # The trigger device fired on the deactivation signal
    @editable:
        ToolTip := DeviceStopTriggersToolTip
        Categories := array{FNDeviceCategory}
    StopTrigger<public>:?trigger_device = false

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            if (Agent := SceneEvent.FindActivatingAgent[]):
                FireFor(Agent)
            else:
                Fire()
        else if (deactivated_event[SceneEvent], Device := StopTrigger?):
            Device.Trigger()
        false

    # Fires Trigger with no agent
    Fire<public>():void =
        if (Device := Trigger?):
            Device.Trigger()

    # Fires Trigger as caused by Agent
    FireFor<public>(Agent:agent):void =
        if (Device := Trigger?):
            Device.Trigger(Agent)

# Role: every time the trigger device in Trigger fires, sends the activation signal to the Targets entities (activated_by_agent_event when the firing agent is known). The entry point that connects device-side events (buttons, timers, elimination counts, ...) to Scene Graph parts through a trigger device
# Placement: attach to an entity in the editor. When Targets is empty, sends to this entity and its descendants
# Notifies: TriggeredEvent (the firing agent; false when unknown)
# Requirements: devices are chosen one at a time (an array of devices cannot be written through MCP). To use several devices, place one of this part on each child entity
device_event_component<public> := class<final_super>(component):

    # The trigger device that sends the signal when it fires
    @editable:
        ToolTip := DeviceEventTriggersToolTip
        Categories := array{FNDeviceCategory}
    Trigger<public>:?trigger_device = false
    # The entities the activation signal is sent to. When empty, this entity and its descendants
    @editable:
        ToolTip := DeviceEventTargetsToolTip
        Categories := array{FNDeviceCategory}
    Targets<public>:[]entity = array{}

    TriggeredEventInternal<private><final>:event(?agent) = event(?agent){}

    # Fires with the firing agent (false when unknown) every time Trigger fires (Await / Subscribe; cannot be Signaled from outside)
    TriggeredEvent<public><final>:listenable(?agent) = MakeProxyListenable(TriggeredEventInternal)

    var<private> Subscriptions:[]cancelable = array{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Device := Trigger?):
            set Subscriptions = array{Device.TriggeredEvent.Subscribe(OnTriggered)}

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        (super:)OnEndSimulation()

    OnTriggered<private>(MaybeAgent:?agent):void =
        TriggeredEventInternal.Signal(MaybeAgent)
        Receivers := if (Targets.Length > 0) then Targets else array{Entity}
        for (Receiver : Receivers):
            if (Agent := MaybeAgent?):
                Receiver.SendActivatedBy(Agent)
            else:
                Receiver.SendActivated()

# Who is passed to the device when the activation signal is received
device_target_agents<public> := enum:
    # The agent who caused the signal (the Agent of activated_by_agent_event). Does nothing when unknown
    Activator
    # The owner (when placed under a slot, e.g. inside a loadout). The agent who caused the signal when there is none
    Owner
    # Everyone in the zone
    Everyone

# Role: helper used by the parts to decide who is passed from the signal to the device
GetDeviceTargets<internal>(InEntity:entity, SceneEvent:scene_event, Targets:device_target_agents)<transacts>:[]agent =
    case (Targets):
        device_target_agents.Everyone =>
            if (Manager := InEntity.FindScopedComponent[player_manager_component]):
                Everyone:[]agent = for (Slot : Manager.GetSlots()):
                    Slot.Player
                Everyone
            else:
                array{}
        device_target_agents.Owner =>
            if (Owner := InEntity.FindOwningPlayer[]):
                Owners:[]agent = array{Owner}
                Owners
            else if (Agent := SceneEvent.FindActivatingAgent[]):
                array{Agent}
            else:
                array{}
        device_target_agents.Activator =>
            if (Agent := SceneEvent.FindActivatingAgent[]) then array{Agent} else array{}
