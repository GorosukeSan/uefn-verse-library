# Make the Kits of PlayerSystem public so they can be used from outside the library (your code).
# Modules created from folders are internal by default, so they cannot be used with `using` from outside unless declared.
ConditionKit<public> := module {}
# Descriptions shown in the editor (message)
TooltipKit<public> := module {}
# Parts that react to Fortnite character motion (jump, landing, crouch, etc.)
MotionKit<public> := module {}
