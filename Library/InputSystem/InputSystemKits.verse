# Make the InputSystem Kits public so they can be used from outside the library (your code).
# Modules created from folders are internal by default; without this declaration they cannot be imported with using.
InputKit<public> := module {}
# "Ready" parts (player_ready_component, all_players_ready_condition_component)
ReadyKit<public> := module {}
# Descriptions (message) shown in the editor
TooltipKit<public> := module {}
