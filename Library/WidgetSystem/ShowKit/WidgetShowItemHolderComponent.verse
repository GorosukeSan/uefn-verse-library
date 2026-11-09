using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ItemSystem }
using { SceneGraphSystem }
using { WidgetSystem }

# Role: while the item has a holder (decided by the item_holder_component on the same entity: holding / equipped), shows every player_widget_component on the same entity to that person, and hides when the holder is removed
#   Used to show an item's HUD (remaining uses, gauge, etc.) only to its owner. To pass notifications that reach the item's entity to the display, turn on ForwardReceivedEvents on the widget
# Placement: in the editor, attach to the item's entity
# Same entity: item_component, item_holder_component, a player_widget_component subclass (set Audience = Chosen)
widget_show_item_holder_component<public> := class<final_super>(component):

    var<private> Subscriptions:[]cancelable = array{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Holder := Entity.GetComponent[item_holder_component]):
            set Subscriptions = array:
                Holder.HolderAddedEvent.Subscribe(OnAdded)
                Holder.HolderRemovedEvent.Subscribe(OnRemoved)
            if (Current := Holder.FindHolder[]):
                OnAdded(Current)

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        (super:)OnEndSimulation()

    OnAdded<private>(Agent:agent):void =
        for (Widget : Entity.GetPlayerWidgets()):
            Widget.ShowFor(Agent)

    OnRemoved<private>(Agent:agent):void =
        for (Widget : Entity.GetPlayerWidgets()):
            Widget.HideFor(Agent)
