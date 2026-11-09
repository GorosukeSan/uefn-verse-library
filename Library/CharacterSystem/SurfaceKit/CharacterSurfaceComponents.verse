using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { /Verse.org/SpatialMath }
using { SceneGraphSystem }
using { CharacterSystem }
using { CharacterSystem.TooltipKit }

# 独自キャラクターと面（character_surface_component）の触れ方
character_surface_contact<public> := enum:
    # 触れ始めた（体の箱と面の箱が TouchMarginCm の余白込みで重なった）
    Touched
    # 離れた（重ならなくなった・面が無効になった・探す範囲から外れた）
    Untouched
    # 上に乗った（接地していて、足元が面の上面にある）
    SteppedOn
    # 上から降りた
    SteppedOff

# 面の箱（世界の軸にそろえた直方体。cm）。回転した面は、回転したあとの箱を囲む直方体になる
character_surface_box<public> := struct<computes>:
    # 小さい側の角（世界の位置、cm）
    MinCm<public>:vector3 = vector3{}
    # 大きい側の角（世界の位置、cm）
    MaxCm<public>:vector3 = vector3{}

# 面に触れた・乗った知らせ。方向：面の entity から根へ（SendUp）
# 送り手：character_touch_component（同じ知らせを Surface の ContactEvent にも届ける）。受け手：面の entity と祖先の component（マップの根・ギミック）。消費しない
character_surface_contact_event<public> := class(scene_event):
    # 触れられた面（知らせの送り元の entity に付いている）
    Surface<public>:character_surface_component
    # 触れた独自キャラクターの体
    Motor<public>:character_motor_component
    # 体の持ち主。持ち主のいない体なら false
    Agent<public>:?agent
    # 触れ方
    Contact<public>:character_surface_contact

# 独自キャラクターが触れられる面の目印のタグ。character_surface_component が開始時にこの entity に付け、止まると外す（character_touch_component はこのタグで面を探す）
character_surface_tag<public> := class(tag):

