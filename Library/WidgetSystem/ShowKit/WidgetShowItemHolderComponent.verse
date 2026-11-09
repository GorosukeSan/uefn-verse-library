using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ItemSystem }
using { SceneGraphSystem }
using { WidgetSystem }

# 役割：アイテムの持ち手（同じ entity の item_holder_component が決める。持っている／装備している）が付いているあいだ、同じ entity の player_widget_component（すべて）をその人に出し、外れたら消す
#   アイテムの HUD（残り回数・ゲージなど）を持ち主にだけ出すときに使う。アイテムの entity に届いた知らせを表示に渡すなら、widget 側の ForwardReceivedEvents をオンにする
# 置き方：エディターで、アイテムの entity に付ける
# 同じ entity：item_component、item_holder_component、player_widget_component の派生（Audience = Chosen にする）
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
