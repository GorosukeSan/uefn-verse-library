using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { CharacterSystem }
using { CharacterSystem.SurfaceKit }
using { MovementSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { _Test }

# 役割：テスト用。触れ方（character_surface_contact）を数える
test_surface_contact_counter<public> := class:
    var<private> Touched:int = 0
    var<private> Untouched:int = 0
    var<private> SteppedOn:int = 0
    var<private> SteppedOff:int = 0

    OnContact<public>(Payload:tuple(character_surface_component, character_surface_contact)):void =
        case (Payload(1)):
            character_surface_contact.Touched => set Touched += 1
            character_surface_contact.Untouched => set Untouched += 1
            character_surface_contact.SteppedOn => set SteppedOn += 1
            character_surface_contact.SteppedOff => set SteppedOff += 1

    GetTouched<public>()<transacts>:int = Touched
    GetUntouched<public>()<transacts>:int = Untouched
    GetSteppedOn<public>()<transacts>:int = SteppedOn
    GetSteppedOff<public>()<transacts>:int = SteppedOff

# 役割：CharacterSystem の SurfaceKit（character_surface_component・character_touch_component・character_ride_component）の動作確認
#   プレイヤーの横・3 m 上に持ち主のいない体（motor + touch + ride）を作って床に落とし、着地した床の高さに、見た目の無い面（SizeCm の箱、上面 = 床の高さ）を作る
#   乗った（Touched・SteppedOn が 1 回・FindStandingSurface）、ride が立っている床（GetGroundEntity）に乗り、当たり判定の無い面を前へ 150 cm 動かしても体は運ばれない、SetActive(false) で離れる・降りる（Untouched・SteppedOff）、GetBox が大きさ・回転どおりかを見る
# テストのレベル：player_manager_component を付けた entity を 1 つと、この component を付けた entity を 1 つ。プレイヤー 1 人が平らな床に立った状態で始める（体はその横の床に落ちる。前 3 m に 5 m 四方の床が要る）
# 結果：出力ログの [TEST] CharacterSurface。約 5 秒
character_surface_test_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        Results := test_log{Name := "CharacterSurface"}
        TickEvents.PrePhysics.Await()
        if:
            Manager := Entity.FindScopedComponent[player_manager_component]
            Slot := Manager.GetSlots()[0]
            FortCharacter := Slot.Player.GetFortCharacter[]
            Feet := FortCharacter.FindGlobalTranslation[]
        then:
            Run(Results, Feet)
        else:
            Results.Fail("setup", "no player character")
        CheckBox(Results)
        if (Results.Finish[]) {}

    Run<private>(Results:test_log, Feet:vector3)<suspends>:void =
        Start := Feet + vector3{Forward := 300.0, Up := 300.0}
        Pawn := entity{}
        Pawn.SetGlobalTransform(MakeTranslationTransform(Start))
        Motor := character_motor_component{Entity := Pawn, SpawnAtOwner := false, ResetOnRoundStart := false}
        Touch := character_touch_component{Entity := Pawn, RefreshSeconds := 0.1}
        Ride := character_ride_component{Entity := Pawn}
        Pawn.AddComponents(array{Motor, Touch, Ride})
        Entity.AddEntities(array{Pawn})
        Counter := test_surface_contact_counter{}
        Subscription := Touch.ContactEvent.Subscribe(Counter.OnContact)
        Sleep(2.5)
        Results.Check("falls and becomes grounded", if (Motor.IsGrounded[]) then true else false)
        Landed := Pawn.GetGlobalTransform().Translation

        # 床の高さを上面にした、見た目の無い面（400 × 400 × 100 cm）
        Pad := entity{}
        Pad.SetGlobalTransform(MakeTranslationTransform(Landed - vector3{Up := 100.0}))
        Surface := character_surface_component{Entity := Pad, SizeCm := vector3{Forward := 400.0, Left := 400.0, Up := 100.0}}
        Pad.AddComponents(array{Surface})
        Entity.AddEntities(array{Pad})
        Touch.SetSearchRoot(option{Entity})
        Sleep(0.5)
        Results.CheckInt("Touched once", Counter.GetTouched(), 1)
        Results.CheckInt("SteppedOn once", Counter.GetSteppedOn(), 1)
        Results.Check("FindStandingSurface", if (Standing := Touch.FindStandingSurface[], Standing = Surface) then true else false)
        Results.Check("IsTouching", if (Touch.IsTouching[Surface]) then true else false)

        # ride は体が立っている物（接地の掃引で当たった entity ＝止まっている床）に乗る。当たり判定の無い面の箱を前へ 150 cm 動かしても、体は運ばれない
        #   動く床（当たり判定のあるメッシュ）に乗って運ばれるかは、メッシュを作れないこのテストでは見ない（README の「確かめ方」の手順で実機で見る）
        Results.Check("GetGroundEntity while grounded", if (Motor.GetGroundEntity[]) then true else false)
        Results.Check("ride tracks the ground entity", if (Riding := Ride.FindRidingEntity[], Ground := Motor.GetGroundEntity[], Riding = Ground) then true else false)
        Before := Pawn.GetGlobalTransform().Translation
        Pad.SetGlobalTransform(MakeTranslationTransform(Landed - vector3{Up := 100.0} + vector3{Forward := 150.0}))
        Sleep(0.3)
        After := Pawn.GetGlobalTransform().Translation
        Results.CheckFloat("ride ignores a moved box without collision", After.Forward - Before.Forward, 0.0, 5.0)
        Results.CheckFloat("ground velocity on a still floor", Motor.GetGroundVelocity().Length(), 0.0, 1.0)

        Surface.SetActive(false)
        Sleep(0.3)
        Results.CheckInt("Untouched once after SetActive(false)", Counter.GetUntouched(), 1)
        Results.CheckInt("SteppedOff once after SetActive(false)", Counter.GetSteppedOff(), 1)
        Results.Check("not standing after SetActive(false)", if (Touch.FindStandingSurface[]) then false else true)
        Subscription.Cancel()
        Pad.RemoveFromParent()
        Pawn.RemoveFromParent()

    # GetBox：大きさ 2 × 1 × 3、底が原点のメッシュ（MeshSizeCm 100）を 90 度回すと、前後と左右が入れ替わる
    CheckBox<private>(Results:test_log):void =
        Box := entity{}
        Box.SetGlobalTransform(transform{Translation := vector3{Forward := 1000.0, Left := 0.0, Up := 500.0}, Rotation := MakeRotationFromYawPitchRollDegrees(90.0, 0.0, 0.0), Scale := vector3{Forward := 2.0, Left := 1.0, Up := 3.0}})
        Surface := character_surface_component{Entity := Box}
        Box.AddComponents(array{Surface})
        Value := Surface.GetBox()
        Results.CheckFloat("GetBox forward size (rotated)", Value.MaxCm.Forward - Value.MinCm.Forward, 100.0, 1.0)
        Results.CheckFloat("GetBox left size (rotated)", Value.MaxCm.Left - Value.MinCm.Left, 200.0, 1.0)
        Results.CheckFloat("GetBox bottom at pivot", Value.MinCm.Up, 500.0, 1.0)
        Results.CheckFloat("GetBox top", Value.MaxCm.Up, 800.0, 1.0)