# 役割：独自キャラクター（CharacterSystem）が「触れた・乗った」を知れる面（箱）。entity の位置・回転・大きさから箱を決める
#   独自キャラクターは自前のカプセルで動くので、メッシュの重なりの知らせ（EntityEnteredEvent）が来ない。この component が箱を持ち、キャラクターの側の character_touch_component が毎フレーム箱と体を比べる
#   箱の大きさ：SizeCm がすべて 0 より大きければそれ（entity の大きさは見ない）。そうでなければ entity の大きさ（Scale）× MeshSizeCm（100 cm の立方体のメッシュなら 100）。PivotAtBottom なら entity の位置を箱の底面の真ん中、オフなら箱の真ん中とする
# 置き方：エディターで、足場・壁・ギミックの entity（当たり判定のあるメッシュと同じ entity）に付ける。触れるだけの物（ゴールの結晶など）は当たり判定の無いメッシュでもよい
# いつ：開始から止まるまで。SetActive(false) のあいだは触れない（消える足場など）
# 知らせ：ContactEvent（触れ始めた・離れた・乗った・降りた）と character_surface_contact_event（SendUp）。送るのは character_touch_component
# タグ：この entity に character_surface_tag を付ける
# 外から：GetBox / SetActive / IsActive
# 前提・注意：動く面（MoverSystem）も、毎フレームの位置で比べる。⚠ 未検証：keyframed_movement_component で動かしている entity の GetGlobalTransform が、毎フレーム動いた位置を返すか
character_surface_component<public> := class<final_super>(component):

    # 箱の大きさ（cm。前後・左右・上下）。すべて 0 より大きければこれを使う（entity の大きさは見ない）。既定 0（entity の大きさ × MeshSizeCm）
    @editable:
        ToolTip := SurfaceSizeToolTip
        Categories := array{CharacterSurfaceCategory}
    SizeCm<public>:vector3 = vector3{}
    # 大きさ 1 のときのメッシュの一辺（cm）。SizeCm を使わないとき、entity の大きさに掛ける。既定 100
    @editable_number(float):
        ToolTip := SurfaceMeshSizeToolTip
        Categories := array{CharacterSurfaceCategory}
        MinValue := option{1.0}
        MaxValue := option{100000.0}
    MeshSizeCm<public>:float = 100.0
    # オンなら entity の位置を箱の底面の真ん中とする（底が原点のメッシュ）。オフなら箱の真ん中。既定オン
    @editable:
        ToolTip := SurfacePivotAtBottomToolTip
        Categories := array{CharacterSurfaceCategory}
    PivotAtBottom<public>:logic = true

    ContactEventInternal<private><final>:event(tuple(character_motor_component, character_surface_contact)) = event(tuple(character_motor_component, character_surface_contact)){}

    # 独自キャラクターが触れ始めた・離れた・乗った・降りたときに、（その体, 触れ方）で届く（Await / Subscribe する。外から Signal はできない）
    ContactEvent<public><final>:listenable(tuple(character_motor_component, character_surface_contact)) = MakeProxyListenable(ContactEventInternal)

    var<private> Active:logic = true
    var<private> TagKey:?tag_key = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set TagKey = option{Entity.AddTag(character_surface_tag{})}

    OnEndSimulation<override>():void =
        if (Key := TagKey?, Entity.RemoveTag[Key]) {}
        set TagKey = false
        (super:)OnEndSimulation()

    # 今の箱（世界の位置、cm）。毎回 entity の位置から計算する
    GetBox<public>()<transacts>:character_surface_box =
        Transform := Entity.GetGlobalTransform()
        Size := GetLocalSizeCm(Transform.Scale)
        Half := Size / 2.0
        Rotation := Transform.Rotation
        AxisForward := Rotation.GetForwardAxis()
        AxisLeft := Rotation.GetLeftAxis()
        AxisUp := Rotation.GetUpAxis()
        Center := if (PivotAtBottom?) then Transform.Translation + AxisUp * Half.Up else Transform.Translation
        Extent := vector3:
            Forward := Abs(AxisForward.Forward) * Half.Forward + Abs(AxisLeft.Forward) * Half.Left + Abs(AxisUp.Forward) * Half.Up
            Left := Abs(AxisForward.Left) * Half.Forward + Abs(AxisLeft.Left) * Half.Left + Abs(AxisUp.Left) * Half.Up
            Up := Abs(AxisForward.Up) * Half.Forward + Abs(AxisLeft.Up) * Half.Left + Abs(AxisUp.Up) * Half.Up
        character_surface_box{MinCm := Center - Extent, MaxCm := Center + Extent}

    # 触れられるかを切り替える（false のあいだは、触れている体にも「離れた」が届き、乗れない）。当たり判定・見た目は変えない
    SetActive<public>(Value:logic):void =
        set Active = Value

    # 触れられる（SetActive(false) にしていない）なら成功する
    IsActive<public>()<decides><transacts>:void =
        Active?

    # character_touch_component から呼ばれる：触れ方を ContactEvent と character_surface_contact_event（SendUp）で知らせる
    NotifyContact<internal>(Motor:character_motor_component, Contact:character_surface_contact):void =
        ContactEventInternal.Signal((Motor, Contact))
        Owner:?agent = if (Player := Motor.FindOwner[]) then option{Player} else false
        Entity.SendUp(character_surface_contact_event{Surface := Self, Motor := Motor, Agent := Owner, Contact := Contact})

    GetLocalSizeCm<private>(Scale:vector3)<transacts>:vector3 =
        if (SizeCm.Forward > 0.0, SizeCm.Left > 0.0, SizeCm.Up > 0.0):
            SizeCm
        else:
            vector3{Forward := Abs(Scale.Forward) * MeshSizeCm, Left := Abs(Scale.Left) * MeshSizeCm, Up := Abs(Scale.Up) * MeshSizeCm}

