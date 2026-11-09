using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Devices }
using { PlayerSystem }
using { SceneGraphSystem }
using { ScheduleSystem }
using { ScheduleSystem.TooltipKit }

# 役割：スケジュールが Active のあいだ、シネマティック シーケンス デバイスを再生する。期間の途中（サーバの起動・デバッグの時刻移動）なら Play のあと SetPlaybackTime(経過秒) で位置を合わせ、期間から出たら Stop する
# 置き方：エディターで entity に付ける。schedule_component の entity かその子孫に置く。Sequence にデバイス（Visibility = Everyone）を入れる（デバイスの配列は MCP で書けないので 1 つ。複数なら子の entity にこの部品を 1 つずつ置く）
# 外から：IsPlaying、Resync（今の経過時間に合わせ直す）
# 前提・注意（実機で確認すること）：
#   - 途中参加の人に映像が合うかは、デバイス側の仕様に依る。ResyncOnPlayerJoin がオンなら参加のたびに Play ＋ SetPlaybackTime をやり直す（全員の再生が一瞬跳ねるかもしれない）。合わないなら、人ごとのデバイス（Visibility = Instigator）を人数分用意して Play(Agent) する作りに変える
#   - SetPlaybackTime は Play の直後に呼ぶ（実績のある順）。1 秒未満の誤差は合わせない（0.5 秒未満なら呼ばない）
#   - シーケンスが Active の長さより短いときは、終わったあとは止まったまま（ループは設定しない）
schedule_sequence_component<public> := class<final_super>(component):

    # 期間中に再生するシネマティック シーケンス デバイス（Visibility = Everyone のもの）
    @editable:
        ToolTip := ScheduleSequencesToolTip
        Categories := array{ScheduleCategory}
    Sequence<public>:?cinematic_sequence_device = false

    # 期間に入った時点で開始からこの秒数より経っていたら再生しない。0 なら制限なし（既定）
    @editable_number(float):
        ToolTip := ScheduleMaxLateStartToolTip
        Categories := array{ScheduleCategory}
        MinValue := option{0.0}
    MaxLateStartSeconds<public>:float = 0.0

    # オンなら期間中にプレイヤーが参加するたびに Play して経過時間に合わせ直す（実機で確認）。既定オン
    @editable:
        ToolTip := ScheduleResyncOnJoinToolTip
        Categories := array{ScheduleCategory}
    ResyncOnPlayerJoin<public>:logic = true

    Follower<private>:schedule_follower = schedule_follower{}
    var<private> Playing:logic = false
    var<private> JoinSubscription:?cancelable = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Attached := Follower.Attach(Entity, OnScheduleChanged, false)
        if (not Attached?):
            Print("[schedule_sequence_component] schedule_component がこの entity にも祖先にも見つかりません")
        if (ResyncOnPlayerJoin?, Manager := Entity.FindScopedComponent[player_manager_component]):
            set JoinSubscription = option{Manager.PlayerAddedEvent.Subscribe(OnPlayerAdded)}

    OnEndSimulation<override>():void =
        JoinSubscription.CancelIfSet()
        set JoinSubscription = false
        Follower.Detach()
        StopAll()
        (super:)OnEndSimulation()

    # 再生しているあいだ成功する
    IsPlaying<public>()<decides><transacts>:void =
        Playing?

    # 再生中なら、今の経過時間に合わせ直す（Play ＋ SetPlaybackTime）。再生していなければ何もしない
    Resync<public>():void =
        if (not Playing?):
            return
        if (Schedule := Follower.FindSchedule[]):
            Snapshot := Schedule.GetCurrentSnapshot()
            if (Snapshot.IsActive[]):
                PlayAll(Snapshot.ElapsedSeconds)

    OnScheduleChanged<private>(Snapshot:schedule_snapshot):void =
        if (Snapshot.IsActive[]):
            if (Playing?):
                return
            if (MaxLateStartSeconds > 0.0 and Snapshot.ElapsedSeconds > MaxLateStartSeconds):
                return
            set Playing = true
            PlayAll(Snapshot.ElapsedSeconds)
        else:
            StopAll()

    OnPlayerAdded<private>(Player:player):void =
        Resync()

    PlayAll<private>(ElapsedSeconds:float):void =
        if (Device := Sequence?):
            Device.Play()
            if (ElapsedSeconds >= 0.5):
                Device.SetPlaybackTime(ElapsedSeconds)

    StopAll<private>():void =
        if (not Playing?):
            return
        set Playing = false
        if (Device := Sequence?):
            Device.Stop()
