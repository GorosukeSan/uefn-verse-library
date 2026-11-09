using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { VolumeSystem }
using { VolumeSystem.TooltipKit }

# 役割：ボリュームに最初の 1 人が入ったら起動の合図（activated_event）、最後の 1 人が出たら停止の合図（deactivated_event）を Targets へ送る（「人がいるあいだだけ動く」仕掛け）
# 置き方：エディターで、player_volume_component と同じ entity か、その祖先の entity に付ける
# 知らせ：Targets の entity とその子孫へ activated_event / deactivated_event。Targets が空なら、この entity の子の entity へ送る（自分の entity と、player_volume_component の付いた entity へは送らない。ボリュームが停止の合図で止まってしまうため）
# 前提：数えるのは、この entity か子孫のボリュームから上へ届いた知らせ（複数あれば合計の人数）
volume_activation_component<public> := class<final_super>(component):

    # 最初の 1 人が入ったら起動の合図、最後の 1 人が出たら停止の合図を送る entity（その entity と子孫に届く）。空ならこの entity の子へ送る
    @editable:
        ToolTip := VolumeActivationTargetsToolTip
        Categories := array{VolumeCategory}
    Targets<public>:[]entity = array{}

    var<private> Inside:[agent]int = map{}

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Entered := player_volume_entered_event[SceneEvent]):
            WasEmpty := IsEmpty()
            Count := if (Current := Inside[Entered.Agent]) then Current else 0
            if (set Inside[Entered.Agent] = Count + 1) {}
            if (WasEmpty?):
                Send(true, option{Entered.Agent})
        else if (Exited := player_volume_exited_event[SceneEvent]):
            if (Current := Inside[Exited.Agent], Current > 0):
                if (set Inside[Exited.Agent] = Current - 1) {}
                if (IsEmpty()?):
                    Send(false, false)
        false

    # 今だれかが中にいれば成功する
    IsOccupied<public>()<decides><transacts>:void =
        not IsEmpty()?

    IsEmpty<private>()<transacts>:logic =
        Occupied := for (Agent -> Count : Inside, Count > 0):
            Agent
        if (Occupied.Length = 0) then true else false

    Send<private>(Activate:logic, By:?agent):void =
        Receivers := if (Targets.Length > 0) then Targets else Entity.GetEntities()
        # ボリュームの entity には送らない（停止の合図でボリュームが止まり、二度と出入りを調べなくなるため）
        for (Receiver : Receivers, not Receiver.GetComponent[player_volume_component]):
            if (Activate?):
                if (Agent := By?):
                    Receiver.SendActivatedBy(Agent)
                else:
                    Receiver.SendActivated()
            else:
                Receiver.SendDeactivated()
