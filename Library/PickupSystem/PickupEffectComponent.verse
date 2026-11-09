using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { PickupSystem.TooltipKit }

# 同じ効果（EffectId が同じ）をもう持っている人が、また拾ったときにどうするか
pickup_effect_stack_mode<public> := enum:
    # 続いている効果の残り時間に、新しい効果の DurationSeconds を足す（新しい効果は始めない）
    Extend
    # 続いている効果の残り時間を、新しい効果の DurationSeconds に戻す（新しい効果は始めない）
    Refresh
    # もう 1 つ重ねる（中の部品が 2 つ分効く。MaxStacks まで。届いていたら一番早く終わるものを Refresh する）
    Stack
    # 続いている効果を終えて、新しい効果を始める
    Replace
    # 続いているあいだは何もしない（新しい効果は始めない）
    Ignore

# 効果（pickup_effect_component）を受けているあいだ、持ち主（agent）に付くタグ。効果 1 つにつき 1 つ付く
#   何の効果かは、Entity.GetActivePickupEffects(Agent) の EffectId で分かる。中の部品が、効果ごとのタグ（CharacterSystem の BuffKit の character_speed_modified_tag など）も付ける
pickup_effect_tag<public> := class(player_state_tag):

# 効果が始まった・終わった知らせ
# 方向：効果の entity から根へ（SendUp。プレイヤーの slot → player_manager_component の entity へと届く）
# 送り手：pickup_effect_component（Effect）。受け手：slot の祖先の component（ゲームの根など）。消費しない
pickup_effect_changed_event<public> := class(scene_event):
    # 始まった・終わった効果（送り元）
    Effect<public>:pickup_effect_component
    # 効果を受けている人（持ち主）
    Agent<public>:agent
    # true なら始まった、false なら終わった
    Started<public>:logic

# 持ち主の側に届く、効果の知らせの種類（pickup_effect_owner_event.Notice）
pickup_effect_notice<public> := enum:
    # 効果が始まった（Instant の効果も。すぐあとに Ended が続く）
    Started
    # 同じ効果（EffectId が同じ）をまた拾ったが、新しい効果は始めず、続いている効果に任せた（StackMode が Extend / Refresh / Ignore と、Stack の上限）。残り時間は Effect.GetRemainingSeconds で読む
    Renewed
    # 効果が終わった（時間・End・EndPickupEffectsFor）。持ち主の退出などで消えたときは届かない
    Ended

# 効果の知らせ（持ち主の側）。拾ったときの HUD など、持ち主のロードアウト・キャラクターの中の部品が受ける
# 方向：持ち主の slot の entity から下へ（SendDown。slot の下の entity すべて：ロードアウト・キャラクター・widget の view・効果のプレハブ）
# 送り手：pickup_effect_component（拾った効果）。受け手：slot の下の component（HudKit の pickup_effect_hud_component など）。消費しない
# pickup_effect_changed_event（SendUp。slot の祖先＝ゲームの根などが受ける）と同じ時に届く。Renewed はこちらだけ
pickup_effect_owner_event<public> := class(scene_event):
    # 続いている効果。Started・Ended なら拾った効果と同じ。Renewed なら、残り時間が延びた（任された）方の効果
    Effect<public>:pickup_effect_component
    # 拾った効果（知らせを送った効果）。Renewed なら、始まらずにすぐ消える方（見せ方（card_info_component）はこちらから読む）
    Picked<public>:pickup_effect_component
    # 効果を受けている人（持ち主）
    Agent<public>:agent
    # 何が起きたか
    Notice<public>:pickup_effect_notice

