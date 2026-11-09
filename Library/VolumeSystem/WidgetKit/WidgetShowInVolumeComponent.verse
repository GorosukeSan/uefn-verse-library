using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { VolumeSystem }
using { WidgetSystem }

# 役割：ボリュームの中にいるあいだ、同じ entity の player_widget_component（すべて）をその人に出し、出たら消す（「この場所に入ると説明が出る」「売り場に入るとメニューが開く」など）
# 置き方：エディターで entity に付ける。player_volume_component と同じ entity か、その祖先（子孫のボリュームの知らせを数える）
# 同じ entity：player_widget_component の派生（Audience = Chosen にする）
# 前提・注意：Mode = Menu の widget なら、閉じるボタンで閉じてもボリュームにいるあいだは出し直さない（入り直すとまた出る）
widget_show_in_volume_component<public> := class<final_super>(component):

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Entered := player_volume_entered_event[SceneEvent]):
            for (Widget : Entity.GetPlayerWidgets()):
                Widget.ShowFor(Entered.Agent)
        else if (Exited := player_volume_exited_event[SceneEvent]):
            for (Widget : Entity.GetPlayerWidgets()):
                Widget.HideFor(Exited.Agent)
        false
