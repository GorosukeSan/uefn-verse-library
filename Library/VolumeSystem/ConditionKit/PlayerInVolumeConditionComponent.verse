using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { SceneGraphSystem }
using { VolumeSystem }
using { VolumeSystem.TooltipKit }

# Role: satisfied when at least MinPlayers players are inside the volume (summed when watching several volumes)
# Placement: attach to an entity in the editor
# Parent: directly under the entity of a game_transition_component or condition_all / condition_any
# Children: entities with player_volume_component (anywhere among the descendants; counts the volumes whose notifications reach this entity). When it cannot be a child, pick it with Volume
player_in_volume_condition_component<public> := class<final_super>(condition_component):

    # Satisfied when at least this many players are inside (1-100, default 1)
    @editable_number(int):
        ToolTip := VolumeMinPlayersToolTip
        Categories := array{VolumeCategory}
        MinValue := option{1}
        MaxValue := option{100}
    MinPlayers<public>:int = 1

    # The volume to watch (an entity with player_volume_component). When empty, counts the notifications from volumes on this entity or its descendants
    @editable:
        ToolTip := VolumeConditionVolumeToolTip
        Categories := array{VolumeCategory}
    Volume<public>:?entity = false

    var<private> Volumes:[]player_volume_component = array{}
    var<private> Subscriptions:[]cancelable = array{}

    IsSatisfied<override>()<decides><transacts>:void =
        var Total:int = 0
        for (Watched : Volumes):
            set Total += Watched.GetInsideCount()
        Total >= MinPlayers

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (VolumeEntity := Volume?, Found := VolumeEntity.GetComponent[player_volume_component]):
            Watch(Found)
            set Subscriptions = array:
                Found.PlayerEnteredEvent.Subscribe(OnChanged)
                Found.PlayerExitedEvent.Subscribe(OnChanged)

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        (super:)OnEndSimulation()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Entered := player_volume_entered_event[SceneEvent]):
            Watch(Entered.Volume)
            NotifyChanged()
        else if (Exited := player_volume_exited_event[SceneEvent]):
            Watch(Exited.Volume)
            NotifyChanged()
        false

    OnChanged<private>(Agent:agent):void =
        NotifyChanged()

    Watch<private>(Found:player_volume_component):void =
        if (not Volumes.Find[Found]):
            set Volumes += array{Found}
