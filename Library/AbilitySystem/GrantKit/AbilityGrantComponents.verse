using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }
using { ActivationSystem }
using { ConditionSystem }
using { ItemSystem }
using { SceneGraphSystem }
using { AbilitySystem }
using { AbilitySystem.TooltipKit }

# 役割：区画の全プレイヤー（途中参加も）に、同じ entity の能力すべてを付与する。退出した人からは剥奪する。持ち主のいる entity（CharacterSystem のキャラクターの中など）なら、持ち主にだけ付与する
# いつ：GrantOnBegin が true ならシミュレーション開始から（参加したらすぐ）。false なら起動の合図（activated_event）から停止の合図（deactivated_event）まで
# 置き方：エディターで、能力（ability_component の派生）と同じ entity に付ける
# 前提：区画（または世界）に player_manager_component が 1 つ
ability_grant_players_component<public> := class<final_super>(component):

    # true（既定）ならシミュレーション開始から全員に付与する。false なら起動の合図から停止の合図まで
    @editable:
        ToolTip := AbilityGrantOnBeginToolTip
        Categories := array{AbilityGrantCategory}
    GrantOnBegin<public>:logic = true

    Feed<private>:ability_player_feed = ability_player_feed{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (GrantOnBegin?):
            Feed.Start(Entity)

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Feed.Start(Entity)
        else if (deactivated_event[SceneEvent]):
            Feed.Stop()
        false

    OnEndSimulation<override>():void =
        Feed.Stop()
        (super:)OnEndSimulation()

    # 付与しているあいだ成功する
    IsGranting<public>()<decides><transacts>:void =
        Feed.IsRunning[]

# 役割：アイテムの持ち手（同じ entity の item_holder_component が決める。装備しているあいだ／持っているあいだ）に、同じ entity の能力すべてを付与し、外れたら剥奪する
# 置き方：エディターで、アイテムの entity（item_component・item_holder_component・能力と同じ entity）に付ける
ability_grant_item_component<public> := class<final_super>(component):

    Set<private>:ability_grant_set = ability_grant_set{}
    var Subscriptions<private>:[]cancelable = array{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Holder := Entity.GetComponent[item_holder_component]):
            set Subscriptions = array:
                Holder.HolderAddedEvent.Subscribe(OnHolderAdded)
                Holder.HolderRemovedEvent.Subscribe(OnHolderRemoved)
            if (Current := Holder.FindHolder[]):
                OnHolderAdded(Current)

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        Set.RevokeAll(Entity)
        (super:)OnEndSimulation()

    OnHolderAdded<private>(Agent:agent):void =
        Set.GrantTo(Entity, Agent)

    OnHolderRemoved<private>(Agent:agent):void =
        Set.RevokeFrom(Entity, Agent)

# 役割：条件（直下の子の condition_component の派生）を満たしているあいだ、区画の全プレイヤー（途中参加も）に、同じ entity の能力すべてを付与する。満たさなくなったら剥奪する。持ち主のいる entity なら、持ち主にだけ付与する（キャラクターの中で「しゃがんでいるあいだだけ使える」能力など）
# 置き方：エディターで、能力と同じ entity に付ける
# 子：condition_component の派生を付けた entity を直下に 1 つ（複数の条件は condition_all / condition_any でまとめる）
# 前提：区画（または世界）に player_manager_component が 1 つ
ability_grant_condition_component<public> := class<final_super>(component):

    Feed<private>:ability_player_feed = ability_player_feed{}
    var Subscription<private>:?cancelable = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Condition := Entity.FindChildComponent[condition_component]):
            set Subscription = option{Condition.ChangedEvent.Subscribe(OnConditionChanged)}
            OnConditionChanged(if (Condition.IsSatisfied[]) then true else false)

    OnEndSimulation<override>():void =
        Subscription.CancelIfSet()
        set Subscription = false
        Feed.Stop()
        (super:)OnEndSimulation()

    OnConditionChanged<private>(Satisfied:logic):void =
        if (Satisfied?):
            Feed.Start(Entity)
        else:
            Feed.Stop()

    # 付与しているあいだ（条件を満たしているあいだ）成功する
    IsGranting<public>()<decides><transacts>:void =
        Feed.IsRunning[]
