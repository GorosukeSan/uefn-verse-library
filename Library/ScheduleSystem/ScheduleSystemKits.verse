# Makes the ScheduleSystem Kits public so that code outside the library (your code) can use them.
# Modules created from folders are internal by default, so they cannot be used from outside without this declaration.
ConditionKit<public> := module {}
# Components that show the remaining time as text or digit meshes (schedule_text_component / schedule_digit_display_component)
DisplayKit<public> := module {}
# Component that shows a pre-start countdown on screen (schedule_countdown_hud_component)
HudKit<public> := module {}
# Descriptions shown in the editor (message)
TooltipKit<public> := module {}
