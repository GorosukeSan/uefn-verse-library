using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { ScheduleSystem }

# 役割：スケジュールが Active のあいだ満たす条件（ゲームの流れの遷移、ability_grant_condition などに渡す）
# 置き方：エディターで entity に付ける。schedule_component の entity かその子孫に置く（一番近い祖先のスケジュールを見る）
# 親：game_transition_component か condition_all / condition_any（または ability_grant_condition_component）の entity の直下。そのうえで schedule_component の entity の子孫
# 知らせ：スケジュールの状態が変わったときだけ condition_changed_event を上へ送り、ChangedEvent に届ける（毎秒の処理は無い）
schedule_active_condition_component<public> := class<final_super>(condition_component):

    var<private> Active:logic = false
    Follower<private>:schedule_follower = schedule_follower{}

    IsSatisfied<override>()<decides><transacts>:void =
        Active?

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Attached := Follower.Attach(Entity, OnScheduleChanged, false)
        if (not Attached?):
            Print("[schedule_active_condition_component] schedule_component がこの entity にも祖先にも見つかりません")

    OnEndSimulation<override>():void =
        Follower.Detach()
        (super:)OnEndSimulation()

    OnScheduleChanged<private>(Snapshot:schedule_snapshot):void =
        NowActive := if (Snapshot.IsActive[]) then true else false
        if (Active <> NowActive):
            set Active = NowActive
            NotifyChanged()
