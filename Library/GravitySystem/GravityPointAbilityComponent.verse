using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Input }
using { AbilitySystem }
using { ItemSystem }
using { InputSystem }
using { MovementSystem }
using { SceneGraphSystem }
using { GravitySystem.TooltipKit }

# 役割：引力の点を置く能力。付与された人が PlaceAction（既定は射撃）を押すと、レティクルの先（PlaceDistanceCm 以内で物に当たればその手前、当たらなければ PlaceDistanceCm 先）に引力の点（gravity_well_component）を置き、DurationSeconds 秒で消す。
#   置いているあいだにもう一度押すと、時間を待たずに消す。1 人が置けるのは 1 つまで（この能力 1 つにつき）。剥奪されても、置いた点は時間まで残る（シミュレーションの終わりには消す）
#   点の見た目は WellPrefab（メッシュなどを付けた prefab）から作り、gravity_well_component（RadiusCm・StrengthCmPerSecondSquared）を足す。WellPrefab が既定の entity のままなら見た目の無い点になる
# 付与の仕方は同じ entity に置く component で選ぶ：
#   - アイテムとして（装備しているあいだ） → アイテムの entity に item_component・item_holder_component・ability_grant_item_component と一緒に置く。1 人 1 つまでにするなら exclusive_item_component
#   - 全員に最初から／起動しているあいだ → ability_grant_players_component（1 人 1 つずつ置ける）
#   - 条件を満たしているあいだ → ability_grant_condition_component（子に条件）
#   - コードから → Grant / Revoke
# 知らせ：置いたら PlacedEvent、消えたら RemovedEvent
# 前提：引力が引く相手を知るため、区画（または世界）に player_manager_component が 1 つ
gravity_point_ability_component<public> := class<final_super>(ability_component):

    # 置く点の見た目にする prefab。置くたびにこれを作り、引力を足す（既定の entity のままなら見た目の無い点）
    @editable:
        ToolTip := GravityWellPrefabToolTip
        Categories := array{GravityCategory}
    WellPrefab<public>:concrete_subtype(entity) = entity
    # 置いた点が消えるまでの時間（秒。既定 30）。置いているあいだにもう一度押すとすぐ消える
    @editable_number(float):
        ToolTip := GravityDurationToolTip
        Categories := array{GravityCategory}
        MinValue := option{1.0}
        MaxValue := option{600.0}
    DurationSeconds<public>:float = 30.0
    # レティクルの先、何センチメートルに置くか（既定 800）。あいだに物があればその手前に置く
    @editable_number(float):
        ToolTip := GravityPlaceDistanceToolTip
        Categories := array{GravityCategory}
        MinValue := option{100.0}
        MaxValue := option{10000.0}
    PlaceDistanceCm<public>:float = 800.0
    # 置いた点の引力が届く半径（センチメートル。既定 1500）。中心で一番強く、この距離で 0
    @editable_number(float):
        ToolTip := GravityRadiusToolTip
        Categories := array{GravityCategory}
        MinValue := option{100.0}
        MaxValue := option{20000.0}
    RadiusCm<public>:float = 1500.0
    # 置いた点の中心での引く強さ（センチメートル毎秒毎秒。既定 1200）
    @editable_number(float):
        ToolTip := GravityStrengthToolTip
        Categories := array{GravityCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    StrengthCmPerSecondSquared<public>:float = 1200.0
    # 押すと点を置く（置いているときは消す）操作。既定は WeaponPrimary（攻撃のボタン）
    @editable:
        ToolTip := GravityPlaceActionToolTip
        Categories := array{GravityCategory, GravityInputCategory}
    PlaceAction<public>:input_action(logic) = Character.WeaponPrimary
    # 付与しているあいだ有効にするキー割り当て。PlaceAction を含むもの。既定は RangedWeaponMapping
    @editable:
        ToolTip := GravityPlaceMappingToolTip
        Categories := array{GravityCategory, GravityInputCategory}
    PlaceMapping<public>:input_mapping = Character.RangedWeaponMapping
    # true なら剥奪したときに PlaceMapping を外す（この能力専用の割り当てのときだけ。既定 false）
    @editable:
        ToolTip := GravityRemoveMappingToolTip
        Categories := array{GravityCategory, GravityInputCategory}
    RemoveMappingOnRevoke<public>:logic = false

    # 当たった面から手前に離す距離（センチメートル）
    SurfaceGapCm<private>:float = 150.0

    PlacedEventInternal<private><final>:event(tuple(agent, gravity_well_component)) = event(tuple(agent, gravity_well_component)){}
    RemovedEventInternal<private><final>:event(agent) = event(agent){}

    # だれかが点を置いたときに、（置いた人, 置いた点）で届く（Await / Subscribe する。外から Signal はできない）
    PlacedEvent<public><final>:listenable(tuple(agent, gravity_well_component)) = MakeProxyListenable(PlacedEventInternal)

    # だれかの点が消えた（時間切れ・もう一度押した・シミュレーションの終わり）ときに、置いた人で届く
    RemovedEvent<public><final>:listenable(agent) = MakeProxyListenable(RemovedEventInternal)

    var Wells<private>:[agent]gravity_well_component = map{}
    var PlaceCounts<private>:[agent]int = map{}

    # Agent が置いた点が今あれば返す。無ければ失敗する
    FindWell<public>(Agent:agent)<decides><transacts>:gravity_well_component =
        Wells[Agent]

    RunFor<override>(Agent:agent)<suspends>:void =
        MaybeInput := Agent.AwaitPlayerInput()
        if (PlayerInput := MaybeInput?):
            race:
                PlayerInput.HoldInputMapping(PlaceMapping, RemoveMappingOnRevoke)
                loop:
                    PlayerInput.AwaitPressed(PlaceAction)
                    Toggle(Agent)

    # Agent の点が無ければレティクルの先に置き、あれば消す（押したときと同じ処理。入力を通さずに使わせたいときに呼ぶ）。キャラクターがいなければ何もしない
    Toggle<public>(Agent:agent):void =
        if (FindWell[Agent]):
            RemoveWell(Agent)
        else if (FortCharacter := Agent.GetFortCharacter[]):
            PlaceWell(Agent, FindPlacePosition(FortCharacter))

    # Agent の点を消す。無ければ何もしない
    RemoveWell<public>(Agent:agent):void =
        if (Well := Wells[Agent]):
            set Wells = Wells.RemoveKey(Agent)
            Well.Entity.RemoveFromParent()
            RemovedEventInternal.Signal(Agent)

    OnEndSimulation<override>():void =
        for (Agent -> Well : Wells):
            RemoveWell(Agent)
        (super:)OnEndSimulation()

    PlaceWell<private>(Agent:agent, Position:vector3):void =
        if (SimulationEntity := Entity.GetSimulationEntity[]):
            Body := WellPrefab{}
            Well := gravity_well_component{Entity := Body, RadiusCm := RadiusCm, StrengthCmPerSecondSquared := StrengthCmPerSecondSquared}
            Body.AddComponents(array{Well})
            SimulationEntity.AddEntities(array{Body})
            Current := Body.GetGlobalTransform()
            Body.SetGlobalTransform(Current.WithTranslation(Position))
            Count := GetPlaceCount(Agent) + 1
            if (set PlaceCounts[Agent] = Count) {}
            if (set Wells[Agent] = Well) {}
            PlacedEventInternal.Signal((Agent, Well))
            spawn{ExpireLater(Agent, Count)}

    GetPlaceCount<private>(Agent:agent)<transacts>:int =
        if (Count := PlaceCounts[Agent]) then Count else 0

    ExpireLater<private>(Agent:agent, Count:int)<suspends>:void =
        Sleep(DurationSeconds)
        if (GetPlaceCount(Agent) = Count):
            RemoveWell(Agent)

    FindPlacePosition<private>(FortCharacter:fort_character)<transacts>:vector3 =
        Origin := FortCharacter.GetViewOrigin()
        Direction := FortCharacter.GetViewDirection()
        if (CharacterEntity := FortCharacter.GetEntity[], Hit := FindFirstHit[CharacterEntity, Origin, Direction * PlaceDistanceCm]):
            Origin + Direction * Max(Hit.SourceHitDistance - SurfaceGapCm, 0.0)
        else:
            Origin + Direction * PlaceDistanceCm

    FindFirstHit<private>(CharacterEntity:entity, Origin:vector3, Displacement:vector3)<decides><transacts>:sweep_hit =
        first:
            Hit : CharacterEntity.FindSweepHits(Displacement, MakeTranslationTransform(Origin), collision_point{})
            Hit.TargetComponent.Entity <> CharacterEntity
        do:
            Hit
