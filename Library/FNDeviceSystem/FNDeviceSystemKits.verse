# Make the FNDeviceSystem Kits public so they can be used from outside the library (your code).
# Modules created from folders are internal by default; without this declaration they cannot be imported with using.
# Component that plays a cinematic sequence device while a schedule (ScheduleSystem) is active (schedule_sequence_component)
ScheduleKit<public> := module {}
# Descriptions (message) shown in the editor
TooltipKit<public> := module {}