# 役割：独自キャラクターが面（character_surface_component）に触れた・乗ったを毎フレーム決めて知らせる
#   体（同じ entity の character_motor_component）が動いたあと（PostMoveEvent）、体の箱（足元を底にした、直径 RadiusCm × 2・高さ HeightCm の箱に TouchMarginCm の余白）と、近くの面の箱を比べる
#   乗っている面：体が接地の掃引で立っている entity（体の GetGroundEntity）に、使える面が付いていればその面（箱の大きさ・原点の設定がずれていても乗っているになる。触れているにも入れる）
#     付いていなければ箱で決める：接地していて、足元の高さが面の上面から StandToleranceCm 以内、足元が面の上（横に RadiusCm まではみ出してよい）。いくつも当てはまるときは、足元に一番近い面（同じなら高い面）
#   面の候補は RefreshSeconds ごとに探し直す（SearchRoot の子孫、無ければ世界から character_surface_tag で探し、足元から SearchRadiusCm 以内の箱だけを覚える。毎フレーム世界を探さない）
# 置き方：エディターで、character_motor_component と同じ entity に付ける
# 同じ entity：character_motor_component（必須）。動く面に乗せる character_ride_component は、この部品が無くても動く
# いつ：開始から止まるまで。止まるとき、触れていた面に「離れた」「降りた」を知らせる
# 知らせ：ContactEvent（触れた面, 触れ方）。面の ContactEvent と character_surface_contact_event（SendUp）にも同じ知らせが届く。順番は 降りた → 離れた → 触れ始めた → 乗った
# 外から：SetSearchRoot（探す場所を絞る。例 今遊んでいるマップの根）、GetTouchingSurfaces、IsTouching、FindStandingSurface
# 前提・注意：比べるのは世界の軸にそろえた箱どうし（回転した面は囲む箱になる）。速すぎて 1 フレームで面を通り抜けると触れない（薄い面は厚くする）
character_touch_component<public> := class<final_super>(component):

    # 体の箱に足す余白（cm）。体は面の手前 2 cm で止まるので、それより大きくする。既定 8
    @editable_number(float):
        ToolTip := TouchMarginToolTip
        Categories := array{CharacterSurfaceCategory}
        MinValue := option{0.0}
        MaxValue := option{500.0}
    TouchMarginCm<public>:float = 8.0
    # 足元の高さが面の上面からこの距離（cm）以内なら「乗っている」。既定 15
    @editable_number(float):
        ToolTip := TouchStandToleranceToolTip
        Categories := array{CharacterSurfaceCategory}
        MinValue := option{1.0}
        MaxValue := option{200.0}
    StandToleranceCm<public>:float = 15.0
    # 足元からこの距離（cm）以内の面だけを候補にする。既定 3000
    @editable_number(float):
        ToolTip := TouchSearchRadiusToolTip
        Categories := array{CharacterSurfaceCategory}
        MinValue := option{100.0}
        MaxValue := option{100000.0}
    SearchRadiusCm<public>:float = 3000.0
    # 候補の面を探し直す間隔（秒）。既定 0.5
    @editable_number(float):
        ToolTip := TouchRefreshToolTip
        Categories := array{CharacterSurfaceCategory}
        MinValue := option{0.05}
        MaxValue := option{10.0}
    RefreshSeconds<public>:float = 0.5

    ContactEventInternal<private><final>:event(tuple(character_surface_component, character_surface_contact)) = event(tuple(character_surface_component, character_surface_contact)){}

    # 面に触れ始めた・離れた・乗った・降りたときに、（その面, 触れ方）で届く（Await / Subscribe する。外から Signal はできない）
    ContactEvent<public><final>:listenable(tuple(character_surface_component, character_surface_contact)) = MakeProxyListenable(ContactEventInternal)

    var<private> Motor:?character_motor_component = false
    var<private> Subscription:?cancelable = false
    var<private> SearchRoot:?entity = false
    var<private> Candidates:[]character_surface_component = array{}
    var<private> Touching:[]character_surface_component = array{}
    var<private> Standing:?character_surface_component = false
    var<private> NextRefreshSeconds:float = 0.0

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := Entity.FindCharacterMotorAbove[]):
            set Motor = option{Found}
            set Subscription = option{Found.PostMoveEvent.Subscribe(OnPostMove)}
        else:
            Print("[character_touch_component] character_motor_component が見つかりません（同じ entity に置いてください）")

    OnEndSimulation<override>():void =
        Subscription.CancelIfSet()
        set Subscription = false
        if (Found := Motor?):
            Update(Found, array{}, false)
        set Candidates = array{}
        set Motor = false
        (super:)OnEndSimulation()

    # 面を探す場所を Root の子孫に絞る（false なら世界全体）。次のフレームで探し直す
    SetSearchRoot<public>(Root:?entity):void =
        set SearchRoot = Root
        set NextRefreshSeconds = 0.0

    # 今触れている面（並び順は決まっていない）
    GetTouchingSurfaces<public>()<transacts>:[]character_surface_component =
        Touching

    # Surface に今触れていれば成功する（最大 1 フレーム遅れる）
    IsTouching<public>(Surface:character_surface_component)<decides><transacts>:void =
        Touching.Find[Surface]

    # 今乗っている面。乗っていなければ失敗する（最大 1 フレーム遅れる）
    FindStandingSurface<public>()<decides><transacts>:character_surface_component =
        Standing?

    OnPostMove<private>(DeltaTime:float):void =
        if (Found := Motor?):
            Now := GetSimulationElapsedTime()
            if (Now >= NextRefreshSeconds):
                set NextRefreshSeconds = Now + RefreshSeconds
                RefreshCandidates(Found)
            Feet := Found.Entity.GetGlobalTranslation()
            Reach := Found.RadiusCm + TouchMarginCm
            BodyMin := Feet - vector3{Forward := Reach, Left := Reach, Up := TouchMarginCm}
            BodyMax := Feet + vector3{Forward := Reach, Left := Reach, Up := Found.HeightCm + TouchMarginCm}
            Grounded := if (Found.IsGrounded[]) then true else false
            # 立っている entity に面が付いていれば、それが乗っている面（箱では決めない）
            GroundSurface:?character_surface_component = if (Ground := Found.GetGroundEntity[], OnGround := Ground.GetComponent[character_surface_component], OnGround.IsActive[]) then option{OnGround} else false
            var NowTouching:[]character_surface_component = array{}
            var NowStanding:?character_surface_component = GroundSurface
            var BestDistance:float = Inf
            var BestTop:float = -Inf
            if (OnGround := GroundSurface?):
                set NowTouching += array{OnGround}
            for (Surface : Candidates, Surface.IsActive[], not IsSame[Surface, GroundSurface]):
                Box := Surface.GetBox()
                if (Overlaps[BodyMin, BodyMax, Box]):
                    set NowTouching += array{Surface}
                    if (not GroundSurface?, Grounded?, Abs(Feet.Up - Box.MaxCm.Up) <= StandToleranceCm):
                        Away := HorizontalDistance(Feet, Box)
                        if (Away <= Found.RadiusCm, (Away < BestDistance or (Away = BestDistance and Box.MaxCm.Up > BestTop))):
                            set NowStanding = option{Surface}
                            set BestDistance = Away
                            set BestTop = Box.MaxCm.Up
            Update(Found, NowTouching, NowStanding)

    # 前のフレームと比べて、変わった分を知らせる
    Update<private>(Found:character_motor_component, NowTouching:[]character_surface_component, NowStanding:?character_surface_component):void =
        Before := Touching
        WasStanding := Standing
        set Touching = NowTouching
        set Standing = NowStanding
        if (Old := WasStanding?, not IsSame[Old, NowStanding]):
            Notify(Found, Old, character_surface_contact.SteppedOff)
        for (Old : Before, not NowTouching.Find[Old]):
            Notify(Found, Old, character_surface_contact.Untouched)
        for (New : NowTouching, not Before.Find[New]):
            Notify(Found, New, character_surface_contact.Touched)
        if (New := NowStanding?, not IsSame[New, WasStanding]):
            Notify(Found, New, character_surface_contact.SteppedOn)

    Notify<private>(Found:character_motor_component, Surface:character_surface_component, Contact:character_surface_contact):void =
        ContactEventInternal.Signal((Surface, Contact))
        Surface.NotifyContact(Found, Contact)

    RefreshCandidates<private>(Found:character_motor_component):void =
        Feet := Found.Entity.GetGlobalTranslation()
        MaybeRoot:?entity = if (Root := SearchRoot?) then option{Root} else if (World := Entity.GetSimulationEntity[]) then option{World} else false
        if (Root := MaybeRoot?):
            set Candidates = for (Tagged : Root.FindDescendantEntitiesWithTag(character_surface_tag), Surface := Tagged.GetComponent[character_surface_component], DistanceToBox(Feet, Surface.GetBox()) <= SearchRadiusCm):
                Surface
        else:
            set Candidates = array{}

