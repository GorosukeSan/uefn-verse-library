using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/UI }
using { PlayerSystem }
using { SceneGraphSystem }

# Role: adds a widget to one person's screen and removes it when it goes away (then sends widget_view's HiddenEvent). Passes notifications from the creator (player_view_source_event) and from the same person's other views (player_event) to widget_view.ReceivedEvent
#   With Mode = Menu, avoids overlapping the same person's other menus (Owner's MenuConflict). Other menus are looked up among the views under the same slot
# Placement: created at runtime by player_widget_component (not placed in the editor)
player_widget_view_component<public> := class<final_super><internal>(component):
    # The view for one person
    View<public>:widget_view
    # The widget added to the screen
    Root<public>:widget
    # Stacking order and input mode when added to the screen
    Slot<public>:player_ui_slot

    var<private> Added:logic = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Player := View.Player
        if (Slot.InputMode = ui_input_mode.All):
            if (Other := FindOtherMenu[]):
                if (View.Owner.MenuConflict = player_widget_menu_conflict.KeepOther):
                    # Do not show this one (treat as closed and remove the whole view)
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

    # The view of another menu (Mode = Menu) shown to the same person (under the same slot). Fails if there is none
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
