using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Random }
using { ActivationSystem }
using { SceneGraphSystem }
using { SpawnSystem }
using { SpawnSystem.TooltipKit }

# spawn_prefab_component が直下の spawn_point_component をどの順に使うか
spawn_point_order<public> := enum:
    # Order の小さい順に 1 つずつ使い、最後まで行ったら最初に戻る
    InOrder
    # 毎回ランダムに 1 つ選ぶ
    Random

# 役割：Prefab を出してこの entity の子にし、出したものを数え、まとめて消す。起動の合図で SpawnOnActivate 個を出し、停止の合図で（DespawnOnDeactivate なら）全部消す
# 出す場所：直下の子に spawn_point_component があればその位置と向き（PointOrder の順）、無ければこの entity の位置と向き。そこから ScatterHalfSizeCm の箱の中にランダムにずらす（向きの軸で。0 ならずらさない）。大きさは 1。TrySpawnAt なら好きな場所に出せる
# 数：MaxCount が 0 より大きければ、出ている数がそれに届くとそれ以上出さない
# 置き方：エディターで entity に付ける
# 親：起動の合図が届く場所（ゲームの流れなら、ノードの entity かその子孫）。起動の合図を使わないなら、どこでもよい（コードから Spawn / TrySpawnAt を呼ぶ）
# 子：出す場所の目印（spawn_point_component）。出したもの（prefab_spawned_component が付く）もこの entity の子になる
# 知らせ：出したとき SpawnedEvent、出したものが世界から外れたとき（Despawn・DespawnAll・停止の合図・ほかのコードが消した）DespawnedEvent
# 外から：Spawn / TrySpawnAt / Despawn / DespawnAll、GetSpawned / GetSpawnedCount / GetSpawnPoints / IsFull
spawn_prefab_component<public> := class<final_super>(component):

    # 出す prefab。既定の entity のままだと、何も無い entity を出すだけ
    @editable:
        ToolTip := SpawnPrefabToolTip
        Categories := array{SpawnPrefabCategory}
    Prefab<public>:concrete_subtype(entity) = entity

    # 起動の合図（activated_event）が届くたびに出す数。0 なら起動の合図では出さない（コードから Spawn / TrySpawnAt を呼ぶ）。既定 1
    @editable_number(int):
        ToolTip := SpawnPrefabOnActivateToolTip
        Categories := array{SpawnPrefabCategory}
        MinValue := option{0}
        MaxValue := option{100}
    SpawnOnActivate<public>:int = 1

    # 同時に出しておける数の上限。届いたらそれ以上出さない。0 なら上限なし（既定）
    @editable_number(int):
        ToolTip := SpawnPrefabMaxCountToolTip
        Categories := array{SpawnPrefabCategory}
        MinValue := option{0}
        MaxValue := option{1000}
    MaxCount<public>:int = 0

    # 直下の spawn_point_component をどの順に使うか。既定 InOrder（Order の小さい順に 1 つずつ）
    @editable:
        ToolTip := SpawnPrefabPointOrderToolTip
        Categories := array{SpawnPrefabCategory}
    PointOrder<public>:spawn_point_order = spawn_point_order.InOrder

    # 出す場所（点かこの entity）から、前・左・上それぞれ ± この長さ（センチメートル）の箱の中にランダムにずらす（点の向きの軸で）。0 の軸はずらさない。既定 0
    @editable:
        ToolTip := SpawnPrefabScatterToolTip
        Categories := array{SpawnPrefabCategory}
    ScatterHalfSizeCm<public>:vector3 = vector3{}

    # オンなら停止の合図（deactivated_event）で出したものを全部消す（既定）。オフなら停止の合図では消さない（DespawnAll か、シミュレーションの終わりで消える）
    @editable:
        ToolTip := SpawnPrefabDespawnOnDeactivateToolTip
        Categories := array{SpawnPrefabCategory}
    DespawnOnDeactivate<public>:logic = true

    SpawnedEventInternal<private><final>:event(entity) = event(entity){}

    # 1 つ出して置いたあとに、出した entity で届く（Await / Subscribe する。外から Signal はできない）
    SpawnedEvent<public><final>:listenable(entity) = MakeProxyListenable(SpawnedEventInternal)

    DespawnedEventInternal<private><final>:event(entity) = event(entity){}

    # 出したものが世界から外れたときに、その entity で届く（Despawn・DespawnAll・停止の合図・ほかのコードが消したとき。Await / Subscribe する。外から Signal はできない）
    DespawnedEvent<public><final>:listenable(entity) = MakeProxyListenable(DespawnedEventInternal)

    # PointOrder が InOrder のとき、次に使う点の番号
    var<private> NextPoint:int = 0

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Spawn(SpawnOnActivate)
        else if (deactivated_event[SceneEvent]):
            if (DespawnOnDeactivate?):
                DespawnAll()
        false

    OnEndSimulation<override>():void =
        DespawnAll()
        (super:)OnEndSimulation()

    # 決めた場所（直下の spawn_point_component か、この entity の位置。ScatterHalfSizeCm でずらす）に Count 個出し、出したものを返す。MaxCount に届いたらそこでやめる（返る数は Count より少ない）
    Spawn<public>(Count:int):[]entity =
        var Result:[]entity = array{}
        var Left:int = Count
        loop:
            if (Left <= 0):
                break
            set Left -= 1
            MaybeSpawned := TrySpawnAt(NextTransform())
            if (Spawned := MaybeSpawned?):
                set Result += array{Spawned}
            else:
                break
        Result

    # 世界での位置・向き・大きさを Transform にして 1 つ出し、出したものを返す。MaxCount に届いているときは出さずに false（出すと世界が変わるので <decides> にしない）
    TrySpawnAt<public>(Transform:transform):?entity =
        if (IsFull[]):
            return false
        Spawned := Prefab{}
        Spawned.AddComponents(array{prefab_spawned_component{Entity := Spawned, Source := Self}})
        Entity.AddEntities(array{Spawned})
        Spawned.SetGlobalTransform(Transform)
        SpawnedEventInternal.Signal(Spawned)
        option{Spawned}

    # Spawned がこの component の出したものなら、すぐ消す（DespawnedEvent が届く）。ほかのものなら何もしない
    Despawn<public>(Spawned:entity):void =
        if (Marker := Spawned.GetComponent[prefab_spawned_component], Marker.Source = Self):
            Marker.Remove()

    # 出したものを全部すぐ消す（1 つずつ DespawnedEvent が届く）
    DespawnAll<public>():void =
        for (Marker : GetMarkers()):
            Marker.Remove()

    # 今出ているもの（消しはじめたものは除く）。この entity の直下の子だけを見る。並び順は決まっていない
    GetSpawned<public>()<reads>:[]entity =
        for (Marker : GetMarkers()):
            Marker.Entity

    # 今出ているものの数（GetSpawned の数）
    GetSpawnedCount<public>()<reads>:int =
        GetMarkers().Length

    # MaxCount が 0 より大きく、出ている数がそれに届いていれば成功する
    IsFull<public>()<decides><reads>:void =
        MaxCount > 0
        GetSpawnedCount() >= MaxCount

    # 直下の子の spawn_point_component を Order の小さい順に返す（Order が同じものどうしの順は決まらない）
    GetSpawnPoints<public>()<transacts>:[]spawn_point_component =
        var Sorted:[]spawn_point_component = array{}
        for (Point : Entity.GetChildComponents(spawn_point_component)):
            set Sorted = InsertSpawnPointByOrder(Sorted, Point)
        Sorted

    # prefab_spawned_component が世界から外れるときに呼ぶ
    NotifyDespawned<internal>(Spawned:entity):void =
        DespawnedEventInternal.Signal(Spawned)

    GetMarkers<private>()<reads>:[]prefab_spawned_component =
        for (Marker : Entity.GetChildComponents(prefab_spawned_component), Marker.Source = Self, not Marker.IsLeaving[]):
            Marker

    # 次に出す場所。点があれば PointOrder で選んだ点、無ければこの entity。そこから ScatterHalfSizeCm の箱の中にずらす（向きの軸で）。大きさは 1
    NextTransform<private>()<transacts>:transform =
        Points := GetSpawnPoints()
        Base := if (Point := Points[NextPointIndex(Points.Length)]) then Point.Entity.GetGlobalTransform() else Entity.GetGlobalTransform()
        Offset := vector3:
            Forward := RandomWithin(ScatterHalfSizeCm.Forward)
            Left := RandomWithin(ScatterHalfSizeCm.Left)
            Up := RandomWithin(ScatterHalfSizeCm.Up)
        transform:
            Translation := Base.Translation + Offset * Base.Rotation
            Rotation := Base.Rotation
            Scale := vector3{Forward := 1.0, Left := 1.0, Up := 1.0}

    # 使う点の番号（点が無ければ -1）。InOrder なら 1 つずつ進める
    NextPointIndex<private>(Count:int)<transacts>:int =
        if (Count <= 0):
            -1
        else if (PointOrder = spawn_point_order.Random):
            GetRandomInt(0, Count - 1)
        else:
            Index := Mod[NextPoint, Count] or 0
            set NextPoint = Index + 1
            Index

    RandomWithin<private>(Half:float)<transacts>:float =
        if (Half > 0.0) then GetRandomFloat(-Half, Half) else 0.0