# Surface が Maybe の中身と同じなら成功する
IsSame<internal>(Surface:character_surface_component, Maybe:?character_surface_component)<decides><transacts>:void =
    Other := Maybe?
    Other = Surface

# 体の箱（Low〜High）と Box が重なれば成功する
Overlaps<internal>(Low:vector3, High:vector3, Box:character_surface_box)<decides><transacts>:void =
    Low.Forward <= Box.MaxCm.Forward
    High.Forward >= Box.MinCm.Forward
    Low.Left <= Box.MaxCm.Left
    High.Left >= Box.MinCm.Left
    Low.Up <= Box.MaxCm.Up
    High.Up >= Box.MinCm.Up

# Point から Box までの距離（cm。中なら 0）
DistanceToBox<internal>(Point:vector3, Box:character_surface_box)<transacts>:float =
    DF := Max(Max(Box.MinCm.Forward - Point.Forward, 0.0), Point.Forward - Box.MaxCm.Forward)
    DL := Max(Max(Box.MinCm.Left - Point.Left, 0.0), Point.Left - Box.MaxCm.Left)
    DU := Max(Max(Box.MinCm.Up - Point.Up, 0.0), Point.Up - Box.MaxCm.Up)
    Sqrt(DF * DF + DL * DL + DU * DU)

