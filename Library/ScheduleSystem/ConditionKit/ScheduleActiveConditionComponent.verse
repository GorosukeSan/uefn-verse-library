using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { ScheduleSystem }

# Role: a condition satisfied while the schedule is Active (pass it to game flow transitions, ability_grant_condition, ...)
# Placement: attach to an entity in the editor, on the schedule_component entity or a descendant (follows the nearest ancestor schedule)
# Parent: directly under the entity of game_transition_component or condition_all / condition_any (or ability_grant_condition_component), which is itself a descendant of the schedule_component entity
# Notifies: only when the schedule state changes, sends condition_changed_event up and fires ChangedEvent (no per-second work)
schedule_active_condition_component<public> := class<final_super>(condition_component):

    var<private> Active:logic = false
    Follower<private>:schedule_follower = schedule_follower{}

    IsSatisfied<override>()<decides><transacts>:void =
        Active?

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Attached := Follower.Attach(Entity, OnScheduleChanged, false)
        if (not Attached?):
            Print("[schedule_active_condition_component] schedule_component not found on this entity or any ancestor")

    OnEndSimulation<override>():void =
        Follower.Detach()
        (super:)OnEndSimulation()

    OnScheduleChanged<private>(Snapshot:schedule_snapshot):void =
        NowActive := if (Snapshot.IsActive[]) then true else false
        if (Active <> NowActive):
            set Active = NowActive
            NotifyChanged()