# 役割：spawn_prefab_component が出した entity に付く目印。spawn_prefab_component はこれが付いた直下の子だけを数える（消しはじめたものは数えない）。世界から外れるときに出した component へ知らせる
# 置き方：実行時に spawn_prefab_component が付ける（エディターでは置かない）
prefab_spawned_component<public> := class<final_super>(component):

    # 出した spawn_prefab_component
    Source<public>:spawn_prefab_component

    var<private> Leaving:logic = false

    # 消しはじめていれば成功する
    IsLeaving<public>()<decides><reads>:void =
        Leaving?

    # 消しはじめた印を付けてから、世界から外す（同じフレームで数えなおしても数に入らないように）
    Remove<internal>():void =
        if (not Leaving?):
            set Leaving = true
            Entity.RemoveFromParent()

    OnEndSimulation<override>():void =
        Source.NotifyDespawned(Entity)
        (super:)OnEndSimulation()

InsertSpawnPointByOrder<internal>(Sorted:[]spawn_point_component, Item:spawn_point_component)<reads>:[]spawn_point_component =
    Index := FindSpawnPointInsertIndex[Sorted, Item.Order] or Sorted.Length
    Before := for (I -> Current : Sorted, I < Index):
        Current
    After := for (I -> Current : Sorted, I >= Index):
        Current
    Before + array{Item} + After

FindSpawnPointInsertIndex<internal>(Sorted:[]spawn_point_component, Order:int)<decides><reads>:int =
    first (I -> Current : Sorted, Current.Order > Order):
        I
