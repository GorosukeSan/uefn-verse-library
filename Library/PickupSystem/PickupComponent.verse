using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { VolumeSystem }
using { CharacterSystem.SurfaceKit }
using { PickupSystem.TooltipKit }

# 拾った知らせ
# 方向：拾われた物の entity から根へ（SendUp）
# 送り手：pickup_component（Pickup）。受け手：祖先の component（マップの根・ゲームの根など）。消費しない
pickup_picked_event<public> := class(scene_event):
    # 拾われた物（送り元）
    Pickup<public>:pickup_component
    # 拾った人
    Agent<public>:agent
    # 作った効果のプレハブの entity。作れなかった（Effect が空・slot が無い）ときは false
    Effect<public>:?entity

# 役割：拾える人を絞る条件の基底（コードで条件を書くときに派生を作る。中身は CanPick だけ）。pickup_component は同じ entity のこの派生がすべて成功した人だけに拾わせる
#   例：ゲームの「遊んでいる人だけ」。タグで絞るなら Agent.HasPlayerTag[タグ] を書く
# 置き方：エディターで、pickup_component と同じ entity に付ける。派生どうしは 1 entity に 1 つまで（エディターは同じ基底を 2 つ付けられない）
pickup_filter_component<public> := class<abstract><final_super>(component):
    # Agent が Pickup を拾えるなら成功する
    CanPick<public>(Pickup:pickup_component, Agent:agent)<decides><transacts>:void

