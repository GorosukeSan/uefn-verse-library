using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { SceneGraphSystem }

# 同じ人の view どうしで知らせを渡す包み
# 方向：slot の entity から下へ（SendDown）。player_view_set.SendToPlayer で送る
# 受け手：同じ人の slot の下にある view。消費しない
player_event<public> := class(scene_event):
    # 送った view（component）
    Sender<public>:component
    # 渡す知らせ（受けた view はこの中身を見る）
    Event<public>:scene_event

# view を作った component から、その view へ知らせを渡す包み
# 方向：player_view_set が作った view の entity へ（SendDown）。player_view_set.SendToViews で送る
# 受け手：その view。消費しない
player_view_source_event<public> := class(scene_event):
    # view を作った側（player_view_set を持つ component）から渡された知らせ
    Event<public>:scene_event

# player_view_set がだれに view を作ってよいかを決める窓口（Activate の ViewFilter に渡す）
# 実装する側：player_widget_component など、だれに見せてよいかの条件を持つもの
player_view_filter<public> := interface:
    # Agent に view を作ってよいなら成功する
    AllowsView<public>(Agent:agent)<decides><transacts>:void

# 役割：起動しているあいだ、区画の全プレイヤーの slot の下に 1 人分の view（entity）を作り、停止で消す部品。途中参加の人にも作り、退出した人の分は slot ごと世界から外れる（view の component は OnEndSimulation を通る。GetViews などからも除く）
# 使い方：component のフィールドに player_view_set{} を持ち、OnReceive で HandleActivation、OnEndSimulation で Deactivate を呼ぶ（継承はしない）。view は CreateView 関数が作る普通の component
# 前提：区画（または世界）に player_manager_component が 1 つ
player_view_set<public> := class<unique>:

    var<private> Views:[]entity = array{}
    var<private> Active:logic = false
    var<private> CreateView:?type{_(:entity, :player_slot_component):component} = false
    var<private> AddedSubscription:?cancelable = false
    var<private> RemovedSubscription:?cancelable = false
    var<private> Manager:?player_manager_component = false
    var<private> Filter:?player_view_filter = false

    # 起動しているあいだ（Activate から Deactivate まで）成功する
    IsActive<public>()<decides><transacts>:void =
        Active?

    # 今ある view の entity（世界に入っているものだけ。退出した人・HideFor で消した人の分は含まない。並び順は決まっていない）
    GetViews<public>()<transacts>:[]entity =
        for (View : Views, View.GetSimulationEntity[]):
            View

    # Owner の区画の player_manager_component を探し、今いる全員の slot の下に CreateView で view を作り、以後の参加も待つ。もう起動していれば何もしない
    # Everyone が false なら、だれにも作らずに起動だけする（ShowFor で決めた人にだけ作る。途中参加の人にも作らない）
    # ViewFilter を渡すと、ViewFilter が許す人にだけ作る（全員にも、ShowFor でも。許されない人は何もしない）
    # player_manager_component が見つからないと、起動した扱いにはなるが view は作らない（参加も待たない。1 回 Print する）
    # 退出した人の view は、manager の退出の知らせ（PlayerRemovedEvent）で覚えている一覧から除く
    Activate<public>(Owner:entity, MakeView:type{_(:entity, :player_slot_component):component}, ?Everyone:logic = true, ?ViewFilter:?player_view_filter = false):void =
        if (Active?):
            return
        set Active = true
        set CreateView = option{MakeView}
        set Filter = ViewFilter
        set Manager = Owner.ResolveScopedComponent(Manager, player_manager_component)
        if (Found := Manager?):
            set RemovedSubscription = option{Found.PlayerRemovedEvent.Subscribe(OnPlayerRemoved)}
            if (Everyone?):
                set AddedSubscription = option{Found.PlayerAddedEvent.Subscribe(OnPlayerAdded)}
                for (Slot : Found.GetSlots()):
                    Attach(Slot)
        else:
            Print("[player_view_set] player_manager_component が区画（または世界）に見つかりません。view を作りません")

    # 作った view をすべて消し、参加を待つのをやめる。起動していなければ何もしない
    Deactivate<public>():void =
        if (not Active?):
            return
        set Active = false
        AddedSubscription.CancelIfSet()
        set AddedSubscription = false
        RemovedSubscription.CancelIfSet()
        set RemovedSubscription = false
        set Manager = false
        set Filter = false
        for (View : Views):
            View.RemoveFromParent()
        set Views = array{}

    # SceneEvent が activated_event なら Activate、deactivated_event なら Deactivate する。それ以外は何もしない。component の OnReceive から呼ぶ
    HandleActivation<public>(SceneEvent:scene_event, Owner:entity, MakeView:type{_(:entity, :player_slot_component):component}):void =
        if (activated_event[SceneEvent]):
            Activate(Owner, MakeView)
        else if (deactivated_event[SceneEvent]):
            Deactivate()

    # Agent の view があれば返す。起動していない・参加していない・HideFor で消しているときは失敗する
    FindViewFor<public>(Agent:agent)<decides><transacts>:entity =
        first:
            View : GetViews()
            Slot := View.GetParent[].GetComponent[player_slot_component]
            Slot.Player = Agent
        do:
            View

    # Agent の view を消す（その人だけ止める）。起動中なら、ShowFor で作り直せる。view が無ければ何もしない
    HideFor<public>(Agent:agent):void =
        if (View := FindViewFor[Agent]):
            View.RemoveFromParent()
            set Views = GetViews()

    # 起動中で、Agent が参加していて view が無ければ作る（HideFor で消した人を戻す）。それ以外は何もしない
    ShowFor<public>(Agent:agent):void =
        if:
            Active?
            not FindViewFor[Agent]
            Found := Manager?
            Player := player[Agent]
            Slot := Found.FindSlot[Player]
        then:
            Attach(Slot)

    # 今ある view の entity すべてへ、player_view_source_event{Event := SceneEvent} を送る（view は OnReceive で受ける）
    SendToViews<public>(SceneEvent:scene_event):void =
        for (View : GetViews()):
            View.SendDown(player_view_source_event{Event := SceneEvent})

    OnPlayerAdded<private>(Player:player):void =
        if (Active?, Found := Manager?, Slot := Found.FindSlot[Player]):
            Attach(Slot)

    # 退出した人の view を一覧から除く（view の entity は slot ごと世界から外れている）
    OnPlayerRemoved<private>(Player:player):void =
        set Views = for (View : Views, Slot := View.GetParent[].GetComponent[player_slot_component], Slot.Player <> Player):
            View

    Attach<private>(Slot:player_slot_component):void =
        if (MakeView := CreateView?, IsAllowed[Slot.Player]):
            ViewEntity := entity{}
            ViewEntity.AddComponents(array{MakeView(ViewEntity, Slot)})
            Slot.Entity.AddEntities(array{ViewEntity})
            set Views = GetViews() + array{ViewEntity}

    IsAllowed<private>(Agent:agent)<decides><transacts>:void =
        if (Check := Filter?, not Check.AllowsView[Agent]):
            false?

# View（slot の下の view の component）と同じ人の slot の下へ、player_event{Sender := View, Event := SceneEvent} を送る。同じ人のほかの view が OnReceive で受ける
# View が slot の下に無い（親が無い）ときは何もしない
(View:component).SendToPlayer<public>(SceneEvent:scene_event):void =
    if (Slot := View.Entity.GetParent[]):
        Slot.SendDown(player_event{Sender := View, Event := SceneEvent})

# View の entity の親（slot）の player_slot_component を返す。view 以外では失敗する
(View:component).FindViewSlot<public>()<decides><transacts>:player_slot_component =
    View.Entity.GetParent[].GetComponent[player_slot_component]
