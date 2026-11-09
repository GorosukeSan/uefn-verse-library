using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { LoadoutSystem.TooltipKit }

# Notification that a loadout was applied or removed
# Direction: the whole scope (SendScoped; the whole world when there is no scope)
# Sender: loadout_component (Loadout). Receivers: parts that count loadout choices, your components. Not consumed
loadout_changed_event<public> := class(scene_event):
    # The component that sent it
    Loadout<public>:loadout_component
    # The agent it was applied to / removed from
    Agent<public>:agent
    # true when applied, false when removed
    Applied<public>:logic

# Role: builds one player's loadout (a prefab holding abilities, energy, HUD, attachments, motion reactions, ...) per player and places it under that player's slot. Removing it deletes the instance
#   The parts inside the prefab affect only the owner (ability grants, widgets, player_attach_component, item_grant_component and hud_hide_component narrow to the owner through FindOwningPlayer). Lets you attach abilities, looks and HUD to a player as a bundle of parts, with no code (a CharacterSystem custom loadout can go in the prefab as well)
#   On the frame after creation, the activate signal (activated_event) is sent to the loadout entity and its descendants (parts that wait for activation start). On removal the deactivate signal is sent before deletion
#   Only one instance per player (calling ApplyTo repeatedly still gives one). When Group is not empty, other loadouts of the same Group are removed from that player before applying (job / class switching)
# Placement: attach to an entity in the editor (anywhere inside the scope)
# When: with ApplyToEveryone, everyone on activation (late joiners too). When off, decided by ApplyTo / RemoveFrom (from choice_menu_component Targets, a volume entrance, ...)
#   Activation: from the start with ActiveOnBegin, otherwise from the activate signal (activated_event) or Activate. The deactivate signal (deactivated_event) or Deactivate removes it from everyone
#   When ApplyToEveryone is off and an activate signal that knows who triggered it arrives (activated_by_agent_event: volume entrance, interact, choice menu Targets, ...), it is applied to that agent ("apply to whoever enters / presses" with no code)
# Notifies: on apply / remove, loadout_changed_event to the whole scope and AppliedEvent / RemovedEvent
# From outside: Activate / Deactivate / ApplyTo / RemoveFrom / RemoveFromAll / IsAppliedTo / FindInstance / GetAppliedAgents
# Requirements: one player_manager_component in the scope (or the world), because the instance is placed under the slot
loadout_component<public> := class<final_super>(component):

    # Prefab of one player's loadout. Put parts such as abilities, energy and HUD inside it
    @editable:
        ToolTip := LoadoutPrefabToolTip
        Categories := array{LoadoutCategory}
    Prefab<public>:concrete_subtype(entity) = entity
    # When on, applied to everyone on activation (late joiners too). Default on
    @editable:
        ToolTip := LoadoutEveryoneToolTip
        Categories := array{LoadoutCategory}
    ApplyToEveryone<public>:logic = true
    # When on, applied from the start of the game. Default off
    @editable:
        ToolTip := LoadoutActiveOnBeginToolTip
        Categories := array{LoadoutCategory}
    ActiveOnBegin<public>:logic = false
    # Exclusive group. When not empty, other loadouts of the same group are removed from the player before applying (one job per player, ...). Default empty
    @editable:
        ToolTip := LoadoutGroupToolTip
        Categories := array{LoadoutCategory}
    Group<public>:string = ""

    AppliedEventInternal<private><final>:event(tuple(agent, entity)) = event(tuple(agent, entity)){}
    RemovedEventInternal<private><final>:event(agent) = event(agent){}

    # Fires with (the agent, the loadout entity) when applied (Await / Subscribe; cannot be Signaled from outside)
    AppliedEvent<public><final>:listenable(tuple(agent, entity)) = MakeProxyListenable(AppliedEventInternal)

    # Fires with the agent when removed
    RemovedEvent<public><final>:listenable(agent) = MakeProxyListenable(RemovedEventInternal)

    var<private> Active:logic = false
    var<private> Instances:[agent]entity = map{}
    var<private> Manager:?player_manager_component = false
    var<private> Subscriptions:[]cancelable = array{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (ActiveOnBegin?):
            Activate()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            # Not applying to everyone, and the signal knows who triggered it (entered a volume, pressed a button, ...): apply to that agent
            if (not ApplyToEveryone?, Agent := SceneEvent.FindActivatingAgent[]):
                ApplyTo(Agent)
            else:
                Activate()
        else if (deactivated_event[SceneEvent]):
            Deactivate()
        false

    OnEndSimulation<override>():void =
        Deactivate()
        (super:)OnEndSimulation()

    # Start applying (with ApplyToEveryone: everyone present now and everyone who joins later). Does nothing when already active
    Activate<public>():void =
        if (Active?):
            return
        set Active = true
        set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)
        if (Found := Manager?):
            set Subscriptions = array{Found.PlayerRemovedEvent.Subscribe(OnPlayerRemoved)}
            if (ApplyToEveryone?):
                set Subscriptions += array{Found.PlayerAddedEvent.Subscribe(OnPlayerAdded)}
                for (Slot : Found.GetSlots()):
                    ApplyTo(Slot.Player)
        else:
            Print("[loadout_component] player_manager_component not found; the loadout cannot be applied")

    # Remove from everyone and stop applying. Does nothing when not active
    Deactivate<public>():void =
        if (not Active?):
            return
        set Active = false
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        RemoveFromAll()
        set Manager = false

    # Apply the loadout to Agent (does nothing when already applied). Activates first when not active. Removes other loadouts of the same Group. false when it could not be applied (agent not joined)
    ApplyTo<public>(Agent:agent):logic =
        if (not Active?):
            Activate()
        if (Instances[Agent]):
            return true
        if (Player := player[Agent], Found := Manager?, Slot := Found.FindSlot[Player]):
            RemoveSameGroup(Slot, Agent)
            Instance := Prefab{}
            Instance.AddComponents(array{loadout_instance_component{Entity := Instance, Source := Self, Player := Player}})
            Slot.Entity.AddEntities(array{Instance})
            if (set Instances[Agent] = Instance) {}
            Entity.SendScoped(loadout_changed_event{Loadout := Self, Agent := Agent, Applied := true})
            AppliedEventInternal.Signal((Agent, Instance))
            return true
        false

    # Remove the loadout from Agent (sends the deactivate signal, then deletes). Does nothing when not applied
    RemoveFrom<public>(Agent:agent):void =
        if (Instance := Instances[Agent]):
            set Instances = Instances.RemoveKey(Agent)
            Instance.SendDeactivated()
            Instance.RemoveFromParent()
            Entity.SendScoped(loadout_changed_event{Loadout := Self, Agent := Agent, Applied := false})
            RemovedEventInternal.Signal(Agent)

    # Remove from everyone
    RemoveFromAll<public>():void =
        for (Agent -> Instance : Instances):
            RemoveFrom(Agent)

    # Succeeds when applied to Agent
    IsAppliedTo<public>(Agent:agent)<decides><transacts>:void =
        Instances[Agent]

    # The loadout entity applied to Agent. Fails when not applied
    FindInstance<public>(Agent:agent)<decides><transacts>:entity =
        Instances[Agent]

    # The agents the loadout is currently applied to (order unspecified)
    GetAppliedAgents<public>()<transacts>:[]agent =
        for (Agent -> Instance : Instances):
            Agent

    OnPlayerAdded<private>(Player:player):void =
        if (Active?, ApplyToEveryone?):
            ApplyTo(Player)

    OnPlayerRemoved<private>(Player:player):void =
        RemoveFrom(Player)

    # Remove other loadouts of the same Group that sit under the same player's slot
    RemoveSameGroup<private>(Slot:player_slot_component, Agent:agent):void =
        if (Group <> ""):
            for (Child : Slot.Entity.GetEntities(), Other := Child.GetComponent[loadout_instance_component], Other.Source <> Self, Other.Source.Group = Group):
                Other.Source.RemoveFrom(Agent)

# Role: marker on the root of a loadout (the prefab created by loadout_component). Holds whose loadout it is and which loadout_component created it, and sends the activate signal to its descendants on the frame after creation
# Placement: attached at runtime by loadout_component (never placed in the editor)
loadout_instance_component<public> := class<final_super><internal>(component):
    # The loadout_component that created it
    Source<public>:loadout_component
    # The owner
    Player<public>:player

    OnSimulate<override>()<suspends>:void =
        # Wait one frame so that every part of the prefab has finished OnBeginSimulation before the signal arrives
        TickEvents.PrePhysics.Await()
        Entity.SendActivated()

# The loadout (loadout_instance_component) of InEntity or one of its ancestors. Fails when not inside a loadout
(InEntity:entity).FindLoadoutInstance<public>()<decides><transacts>:loadout_instance_component =
    var Current:entity = InEntity
    var Found:?loadout_instance_component = false
    loop:
        if (Instance := Current.GetComponent[loadout_instance_component]):
            set Found = option{Instance}
            break
        if (Parent := Current.GetParent[]):
            set Current = Parent
        else:
            break
    Found?
