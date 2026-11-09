# Makes the CountdownSystem Kits public so they can be used from outside the library (your code).
# Modules created from folders are internal by default, so without this declaration they cannot be used with using from outside.
ConditionKit<public> := module {}
# Kit holding the descriptions shown in the editor (message)
TooltipKit<public> := module {}
