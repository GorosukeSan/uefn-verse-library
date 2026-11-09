# Makes the VolumeSystem Kits public so they can be used from outside the library (your code).
# Modules created from folders are internal by default, so without this declaration they cannot be used with using from outside.
ActivationKit<public> := module {}
# Condition on the number of players inside a volume (player_in_volume_condition_component)
ConditionKit<public> := module {}
# Descriptions shown in the editor (message)
TooltipKit<public> := module {}
# Part that shows a widget only to players inside a volume
WidgetKit<public> := module {}
