using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Verse.org/Input/UI }
using { AbilitySystem }
using { AbilitySystem.GrantKit }
using { ActivationSystem }
using { GravitySystem }
using { HoverSystem }
using { InputSystem }
using { JetpackSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { SwingSystem }

# 役割：AbilitySystem の見本。自分で能力は置かず、同じ entity にある能力（ability_component の派生）と付与の component を開始時に Print で一覧し、各能力の GrantedEvent / RevokedEvent を Print する。動いているあいだ、各プレイヤーは ToggleAction（既定 E / RB）を押すと、この entity の能力すべてについて自分への付与を切り替えられる（付与されていれば Revoke、されていなければ Grant）
# 置き方：エディターで、能力の component（swing_ability_component・jetpack_ability_component・hover_ability_component・gravity_point_ability_component など）を 1 つ以上付けた entity に付ける。付与の component（ability_grant_players_component など）は付けても付けなくてもよい。区画（または世界）に player_manager_component を 1 つ置く
# 試し方：セッションを始めると出力ログに「能力: n 個」「付与: …」と出る。ToggleAction を押すと「Grant」「Revoke」と、能力の GrantedEvent / RevokedEvent の Print が交互に出る。ability_grant_players_component（GrantOnBegin）を一緒に置くと、最初から付与されているので 1 回目の押下で Revoke になる（付与の回数が 1 → 0）
# いつ：StartOnBegin が true ならシミュレーション開始から。false なら起動の合図（activated_event）から停止の合図（deactivated_event）まで
# 前提・注意：Revoke は付与の回数を 1 減らすだけなので、複数の付与元から付与されているときは 1 回では止まらない（ability_component の説明）。ToggleMapping は停止時に外す（RemoveMappingOnStop）。キャラクター操作の Mapping を ToggleMapping に選ぶなら RemoveMappingOnStop をオフにする（外すと動けなくなる）
ability_sample_component<public> := class<final_super>(component):

    # オンなら、シミュレーション開始から始める。オフなら起動の合図を待つ
    @editable
    StartOnBegin<public>:logic = true

    # 付与を切り替える入力（ToggleMapping に含まれているものを選ぶ）
    @editable
    ToggleAction<public>:input_action(logic) = NextTab

    # 動いているあいだ各プレイヤーに足すキー割り当て
    @editable
    ToggleMapping<public>:input_mapping = MenuNavigationMapping

    # オンなら、止まるときに ToggleMapping を外す。キャラクター操作の Mapping を選んだときはオフにする
    @editable
    RemoveMappingOnStop<public>:logic = true

    Views<private>:player_view_set = player_view_set{}
    var<private> Subscriptions:[]cancelable = array{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Describe()
        for (Ability : Entity.GetAbilities()):
            set Subscriptions += array:
                Ability.GrantedEvent.Subscribe(OnGranted)
                Ability.RevokedEvent.Subscribe(OnRevoked)
        if (StartOnBegin?):
            Activate()

    OnReceive<override>(SceneEvent:scene_event):logic =
        Views.HandleActivation(SceneEvent, Entity, CreateView)
        false

    OnEndSimulation<override>():void =
        Views.Deactivate()
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        (super:)OnEndSimulation()

    # 全員（途中参加も）の切り替え入力を受け付ける。もう受け付けていれば何もしない
    Activate<public>():void =
        Views.Activate(Entity, CreateView)

    # 受け付けをやめる
    Deactivate<public>():void =
        Views.Deactivate()

    # 動いているあいだ成功する
    IsActive<public>()<decides><transacts>:void =
        Views.IsActive[]

    # Agent について、この entity の能力すべての付与を切り替える（view から呼ばれる）
    Toggle<internal>(Agent:agent):void =
        Abilities := Entity.GetAbilities()
        if (Abilities.Length = 0):
            Print("[ability_sample] この entity に能力（ability_component の派生）がありません", ?Duration := 4.0)
            return
        for (Ability : Abilities):
            Label := DescribeAbility(Ability)
            if (Ability.IsGranted[Agent]):
                Print("[ability_sample] Revoke: {Label}", ?Duration := 4.0)
                Ability.Revoke(Agent)
            else:
                Print("[ability_sample] Grant: {Label}", ?Duration := 4.0)
                Ability.Grant(Agent)

    # 同じ entity の能力と付与の component を Print する
    Describe<private>():void =
        Abilities := Entity.GetAbilities()
        Print("[ability_sample] 能力: {Abilities.Length} 個", ?Duration := 8.0)
        for (Ability : Abilities):
            Print("[ability_sample]   - {DescribeAbility(Ability)}", ?Duration := 8.0)
        var GrantCount:int = 0
        if (Grant := Entity.GetComponent[ability_grant_players_component]):
            set GrantCount += 1
            OnBegin := if (Grant.GrantOnBegin?) then "オン" else "オフ"
            Print("[ability_sample] 付与: ability_grant_players_component（全員に。GrantOnBegin は {OnBegin}）", ?Duration := 8.0)
        if (Entity.GetComponent[ability_grant_item_component]):
            set GrantCount += 1
            Print("[ability_sample] 付与: ability_grant_item_component（アイテムの持ち手に）", ?Duration := 8.0)
        if (Entity.GetComponent[ability_grant_condition_component]):
            set GrantCount += 1
            Print("[ability_sample] 付与: ability_grant_condition_component（子の条件を満たすあいだ）", ?Duration := 8.0)
        if (GrantCount = 0):
            Print("[ability_sample] 付与: なし（ToggleAction を押すとコードから Grant / Revoke します）", ?Duration := 8.0)

    # 能力の種類を人が読める名前にする（Library の能力は名前で、ほかは「その他」）
    DescribeAbility<private>(Ability:ability_component)<transacts>:string =
        if (swing_ability_component[Ability]):
            "swing_ability_component（スイング）"
        else if (jetpack_ability_component[Ability]):
            "jetpack_ability_component（ジェットパック）"
        else if (hover_ability_component[Ability]):
            "hover_ability_component（ホバー）"
        else if (gravity_point_ability_component[Ability]):
            "gravity_point_ability_component（重力点）"
        else:
            "ability_component の派生（その他）"

    OnGranted<private>(Agent:agent):void =
        Print("[ability_sample] GrantedEvent: 付与されました（付与中 {GrantedCount()} 人）", ?Duration := 4.0)

    OnRevoked<private>(Agent:agent):void =
        Print("[ability_sample] RevokedEvent: 剥奪されました（付与中 {GrantedCount()} 人）", ?Duration := 4.0)

    # いずれかの能力が付与されている人数（能力ごとの合計ではなく、最初の能力の人数）
    GrantedCount<private>()<transacts>:int =
        if (First := Entity.GetAbilities()[0]) then First.GetGrantedAgents().Length else 0

    CreateView<private>(ViewEntity:entity, Slot:player_slot_component):component =
        ability_sample_view_component{Entity := ViewEntity, Source := Self, Player := Slot.Player}

# 役割：1 人分の切り替え入力。ToggleMapping を足し、ToggleAction が押されるたびに Source.Toggle を呼ぶ
# 置き方：実行時に ability_sample_component が作る（エディターでは置かない）
ability_sample_view_component<public> := class<final_super>(component):

    Source<public>:ability_sample_component
    Player<public>:player

    OnSimulate<override>()<suspends>:void =
        if (PlayerInput := Player.FindPlayerInput[]):
            Print("[ability_sample] 付与を切り替えるキー（既定 E / RB）を押してください", ?Duration := 6.0)
            race:
                PlayerInput.HoldInputMapping(Source.ToggleMapping, Source.RemoveMappingOnStop)
                loop:
                    PlayerInput.AwaitPressed(Source.ToggleAction)
                    Source.Toggle(Player)
        else:
            Print("[ability_sample] この人の入力（player_input）が取れません")