# 役割：効果のプレハブの根に置く「効果の土台」。持ち主（拾った人）・寿命（DurationSeconds）・同じ効果の重ねがけ（StackMode）を受け持ち、中身の部品へ寿命の始まりと終わりを合図で伝える
#   始まり：作られた次のフレームに、この entity とその子孫へ、持ち主が起こした起動の合図（activated_by_agent_event）を送る。中身の部品（バフ・能力の付与・ステージへの合図・HUD の文字など、起動の合図で動くもの）はこれで動き出す
#   終わり：DurationSeconds 秒たつか End で、停止の合図（deactivated_event）を送ってから、この entity（効果のプレハブ）を消す。中身の部品は停止の合図か OnEndSimulation で元に戻す
#   中身の部品は、持ち主を FindOwningPlayer（効果はプレイヤーの slot の下に作られる）か起動の合図の Agent で、拾った物（オーブ）を Entity.FindPickupEffect[].FindSource[] で知る。この component を知らない部品（Library の起動の合図で動く部品）もそのまま使える
# 置き方：エディターで、効果のプレハブの根の entity に付ける。中身の部品は同じ entity か子に置く（同じ型の部品を 2 つ使うなら子の entity に分ける）
#   プレハブは、オーブ（pickup_component の Effect）か、コードの Entity.GrantPickupEffect(Agent, Prefab, Origin, Source) が、その人の slot の下に作る。作った entity の位置は拾った物の位置
#   持ち主のいる場所（ロードアウトの中など）にエディターで置いても動く（持ち主 = その場所の持ち主、開始の次のフレームから）
# いつ：作られた次のフレームから DurationSeconds 秒（0 ならずっと。End か EndPickupEffectsFor で終える）。Instant なら起動の合図を送った次のフレームで終える（1 回きりの効果）
# 知らせ：StartedEvent / EndedEvent（持ち主）、pickup_effect_changed_event（SendUp）、pickup_effect_owner_event（持ち主の slot から SendDown。Started / Renewed / Ended）
# タグ：効果のあいだ、持ち主に pickup_effect_tag
# 外から：End / AddSeconds / GetRemainingSeconds / IsActive / FindOwner / FindSource / GetOriginTransform。Entity.FindPickupEffect[]（祖先の効果）、Entity.GetActivePickupEffects(Agent)、Entity.EndPickupEffectsFor(Agent)
# 前提：持ち主のいない場所では始まらない（出力ログに出して消える）
pickup_effect_component<public> := class<final_super>(component):

    # 効果が続く秒数。0 ならずっと（End・EndPickupEffectsFor・持ち主の退出まで）。既定 10
    @editable_number(float):
        ToolTip := EffectDurationToolTip
        Categories := array{PickupEffectCategory}
        MinValue := option{0.0}
        MaxValue := option{3600.0}
    DurationSeconds<public>:float = 10.0
    # オンなら、起動の合図を送った次のフレームで終える（タイムを縮めるなど、1 回きりの効果）。DurationSeconds は使わない。既定オフ
    @editable:
        ToolTip := EffectInstantToolTip
        Categories := array{PickupEffectCategory}
    Instant<public>:logic = false
    # 同じ効果の見分け。同じ人の、同じ EffectId の効果どうしに StackMode が効く。空なら毎回別の効果（いつも重ねる）。既定 空
    @editable:
        ToolTip := EffectIdToolTip
        Categories := array{PickupEffectCategory}
    EffectId<public>:string = ""
    # 同じ効果をもう持っている人が拾ったときどうするか（Extend / Refresh / Stack / Replace / Ignore）。既定 Extend
    @editable:
        ToolTip := EffectStackModeToolTip
        Categories := array{PickupEffectCategory}
    StackMode<public>:pickup_effect_stack_mode = pickup_effect_stack_mode.Extend
    # StackMode が Stack のとき、同時に重ねられる数の上限。0 なら上限なし。既定 0
    @editable_number(int):
        ToolTip := EffectMaxStacksToolTip
        Categories := array{PickupEffectCategory}
        MinValue := option{0}
        MaxValue := option{100}
    MaxStacks<public>:int = 0

    StartedEventInternal<private><final>:event(agent) = event(agent){}
    EndedEventInternal<private><final>:event(agent) = event(agent){}

    # 効果が始まったとき（起動の合図を送ったあと）に、持ち主で届く（Await / Subscribe する。外から Signal はできない）
    StartedEvent<public><final>:listenable(agent) = MakeProxyListenable(StartedEventInternal)

    # 効果が終わったとき（停止の合図を送ったあと、消す前）に、持ち主で届く
    EndedEvent<public><final>:listenable(agent) = MakeProxyListenable(EndedEventInternal)

    var<private> Owner:?agent = false
    var<private> Source:?entity = false
    var<private> OriginTransform:transform = transform{}
    var<private> Started:logic = false
    var<private> Finished:logic = false
    var<private> EndSeconds:float = 0.0
    WakeEventInternal<private>:event() = event(){}
    OwnerTags<private>:player_tag_holder = player_tag_holder{}

    OnSimulate<override>()<suspends>:void =
        # 同じプレハブの部品がみな OnBeginSimulation を終えてから合図を送るように、1 フレーム待つ
        Sleep(0.0)
        if (Finished? or Started?):
            return
        ReadGrant()
        if (Agent := Owner?):
            ShouldBegin := ResolveStacking(Agent)
            if (ShouldBegin?):
                Begin(Agent)
                RunTimer()
            Finish()
        else:
            Print("[pickup_effect_component] 持ち主がいないので効果を始めません（プレイヤーの slot の下に作ってください。GrantPickupEffect / pickup_component）")
            Finish()

    OnEndSimulation<override>():void =
        # 持ち主の退出などで、終わる前に消えたとき（中身の部品は自分の OnEndSimulation で戻す）
        if (not Finished?):
            set Finished = true
            OwnerTags.RemoveAll()
            if (Started?, Agent := Owner?):
                EndedEventInternal.Signal(Agent)
        (super:)OnEndSimulation()

    # 今すぐ終える：停止の合図を送り、持ち主のタグを外し、この entity（効果のプレハブ）を消す。もう終わっていれば何もしない
    End<public>():void =
        Finish()

    # 残り時間に Seconds 秒を足す（負なら縮める）。ずっと続く（DurationSeconds = 0）・Instant の効果では何もしない
    AddSeconds<public>(Seconds:float):void =
        if (DurationSeconds > 0.0, not Instant?, not Finished?):
            set EndSeconds = Max(EndSeconds, GetSimulationElapsedTime()) + Seconds
            WakeEventInternal.Signal()

    # 残り時間を Seconds 秒にする。ずっと続く・Instant の効果では何もしない
    SetRemainingSeconds<public>(Seconds:float):void =
        if (DurationSeconds > 0.0, not Instant?, not Finished?):
            set EndSeconds = GetSimulationElapsedTime() + Seconds
            WakeEventInternal.Signal()

    # 残りの秒数。ずっと続く効果は -1。始まる前は DurationSeconds、終わったら 0
    GetRemainingSeconds<public>()<transacts>:float =
        if (Finished?):
            0.0
        else if (DurationSeconds <= 0.0 and not Instant?):
            -1.0
        else if (not Started?):
            DurationSeconds
        else:
            Max(EndSeconds - GetSimulationElapsedTime(), 0.0)

    # 効果が始まっていて、まだ終わっていなければ成功する
    IsActive<public>()<decides><transacts>:void =
        Started?
        not Finished?

    # 持ち主（効果を受けている人）。まだ決まっていない（作られた最初のフレーム）・持ち主のいない場所なら失敗する
    FindOwner<public>()<decides><transacts>:agent =
        Owner?

    # 効果を与えた物（拾ったオーブの entity）。コードから与えて Source を渡さなかったときは失敗する
    FindSource<public>()<decides><transacts>:entity =
        Source?

    # 拾った物の、拾ったときの世界の位置・向き（コードから与えたときは渡した Origin）
    GetOriginTransform<public>()<transacts>:transform =
        OriginTransform

    # Agent に、同じ EffectId の効果としてこの効果が続いているなら成功する（重ねがけの判断に使う）
    IsSameEffectFor<internal>(Agent:agent, Id:string)<decides><transacts>:void =
        EffectId = Id
        Owner? = Agent
        not Finished?

    # Agent の効果なら成功する（持ち主がまだ決まっていない最初のフレームは、作った側の印で見る）。終わったものは失敗する
    IsForAgent<internal>(Agent:agent)<decides><transacts>:void =
        not Finished?
        if (Known := Owner?):
            Known = Agent
        else:
            Entity.GetComponent[pickup_effect_grant_component].Agent = Agent

    # 持ち主・与えた物・位置を、作った側（pickup_effect_grant_component）か、置かれた場所の持ち主から読む
    ReadGrant<private>():void =
        if (Grant := Entity.GetComponent[pickup_effect_grant_component]):
            set Owner = option{Grant.Agent}
            set Source = Grant.Source
            set OriginTransform = Grant.Origin
        else:
            if (Player := Entity.FindOwningPlayer[]):
                set Owner = option{Player}
            set OriginTransform = Entity.GetGlobalTransform()

    # 同じ効果をもう持っているときの扱い。この効果を始めるなら true
    ResolveStacking<private>(Agent:agent):logic =
        if (EffectId = ""):
            return true
        Others := Entity.GetActivePickupEffects(Agent).FilterSameEffect(Self, EffectId)
        if (Others.Length = 0):
            return true
        if (StackMode = pickup_effect_stack_mode.Replace):
            for (Other : Others):
                Other.End()
            return true
        if (StackMode = pickup_effect_stack_mode.Stack and (MaxStacks <= 0 or Others.Length < MaxStacks)):
            return true
        # 始めずに任せる、続いている効果（持ち主の側へ Renewed で知らせる）
        var Kept:?pickup_effect_component = false
        if (StackMode = pickup_effect_stack_mode.Extend):
            if (First := Others[0]):
                First.AddSeconds(DurationSeconds)
                set Kept = option{First}
        else if (StackMode = pickup_effect_stack_mode.Refresh):
            if (First := Others[0]):
                First.SetRemainingSeconds(Max(First.GetRemainingSeconds(), DurationSeconds))
                set Kept = option{First}
        else if (StackMode = pickup_effect_stack_mode.Stack):
            # 上限に届いている：一番早く終わるものを延ばす
            var Soonest:?pickup_effect_component = false
            for (Other : Others):
                if (Current := Soonest?):
                    if (Other.GetRemainingSeconds() < Current.GetRemainingSeconds()):
                        set Soonest = option{Other}
                else:
                    set Soonest = option{Other}
            if (Found := Soonest?):
                Found.SetRemainingSeconds(Max(Found.GetRemainingSeconds(), DurationSeconds))
            set Kept = Soonest
        else:
            # Ignore：何も変えない（拾ったことだけ知らせる）
            if (First := Others[0]):
                set Kept = option{First}
        if (Found := Kept?):
            NotifyOwner(Agent, Found, pickup_effect_notice.Renewed)
        false

    Begin<private>(Agent:agent):void =
        set Started = true
        set EndSeconds = GetSimulationElapsedTime() + DurationSeconds
        OwnerTags.Add(Agent, pickup_effect_tag{})
        Entity.SendActivatedBy(Agent)
        StartedEventInternal.Signal(Agent)
        Entity.SendUp(pickup_effect_changed_event{Effect := Self, Agent := Agent, Started := true})
        NotifyOwner(Agent, Self, pickup_effect_notice.Started)

    # 持ち主の slot の下へ、効果の知らせ（pickup_effect_owner_event）を送る。slot の下に無ければ送らない
    NotifyOwner<private>(Agent:agent, Target:pickup_effect_component, Notice:pickup_effect_notice):void =
        if (Slot := Entity.FindOwningSlot[]):
            Slot.Entity.SendDown(pickup_effect_owner_event{Effect := Target, Picked := Self, Agent := Agent, Notice := Notice})

    RunTimer<private>()<suspends>:void =
        if (Instant?):
            # 中身の部品が起動の合図で 1 回きりのことを済ませてから終える
            Sleep(0.0)
        else if (DurationSeconds <= 0.0):
            loop:
                WakeEventInternal.Await()
                if (Finished?):
                    break
        else:
            loop:
                Remaining := EndSeconds - GetSimulationElapsedTime()
                if (Finished? or Remaining <= 0.0):
                    break
                race:
                    Sleep(Remaining)
                    WakeEventInternal.Await()

    Finish<private>():void =
        if (Finished?):
            return
        set Finished = true
        if (Started?, Agent := Owner?):
            Entity.SendDeactivated()
            OwnerTags.RemoveAll()
            EndedEventInternal.Signal(Agent)
            Entity.SendUp(pickup_effect_changed_event{Effect := Self, Agent := Agent, Started := false})
            NotifyOwner(Agent, Self, pickup_effect_notice.Ended)
        WakeEventInternal.Signal()
        Entity.RemoveFromParent()

