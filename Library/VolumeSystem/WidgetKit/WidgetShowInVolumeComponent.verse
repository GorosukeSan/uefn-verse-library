using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { VolumeSystem }
using { WidgetSystem }

# Role: while a player is inside the volume, shows every player_widget_component on the same entity to that player and hides them when they leave ("an explanation appears when you enter this place", "a menu opens when you enter the shop", etc.)
# Placement: attach to an entity in the editor. The same entity as player_volume_component, or an ancestor (counts the notifications from descendant volumes)
# Same entity: a player_widget_component subclass (set Audience = Chosen)
# Requirements / notes: for a Mode = Menu widget, closing it with the close button does not show it again while the player stays in the volume (re-entering shows it again)
widget_show_in_volume_component<public> := class<final_super>(component):

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Entered := player_volume_entered_event[SceneEvent]):
            for (Widget : Entity.GetPlayerWidgets()):
                Widget.ShowFor(Entered.Agent)
        else if (Exited := player_volume_exited_event[SceneEvent]):
            for (Widget : Entity.GetPlayerWidgets()):
                Widget.HideFor(Exited.Agent)
        false