# Point から Box までの水平の距離（cm。真上・真下なら 0）
HorizontalDistance<internal>(Point:vector3, Box:character_surface_box)<transacts>:float =
    DF := Max(Max(Box.MinCm.Forward - Point.Forward, 0.0), Point.Forward - Box.MaxCm.Forward)
    DL := Max(Max(Box.MinCm.Left - Point.Left, 0.0), Point.Left - Box.MaxCm.Left)
    Sqrt(DF * DF + DL * DL)

# 役割：動く床に乗った独自キャラクターを、床と一緒に運ぶ。乗っている物は、体（character_motor_component）が接地の掃引で当たった entity（GetGroundEntity。動く床のメッシュの entity か、その親ごと動く子）
#   毎フレーム 2 回、前に覚えた床の位置・ヨーと今を比べ、動いた分だけ体を運ぶ（体の CarryBy：上下はそのまま、水平は床以外に当たれば手前で止める。速度は変えない）
#     1 回目：体が動く前（PreMoveEvent）。体は床と同じだけ動いてから、自分の速度で動く（床が上がっても、床にめり込んだまま掃引しない）
#     2 回目：物理のあと（TickEvents.PostPhysics）。床（MoverSystem の keyframe・Verse で毎フレーム動かす床）が体より後に動いたフレームも、フレームの終わりには床の上にそろえる
#   FollowYaw なら、床がヨーで回った分だけ、体の位置も床の位置（entity の原点）のまわりに回す（体の向きは変えない）
#   床の速度（運んだ量 ÷ 秒）を、体の GetGroundVelocity と GetRideVelocity に入れる
#   離れたとき：上向きに離れた（ジャンプ・打ち上げ）・縁から落ちた・GraceSeconds を過ぎた、なら乗るのをやめる。InheritVelocity なら床の速度（下向きの速さは除く）を体の速度に足す（体の InheritVelocity。walk は空中でこの分を減速しない）
#     一瞬だけ接地が切れても（上がっていないで、足元から下 50 cm 以内にまだ同じ床があれば）、GraceSeconds 秒は乗っているとして運び続ける
#   空中から乗ったとき：InheritVelocity なら、体の水平の速度のうち床の動く向きの分を、床の速さまで消す（跳んで同じ床に戻ったときに床の上で滑らない。止まった床から乗ったときは消す分が無い）
# 置き方：エディターで、character_motor_component と同じ entity に付ける（character_touch_component・床の character_surface_component は要らない。触れた・乗ったの知らせが要るときだけ足す）
# いつ：開始から止まるまで。乗り換えた最初のフレームは、乗った瞬間の位置を覚えるだけ（その前の動きは運ばない）
# 外から：FindRidingEntity（今乗って運んでいる物）、GetRideVelocity（その速度）。体の GetGroundVelocity / GetInheritedVelocity でも読める
# 前提・注意：運ぶのは体の位置だけ（体の向きは変えない。床のピッチ・ロールには合わせない）。床が一瞬で大きく動いた（MaxCarryCm を超えた）フレームは運ばない（ワープ・やり直しで連れて行かれないように）
#   運ばれて上の天井に挟まれても押し返さない（体は天井にめり込む）。体の AxisLock で縛った軸には運ばない
# ⚠ 未検証：keyframed_movement_component で動いている床の GetGlobalTransform が、サーバーで毎フレーム動いた位置を返すか。クライアントの見た目で、運ばれる体と床がずれないか（体はサーバーの位置が届き、床はクライアントで再生する）
character_ride_component<public> := class<final_super>(component):

    # 1 フレームにこれ（cm）より大きく動いた床には付いていかない。既定 300
    @editable_number(float):
        ToolTip := RideMaxCarryToolTip
        Categories := array{CharacterSurfaceCategory}
        MinValue := option{1.0}
        MaxValue := option{10000.0}
    MaxCarryCm<public>:float = 300.0
    # オンなら、乗っている床がヨーで回ったとき、体の位置も床の位置（entity の原点）のまわりに同じだけ回す（体の向きは変えない）。オフなら床の位置の動きだけを足す。既定オン
    @editable:
        ToolTip := RideFollowYawToolTip
        Categories := array{CharacterSurfaceCategory}
    FollowYaw<public>:logic = true
    # 接地が一瞬切れても、足元のすぐ下にまだ同じ床があれば、この秒数までは乗っているとして運び続ける（上向きに離れたときは使わない）。0 で使わない。既定 0.1
    @editable_number(float):
        ToolTip := RideGraceToolTip
        Categories := array{CharacterSurfaceCategory}
        MinValue := option{0.0}
        MaxValue := option{2.0}
    GraceSeconds<public>:float = 0.1
    # オンなら、動く床から離れたとき（ジャンプ・縁から落ちた）に床の速度（下向きの速さは除く）を体の速度に足し、空中から乗ったときは受け継いでいた分を消す。オフなら足さない（離れた瞬間に床の動きが無くなる）。既定オン
    @editable:
        ToolTip := RideInheritVelocityToolTip
        Categories := array{CharacterSurfaceCategory}
    InheritVelocity<public>:logic = true

    # 接地が一瞬切れたとき、足元から下へ同じ床を探す距離（cm）
    GraceProbeCm<private>:float = 50.0

    var<private> Motor:?character_motor_component = false
    var<private> Subscriptions:[]cancelable = array{}
    # 乗って運んでいる物と、最後に運んだ（覚えた）ときのその位置・ヨー（ラジアン）
    var<private> Riding:?entity = false
    var<private> LastPosition:vector3 = vector3{}
    var<private> LastYaw:float = 0.0
    var<private> GraceLeft:float = 0.0
    # 前の PreMoveEvent から運んだ量の合計（cm。床の速度を出す）と、出した床の速度（cm/s）
    var<private> CarriedSinceSample:vector3 = vector3{}
    var<private> RideVelocity:vector3 = vector3{}
    # 空中から乗ったばかり（次の PreMoveEvent で、床の速度が分かってから受け継いでいた分を消す）
    var<private> JustLanded:logic = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := Entity.FindCharacterMotorAbove[]):
            set Motor = option{Found}
            set Subscriptions = array{Found.PreMoveEvent.Subscribe(OnPreMove), Found.PostMoveEvent.Subscribe(OnPostMove), TickEvents.PostPhysics.Subscribe(OnPostPhysics)}
        else:
            Print("[character_ride_component] character_motor_component が見つかりません（同じ entity に置いてください）")

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        if (Found := Motor?, Riding?):
            Found.SetGroundVelocity(vector3{})
        set Riding = false
        set RideVelocity = vector3{}
        (super:)OnEndSimulation()

    # 今乗って運んでいる物（体が立っている entity。一瞬離れた GraceSeconds のあいだも）。乗っていなければ失敗する
    FindRidingEntity<public>()<decides><transacts>:entity =
        Riding?

    # 今乗っている物の速度（cm/s。世界の向き。回る床なら足元の速度）。乗っていなければ 0
    GetRideVelocity<public>()<transacts>:vector3 =
        RideVelocity

    # 体が動く前：床が動いた分を運び、床の速度を出す。空中から乗ったばかりなら、受け継いでいた速度を消す
    OnPreMove<private>(DeltaTime:float):void =
        if (Found := Motor?, Platform := Riding?):
            Sync(Found, Platform)
            set RideVelocity = if (DeltaTime > 0.0) then CarriedSinceSample / DeltaTime else vector3{}
            set CarriedSinceSample = vector3{}
            Found.SetGroundVelocity(RideVelocity)
            if (JustLanded?):
                set JustLanded = false
                if (InheritVelocity?):
                    CancelLandingVelocity(Found)

    # 物理のあと：体より後に動いた床の分を運ぶ（フレームの終わりに床の上へそろえる）
    OnPostPhysics<private>(DeltaTime:float):void =
        if (Found := Motor?, Platform := Riding?):
            Sync(Found, Platform)

    # 体が動いたあと：立っている物が変わったら乗り換え、地面から離れたら（一瞬なら GraceSeconds まで待って）乗るのをやめる
    OnPostMove<private>(DeltaTime:float):void =
        if (Found := Motor?):
            if (Ground := Found.GetGroundEntity[]):
                if (Platform := Riding?, Platform = Ground):
                    set GraceLeft = GraceSeconds
                else:
                    FromAir := if (Riding?) then false else true
                    Begin(Ground, FromAir)
            else if (Platform := Riding?):
                # 上向きに離れた（ジャンプ・打ち上げ）なら、すぐやめる。そうでなければ、足元のすぐ下に同じ床があるあいだ GraceSeconds まで待つ
                Rising := if (Found.GetVelocity().Up > 1.0) then true else false
                if (not Rising?, GraceLeft > 0.0, Below := Found.FindGroundEntityBelow[GraceProbeCm], Below = Platform):
                    set GraceLeft -= DeltaTime
                else:
                    Leave(Found)

    # Ground に乗り始める（今の位置・ヨーを覚えるだけ。運ぶのは次から）。FromAir なら空中から乗った
    Begin<private>(Ground:entity, FromAir:logic):void =
        set Riding = option{Ground}
        Remember(Ground.GetGlobalTransform())
        set CarriedSinceSample = vector3{}
        set GraceLeft = GraceSeconds
        set JustLanded = FromAir

    # 乗るのをやめる。InheritVelocity なら、床の速度（下向きの速さは除く）を体の速度に足す
    Leave<private>(Found:character_motor_component):void =
        if (InheritVelocity?):
            Found.InheritVelocity(vector3{Forward := RideVelocity.Forward, Left := RideVelocity.Left, Up := Max(RideVelocity.Up, 0.0)})
        else:
            Found.SetGroundVelocity(vector3{})
        set Riding = false
        set RideVelocity = vector3{}
        set CarriedSinceSample = vector3{}
        set JustLanded = false

    # 前に覚えた床の位置・ヨーから今までに床が動いた分（FollowYaw なら回った分も、体の位置で）を、体に運ばせる。MaxCarryCm を超えたら運ばない。今の位置・ヨーを覚え直す
    Sync<private>(Found:character_motor_component, Platform:entity):void =
        Transform := Platform.GetGlobalTransform()
        Position := Transform.Translation
        Body := Found.Entity.GetGlobalTransform().Translation
        Turn := if (FollowYaw?) then YawRadiansOf(Transform) - LastYaw else 0.0
        Delta := Position + TurnAroundUp(Body - LastPosition, Turn) - Body
        Moved := Delta.Length()
        if (Moved > 0.01, Moved <= MaxCarryCm):
            Found.CarryBy(Delta, Platform)
            set CarriedSinceSample = CarriedSinceSample + Delta
        Remember(Transform)

    Remember<private>(Transform:transform):void =
        set LastPosition = Transform.Translation
        set LastYaw = YawRadiansOf(Transform)

    # 空中から乗ったとき：体の水平の速度のうち、床の動く向きの分を、床の速さまで消す（床から受け継いだ分。逆向き・止まっていれば何もしない）
    CancelLandingVelocity<private>(Found:character_motor_component):void =
        Platform := vector3{Forward := RideVelocity.Forward, Left := RideVelocity.Left}
        PlatformCm := Platform.Length()
        if (PlatformCm > 1.0):
            Direction := Platform / PlatformCm
            Velocity := Found.GetVelocity()
            Along := Clamp(DotProduct(Velocity, Direction), 0.0, PlatformCm)
            if (Along > 0.0):
                Found.SetVelocity(Velocity - Direction * Along)

# Transform の前（Forward 軸）の水平の向きのヨー（ラジアン。前 = 0、左へ回ると正）
YawRadiansOf<internal>(Transform:transform)<reads>:float =
    Axis := Transform.Rotation.GetForwardAxis()
    ArcTan(Axis.Left, Axis.Forward)

# Offset を上の軸まわりに、前を左へ回す向きに LeftTurnRadians（ラジアン）回す（上の成分は変えない）
TurnAroundUp<internal>(Offset:vector3, LeftTurnRadians:float)<reads>:vector3 =
    C := Cos(LeftTurnRadians)
    S := Sin(LeftTurnRadians)
    vector3{Forward := Offset.Forward * C - Offset.Left * S, Left := Offset.Forward * S + Offset.Left * C, Up := Offset.Up}
