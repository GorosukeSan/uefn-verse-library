using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { GridSystem }
using { SceneGraphSystem }

# 方向：spawner の entity から SendDown（spawner 自身と子孫。出したものは spawner の子なので、出したもの自身にも届く）
# 送り手：spawner_component（Spawner）。1 つ出して置いたあと（SpawnedEvent と同じタイミング）
# 受け手：出したものに見た目を足す component など。消費しない
spawned_event<public> := class(scene_event):
    # 出した spawner
    Spawner<public>:spawner_component
    # 出した entity（spawner の子）
    Spawned<public>:entity
    # 出した場所（借りた範囲）
    Area<public>:spawn_area

# 方向：spawner の entity から SendDown（spawner 自身と子孫）
# 送り手：spawner_component（Spawner）。出したものが世界から外れたとき（縮んで消えた・ClearAll・停止。DespawnedEvent と同じタイミング）
# 受け手：数を数える component など。消費しない
despawned_event<public> := class(scene_event):
    # 出した spawner
    Spawner<public>:spawner_component
    # 世界から外れた entity
    Spawned<public>:entity

# 役割：spawner が出したもの 1 つ分の場所。Inner は使ってよい範囲（マス）、Reservation は Inner のまわりに空ける分（GapCells）も含めた借用
# 作り方：spawner_component が作る（外からは作らない）
spawn_area<public> := class:

    # 借りた先のグリッド
    Grid<public>:grid_component
    # 使ってよい範囲（マス）
    Inner<public>:grid_box
    # Inner のまわりの空きも含めた借用。出したものが世界から外れると返る
    Reservation<public>:grid_reservation

    # 使ってよい範囲（Inner）の始まりの角の世界での位置（センチメートル）
    GetMinPosition<public>()<transacts>:vector3 =
        Grid.CellToPosition(Inner.Start)

    # 使ってよい範囲（Inner）の終わりの角の世界での位置（センチメートル）
    GetMaxPosition<public>()<transacts>:vector3 =
        Grid.CellToPosition(Inner.GetEnd())

    # 使ってよい範囲（Inner）の真ん中の世界での位置（センチメートル）
    GetCenter<public>()<transacts>:vector3 =
        (GetMinPosition() + GetMaxPosition()) / 2.0

    # 使ってよい範囲（Inner）の各軸の長さ（センチメートル）
    GetSize<public>()<transacts>:vector3 =
        GetMaxPosition() - GetMinPosition()

    # 範囲の真ん中に、範囲いっぱいの大きさで置く transform（回転なし）。MeshSizeCm はメッシュの大きさ 1 のときの 1 辺（センチメートル。エンジンのキューブなら 100）。0 以下なら大きさ 1
    MakeFitTransform<public>(MeshSizeCm:float)<transacts>:transform =
        Scale := if (MeshSizeCm > 0.0) then GetSize() / MeshSizeCm else vector3{Forward := 1.0, Left := 1.0, Up := 1.0}
        transform:
            Translation := GetCenter()
            Rotation := IdentityRotation()
            Scale := Scale

# 役割：spawner が出した entity に付く目印。spawner はこれが付いた子だけを数える（Leave で消えはじめたものは数えない）。世界から外れるときに借用を返し、spawner に知らせる
# 置き方：実行時に spawner_component が付ける（エディターでは置かない）
spawned_component<public> := class<final_super>(component):

    # 出した spawner
    Spawner<public>:spawner_component
    # 出した場所
    Area<public>:spawn_area

    # Leave で消えはじめたら true（外からは読むだけ）
    var<private> Leaving<public>:logic = false

    # Seconds 秒かけて小さくしてから entity を消す（消えると借用を返す）。すぐ戻り、消えるのを待たない。2 回目以降は何もしない
    Leave<public>(Seconds:float):void =
        if (not Leaving?):
            set Leaving = true
            spawn{ShrinkAndRemove(Seconds)}

    # Leave で消えはじめていれば成功する
    IsLeaving<public>()<decides><reads>:void =
        Leaving?

    ShrinkAndRemove<private>(Seconds:float)<suspends>:void =
        Entity.ShrinkOut(Seconds, TickEvents.PrePhysics)
        Entity.RemoveFromParent()

    OnEndSimulation<override>():void =
        Area.Reservation.Release()
        Spawner.NotifyDespawned(Entity)
        (super:)OnEndSimulation()

AppearMinScale<internal>:float = 0.01

# 大きさを 0 に近い所から今の大きさへ、Seconds 秒かけて変える（位置と向きは毎フレーム今のまま。Tick は持ち主の component の TickEvents.PrePhysics）
# 注意：毎フレーム SetGlobalTransform するので、keyframed_movement_component で動いている entity には使わない（AppearSeconds を 0 にする）
(InEntity:entity).GrowIn<public>(Seconds:float, Tick:listenable(float))<suspends>:void =
    Final := InEntity.GetGlobalTransform().Scale
    InEntity.ScaleTo(Final * AppearMinScale)
    InEntity.AnimateScale(Final * AppearMinScale, Final, Seconds, Tick)

# 大きさを今の大きさから 0 に近い所へ、Seconds 秒かけて変える（Tick は持ち主の component の TickEvents.PrePhysics）
(InEntity:entity).ShrinkOut<public>(Seconds:float, Tick:listenable(float))<suspends>:void =
    Start := InEntity.GetGlobalTransform().Scale
    InEntity.AnimateScale(Start, Start * AppearMinScale, Seconds, Tick)

# 経過時間は Tick の DeltaTime の足し合わせ（フレーム数では数えない）
(InEntity:entity).AnimateScale<internal>(From:vector3, To:vector3, Seconds:float, Tick:listenable(float))<suspends>:void =
    var Elapsed:float = 0.0
    loop:
        set Elapsed += Tick.Await()
        Ratio := if (Seconds > 0.0) then Min(Elapsed / Seconds, 1.0) else 1.0
        Eased := 1.0 - (1.0 - Ratio) * (1.0 - Ratio)
        InEntity.ScaleTo(From + (To - From) * Eased)
        if (Ratio >= 1.0):
            break

(InEntity:entity).ScaleTo<internal>(Scale:vector3):void =
    Current := InEntity.GetGlobalTransform()
    InEntity.SetGlobalTransform(transform{Translation := Current.Translation, Rotation := Current.Rotation, Scale := Scale})
