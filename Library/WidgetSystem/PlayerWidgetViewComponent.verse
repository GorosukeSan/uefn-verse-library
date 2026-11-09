using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/UI }
using { PlayerSystem }
using { SceneGraphSystem }

# 役割：1 人の画面に widget を足し、消えるときに外す（外したあと widget_view の HiddenEvent を送る）。作った側からの知らせ（player_view_source_event）と、同じ人のほかの view からの知らせ（player_event）を widget_view.ReceivedEvent に渡す
#   Mode = Menu なら、同じ人のほかのメニューと重ならないようにする（Owner の MenuConflict）。ほかのメニューは、同じ slot の下の view から探す
# 置き方：実行時に player_widget_component が作る（エディターでは置かない）
player_widget_view_component<public> := class<final_super><internal>(component):
    # 1 人分の窓口
    View<public>:widget_view
    # 画面に足す widget
    Root<public>:widget
    # 画面に足すときの重ね順と入力モード
    Slot<public>:player_ui_slot

    var<private> Added:logic = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Player := View.Player
        if (Slot.InputMode = ui_input_mode.All):
            if (Other := FindOtherMenu[]):
                if (View.Owner.MenuConflict = player_widget_menu_conflict.KeepOther):
                    # こちらを出さない（閉じた扱いにして view ごと外す）
                    View.Close()
                    return
                Other.View.Close()
        if (PlayerUI := GetPlayerUI[Player]):
            PlayerUI.AddWidget(Root, Slot)
            set Added = true
            if (Slot.InputMode = ui_input_mode.All):
                PlayerUI.SetFocus(Root)
            spawn{View.NotifyShown()}

    OnEndSimulation<override>():void =
        Player := View.Player
        if (Added?, PlayerUI := GetPlayerUI[Player]):
            PlayerUI.RemoveWidget(Root)
        set Added = false
        View.NotifyHidden()
        (super:)OnEndSimulation()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (FromSource := player_view_source_event[SceneEvent]):
            View.NotifyReceived(FromSource.Event)
        else if (ForPlayer := player_event[SceneEvent], ForPlayer.Sender <> Self):
            View.NotifyReceived(ForPlayer.Event)
        false

    # 同じ人（同じ slot の下）に出ている、ほかのメニュー（Mode = Menu）の view。無ければ失敗する
    FindOtherMenu<private>()<decides><transacts>:player_widget_view_component =
        SlotEntity := Entity.GetParent[]
        Found := for:
            Sibling : SlotEntity.GetEntities()
            Other := Sibling.GetComponent[player_widget_view_component]
            Other <> Self
            Other.Slot.InputMode = ui_input_mode.All
            Other.View.IsShown[]
        do:
            Other
        Found[0]
