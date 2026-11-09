using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { ActivationSystem }
using { SceneGraphSystem }
using { PickupSystem }
using { PickupSystem.TooltipKit }

# ステージへの合図の種類
pickup_stage_signal<public> := enum:
    # 起動の合図（activated_event）を送る（隠れた足場を出す・仕掛けを動かすなど）
    Activate
    # 停止の合図（deactivated_event）を送る（ハザードを止める・仕掛けを止めるなど）
    Deactivate

# ステージへの合図を送る相手を探す範囲
pickup_stage_scope<public> := enum:
    # 拾った物（オーブ。効果の外なら、この entity）の一番上の祖先（レベルの最上位の entity）の中。マップを最上位の entity に分けたゲームなら、そのマップの中
    SourceRoot
    # 拾った物の区画（祖先の game_scope_component）の中。区画が無ければ世界
    SourceScope
    # 世界全体
    World

# ステージへの合図を受ける entity の目印のタグ。pickup_stage_target_component が開始時に自分の entity に付け、止まると外す
pickup_stage_target_tag<public> := class(tag):

# 役割：ステージへの合図（pickup_stage_signal_component）を受ける entity の目印。Group が同じ合図を受けると、この entity とその子孫へ起動・停止の合図を送る
#   合図を受けた entity の部品（ActivationSystem の enable_on_activation_component、ゲームの隠れた足場、仕掛けなど）が、起動・停止の合図で動く
#   元に戻す合図（効果が終わったとき）は数える：同じ合図を 2 つの効果から受けたら、2 つとも終わったときに逆の合図を送る
# 置き方：エディターで、合図で動かしたい entity（隠れた足場・ハザードなど）に付ける。Group に名前を入れる（効果の側の Group と同じ名前）
# タグ：この entity に pickup_stage_target_tag（合図を送る側がこのタグで探す）
# 外から：Hold / Release / Pulse（pickup_stage_signal_component が呼ぶ。コードからも使える）、IsHeld
pickup_stage_target_component<public> := class<final_super>(component):

    # 合図のグループの名前。合図を送る側（pickup_stage_signal_component）の Group と同じなら受ける。空なら受けない。既定 空
    @editable:
        ToolTip := StageTargetGroupToolTip
        Categories := array{PickupStageCategory}
    Group<public>:string = ""

    var<private> TagKey:?tag_key = false
    var<private> ActivateHolds:int = 0
    var<private> DeactivateHolds:int = 0

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set TagKey = option{Entity.AddTag(pickup_stage_target_tag{})}

    OnEndSimulation<override>():void =
        if (Key := TagKey?, Entity.RemoveTag[Key]) {}
        set TagKey = false
        set ActivateHolds = 0
        set DeactivateHolds = 0
        (super:)OnEndSimulation()

    # Signal を「持つ」：最初の 1 つ目で Signal の合図をこの entity と子孫へ送る（Activator がいれば、その人が起こした起動の合図）。Release で放す
    Hold<public>(Signal:pickup_stage_signal, Activator:?agent):void =
        if (Signal = pickup_stage_signal.Activate):
            set ActivateHolds += 1
            if (ActivateHolds = 1):
                Send(Signal, Activator)
        else:
            set DeactivateHolds += 1
            if (DeactivateHolds = 1):
                Send(Signal, Activator)

    # Hold した Signal を 1 つ放す。だれも持たなくなったら、逆の合図を送る（もう一方の合図を持っている人がいれば、そちらを送り直す）
    Release<public>(Signal:pickup_stage_signal):void =
        if (Signal = pickup_stage_signal.Activate):
            if (ActivateHolds > 0):
                set ActivateHolds -= 1
                if (ActivateHolds = 0):
                    Send(if (DeactivateHolds > 0) then pickup_stage_signal.Deactivate else Opposite(Signal), false)
        else:
            if (DeactivateHolds > 0):
                set DeactivateHolds -= 1
                if (DeactivateHolds = 0):
                    Send(if (ActivateHolds > 0) then pickup_stage_signal.Activate else Opposite(Signal), false)

    # 数えずに、Signal の合図を 1 回だけ送る（元に戻さない合図）
    Pulse<public>(Signal:pickup_stage_signal, Activator:?agent):void =
        Send(Signal, Activator)

    # だれかが Signal を持っていれば成功する
    IsHeld<public>(Signal:pickup_stage_signal)<decides><transacts>:void =
        if (Signal = pickup_stage_signal.Activate) then ActivateHolds > 0 else DeactivateHolds > 0

    Send<private>(Signal:pickup_stage_signal, Activator:?agent):void =
        if (Signal = pickup_stage_signal.Activate):
            if (Agent := Activator?):
                Entity.SendActivatedBy(Agent)
            else:
                Entity.SendActivated()
        else:
            Entity.SendDeactivated()

    Opposite<private>(Signal:pickup_stage_signal)<transacts>:pickup_stage_signal =
        if (Signal = pickup_stage_signal.Activate) then pickup_stage_signal.Deactivate else pickup_stage_signal.Activate

