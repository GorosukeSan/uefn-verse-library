# Make the Kits of ConditionSystem public so they can be used from outside the library (your code).
# Modules created from folders are internal by default, so they cannot be used with `using` from outside unless declared.
GroupKit<public> := module {}
# Condition satisfied by a received scene_event (event_received_condition_component)
EventKit<public> := module {}
# Descriptions shown in the editor (message)
TooltipKit<public> := module {}
