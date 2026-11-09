# Make the Kits of PickupSystem public so that code outside the library (your code) can use them.
# A module created from a folder is internal by default, so it cannot be used from outside without this declaration.
# Stage effects (from inside an effect, send activate / deactivate signals to targets found by tag)
StageKit<public> := module {}
# Descriptions shown in the editor (message)
TooltipKit<public> := module {}
# HUD that shows picked-up effects on screen (a notice on pickup and a list of ongoing effects; built from WidgetSystem parts)
HudKit<public> := module {}