# 役割：GrantPickupEffect が効果のプレハブの根に付ける印。だれに・何から・どこで与えたかを持つ（pickup_effect_component が次のフレームに読む）
#   根に pickup_effect_component が無いプレハブなら、出力ログに出して既定の pickup_effect_component を足す
# 置き方：実行時に GrantPickupEffect が付ける（エディターでは置かない）
pickup_effect_grant_component<public> := class<final_super><internal>(component):
    # 効果を受ける人（持ち主）
    Agent<public>:agent
    # 与えた物（拾ったオーブの entity）。コードから与えたときは false のこともある
    Source<public>:?entity
    # 与えたときの、与えた物の世界の位置・向き
    Origin<public>:transform

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (not Entity.GetComponent[pickup_effect_component]):
            Print("[pickup_effect_grant_component] 効果のプレハブの根に pickup_effect_component がありません。既定（10 秒）で足します")
            Entity.AddComponents(array{pickup_effect_component{Entity := Entity}})

# Agent に効果のプレハブ Prefab を 1 つ作って与える。その人の slot（区画か世界の player_manager_component が作るもの）の下に置き、世界の位置・向きを Origin にする
#   Source は与えた物（オーブの entity。効果の中身の部品が FindSource[] で読む。無ければ false）。作った entity を返す。slot が見つからない（参加していない）ときは false
#   同じ効果の重ねがけ（StackMode）は、作った効果が次のフレームに決める（Extend などで始めないときは、作った entity はすぐ消える）
(InEntity:entity).GrantPickupEffect<public>(Agent:agent, Prefab:concrete_subtype(entity), Origin:transform, Source:?entity):?entity =
    # 引数のままでは Prefab{} と書けない（V3545）ので、いったん変数に受ける
    PrefabType:concrete_subtype(entity) = Prefab
    InEntity.GrantPickupEffectEntity(Agent, PrefabType{}, Origin, Source)

