using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { ActivationSystem }
using { MovementSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { VolumeSystem.TooltipKit }

# ボリュームの形
player_volume_shape<public> := enum:
    # 箱（幅 × 奥行き × 高さ）
    Box
    # 縦の円柱（直径 = 幅。奥行きは使わない）
    Cylinder

# プレイヤーがボリュームに入った知らせ
# 方向：player_volume_component の entity から根へ（SendUp）
# 送り手：player_volume_component（Volume）。受け手：同じ entity と祖先の component（VolumeSystem の Kit、利用者の component）。消費しない
# 受け手は Volume で「どのボリュームの知らせか」を見分ける（自分の entity のボリュームだけなら Entered.Volume.Entity = Entity）
player_volume_entered_event<public> := class(scene_event):
    # 送ったボリューム
    Volume<public>:player_volume_component
    # 入った人
    Agent<public>:agent

# プレイヤーがボリュームから出た知らせ（出た・キャラクターがいなくなった・退出した・ボリュームが止まった）
# 方向・送り手・受け手は player_volume_entered_event と同じ
player_volume_exited_event<public> := class(scene_event):
    # 送ったボリューム
    Volume<public>:player_volume_component
    # 出た人
    Agent<public>:agent

# 役割：この entity の位置を基準にした箱か円柱の範囲に、プレイヤーが入った・出たを調べて知らせる。中で何をするか（条件・起動・効果）は持たず、同じ entity か祖先に置く別の component が知らせを受けて決める（継承しない）
#   調べ方：起動しているあいだ PollIntervalSeconds 秒ごとに、(1) この entity のメッシュに重なっている entity を FindOverlapHits で調べ、possessable_component の Agent で人を出す（⚠ 未検証）、(2) 見つからなかった人はキャラクターの位置を範囲と比べる（実機で確認済み）。どちらかで見つかれば中にいる
#   範囲：底面の真ん中がこの entity の位置。幅 WidthCm（前後）× 奥行き DepthCm（左右）× 高さ HeightCm に、この entity の大きさ（Scale）を掛ける。回転は見ない。上下に HeightMarginCm の余裕（キャラクターの位置は体の真ん中なので、薄い床のような範囲では大きくする）
# 置き方：エディターで entity に付ける（見た目が要らなければメッシュは無くてよい）
# 同じ entity・親：知らせを受ける component（ConditionKit の player_in_volume_condition_component、ActivationKit の volume_activation_component、利用者の component）
# いつ：ActiveOnBegin なら開始から。起動の合図（activated_event）で始め、停止の合図（deactivated_event）で止める。コードから Activate / Deactivate も呼べる
# 知らせ：変わったときだけ player_volume_entered_event / player_volume_exited_event を上へ送り、PlayerEnteredEvent / PlayerExitedEvent に届ける。止まるときは中にいた人ぶんの「出た」を送ってから空にする
# タグ：中にいるあいだ、その人（agent）に in_volume_tag を付ける（どのボリュームかは区別しない）
# 外から：GetAgentsInside / GetInsideCount / IsInside / AwaitLeft / IsActive
# 前提：区画（または世界）に player_manager_component が 1 つ（見つけたら覚えておく）
player_volume_component<public> := class<final_super>(component):

    # 範囲の形。Box は箱、Cylinder は直径が WidthCm の縦の円柱（既定 Box）
    @editable:
        ToolTip := VolumeShapeToolTip
        Categories := array{VolumeCategory}
    Shape<public>:player_volume_shape = player_volume_shape.Box
    # 範囲の幅（前後、cm）。entity の Scale を掛ける。円柱では直径（既定 100.0）
    @editable_number(float):
        ToolTip := VolumeWidthToolTip
        Categories := array{VolumeCategory}
        MinValue := option{1.0}
    WidthCm<public>:float = 100.0
    # 範囲の奥行き（左右、cm）。entity の Scale を掛ける。円柱では使わない（既定 100.0）
    @editable_number(float):
        ToolTip := VolumeDepthToolTip
        Categories := array{VolumeCategory}
        MinValue := option{1.0}
    DepthCm<public>:float = 100.0
    # 範囲の高さ（cm）。底面が entity の位置。entity の Scale を掛ける（既定 100.0）
    @editable_number(float):
        ToolTip := VolumeHeightToolTip
        Categories := array{VolumeCategory}
        MinValue := option{1.0}
    HeightCm<public>:float = 100.0
    # 範囲の上下に足す余裕（cm）。薄い床のような範囲では 300 くらいにする（既定 100.0）
    @editable_number(float):
        ToolTip := VolumeHeightMarginToolTip
        Categories := array{VolumeCategory}
        MinValue := option{0.0}
        MaxValue := option{2000.0}
    HeightMarginCm<public>:float = 100.0
    # 出入りを調べる間隔（秒）。短いほど早く気付くが重くなる（既定 0.25）
    @editable_number(float):
        ToolTip := VolumePollIntervalToolTip
        Categories := array{VolumeCategory}
        MinValue := option{0.05}
        MaxValue := option{10.0}
    PollIntervalSeconds<public>:float = 0.25
    # true ならシミュレーション開始から調べる。false なら起動の合図から（既定 true）
    @editable:
        ToolTip := VolumeActiveOnBeginToolTip
        Categories := array{VolumeCategory}
    ActiveOnBegin<public>:logic = true

    PlayerEnteredEventInternal<private><final>:event(agent) = event(agent){}
    PlayerExitedEventInternal<private><final>:event(agent) = event(agent){}

    # だれかが入るたびに、その人で届く（Await / Subscribe する。外から Signal はできない）
    PlayerEnteredEvent<public><final>:listenable(agent) = MakeProxyListenable(PlayerEnteredEventInternal)

    # だれかが出るたびに、その人で届く（止まるときは中にいた人ぶんも届く）
    PlayerExitedEvent<public><final>:listenable(agent) = MakeProxyListenable(PlayerExitedEventInternal)

    var<private> Inside:[agent]logic = map{}
    var<private> InsideTags:player_tag_holder = player_tag_holder{}
    var<private> Active:logic = false
    var<private> Manager:?player_manager_component = false
    StopEvent<private>:event() = event(){}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (ActiveOnBegin?):
            Activate()

    OnSimulate<override>()<suspends>:void =
        loop:
            if (not Active?):
                StartEvent.Await()
            race:
                StopEvent.Await()
                PollWhileActive()

    StartEvent<private>:event() = event(){}

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Activate()
        else if (deactivated_event[SceneEvent]):
            Deactivate()
        false

    OnEndSimulation<override>():void =
        set Active = false
        LeaveAll()
        (super:)OnEndSimulation()

    # 調べ始める。もう調べていれば何もしない
    Activate<public>():void =
        if (not Active?):
            set Active = true
            StartEvent.Signal()

    # 調べるのをやめ、中にいた人ぶんの「出た」を送って空にする。止まっていれば何もしない
    Deactivate<public>():void =
        if (Active?):
            set Active = false
            StopEvent.Signal()
            LeaveAll()

    # 調べているあいだ成功する
    IsActive<public>()<decides><transacts>:void =
        Active?

    # 今中にいる人（並び順は決まっていない）
    GetAgentsInside<public>()<transacts>:[]agent =
        for (Agent -> Value : Inside, Value?):
            Agent

    # 今中にいる人数
    GetInsideCount<public>()<transacts>:int =
        GetAgentsInside().Length

    # Agent が今中にいれば成功する
    IsInside<public>(Agent:agent)<decides><transacts>:void =
        Inside[Agent]?

    # Agent が出るまで待つ（今いなければすぐ戻る）
    AwaitLeft<public>(Agent:agent)<suspends>:void =
        if (IsInside[Agent]):
            loop:
                Left := PlayerExitedEvent.Await()
                if (Left = Agent):
                    break

    # Position（ワールドの位置、cm）が範囲の中なら成功する。範囲は今のこの entity の位置と大きさで決まる
    Contains<public>(Position:vector3)<decides><transacts>:void =
        Transform := Entity.GetGlobalTransform()
        Base := Transform.Translation
        HalfWidth := WidthCm * Transform.Scale.Forward / 2.0
        HalfDepth := DepthCm * Transform.Scale.Left / 2.0
        Height := HeightCm * Transform.Scale.Up
        Forward := Position.Forward - Base.Forward
        Left := Position.Left - Base.Left
        Position.Up >= Base.Up - HeightMarginCm
        Position.Up <= Base.Up + Height + HeightMarginCm
        if (Shape = player_volume_shape.Cylinder):
            Forward * Forward + Left * Left <= HalfWidth * HalfWidth
        else:
            Abs(Forward) <= HalfWidth
            Abs(Left) <= HalfDepth

    PollWhileActive<private>()<suspends>:void =
        loop:
            Poll()
            Sleep(PollIntervalSeconds)

    Poll<private>():void =
        # 区画の player_manager_component を探して覚える（覚えていれば探さない）
        set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)
        if (Found := Manager?):
            Overlapping := FindOverlappingAgents()
            for (Slot : Found.GetSlots()):
                Agent := Slot.Player
                if (Overlapping.Find[Agent]):
                    Enter(Agent)
                else if (Character := Agent.GetFortCharacter[], Character.IsActive[], Position := Character.FindGlobalTranslation[], Contains[Position]):
                    Enter(Agent)
                else:
                    Leave(Agent)
            # 退出した人（slot が無くなった人）を出す
            for (Agent -> Value : Inside, Value?, Player := player[Agent], not Found.FindSlot[Player]):
                Leave(Agent)

    # この entity のメッシュ（当たり判定で重なりを取れるもの）に今重なっている entity を操っている agent（possessable_component の Agent）。メッシュが無ければ空
    # ⚠ 未検証：プレイヤーのキャラクターの entity が重なりの結果に入り、possessable_component から agent が取れるか。取れなくても位置での判定で見つかる
    FindOverlappingAgents<private>()<transacts>:[]agent =
        for (Hit : Entity.FindOverlapHits(), Agent := Hit.TargetComponent.Entity.FindPossessingAgent[]):
            Agent

    Enter<private>(Agent:agent):void =
        if (not IsInside[Agent]):
            if (set Inside[Agent] = true) {}
            InsideTags.Set(Agent, true, in_volume_tag{})
            Entity.SendUp(player_volume_entered_event{Volume := Self, Agent := Agent})
            PlayerEnteredEventInternal.Signal(Agent)

    Leave<private>(Agent:agent):void =
        if (IsInside[Agent]):
            if (set Inside[Agent] = false) {}
            InsideTags.Remove(Agent)
            Entity.SendUp(player_volume_exited_event{Volume := Self, Agent := Agent})
            PlayerExitedEventInternal.Signal(Agent)

    LeaveAll<private>():void =
        for (Agent : GetAgentsInside()):
            Leave(Agent)
        set Inside = map{}
        InsideTags.RemoveAll()

# どれかの player_volume_component の中にいる人（agent）に付くタグ（ほかの System は Agent.HasPlayerTag[in_volume_tag] で確かめる）
in_volume_tag<public> := class(player_state_tag):
