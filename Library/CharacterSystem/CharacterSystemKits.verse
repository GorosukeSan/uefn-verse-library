# Make the CharacterSystem Kits public so they can be used from outside the library (your code).
# A module created from a folder is internal by default, so without this declaration it cannot be `using`-ed from outside.
# Look and control (facing, syncing with the Fortnite character, input bindings)
BodyKit<public> := module {}
# Buffs / ability grants (while an activation signal is on, stack multipliers, air jumps and dash permission onto the body. Put it in a PickupSystem effect prefab)
BuffKit<public> := module {}
# Follow camera (uses the @experimental camera API. VerseShare distributes it only to projects marked "include experimental")
CameraExperimentalKit<public> := module {}
# Action cells (the shared charge used by air jump, boost and wall kick, plus grants added from effect prefabs)
CellKit<public> := module {}
# State conditions
ConditionKit<public> := module {}
# Reactions to things that happened
EventKit<public> := module {}
# Visual motion (shell squash / stretch, keeping the inner core centered)
LookKit<public> := module {}
# Movement (walk, jump, dash)
MoveKit<public> := module {}
# Touching / standing on surfaces (touchable surfaces, the component that decides a touch, riding moving surfaces)
SurfaceKit<public> := module {}
# Descriptions shown in the editor (message)
TooltipKit<public> := module {}
# Clinging to walls and ceilings (the slime ability. Picked up through GrantCling of BuffKit's character_move_grant_component)
ClingKit<public> := module {}