# 組み立て済みの entity（根に pickup_effect_component）を効果として Agent に与える（GrantPickupEffect の中身。テストやコードで効果を組み立てるとき）。slot が見つからなければ false
(InEntity:entity).GrantPickupEffectEntity<public>(Agent:agent, Effect:entity, Origin:transform, Source:?entity):?entity =
    if (Manager := InEntity.FindScopedComponent[player_manager_component], Player := player[Agent], Slot := Manager.FindSlot[Player]):
        Effect.AddComponents(array{pickup_effect_grant_component{Entity := Effect, Agent := Agent, Source := Source, Origin := Origin}})
        Slot.Entity.AddEntities(array{Effect})
        Effect.SetGlobalTransform(Origin)
        option{Effect}
    else:
        Print("[pickup] 効果を与える人の slot が見つかりません（player_manager_component が区画か世界に 1 つ要ります。参加していない人には与えられません）")
        false

# InEntity か、その祖先の効果の土台（pickup_effect_component）。効果のプレハブの中でなければ失敗する
(InEntity:entity).FindPickupEffect<public>()<decides><transacts>:pickup_effect_component =
    InEntity.FindNearestAncestorComponent[pickup_effect_component]

# Agent が今受けている効果（始まる前の最初のフレームのものも含む。終わったものは除く）。並び順は決まっていない
(InEntity:entity).GetActivePickupEffects<public>(Agent:agent)<transacts>:[]pickup_effect_component =
    if (Manager := InEntity.FindScopedComponent[player_manager_component], Player := player[Agent], Slot := Manager.FindSlot[Player]):
        for (Effect : Slot.Entity.FindDescendantComponents(pickup_effect_component), Effect.IsForAgent[Agent]):
            Effect
    else:
        array{}

# Agent が今受けている効果をすべて今すぐ終える（ゲームの流れでやり直す・マップを出るときなど）。終えた数を返す
(InEntity:entity).EndPickupEffectsFor<public>(Agent:agent):int =
    Effects := InEntity.GetActivePickupEffects(Agent)
    for (Effect : Effects):
        Effect.End()
    Effects.Length

# Effects のうち、Exclude 以外で、同じ人の同じ EffectId のもの
(Effects:[]pickup_effect_component).FilterSameEffect<internal>(Exclude:pickup_effect_component, Id:string)<transacts>:[]pickup_effect_component =
    for (Effect : Effects, Effect <> Exclude, Agent := Exclude.FindOwner[], Effect.IsSameEffectFor[Agent, Id]):
        Effect
