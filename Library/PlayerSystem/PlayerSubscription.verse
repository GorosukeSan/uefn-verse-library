using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Playspaces }
using { SceneGraphSystem }

# Role: calls OnAdded when a player joins and OnRemoved when one leaves the playspace InEntity is in (no listener interface to implement; pass methods directly). Cancel the return value to stop (Cancel it in OnEndSimulation)
# Requirements / Notes:
#   - For players already present, OnAdded is called one by one inside this function (before it returns). The caller must be ready to receive at that point
#   - If InEntity's playspace cannot be obtained (an entity not in the scene, etc.), returns false and calls nothing
#   - If you only want one slot per world, use player_manager_component (PlayerAddedEvent / GetSlots / FindSlot) instead of this
(InEntity:entity).SubscribePlayers<public>(OnAdded:type{_(:player):void}, OnRemoved:type{_(:player):void}):?cancelable =
    if (Playspace := InEntity.GetPlayspaceForEntity[]):
        # Passing the argument function straight to Subscribe gives V3502 in UEFN, so wrap it in a method
        AddedSubscription := Playspace.PlayerAddedEvent().Subscribe(player_callback_relay{Callback := OnAdded}.Invoke)
        RemovedSubscription := Playspace.PlayerRemovedEvent().Subscribe(player_callback_relay{Callback := OnRemoved}.Invoke)
        for (Player : Playspace.GetPlayers()):
            OnAdded(Player)
        option{cancelable_group{Cancelables := array{AddedSubscription, RemovedSubscription}}}
    else:
        false

# Wrapper to pass a function to a listenable's Subscribe (passing a function received as an argument directly gives V3502 in the UEFN build)
player_callback_relay<internal> := class<internal>:
    Callback<internal>:type{_(:player):void}

    Invoke<internal>(Player:player):void =
        Callback(Player)