# 役割：拾える物（オーブ）。触れた人に、効果のプレハブ（Effect）を作って与える（PickupSystem の pickup_effect_component が根にあるプレハブ。その人の slot の下に作られ、持ち主 = 拾った人）
#   拾ったら見た目（この entity と子孫のメッシュ）を消し、RespawnSeconds 秒で戻す（0 なら戻さない。Restore か起動の合図で戻す）
#   触れたことの決め方（どれか。両方あってもよい）：
#     独自キャラクター（CharacterSystem）：同じ entity の character_surface_component（SurfaceKit）に触れた（Touched）
#     Fortnite のキャラクター：同じ entity の player_volume_component（VolumeSystem）に入った
#     コード：TryPickup(Agent)
#   拾える人：RequireGroupMember なら、祖先の一番近い player_group_component（PlayerSystem）の組にいる人だけ（マップを遊んでいる人など）。同じ entity の pickup_filter_component の派生でも絞れる
# 置き方：エディターで、拾える物の entity に付ける（見た目のメッシュと、触れたことを決める部品も同じ entity に）。メッシュは当たり判定なしにする
#   見た目を差し替える：この entity のメッシュを替えるか、Visual に見た目のプレハブを入れる（開始時にこの entity の子に作る）
# いつ：開始から（ActiveOnBegin がオフなら、起動の合図から）。起動の合図で戻し（拾える状態にし）、停止の合図で隠す（拾えない）
# 知らせ：PickedEvent（拾った人）、RestoredEvent、pickup_picked_event（SendUp）
# 外から：TryPickup / Restore / Hide / IsAvailable / CanPick
# 前提：区画か世界に player_manager_component が 1 つ（効果をその人の slot の下に作るため）
pickup_component<public> := class<final_super>(component):

    # 拾った人に与える効果のプレハブ（根に pickup_effect_component）。既定の entity のままだと、既定（10 秒）の空の効果になる
    @editable:
        ToolTip := PickupEffectToolTip
        Categories := array{PickupCategory}
    Effect<public>:concrete_subtype(entity) = entity
    # 拾われてから戻るまでの秒数。0 なら戻さない（1 回だけ。Restore・起動の合図・ゲームのやり直しで戻す）。既定 10
    @editable_number(float):
        ToolTip := PickupRespawnToolTip
        Categories := array{PickupCategory}
        MinValue := option{0.0}
        MaxValue := option{3600.0}
    RespawnSeconds<public>:float = 10.0
    # 見た目のプレハブ。開始時にこの entity の子に作り、拾われたら一緒に消す（この entity のメッシュの代わり・足し）。既定の entity のままなら何も足さない
    @editable:
        ToolTip := PickupVisualToolTip
        Categories := array{PickupCategory}
    Visual<public>:concrete_subtype(entity) = entity
    # オンなら、祖先の一番近い player_group_component の組にいる人だけが拾える（組が無ければだれも拾えない）。既定オフ
    @editable:
        ToolTip := PickupRequireGroupToolTip
        Categories := array{PickupCategory}
    RequireGroupMember<public>:logic = false
    # オンなら、開始から拾える。オフなら、起動の合図まで隠しておく（ステージへの合図で出すオーブなど）。既定オン
    @editable:
        ToolTip := PickupActiveOnBeginToolTip
        Categories := array{PickupCategory}
    ActiveOnBegin<public>:logic = true
    # 表示名（出力ログと、利用者の HUD 用。効果そのものには使わない）。既定 空
    @editable:
        ToolTip := PickupDisplayNameToolTip
        Categories := array{PickupCategory}
    DisplayName<public>:string = ""

    PickedEventInternal<private><final>:event(agent) = event(agent){}
    RestoredEventInternal<private><final>:event(tuple()) = event(tuple()){}

    # 拾われるたびに、拾った人で届く（Await / Subscribe する。外から Signal はできない）
    PickedEvent<public><final>:listenable(agent) = MakeProxyListenable(PickedEventInternal)

    # 拾える状態に戻るたびに届く（時間で戻った・Restore・起動の合図）
    RestoredEvent<public><final>:listenable(tuple()) = MakeProxyListenable(RestoredEventInternal)

    var<private> Available:logic = false
    # 古い「戻す」待ちを無効にするための番号
    var<private> Generation:int = 0
    var<private> VisualEntity:?entity = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        VisualType:concrete_subtype(entity) = Visual
        Made := VisualType{}
        Entity.AddEntities(array{Made})
        Made.SetGlobalTransform(Entity.GetGlobalTransform())
        set VisualEntity = option{Made}

    OnSimulate<override>()<suspends>:void =
        # 同じ entity のメッシュ・触れる箱がそろってから見た目を合わせる
        Sleep(0.0)
        if (ActiveOnBegin?):
            Restore()
        else:
            Hide()

    OnEndSimulation<override>():void =
        set Generation += 1
        set Available = false
        if (Made := VisualEntity?):
            Made.RemoveFromParent()
        set VisualEntity = false
        (super:)OnEndSimulation()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Contact := character_surface_contact_event[SceneEvent]):
            if (Contact.Surface.Entity = Entity, Contact.Contact = character_surface_contact.Touched, Agent := Contact.Agent?):
                TryPickup(Agent)
        else if (Entered := player_volume_entered_event[SceneEvent]):
            if (Entered.Volume.Entity = Entity):
                TryPickup(Entered.Agent)
        else if (activated_event[SceneEvent]):
            Restore()
        else if (deactivated_event[SceneEvent]):
            Hide()
        false

    # Agent に拾わせる：拾える状態で、Agent が拾える人なら、効果を与えて見た目を消し、RespawnSeconds 後に戻す。拾わせたら true
    TryPickup<public>(Agent:agent):logic =
        if (not Available?):
            return false
        if (not CanPick[Agent]):
            return false
        set Available = false
        Show(false)
        MaybeEffect := Entity.GrantPickupEffect(Agent, Effect, Entity.GetGlobalTransform(), option{Entity})
        PickedEventInternal.Signal(Agent)
        Entity.SendUp(pickup_picked_event{Pickup := Self, Agent := Agent, Effect := MaybeEffect})
        set Generation += 1
        if (RespawnSeconds > 0.0):
            spawn{RestoreAfter(Generation)}
        true

    # すぐ拾える状態に戻す（見た目を出す）。戻す待ちは取り消す
    Restore<public>():void =
        set Generation += 1
        set Available = true
        Show(true)
        RestoredEventInternal.Signal(())

    # 隠して拾えなくする（Restore か起動の合図まで）。戻す待ちは取り消す
    Hide<public>():void =
        set Generation += 1
        set Available = false
        Show(false)

    # 今拾えるなら成功する
    IsAvailable<public>()<decides><transacts>:void =
        Available?

    # Agent が拾える人なら成功する（RequireGroupMember の組と、同じ entity の pickup_filter_component の派生すべて）
    CanPick<public>(Agent:agent)<decides><transacts>:void =
        if (RequireGroupMember?):
            Entity.FindAncestorGroup[].IsMember[Agent]
        Refused := for (Each : Entity.GetComponents(), Filter := pickup_filter_component[Each], not Filter.CanPick[Self, Agent]):
            Filter
        Refused.Length = 0

    RestoreAfter<private>(MyGeneration:int)<suspends>:void =
        Sleep(RespawnSeconds)
        if (MyGeneration = Generation):
            Restore()

    # この entity と子孫のメッシュを出す・消す。触れる箱（character_surface_component）も切り替える
    Show<private>(Visible:logic):void =
        for (Mesh : Entity.FindDescendantComponents(mesh_component)):
            ShowMesh(Mesh, Visible)
        for (Each : Entity.GetComponents(), Mesh := mesh_component[Each]):
            ShowMesh(Mesh, Visible)
        if (Surface := Entity.GetComponent[character_surface_component]):
            Surface.SetActive(Visible)

    ShowMesh<private>(Mesh:mesh_component, Visible:logic):void =
        if (Visible?):
            Mesh.Enable()
        else:
            Mesh.Disable()
