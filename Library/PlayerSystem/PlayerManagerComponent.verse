using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SceneGraphSystem }

# Notification that a player joined and a slot was created
# Direction: the whole scope (SendScoped; the whole world if there is no scope)
# Sender: player_manager_component. Receivers: components that look at the player count or slots (player count conditions etc.). Not consumed
# Requirements: the slot is created before this notification (FindSlot succeeds on the receiving side)
player_added_event<public> := class(scene_event):
    # The player_manager_component that sent it
    Manager<public>:player_manager_component
    # The player who joined (a player; cast back with player[Agent] to look up the slot)
    Agent<public>:agent

# Notification that a player left and the slot was removed
# Direction: the whole scope (SendScoped; the whole world if there is no scope)
# Sender: player_manager_component. Receivers: components that look at the player count or slots. Not consumed
# Requirements: the slot is removed before this notification (FindSlot fails on the receiving side)
player_removed_event<public> := class(scene_event):
    # The player_manager_component that sent it
    Manager<public>:player_manager_component
    # The player who left
    Agent<public>:agent

# Role: creates a slot entity as a child for every player who joins and removes it when they leave. Notifies everyone of joins and leaves
# Placement: attach to an entity in the editor. One per scope (or world) (other parts find it with FindScopedComponent)
# Notifies: sends player_added_event on join and player_removed_event on leave to the whole scope. Code of entities created at runtime can Await / Subscribe PlayerAddedEvent / PlayerRemovedEvent, which are Signaled at the same time
# Requirements / Notes: slots of players already present when the simulation starts are created inside this component's OnBeginSimulation, and the notifications at that time (both scene event and event) do not reach anyone not yet subscribed. Code that subscribes later should first look at who is present with GetSlots, then wait for PlayerAddedEvent
player_manager_component<public> := class<final_super>(component):

    PlayerAddedEventInternal<private><final>:event(player) = event(player){}
    PlayerRemovedEventInternal<private><final>:event(player) = event(player){}

    # Delivered with the player after they join and the slot is created (Await / Subscribe to it; it cannot be Signaled from outside)
    PlayerAddedEvent<public><final>:listenable(player) = MakeProxyListenable(PlayerAddedEventInternal)

    # Delivered with the player after they leave and the slot is removed (Await / Subscribe to it; it cannot be Signaled from outside)
    PlayerRemovedEvent<public><final>:listenable(player) = MakeProxyListenable(PlayerRemovedEventInternal)

    var PlayerSubscription<private>:?cancelable = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set PlayerSubscription = Entity.SubscribePlayers(OnPlayerAdded, OnPlayerRemoved)

    OnEndSimulation<override>():void =
        PlayerSubscription.CancelIfSet()
        set PlayerSubscription = false
        (super:)OnEndSimulation()

    # Number of current slots (the number of direct-child player_slot_components). 0 before joins are processed (before OnBeginSimulation)
    GetPlayerCount<public>()<reads>:int =
        Entity.GetChildComponents(player_slot_component).Length

    # Slots of everyone present (direct-child player_slot_components; order is undefined). Empty before joins are processed
    GetSlots<public>()<reads>:[]player_slot_component =
        Entity.GetChildComponents(player_slot_component)

    # Finds Player's slot. Slots are created at runtime, so this fails before that player's join is processed (before player_added_event / PlayerAddedEvent) and after they leave
    FindSlot<public>(Player:player)<decides><reads>:player_slot_component =
        first:
            Slot : Entity.GetChildComponents(player_slot_component)
            Slot.Player = Player
        do:
            Slot

    OnPlayerAdded<private>(Player:player):void =
        if (FindSlot[Player]):
            return
        SlotEntity := entity{}
        SlotEntity.AddComponents(array{player_slot_component{Entity := SlotEntity, Player := Player}})
        Entity.AddEntities(array{SlotEntity})
        Entity.SendScoped(player_added_event{Manager := Self, Agent := Player})
        PlayerAddedEventInternal.Signal(Player)

    OnPlayerRemoved<private>(Player:player):void =
        if (Slot := FindSlot[Player]):
            Slot.Entity.RemoveFromParent()
            Entity.SendScoped(player_removed_event{Manager := Self, Agent := Player})
            PlayerRemovedEventInternal.Signal(Player)
