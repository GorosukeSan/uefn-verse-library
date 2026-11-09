using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { SceneGraphSystem }
using { VolumeSystem }
using { VolumeSystem.TooltipKit }

# 役割：ボリュームの中に MinPlayers 人以上いれば満たす（複数のボリュームを見るときは合計）
# 置き方：エディターで entity に付ける
# 親：game_transition_component か condition_all / condition_any の entity の直下
# 子：player_volume_component を付けた entity（子孫ならどこでも。知らせが上へ届いたボリュームを数える）。子に置けないときは Volume で選ぶ
player_in_volume_condition_component<public> := class<final_super>(condition_component):

    # この人数以上が中にいれば満たす（1〜100、既定 1）
    @editable_number(int):
        ToolTip := VolumeMinPlayersToolTip
        Categories := array{VolumeCategory}
        MinValue := option{1}
        MaxValue := option{100}
    MinPlayers<public>:int = 1

    # 見張るボリューム（player_volume_component を付けた entity）。空なら、この entity か子孫のボリュームの知らせを数える
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
