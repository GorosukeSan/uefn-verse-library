# Make the Kits of SwingSystem public so that code outside the library (your code) can use them.
# A module created from a folder is internal by default, so it cannot be used from outside without this declaration.
ModifierKit<public> := module {}
# TargetKit: behaviors of grabbable objects (swing_life_component / swing_lift_component)
TargetKit<public> := module {}
# TooltipKit: ToolTip / Categories text (message)
TooltipKit<public> := module {}