# 役割：起動の合図を受けたら、範囲（Scope）の中の、Group が同じ pickup_stage_target_component（タグ pickup_stage_target_tag で探す）へ Signal の合図を送る。RevertOnEnd なら、停止の合図を受けたとき（効果が終わったとき）に元に戻す
#   効果のプレハブ（PickupSystem の pickup_effect_component）の中に置くと、範囲の基準は拾った物（オーブ）。例：「そのマップの隠れた足場を 10 秒出す」「そのマップのハザードを 5 秒止める」
#   効果の外（起動の合図が届くほかの場所）に置いてもよい。そのときの範囲の基準はこの entity
# 置き方：エディターで、効果のプレハブの根か子に付ける（Group ごとに entity を分ける）
# いつ：起動の合図を受けたとき・停止の合図を受けたとき。止まるときにも元に戻す（RevertOnEnd のとき）
# 外から：Apply / Revert / GetTargetCount
# 前提・注意：相手は合図を送るときに 1 回だけ探す（あとから増えた相手には送らない）。同じ相手を同じマップのほかの人も見る（ステージは共有）
pickup_stage_signal_component<public> := class<final_super>(component):

    # 合図を送る相手のグループの名前（pickup_stage_target_component の Group）。空なら送らない。既定 空
    @editable:
        ToolTip := StageSignalGroupToolTip
        Categories := array{PickupStageCategory}
    Group<public>:string = ""
    # 送る合図（Activate = 起動 / Deactivate = 停止）。既定 Activate
    @editable:
        ToolTip := StageSignalSignalToolTip
        Categories := array{PickupStageCategory}
    Signal<public>:pickup_stage_signal = pickup_stage_signal.Activate
    # 相手を探す範囲（SourceRoot = 拾った物の最上位の entity の中 / SourceScope = 拾った物の区画 / World = 世界）。既定 SourceRoot
    @editable:
        ToolTip := StageSignalScopeToolTip
        Categories := array{PickupStageCategory}
    Scope<public>:pickup_stage_scope = pickup_stage_scope.SourceRoot
    # オンなら、停止の合図を受けたとき（効果が終わったとき）に元に戻す。オフなら送ったまま（やり直しは相手の部品に任せる）。既定オン
    @editable:
        ToolTip := StageSignalRevertToolTip
        Categories := array{PickupStageCategory}
    RevertOnEnd<public>:logic = true

    var<private> Held:[]pickup_stage_target_component = array{}
    var<private> Applied:logic = false

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Apply(if (Agent := SceneEvent.FindActivatingAgent[]) then option{Agent} else false)
        else if (deactivated_event[SceneEvent]):
            Revert()
        false

    OnEndSimulation<override>():void =
        Revert()
        (super:)OnEndSimulation()

    # 範囲の中の相手へ合図を送る（RevertOnEnd なら、Revert まで持つ）。もう送っていれば何もしない
    Apply<public>(Activator:?agent):void =
        if (Applied? or Group = ""):
            return
        set Applied = true
        Targets := FindTargets()
        if (Targets.Length = 0):
            Print("[pickup_stage_signal_component] Group「{Group}」の相手（pickup_stage_target_component）が範囲の中に見つかりません")
        for (Target : Targets):
            if (RevertOnEnd?):
                Target.Hold(Signal, Activator)
            else:
                Target.Pulse(Signal, Activator)
        if (RevertOnEnd?):
            set Held = Targets

    # 送った合図を元に戻す（RevertOnEnd のとき。送っていなければ何もしない）
    Revert<public>():void =
        if (not Applied?):
            return
        set Applied = false
        for (Target : Held):
            Target.Release(Signal)
        set Held = array{}

    # 今の範囲の中の相手の数（探し直す）
    GetTargetCount<public>()<transacts>:int =
        FindTargets().Length

    FindTargets<private>()<transacts>:[]pickup_stage_target_component =
        Base := if (Effect := Entity.FindPickupEffect[], Source := Effect.FindSource[]) then Source else Entity
        MaybeRoot:?entity = case (Scope):
            pickup_stage_scope.SourceRoot => option{Base.FindTopEntity()}
            pickup_stage_scope.SourceScope =>
                if (ScopeEntity := Base.FindScopeEntity[]) then option{ScopeEntity} else if (World := Base.GetSimulationEntity[]) then option{World} else false
            pickup_stage_scope.World =>
                if (World := Base.GetSimulationEntity[]) then option{World} else false
        if (Root := MaybeRoot?):
            for (Tagged : Root.FindDescendantEntitiesWithTag(pickup_stage_target_tag), Target := Tagged.GetComponent[pickup_stage_target_component], Target.Group = Group):
                Target
        else:
            array{}

# InEntity の一番上の祖先（simulation entity のすぐ下。レベルの最上位の entity）。InEntity が最上位なら InEntity
(InEntity:entity).FindTopEntity<public>()<transacts>:entity =
    var Current:entity = InEntity
    loop:
        if (Parent := Current.GetParent[], Parent.GetParent[]):
            set Current = Parent
        else:
            break
    Current
