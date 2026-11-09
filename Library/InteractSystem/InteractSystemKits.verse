# Makes the InteractSystem Kits public so they can be used from outside the library (your code).
# Modules created from folders are internal by default, so without this declaration they cannot be used with using from outside.
ConditionKit<public> := module {}
# Part that toggles whether it can be pressed (interact_gate_component)
GateKit<public> := module {}
# Descriptions shown in the editor (message)
TooltipKit<public> := module {}
